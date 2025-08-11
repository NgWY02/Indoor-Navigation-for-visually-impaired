import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:pedometer/pedometer.dart';
import '../services/clip_service.dart';
import '../models/path_models.dart';
import 'package:uuid/uuid.dart';

class ContinuousPathRecorder {
  final ClipService _clipService;
  final CameraController _cameraController;
  
  // Recording state
  bool _isRecording = false;
  List<PathWaypoint> _waypoints = [];
  Timer? _recordingTimer;
  StreamSubscription<CompassEvent>? _compassSubscription;
  
  // 🚶 STEP COUNTER: Real distance tracking
  StreamSubscription<StepCount>? _stepCountSubscription;
  StreamSubscription<PedestrianStatus>? _pedestrianStatusSubscription;
  int _stepsAtLastWaypoint = 0;
  int _currentTotalSteps = 0;
  bool _isUserWalking = false;
  static const double _averageStrideLength = 0.7; // meters per step
  
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
  int get waypointCount => _waypoints.length;

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
      _waypoints.clear();
      _sequenceNumber = 0;
      _recordingStartTime = DateTime.now();
      
      // 🚶 Reset step counter state for new recording
      _stepsAtLastWaypoint = 0; // Will be set by first step counter reading
      _currentTotalSteps = 0;
      _isUserWalking = false;
      
      onStatusUpdate?.call('Starting path recording...');
      
      // Initialize compass
      await _initializeCompass();
      
      // 🚶 Initialize step counter for real distance tracking
      await _initializeStepCounter();
      
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
      
      onStatusUpdate?.call('Recording started. Walk naturally along your path.');
      
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
    
    _stepCountSubscription?.cancel();
    _stepCountSubscription = null;
    
    _pedestrianStatusSubscription?.cancel();
    _pedestrianStatusSubscription = null;

    print('✅ All timers cancelled, processing waypoints...');
    onStatusUpdate?.call('Recording stopped. Processing waypoints...');
    
    //Give any in-flight waypoint captures time to check the flag
    await Future.delayed(const Duration(milliseconds: 100));
    
    // Process and filter waypoints
    await _processRecordedWaypoints();
    
