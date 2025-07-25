import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter_compass/flutter_compass.dart';
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
  
  // Tracking variables
  double _lastHeading = 0.0;
  int _sequenceNumber = 0;
  DateTime? _recordingStartTime;
  
  // Configuration
  final Duration _captureInterval = const Duration(seconds: 3);
  final double _significantHeadingChange = 15.0; // Minimum for decision point
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
      
      onStatusUpdate?.call('Starting path recording...');
      
      // Initialize compass
      await _initializeCompass();
      
      // Start periodic recording
      _recordingTimer = Timer.periodic(_captureInterval, (timer) {
        if (!_isRecording) {
          timer.cancel();
          return;
        }
        _captureWaypoint();
      });
      
      onStatusUpdate?.call('Recording started. Walk naturally along your path.');
      
    } catch (e) {
      _isRecording = false;
      onError?.call('Failed to start recording: $e');
    }
  }

  Future<void> stopRecording() async {
    if (!_isRecording) return;

    _isRecording = false;
    _recordingTimer?.cancel();
    _compassSubscription?.cancel();

    onStatusUpdate?.call('Recording stopped. Processing waypoints...');
    
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
    if (!_isRecording || _currentHeading == null) return;

    try {
      // Calculate heading change
      double headingChange = _calculateHeadingChange(_lastHeading, _currentHeading!);
      
      // Detect turn type
      TurnType turnType = _detectTurnType(headingChange);
      
      // Determine if this is a decision point
      bool isDecisionPoint = headingChange.abs() > _significantHeadingChange || 
                           manualDescription != null;

      // Capture image and generate embedding
      final image = await _cameraController.takePicture();
      final File imageFile = File(image.path);
      
      final List<double> embedding = await _clipService.generateImageEmbedding(imageFile);
      
      // Calculate distance from previous waypoint (simplified step counting)
      double? distanceFromPrevious;
      if (_waypoints.isNotEmpty) {
        // Rough estimation: 3 seconds walking ≈ 4-6 steps ≈ 3-4 meters
        distanceFromPrevious = _captureInterval.inSeconds * 1.2; // meters
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

    // Filter out redundant waypoints that are too similar
    List<PathWaypoint> filteredWaypoints = [];
    
    for (int i = 0; i < _waypoints.length; i++) {
      bool shouldKeep = true;
      
      // Always keep the first and last waypoints
      if (i == 0 || i == _waypoints.length - 1) {
        filteredWaypoints.add(_waypoints[i]);
        continue;
      }
      
      // Always keep decision points
      if (_waypoints[i].isDecisionPoint) {
        filteredWaypoints.add(_waypoints[i]);
        continue;
      }
      
      // Check similarity with previous kept waypoint
      if (filteredWaypoints.isNotEmpty) {
        PathWaypoint lastKept = filteredWaypoints.last;
        double similarity = _calculateCosineSimilarity(
          _waypoints[i].embedding, 
          lastKept.embedding
        );
        
        // Skip if too similar and heading hasn't changed much
        if (similarity > 0.95 && 
            (_waypoints[i].heading - lastKept.heading).abs() < 10) {
          shouldKeep = false;
        }
      }
      
      if (shouldKeep) {
        filteredWaypoints.add(_waypoints[i]);
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
    onStatusUpdate?.call('Filtered to ${_waypoints.length} key waypoints');
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
    
    int estimatedSteps = (estimatedDistance * 1.3).round(); // Rough conversion
    
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
