import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show Rect;
import 'package:flutter/foundation.dart';
import 'package:pedometer/pedometer.dart';
import 'package:camera/camera.dart';
import 'package:uuid/uuid.dart';
import '../models/path_models.dart';

class PathRecordingService extends ChangeNotifier {
  static final PathRecordingService _instance = PathRecordingService._internal();
  factory PathRecordingService() => _instance;
  PathRecordingService._internal();

  // Service state
  RecordingSession? _currentSession;
  StreamSubscription<StepCount>? _stepCountSubscription;
  Timer? _objectDetectionTimer;
  
  // Constants
  static const double _stepLengthMeters = 0.65; // Average step length
  static const Duration _objectDetectionInterval = Duration(milliseconds: 500);
  
  // Getters
  RecordingSession? get currentSession => _currentSession;
  bool get isRecording => _currentSession?.state == RecordingState.recording;
  bool get isInCheckpoint => _currentSession?.state == RecordingState.checkpoint;
  bool get hasActiveSession => _currentSession != null;

  // Initialize recording session
  Future<void> startRecordingSession() async {
    try {
      // Get current step count to use as baseline
      final stepCount = await Pedometer.stepCountStream.first;
      
      _currentSession = RecordingSession(
        id: const Uuid().v4(),
        state: RecordingState.recording,
        segments: [],
        detectedObjects: [],
        currentStepCount: stepCount.steps,
        currentDistance: 0.0,
        sessionStartSteps: stepCount.steps,
        startTime: DateTime.now(),
      );
      
      // Start step counting
      _startStepCounting();
      
      // Start object detection timer
      _startObjectDetection();
      
      notifyListeners();
      print('✅ Recording session started with baseline steps: ${stepCount.steps}');
    } catch (e) {
      print('❌ Error starting recording session: $e');
      throw Exception('Failed to start recording session: $e');
    }
  }

  // Start step counting subscription
  void _startStepCounting() {
    _stepCountSubscription?.cancel();
    _stepCountSubscription = Pedometer.stepCountStream.listen(
      (StepCount stepCount) {
        if (_currentSession != null) {
          final distance = (_currentSession!.relativeStepCount * _stepLengthMeters);
          
          _currentSession = _currentSession!.copyWith(
            currentStepCount: stepCount.steps,
            currentDistance: distance,
          );
          
          notifyListeners();
        }
      },
      onError: (error) {
        print('❌ Step count error: $error');
      },
      cancelOnError: false,
    );
  }

  // Start periodic object detection (placeholder for YOLO integration)
  void _startObjectDetection() {
    _objectDetectionTimer?.cancel();
    _objectDetectionTimer = Timer.periodic(_objectDetectionInterval, (timer) {
      if (_currentSession?.state == RecordingState.recording) {
        // This will be called by the UI when YOLO detects objects
        // We just maintain the timer here for consistency
      }
    });
  }

  // Add detected object from YOLO
  void addDetectedObject({
    required String label,
    required double confidence,
    required Rect boundingBox,
    Uint8List? imageFrame,
  }) {
    if (_currentSession == null || !isRecording) return;

    final detectedObject = DetectedObject(
      label: label,
      confidence: confidence,
      boundingBox: boundingBox,
      imageFrame: imageFrame,
      stepCount: _currentSession!.relativeStepCount,
      distance: _currentSession!.currentDistance,
      timestamp: DateTime.now(),
    );

    final updatedObjects = List<DetectedObject>.from(_currentSession!.detectedObjects)
      ..add(detectedObject);

    _currentSession = _currentSession!.copyWith(
      detectedObjects: updatedObjects,
    );

    // Show brief UI feedback (handled by UI layer)
    notifyListeners();
    
    print('🎯 Object detected: $label (confidence: ${(confidence * 100).toStringAsFixed(1)}%) at step ${_currentSession!.relativeStepCount}');
  }

  // Mark manual checkpoint
  Future<void> markCheckpoint({
    required Uint8List frozenFrame,
    required List<DetectedObject> frameObjects,
  }) async {
    if (_currentSession == null || !isRecording) return;

    _currentSession = _currentSession!.copyWith(
      state: RecordingState.checkpoint,
      frozenFrame: frozenFrame,
      frozenFrameObjects: frameObjects,
    );

    // Pause step counting during checkpoint definition
    _stepCountSubscription?.pause();

    notifyListeners();
    print('📍 Checkpoint marked at step ${_currentSession!.relativeStepCount}');
  }

  // Create landmark from selected object
  Landmark createLandmarkFromObject({
    required DetectedObject object,
    required LandmarkType type,
  }) {
    return Landmark(
      id: const Uuid().v4(),
      type: type,
      label: object.label,
      boundingBox: object.boundingBox,
      imageFrame: object.imageFrame ?? Uint8List(0),
      confidence: object.confidence,
      stepCount: object.stepCount,
      distance: object.distance,
      timestamp: object.timestamp,
    );
  }

  // Create custom landmark
  Landmark createCustomLandmark({
    required String label,
    required Rect boundingBox,
    required Uint8List imageFrame,
  }) {
    if (_currentSession == null) {
      throw Exception('No active recording session');
    }

    return Landmark(
      id: const Uuid().v4(),
      type: LandmarkType.custom,
      label: label,
      boundingBox: boundingBox,
      imageFrame: imageFrame,
      confidence: 1.0, // Custom landmarks have 100% confidence
      stepCount: _currentSession!.relativeStepCount,
      distance: _currentSession!.currentDistance,
      timestamp: DateTime.now(),
    );
  }

