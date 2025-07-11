import 'dart:async';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';

import 'supabase_service.dart';
import 'pathfinding_service.dart';
import 'dead_reckoning_service.dart';

enum NavigationState {
  idle,
  locating,
  selectingDestination,
  planning,
  navigating,
  reconfirming,
  lost,
  completed,
}

enum NavigationMode {
  standard,    // Basic pathfinding
  enhanced,    // With enhanced sensors
  training,    // "Teach by walking" mode
}

class NavigationProgress {
  final NavigationStep currentStep;
  final NavigationStep? nextStep;
  final double progressPercent;
  final double distanceRemaining;
  final int stepsRemaining;
  final Duration estimatedTimeRemaining;
  final Position? currentPosition;
  final double confidence;

  NavigationProgress({
    required this.currentStep,
    this.nextStep,
    required this.progressPercent,
    required this.distanceRemaining,
    required this.stepsRemaining,
    required this.estimatedTimeRemaining,
    this.currentPosition,
    required this.confidence,
  });
}

class EnhancedNavigationService {
  // Core services
  final SupabaseService _supabaseService = SupabaseService();
  final PathfindingService _pathfindingService = PathfindingService();
  final DeadReckoningService _deadReckoningService = DeadReckoningService();
  final FlutterTts _tts = FlutterTts();

  // State management
  NavigationState _state = NavigationState.idle;
  NavigationMode _mode = NavigationMode.enhanced;
  NavigationRoute? _currentRoute;
  String? _currentMapId;
  NavigationNode? _currentNode;
  Timer? _navigationTimer;
  CameraController? _cameraController;
  bool _isProcessingFrame = false;

  // Configuration
  static const Duration _sensorScanInterval = Duration(seconds: 5); // Reduced frequency
  static const double _arrivalThreshold = 2.0; // meters
  static const double _positionDeviationThreshold = 3.0; // meters
  static const int _maxLostRecoveryAttempts = 3;
  int _lostRecoveryAttempts = 0;

  // Event streams
  final StreamController<NavigationState> _stateController = StreamController.broadcast();
  final StreamController<NavigationProgress> _progressController = StreamController.broadcast();
  final StreamController<String> _instructionController = StreamController.broadcast();
  final StreamController<String> _errorController = StreamController.broadcast();

  // Public streams
  Stream<NavigationState> get stateStream => _stateController.stream;
  Stream<NavigationProgress> get progressStream => _progressController.stream;
  Stream<String> get instructionStream => _instructionController.stream;
  Stream<String> get errorStream => _errorController.stream;

  // Getters
  NavigationState get currentState => _state;
  NavigationMode get currentMode => _mode;
  NavigationRoute? get currentRoute => _currentRoute;
  bool get isNavigating => _state == NavigationState.navigating;

