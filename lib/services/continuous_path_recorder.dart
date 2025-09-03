import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter_compass/flutter_compass.dart';
import '../services/clip_service.dart';
import '../models/path_models.dart';
import 'package:uuid/uuid.dart';

// Raw waypoint data for batch processing
class RawWaypointData {
  final String id;
  final String imagePath;
  final double heading;
  final double headingChange;
  final TurnType turnType;
  final bool isDecisionPoint;
  final String landmarkDescription;
  final double? distanceFromPrevious;
  final DateTime timestamp;
  final int sequenceNumber;

  RawWaypointData({
    required this.id,
    required this.imagePath,
    required this.heading,
    required this.headingChange,
    required this.turnType,
    required this.isDecisionPoint,
    required this.landmarkDescription,
    required this.distanceFromPrevious,
    required this.timestamp,
    required this.sequenceNumber,
  });
}

class ContinuousPathRecorder {
  final ClipService _clipService;
  final CameraController _cameraController;
  
  // Recording state
  bool _isRecording = false;
  bool _processingCancelled = false; // Flag to cancel waypoint processing
  List<PathWaypoint> _waypoints = [];
  List<RawWaypointData> _rawWaypoints = []; // Store raw frames for batch processing
  Timer? _recordingTimer;
  StreamSubscription<CompassEvent>? _compassSubscription;
  
  // Tracking variables
  double _lastHeading = 0.0;
  int _sequenceNumber = 0;
  DateTime? _recordingStartTime;
  
  // Configuration
  final Duration _captureInterval = const Duration(seconds: 3);
  final double _significantHeadingChange = 30; // Minimum for decision point
  final Uuid _uuid = const Uuid();
  
  // Current state
  double? _currentHeading;
  String? _currentPathId;
  
  // Callbacks
  final Function(String message)? onStatusUpdate;
  final Function(PathWaypoint waypoint)? onWaypointCaptured;
  final Function(String error)? onError;

  ContinuousPathRecorder({
    required ClipService clipService,
    required CameraController cameraController,
    this.onStatusUpdate,
    this.onWaypointCaptured,
    this.onError,
  }) : _clipService = clipService, _cameraController = cameraController;

  // Public methods
  bool get isRecording => _isRecording;
  List<PathWaypoint> get waypoints => List.unmodifiable(_waypoints);
  int get waypointCount => _isRecording ? _rawWaypoints.length : _waypoints.length;

  void cancelProcessing() {
    _processingCancelled = true;
  }

  Future<void> startRecording(String pathId) async {
    if (_isRecording) {
      onError?.call('Recording already in progress');
      return;
    }

    if (!_cameraController.value.isInitialized) {
      onError?.call('Camera not initialized');
      return;
    }

    try {
      _currentPathId = pathId;
      _isRecording = true;
      _processingCancelled = false; // Reset cancellation flag
      _waypoints.clear();
      _rawWaypoints.clear();
      _sequenceNumber = 0;
      _recordingStartTime = DateTime.now();
      
      // Initialize compass
      await _initializeCompass();
      
      // Start periodic recording
      _recordingTimer = Timer.periodic(_captureInterval, (timer) {
        //ROBUST CHECK: Cancel timer immediately if not recording
        if (!_isRecording) {
          print('Timer detected recording stopped - cancelling');
          timer.cancel();
          return;
        }
        
        //ASYNC SAFETY: Don't await to prevent blocking timer, but handle errors
        _captureWaypoint().catchError((error) {
          print('Error during waypoint capture: $error');
          // Don't stop recording for individual waypoint errors
        });
      });
      
      // Announce that recording has started
      onStatusUpdate?.call('Recording Started');
      
    } catch (e) {
      _isRecording = false;
      onError?.call('Failed to start recording: $e');
    }
  }

  Future<void> stopRecording() async {
    if (!_isRecording) return;

    print('Stopping recording - setting flag and cancelling timers...');
    
    //IMMEDIATE STOP: Set flag first to prevent new waypoints
    _isRecording = false;
    
    //CANCEL ALL TIMERS: Stop all periodic operations
    _recordingTimer?.cancel();
    _recordingTimer = null;
    
    _compassSubscription?.cancel();
    _compassSubscription = null;

    print('✅ All timers cancelled, processing waypoints...');
    // Status message removed as requested
    
    //Give any in-flight waypoint captures time to check the flag
    await Future.delayed(const Duration(milliseconds: 100));
    
    // Batch process raw waypoints with inpainting
    await _batchProcessWaypoints();
    
    // Process and filter waypoints
    await _processRecordedWaypoints();
    
    // Status message removed as requested
  }