  // Complete current segment with landmark and action
  void completeSegment({
    required Landmark landmark,
    required TurnDirection action,
  }) {
    if (_currentSession == null || !isInCheckpoint) return;

    final startSteps = _currentSession!.segments.isNotEmpty
        ? _currentSession!.segments.last.endStepCount
        : 0;

    final segment = PathSegment(
      id: const Uuid().v4(),
      startStepCount: startSteps,
      endStepCount: _currentSession!.relativeStepCount,
      distance: _currentSession!.currentDistance - 
                (_currentSession!.segments.isNotEmpty 
                    ? _currentSession!.segments.fold(0.0, (sum, s) => sum + s.distance)
                    : 0.0),
      landmark: landmark,
      action: action,
      timestamp: DateTime.now(),
    );

    final updatedSegments = List<PathSegment>.from(_currentSession!.segments)
      ..add(segment);

    _currentSession = _currentSession!.copyWith(
      state: RecordingState.recording,
      segments: updatedSegments,
      frozenFrame: null,
      frozenFrameObjects: null,
    );

    // Resume step counting
    _stepCountSubscription?.resume();

    notifyListeners();
    print('✅ Segment completed: ${segment.stepCount} steps, ${segment.distance.toStringAsFixed(1)}m, action: ${action.toString()}');
  }

  // Cancel checkpoint and return to recording
  void cancelCheckpoint() {
    if (_currentSession == null || !isInCheckpoint) return;

    _currentSession = _currentSession!.copyWith(
      state: RecordingState.recording,
      frozenFrame: null,
      frozenFrameObjects: null,
    );

    // Resume step counting
    _stepCountSubscription?.resume();

    notifyListeners();
    print('❌ Checkpoint cancelled');
  }

  // Finish recording and move to review
  void finishRecording() {
    if (_currentSession == null || _currentSession!.segments.isEmpty) {
      throw Exception('Cannot finish recording: no segments recorded');
    }

    _currentSession = _currentSession!.copyWith(
      state: RecordingState.review,
    );

    // Stop timers but keep session for review
    _objectDetectionTimer?.cancel();

    notifyListeners();
    print('🏁 Recording finished. Moving to review with ${_currentSession!.segments.length} segments and ${_currentSession!.detectedObjects.length} detected objects');
  }

  // Get suggested checkpoints (auto-detected objects during recording)
  List<Landmark> getSuggestedCheckpoints() {
    if (_currentSession == null) return [];

    // Convert detected objects to landmarks, filtering out duplicates and low-confidence detections
    final suggestions = <Landmark>[];
    const double minConfidence = 0.7;
    const double minDistanceBetweenObjects = 2.0; // meters

    for (final object in _currentSession!.detectedObjects) {
      if (object.confidence < minConfidence) continue;

      // Check if this object is too close to existing suggestions
      final isTooClose = suggestions.any((existing) =>
          (object.distance - existing.distance).abs() < minDistanceBetweenObjects);

      if (!isTooClose) {
        suggestions.add(createLandmarkFromObject(
          object: object,
          type: LandmarkType.yolo,
        ));
      }
    }

    return suggestions;
  }

  // Create final recorded path
  RecordedPath createRecordedPath({
    required String name,
    required String description,
    required List<Landmark> selectedSuggestions,
  }) {
    if (_currentSession == null) {
      throw Exception('No active recording session');
    }

    final now = DateTime.now();
    return RecordedPath(
      id: _currentSession!.id,
      name: name,
      description: description,
      segments: _currentSession!.segments,
      suggestedCheckpoints: selectedSuggestions,
      totalDistance: _currentSession!.currentDistance,
      totalSteps: _currentSession!.relativeStepCount,
      createdAt: _currentSession!.startTime,
      updatedAt: now,
    );
  }

  // Cancel entire recording session
  void cancelRecording() {
    _currentSession = null;
    _cleanup();
    notifyListeners();
    print('❌ Recording session cancelled');
  }

  // Cleanup resources
  void _cleanup() {
    _stepCountSubscription?.cancel();
    _stepCountSubscription = null;
    _objectDetectionTimer?.cancel();
    _objectDetectionTimer = null;
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }

  // Utility methods
  String formatDistance(double meters) {
    if (meters < 1.0) {
      return '${(meters * 100).toStringAsFixed(0)}cm';
    } else {
      return '${meters.toStringAsFixed(1)}m';
    }
  }

  String formatSteps(int steps) {
    return '$steps step${steps != 1 ? 's' : ''}';
  }

  String getTurnDirectionIcon(TurnDirection direction) {
    switch (direction) {
      case TurnDirection.left:
        return '←';
      case TurnDirection.right:
        return '→';
      case TurnDirection.straight:
        return '↑';
    }
  }

  String getTurnDirectionText(TurnDirection direction) {
    switch (direction) {
      case TurnDirection.left:
        return 'Turn Left';
      case TurnDirection.right:
        return 'Turn Right';
      case TurnDirection.straight:
        return 'Go Straight';
    }
  }
} 