  Future<bool> initialize() async {
    try {
      print('EnhancedNavigationService: Initializing...');
      
      // Request permissions
      await _requestPermissions();
      
      // Initialize TTS
      await _initializeTTS();
      
      // Initialize camera
      final cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        _cameraController = CameraController(
          cameras.first,
          ResolutionPreset.high,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.yuv420,
        );
        await _cameraController!.initialize();
      }
      
      // Initialize dead reckoning
      await _deadReckoningService.initialize();
      
      print('EnhancedNavigationService: Initialized successfully');
      return true;
    } catch (e) {
      _emitError('Initialization failed: $e');
      return false;
    }
  }

  Future<void> _requestPermissions() async {
    Map<Permission, PermissionStatus> permissions = await [
      Permission.camera,
      Permission.sensors,
      Permission.activityRecognition,
      Permission.speech,
    ].request();

    for (var permission in permissions.entries) {
      if (permission.value != PermissionStatus.granted) {
        print('Permission ${permission.key} denied');
      }
    }
  }

  Future<void> _initializeTTS() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.9);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  void setNavigationMode(NavigationMode mode) {
    _mode = mode;
    print('Navigation mode set to: $mode');
  }

  // MAIN NAVIGATION FLOW

  // Step 1: Localize user position
  Future<NavigationNode?> localizePosition(String mapId) async {
    _setState(NavigationState.locating);
    _currentMapId = mapId;

    try {
      _speak('Starting location detection. Please rotate slowly in a circle while I scan your surroundings.');

      // Load navigation data for the map
      final navigationData = await _supabaseService.getNavigationData(mapId);
      final nodes = navigationData['nodes'] as List<Map<String, dynamic>>;
      final connections = navigationData['connections'] as List<Map<String, dynamic>>;

      if (nodes.isEmpty) {
        _emitError('No navigation nodes found for this map');
        return null;
      }

      // Initialize pathfinding service with map data
      List<NavigationNode> navNodes = nodes.map((n) => NavigationNode.fromJson(n)).toList();
      List<NavigationConnection> navConnections = connections.map((c) => NavigationConnection.fromJson(c)).toList();
      _pathfindingService.initialize(navNodes, navConnections);

      // Perform 360° scanning for localization (using existing recognition logic)
      NavigationNode? detectedNode = await _perform360ScanLocalization(mapId);
      
      if (detectedNode != null) {
        _currentNode = detectedNode;
        _speak('Location detected: ${detectedNode.name}. You are now ready for navigation.');
        
        // Initialize dead reckoning from current position
        Position initialPosition = Position(
          x: detectedNode.x,
          y: detectedNode.y,
          heading: 0.0, // Will be updated by compass
          timestamp: DateTime.now(),
          confidence: 1.0,
        );
        _deadReckoningService.startTracking(initialPosition);
        
        _setState(NavigationState.selectingDestination);
        return detectedNode;
      } else {
        _emitError('Could not determine your location. Please try again in a different area.');
        _setState(NavigationState.idle);
        return null;
      }
    } catch (e) {
      _emitError('Localization failed: $e');
      _setState(NavigationState.idle);
      return null;
    }
  }

  // Step 2: Get available destinations
  Future<List<NavigationNode>> getAvailableDestinations() async {
    if (_currentNode == null || _currentMapId == null) {
      return [];
    }

    return _pathfindingService.getAllDestinations(_currentNode!.id);
  }

  // Step 3: Start navigation to destination
  Future<bool> startNavigation(NavigationNode destination) async {
    if (_currentNode == null) {
      _emitError('Current location not determined. Please localize first.');
      return false;
    }

    _setState(NavigationState.planning);

    try {
      // Find route using pathfinding
      NavigationRoute? route = _pathfindingService.findRoute(_currentNode!.id, destination.id);
      
      if (route == null) {
        _emitError('No route found to ${destination.name}');
        _setState(NavigationState.selectingDestination);
        return false;
      }

      _currentRoute = route;
      
      // Announce route
      String routeAnnouncement = 'Route to ${destination.name} found. ';
      routeAnnouncement += '${route.steps.length} segments, ';
      routeAnnouncement += 'approximately ${route.totalDistance.toStringAsFixed(0)} meters. ';
      routeAnnouncement += 'Starting navigation.';
      
      _speak(routeAnnouncement);
      
      // Start the navigation loop
      _setState(NavigationState.navigating);
      _startNavigationLoop();
      
      return true;
    } catch (e) {
      _emitError('Failed to start navigation: $e');
      _setState(NavigationState.selectingDestination);
      return false;
    }
  }

  // ENHANCED NAVIGATION LOOP
  void _startNavigationLoop() {
    _navigationTimer = Timer.periodic(Duration(milliseconds: 500), (timer) {
      _updateNavigationProgress();
    });

    // Start enhanced sensor scanning
    if (_mode == NavigationMode.enhanced) {
      _startEnhancedScanning();
    }

    // Announce first instruction
    if (_currentRoute?.currentStep != null) {
      _announceCurrentInstruction();
    }
  }

  void _startEnhancedScanning() {
    // Enhanced sensor scanning could be added here in the future
    // For now, just use basic dead reckoning
  }

  void _updateNavigationProgress() {
    if (_currentRoute == null || _currentRoute!.isComplete) {
      _navigationComplete();
      return;
    }

    NavigationStep currentStep = _currentRoute!.currentStep!;
    Position? currentPosition = _deadReckoningService.currentPosition;

    if (currentPosition == null) return;

    // Check if we've reached the current step's destination
    double distanceToTarget = sqrt(
      pow(currentPosition.x - currentStep.toNode.x, 2) + 
      pow(currentPosition.y - currentStep.toNode.y, 2)
    );

    if (distanceToTarget <= _arrivalThreshold) {
      _arriveAtNode(currentStep.toNode);
      return;
    }

    // Check for significant position deviation
    if (currentPosition.confidence < 0.5) {
      _setState(NavigationState.reconfirming);
      _performEnhancedLocalization();
      return;
    }

    // Emit progress update
    double stepProgress = _getEstimatedProgressAlongStep();
    NavigationProgress progress = NavigationProgress(
      currentStep: currentStep,
      nextStep: _currentRoute!.nextStep,
      progressPercent: stepProgress,
      distanceRemaining: _currentRoute!.totalDistance - (stepProgress * currentStep.distanceMeters),
      stepsRemaining: _currentRoute!.totalSteps,
      estimatedTimeRemaining: _currentRoute!.estimatedDuration,
      currentPosition: currentPosition,
      confidence: currentPosition.confidence,
    );

    _progressController.add(progress);
  }

  double _getEstimatedProgressAlongStep() {
    if (_currentRoute?.currentStep == null) return 0.0;
    
    NavigationStep currentStep = _currentRoute!.currentStep!;
    Position? currentPosition = _deadReckoningService.currentPosition;
    
    if (currentPosition == null) return 0.0;

    // Calculate progress based on distance to start vs total step distance
    double distanceFromStart = sqrt(
      pow(currentPosition.x - currentStep.fromNode.x, 2) + 
      pow(currentPosition.y - currentStep.fromNode.y, 2)
    );

    return min(1.0, distanceFromStart / currentStep.distanceMeters);
  }

  void _arriveAtNode(NavigationNode node) {
    _speak('Arrived at ${node.name}');
    
    // Update current node
    _currentNode = node;
    
    // Update dead reckoning with confirmed position
    Position confirmedPosition = Position(
      x: node.x,
      y: node.y,
      heading: _deadReckoningService.currentPosition?.heading ?? 0.0,
      timestamp: DateTime.now(),
      confidence: 1.0,
    );
    _deadReckoningService.updateKnownPosition(confirmedPosition);
    
    // Move to next step
    _currentRoute = _currentRoute!.removeFirstStep();
    
    if (_currentRoute!.isComplete) {
      _navigationComplete();
    } else {
      _announceCurrentInstruction();
    }
    
    _lostRecoveryAttempts = 0; // Reset recovery attempts
  }

  void _announceCurrentInstruction() {
    if (_currentRoute?.currentStep == null) return;
    
    NavigationStep step = _currentRoute!.currentStep!;
    String instruction = step.detailedInstruction;
    
    _speak(instruction);
    _instructionController.add(instruction);
  }

  Future<void> _performEnhancedLocalization() async {
    if (_cameraController == null || _isProcessingFrame || !_cameraController!.value.isInitialized) return;
    if (_cameraController!.value.isStreamingImages) return;
    
    try {
      _speak('I need to verify your location. Please hold your phone steady for a moment.');
      _isProcessingFrame = true;
      
      await _cameraController?.startImageStream((image) async {
        await _cameraController?.stopImageStream(); // Stop immediately after getting one frame

        try {
          // Try to match against known locations (using existing recognition system)
          // This would integrate with your existing recognition_screen logic
          NavigationNode? confirmedNode = await _attemptVisualLocalization(image);
          
          if (confirmedNode != null) {
            _currentNode = confirmedNode;
            Position confirmedPosition = Position(
              x: confirmedNode.x,
              y: confirmedNode.y,
              heading: _deadReckoningService.currentPosition?.heading ?? 0.0,
              timestamp: DateTime.now(),
              confidence: 1.0,
            );
            _deadReckoningService.updateKnownPosition(confirmedPosition);
            
            _speak('Location confirmed. Continuing navigation.');
            _setState(NavigationState.navigating);
            _lostRecoveryAttempts = 0;
            
            // Recalculate route if needed
            if (_currentRoute != null && !_currentRoute!.isComplete) {
              NavigationStep? currentStep = _currentRoute!.currentStep;
              if (currentStep != null && currentStep.fromNode.id != confirmedNode.id) {
                _recalculateRoute();
              }
            }
          } else {
            _recoverFromLostState();
          }
        } catch (e) {
          print('Enhanced localization error: $e');
          _recoverFromLostState();
        } finally {
          _isProcessingFrame = false;
        }
      });
    } catch (e) {
      print('Enhanced localization error: $e');
      _recoverFromLostState();
      _isProcessingFrame = false; // Ensure flag is reset on outer error
    }
  }

  void _recoverFromLostState() {
    _lostRecoveryAttempts++;
    
    if (_lostRecoveryAttempts >= _maxLostRecoveryAttempts) {
      _setState(NavigationState.lost);
      _speak('I\'m having trouble determining your exact location. Please move to a recognizable landmark and try to localize again.');
      _stopNavigation();
    } else {
      _speak('Let me try to locate you again. Please rotate slowly while I scan.');
      // Continue navigation but with reduced confidence
      _setState(NavigationState.navigating);
    }
  }

  Future<void> _recalculateRoute() async {
    if (_currentNode == null || _currentRoute == null) return;
    
    NavigationStep lastStep = _currentRoute!.steps.last;
    NavigationNode destination = lastStep.toNode;
    
    NavigationRoute? newRoute = _pathfindingService.findRoute(_currentNode!.id, destination.id);
    if (newRoute != null) {
      _currentRoute = newRoute;
      _speak('Route recalculated. Continuing to ${destination.name}.');
      _announceCurrentInstruction();
    }
  }

  void _navigationComplete() {
    _setState(NavigationState.completed);
    _speak('Navigation completed. You have arrived at your destination.');
    _stopNavigation();
  }

  void _stopNavigation() {
    _navigationTimer?.cancel();
    _deadReckoningService.pauseTracking();
    _currentRoute = null;
  }

  // TRAINING MODE (Teach by Walking)
  Future<void> startTrainingMode(String mapId, NavigationNode startNode, NavigationNode endNode) async {
    _setState(NavigationState.navigating);
    _mode = NavigationMode.training;
    
    _speak('Training mode activated. Please walk normally from ${startNode.name} to ${endNode.name}. I will record the path.');
    
    // Start recording movement
    Position startPosition = Position(
      x: startNode.x,
      y: startNode.y,
      heading: 0.0,
      timestamp: DateTime.now(),
      confidence: 1.0,
    );
    _deadReckoningService.startTracking(startPosition);
    
    // Record YOLO detections along the way
    List<Map<String, dynamic>> trainingDetections = [];
    
    Timer.periodic(Duration(seconds: 2), (timer) async {
      if (_state != NavigationState.navigating) {
        timer.cancel();
        return;
      }
      
      if (_cameraController == null || _isProcessingFrame || !_cameraController!.value.isInitialized) return;
      if (_cameraController!.value.isStreamingImages) return;

      _isProcessingFrame = true;

      await _cameraController?.startImageStream((image) async {
        await _cameraController?.stopImageStream();
        try {
          // Removed YOLO detection logic
          // List<DetectedObject> detections = await _yoloService.detectObjects(image);
          // for (var detection in detections) {
          //   trainingDetections.add({
          //     'type': detection.className,
          //     'confidence': detection.confidence,
          //     'side': 'center', // Simplified for now
          //     'position_meters': _getEstimatedWalkingDistance(),
          //     'timestamp': DateTime.now().toIso8601String(),
          //   });
          // }
        } catch (e) {
          print('Error processing training frame: $e');
        } finally {
          _isProcessingFrame = false;
        }
      });
    });
    
    // When training is complete (called externally), save the session
  }

  Future<void> completeTrainingSession(NavigationNode endNode, String instruction) async {
    if (_mode != NavigationMode.training) return;
    
    Position? endPosition = _deadReckoningService.currentPosition;
    if (endPosition == null) return;
    
    // Get movement data
    var movementData = _deadReckoningService.getMovementSinceLastKnown();
    if (movementData == null) return;
    
    // Save the training session
    await _supabaseService.saveWalkingSession(
      mapId: _currentMapId!,
      startNodeId: _currentNode!.id,
      endNodeId: endNode.id,
      distanceMeters: movementData.distance,
      stepCount: movementData.stepCount,
      averageHeading: movementData.averageHeading,
      instruction: instruction,
      detectedObjects: [], // Would collect from the training timer above
    );
    
    _speak('Training session completed. Path data has been recorded.');
    _mode = NavigationMode.enhanced;
    _setState(NavigationState.idle);
  }

  // UTILITY METHODS
  double _getEstimatedWalkingDistance() {
    var movement = _deadReckoningService.getMovementSinceLastKnown();
    return movement?.distance ?? 0.0;
  }

  Future<NavigationNode?> _perform360ScanLocalization(String mapId) async {
    // This would integrate with your existing recognition system
    // For now, returning null - implement with your recognition logic
    return null;
  }

  Future<NavigationNode?> _attemptVisualLocalization(CameraImage image) async {
    // This would integrate with your existing recognition system  
    // For now, returning null - implement with your recognition logic
    return null;
  }

  void _setState(NavigationState state) {
    _state = state;
    _stateController.add(state);
    print('Navigation state changed to: $state');
  }

  void _speak(String text) {
    print('TTS: $text');
    _tts.speak(text);
  }

  void _emitError(String error) {
    print('Navigation error: $error');
    _errorController.add(error);
  }

  // PUBLIC CONTROL METHODS
  void pauseNavigation() {
    if (_state == NavigationState.navigating) {
      _navigationTimer?.cancel();
      _deadReckoningService.pauseTracking();
      _speak('Navigation paused.');
    }
  }

  void resumeNavigation() {
    if (_state == NavigationState.navigating && _currentRoute != null) {
      _startNavigationLoop();
      Position? currentPos = _deadReckoningService.currentPosition;
      if (currentPos != null) {
        _deadReckoningService.resumeTracking(currentPos);
      }
      _speak('Navigation resumed.');
    }
  }

  void cancelNavigation() {
    _stopNavigation();
    _setState(NavigationState.idle);
    _speak('Navigation cancelled.');
  }

  void dispose() {
    _navigationTimer?.cancel();
    _stateController.close();
    _progressController.close();
    _instructionController.close();
    _errorController.close();
    _deadReckoningService.dispose();
    _cameraController?.dispose();
  }
} 