    onStatusUpdate?.call('Recording complete. Captured ${_waypoints.length} waypoints.');
  }

  Future<void> pauseRecording() async {
    if (!_isRecording) return;
    
    _recordingTimer?.cancel();
    onStatusUpdate?.call('Recording paused. Tap resume to continue.');
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
    
    onStatusUpdate?.call('Recording resumed.');
  }

  void addManualWaypoint(String description) {
    if (!_isRecording) return;
    
    // Capture a waypoint immediately with custom description
    _captureWaypoint(manualDescription: description);
  }

  /// 🚶 Initialize step counter for real distance measurement
  Future<void> _initializeStepCounter() async {
    try {
      // Initialize step counting stream
      _stepCountSubscription = Pedometer.stepCountStream.listen(
        (StepCount event) {
          _currentTotalSteps = event.steps;
          print('Recording - Total steps: $_currentTotalSteps');
          
          // Set baseline on first step count reading (not immediately)
          if (_stepsAtLastWaypoint == 0) {
            _stepsAtLastWaypoint = _currentTotalSteps;
            print('🎯 Step baseline set on first reading: $_stepsAtLastWaypoint steps');
          }
        },
        onError: (error) {
          print('Step counter error during recording: $error');
          onError?.call('Step counter unavailable. Using time-based distance estimation.');
        },
      );

      // Initialize pedestrian status detection
      _pedestrianStatusSubscription = Pedometer.pedestrianStatusStream.listen(
        (PedestrianStatus event) {
          _isUserWalking = (event.status == 'walking');
          print('Recording - Walking status: ${_isUserWalking ? "WALKING" : "STOPPED"}');
        },
        onError: (error) {
          print('Pedestrian status error during recording: $error');
        },
      );

      // DON'T set baseline here - wait for first step count reading
      print('Step counter stream initialized - waiting for first reading...');
      
    } catch (e) {
      print('Failed to initialize step counter during recording: $e');
      onError?.call('Step counter unavailable. Recording will use time-based distance estimation.');
    }
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
    // 🚨 DOUBLE-CHECK: Ensure we're still recording before any processing
    if (!_isRecording || _currentHeading == null) return;

    try {
      // 🚨 ADDITIONAL CHECK: Verify recording state hasn't changed during execution
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
      final List<double> embedding = await _clipService.generatePreprocessedEmbedding(imageFile);
      
      // Calculate REAL distance from previous waypoint using step counter
      double? distanceFromPrevious;
      if (_waypoints.isNotEmpty) {
        print('DISTANCE DEBUG:');
        print('Current total steps: $_currentTotalSteps');
        print('Steps at last waypoint: $_stepsAtLastWaypoint');
        
        // Check if step counter baseline has been established
        if (_stepsAtLastWaypoint > 0 && _currentTotalSteps > 0) {
          final stepsSinceLastWaypoint = _currentTotalSteps - _stepsAtLastWaypoint;
          print('   Steps since last waypoint: $stepsSinceLastWaypoint');
          
          if (stepsSinceLastWaypoint > 0) {
            // Real step-based distance calculation
            distanceFromPrevious = stepsSinceLastWaypoint * _averageStrideLength;
            print('📏 REAL distance: ${stepsSinceLastWaypoint} steps = ${distanceFromPrevious.toStringAsFixed(1)}m');
            
            // Update baseline for next waypoint
            _stepsAtLastWaypoint = _currentTotalSteps;
          } else {
            // No steps since last waypoint - user might be standing still
            distanceFromPrevious = 0.5; // Very small distance for stationary waypoints
            print('No movement detected - using minimal distance: ${distanceFromPrevious}m');
          }
        } else {
          // Step counter not ready yet - use time-based fallback
          distanceFromPrevious = _captureInterval.inSeconds * 1.2;
          print('⚠️ Step counter not ready, using time-based estimation: ${distanceFromPrevious.toStringAsFixed(1)}m');
        }
      }

      // Create waypoint
      final waypoint = PathWaypoint(
        id: _uuid.v4(),
        embedding: embedding,
        heading: _normalizeHeading(_currentHeading!),
        headingChange: headingChange,
        turnType: turnType,
        isDecisionPoint: isDecisionPoint,
        landmarkDescription: manualDescription ?? _generateAutoDescription(turnType, headingChange),
        distanceFromPrevious: distanceFromPrevious,
        timestamp: DateTime.now(),
        sequenceNumber: _sequenceNumber++,
      );

      _waypoints.add(waypoint);
      _lastHeading = _normalizeHeading(_currentHeading!);
      
      // Clean up temp image
      await imageFile.delete();
      
      // Notify callback
      onWaypointCaptured?.call(waypoint);
      
      // Update status
      String statusMessage = 'Waypoint ${_waypoints.length} captured';
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

  Future<void> _processRecordedWaypoints() async {
    if (_waypoints.isEmpty) return;

    print('🔄 Processing ${_waypoints.length} recorded waypoints...');
    
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
          if (similarity > 0.92 && headingDiff < 10) {
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
    
    // Update sequence numbers
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
      );
    }
    
    _waypoints = filteredWaypoints;
    print('📊 FILTERING SUMMARY:');
    print('   📥 Original waypoints: ${_waypoints.length + removedCount}');
    print('   ❌ Removed duplicates: $removedCount');
    print('   📤 Final waypoints: ${_waypoints.length}');
    onStatusUpdate?.call('Filtered to ${_waypoints.length} key waypoints (removed $removedCount duplicates)');
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
    
    // 🚶 Proper step calculation: distance ÷ stride length
    int estimatedSteps = (estimatedDistance / _averageStrideLength).round();
    
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
    _stepCountSubscription?.cancel();
    _pedestrianStatusSubscription?.cancel();
  }
}