  Future<void> pauseRecording() async {
    if (!_isRecording) return;
    
    _recordingTimer?.cancel();
    // Status message removed as requested
  }

  Future<void> resumeRecording() async {
    if (!_isRecording) return;
    
    _recordingTimer = Timer.periodic(_captureInterval, (timer) {
      if (!_isRecording) {
        timer.cancel();
        return;
      }
      _captureWaypoint();
    });
    
    // Status message removed as requested
  }

  void addManualWaypoint(String description) {
    if (!_isRecording) return;
    
    // Capture a waypoint immediately with custom description
    _captureWaypoint(manualDescription: description);
  }

  // Private methods
  Future<void> _initializeCompass() async {
    if (FlutterCompass.events == null) {
      throw Exception('Compass not available on this device');
    }
    
    _compassSubscription = FlutterCompass.events!.listen((event) {
      if (event.heading != null) {
        _currentHeading = _normalizeHeading(event.heading!);
      }
    });
    
    // Wait a bit for initial compass reading
    await Future.delayed(const Duration(milliseconds: 500));
    
    if (_currentHeading != null) {
      _lastHeading = _normalizeHeading(_currentHeading!);
    }
  }

  Future<void> _captureWaypoint({String? manualDescription}) async {
    // DOUBLE-CHECK: Ensure we're still recording before any processing
    if (!_isRecording || _currentHeading == null) return;

    try {
      // ADDITIONAL CHECK: Verify recording state hasn't changed during execution
      if (!_isRecording) {
        print('⚠️ Recording stopped during waypoint capture - aborting');
        return;
      }
      
      // Calculate heading change
      double headingChange = _calculateHeadingChange(_lastHeading, _currentHeading!);
      
      // Detect turn type
      TurnType turnType = _detectTurnType(headingChange);
      
      // Determine if this is a decision point
      bool isDecisionPoint = headingChange.abs() > _significantHeadingChange || 
                           manualDescription != null;

      // CRITICAL CHECK: Verify recording state before expensive operations
      if (!_isRecording) {
        print('Recording stopped before image capture - aborting waypoint');
        return;
      }

      // Capture image and generate embedding
      final image = await _cameraController.takePicture();
      
      // FINAL CHECK: Verify recording state after image capture
      if (!_isRecording) {
        print('Recording stopped during image processing - aborting waypoint');
        // Clean up the captured image
        try {
          await File(image.path).delete();
        } catch (e) {
          print('Warning: Could not delete captured image: $e');
        }
        return;
      }
      
      final File imageFile = File(image.path);
      
      // Distance calculation removed - not reliable
      double? distanceFromPrevious = null;

      // Create raw waypoint data (no embedding yet)
      final rawWaypoint = RawWaypointData(
        id: _uuid.v4(),
        imagePath: imageFile.path,
        heading: _normalizeHeading(_currentHeading!),
        headingChange: headingChange,
        turnType: turnType,
        isDecisionPoint: isDecisionPoint,
        landmarkDescription: manualDescription ?? _generateAutoDescription(turnType, headingChange),
        distanceFromPrevious: distanceFromPrevious,
        timestamp: DateTime.now(),
        sequenceNumber: _sequenceNumber++,
      );

      _rawWaypoints.add(rawWaypoint);
      _lastHeading = _normalizeHeading(_currentHeading!);
      
      // Send waypoint capture status update
      String statusMessage = 'Waypoint ${_rawWaypoints.length} captured.';
      if (isDecisionPoint) {
        statusMessage += ' (${turnType.name} turn detected)';
      }
      onStatusUpdate?.call(statusMessage);
      
    } catch (e) {
      onError?.call('Failed to capture waypoint: $e');
    }
  }

  double _calculateHeadingChange(double previousHeading, double currentHeading) {
    // Ensure both headings are normalized
    double normPrevious = _normalizeHeading(previousHeading);
    double normCurrent = _normalizeHeading(currentHeading);
    
    double change = normCurrent - normPrevious;
    
    // Handle 360° wraparound
    if (change > 180) {
      change -= 360;
    } else if (change < -180) {
      change += 360;
    }
    
    return change;
  }

  // Normalize heading to be within 0-360 range
  double _normalizeHeading(double heading) {
    // Handle null, NaN, or infinite values
    if (heading.isNaN || heading.isInfinite) {
      return 0.0;
    }
    
    // Normalize to 0-360 range
    double normalized = heading % 360;
    if (normalized < 0) {
      normalized += 360;
    }
    
    return normalized;
  }

  TurnType _detectTurnType(double headingChange) {
    double absChange = headingChange.abs();
    
    if (absChange < _significantHeadingChange) {
      return TurnType.straight;
    } else if (absChange > 165) {
      return TurnType.uTurn;
    } else if (headingChange > 0) {
      return TurnType.right;
    } else {
      return TurnType.left;
    }
  }

  String _generateAutoDescription(TurnType turnType, double headingChange) {
    switch (turnType) {
      case TurnType.straight:
        return 'Continue straight';
      case TurnType.left:
        return 'Turn left (${headingChange.abs().round()}°)';
      case TurnType.right:
        return 'Turn right (${headingChange.abs().round()}°)';
      case TurnType.uTurn:
        return 'U-turn (${headingChange.abs().round()}°)';
    }
  }

  /// Batch process raw waypoints with inpainting
  Future<void> _batchProcessWaypoints() async {
    if (_rawWaypoints.isEmpty) return;

    print('Batch processing ${_rawWaypoints.length} raw waypoints with inpainting...');
    
    _waypoints.clear(); // Clear any existing waypoints
    
    for (int i = 0; i < _rawWaypoints.length; i++) {
      if (_processingCancelled) {
        print('Processing cancelled by user');
        // Status message removed as requested
        return;
      }
      
      final rawWaypoint = _rawWaypoints[i];
      
      try {
        // Update status - removed as requested
        // onStatusUpdate?.call('Processing frame ${i + 1}/${_rawWaypoints.length}');
        
        // Generate embedding only (no people detection during recording)
        final File imageFile = File(rawWaypoint.imagePath);
        final embedding = await _clipService.generatePreprocessedEmbedding(imageFile);
        
        // Create final waypoint with default people detection values (no YOLO detection)
        final waypoint = PathWaypoint(
          id: rawWaypoint.id,
          embedding: embedding,
          heading: rawWaypoint.heading,
          headingChange: rawWaypoint.headingChange,
          turnType: rawWaypoint.turnType,
          isDecisionPoint: rawWaypoint.isDecisionPoint,
          landmarkDescription: rawWaypoint.landmarkDescription,
          distanceFromPrevious: rawWaypoint.distanceFromPrevious,
          timestamp: rawWaypoint.timestamp,
          sequenceNumber: rawWaypoint.sequenceNumber,
          // No people detection during recording - set defaults
          peopleDetected: false,
          peopleCount: 0,
          peopleConfidenceScores: [],
        );
        
        _waypoints.add(waypoint);
        
        // Clean up the raw image file
        await imageFile.delete();
        
        print('Processed waypoint ${i + 1}/${_rawWaypoints.length}: embedding=${embedding.length}d (no YOLO detection)');
        
      } catch (e) {
        print('Error processing waypoint ${i + 1}: $e');
        onError?.call('Failed to process waypoint ${i + 1}: $e');
        
        // Clean up the raw image file even on error
        try {
          await File(rawWaypoint.imagePath).delete();
        } catch (deleteError) {
          print('Warning: Could not delete raw image: $deleteError');
        }
      }
    }
    
    // Clear raw waypoints after processing
    _rawWaypoints.clear();
    
    print('Batch processing complete. Generated ${_waypoints.length} waypoints with embeddings.');
  }

  Future<void> _processRecordedWaypoints() async {
    if (_waypoints.isEmpty) return;

    if (_processingCancelled) {
      print('Processing cancelled by user');
      // Status message removed as requested
      return;
    }

    print('Processing ${_waypoints.length} recorded waypoints...');
    
    // Filter out redundant waypoints that are too similar
    List<PathWaypoint> filteredWaypoints = [];
    int removedCount = 0;
    
    for (int i = 0; i < _waypoints.length; i++) {
      bool shouldKeep = true;
      String keepReason = '';
      
      // Always keep the first and last waypoints
      if (i == 0) {
        keepReason = 'FIRST waypoint';
      } else if (i == _waypoints.length - 1) {
        keepReason = 'LAST waypoint';
      } else if (_waypoints[i].isDecisionPoint) {
        keepReason = 'DECISION POINT (${_waypoints[i].turnType.name})';
      } else if (i < _waypoints.length - 1 && _waypoints[i + 1].isDecisionPoint) {
        // Keep waypoint before a decision point (turn)
        keepReason = 'BEFORE TURN (${_waypoints[i + 1].turnType.name})';
      } else {
        // Check similarity with previous kept waypoint
        if (filteredWaypoints.isNotEmpty) {
          PathWaypoint lastKept = filteredWaypoints.last;
          double similarity = _calculateCosineSimilarity(
            _waypoints[i].embedding, 
            lastKept.embedding
          );
          
          double headingDiff = (_waypoints[i].heading - lastKept.heading).abs();
          
          // Skip if too similar and heading hasn't changed much
          if (similarity > 0.95 && headingDiff < 10) {
            shouldKeep = false;
            removedCount++;
            print('REMOVED waypoint ${i+1}: similarity=${similarity.toStringAsFixed(3)}, heading_diff=${headingDiff.toStringAsFixed(1)}°');
          } else {
            keepReason = 'UNIQUE (similarity=${similarity.toStringAsFixed(3)}, heading_diff=${headingDiff.toStringAsFixed(1)}°)';
          }
        } else {
          keepReason = 'FIRST in filtered list';
        }
      }
      
      if (shouldKeep) {
        filteredWaypoints.add(_waypoints[i]);
        print('KEPT waypoint ${i+1}: $keepReason');
      }
    }
    
    // Update sequence numbers while preserving ALL data including people detection
    for (int i = 0; i < filteredWaypoints.length; i++) {
      filteredWaypoints[i] = PathWaypoint(
        id: filteredWaypoints[i].id,
        embedding: filteredWaypoints[i].embedding,
        heading: filteredWaypoints[i].heading,
        headingChange: filteredWaypoints[i].headingChange,
        turnType: filteredWaypoints[i].turnType,
        isDecisionPoint: filteredWaypoints[i].isDecisionPoint,
        landmarkDescription: filteredWaypoints[i].landmarkDescription,
        distanceFromPrevious: filteredWaypoints[i].distanceFromPrevious,
        timestamp: filteredWaypoints[i].timestamp,
        sequenceNumber: i,
        // 🐛 FIX: Preserve people detection data during filtering
        peopleDetected: filteredWaypoints[i].peopleDetected,
        peopleCount: filteredWaypoints[i].peopleCount,
        peopleConfidenceScores: filteredWaypoints[i].peopleConfidenceScores,
      );
    }
    
    _waypoints = filteredWaypoints;
    print('FILTERING SUMMARY:');
    print('Original waypoints: ${_waypoints.length + removedCount}');
    print('Removed duplicates: $removedCount');
    print('Final waypoints: ${_waypoints.length}');
    // Status message removed as requested
  }

  double _calculateCosineSimilarity(List<double> vec1, List<double> vec2) {
    if (vec1.length != vec2.length) return 0.0;
    
    double dotProduct = 0.0;
    double normVec1 = 0.0;
    double normVec2 = 0.0;
    
    for (int i = 0; i < vec1.length; i++) {
      dotProduct += vec1[i] * vec2[i];
      normVec1 += vec1[i] * vec1[i];
      normVec2 += vec2[i] * vec2[i];
    }
    
    normVec1 = sqrt(normVec1);
    normVec2 = sqrt(normVec2);
    
    if (normVec1 == 0 || normVec2 == 0) return 0.0;
    
    return dotProduct / (normVec1 * normVec2);
  }

  NavigationPath createNavigationPath({
    required String name,
    required String startLocationId,
    required String endLocationId,
  }) {
    double estimatedDistance = _waypoints.fold(0.0, (sum, waypoint) =>
        sum + (waypoint.distanceFromPrevious ?? 0.0));
    
    // Step calculation removed - not reliable
    int estimatedSteps = 0;
    
    return NavigationPath(
      id: _currentPathId ?? _uuid.v4(),
      name: name,
      startLocationId: startLocationId,
      endLocationId: endLocationId,
      waypoints: _waypoints,
      estimatedDistance: estimatedDistance,
      estimatedSteps: estimatedSteps,
      createdAt: _recordingStartTime ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  void dispose() {
    _recordingTimer?.cancel();
    _compassSubscription?.cancel();
  }
}
