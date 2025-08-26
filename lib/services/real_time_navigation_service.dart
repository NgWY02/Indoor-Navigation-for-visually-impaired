import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:pedometer/pedometer.dart';
import '../services/clip_service.dart';
import '../services/position_localization_service.dart';
import '../models/path_models.dart';

enum NavigationState {
  idle,
  initialOrientation,
  navigating,
  approachingWaypoint,
  reorientingUser,
  destinationReached,
  offTrack,
}

class RealTimeNavigationService {
  final ClipService _clipService;
  final FlutterTts _tts;
  
  // Navigation state
  NavigationRoute? _currentRoute;
  NavigationState _state = NavigationState.idle;
  int _currentWaypointIndex = 0;
  int _currentSequenceNumber = 0; 
  Timer? _navigationTimer;
  StreamSubscription<CompassEvent>? _compassSubscription;
  
  // STEP COUNTER SOLUTION: Movement validation with REAL distances
  StreamSubscription<StepCount>? _stepCountSubscription;
  StreamSubscription<PedestrianStatus>? _pedestrianStatusSubscription;
  int _stepsAtLastWaypoint = 0;
  int _currentTotalSteps = 0;

  bool _isUserWalking = false;
  // Note: Now uses real step-based distances from path recording
  
  // Tracking
  double? _currentHeading;
  List<double>? _lastCapturedEmbedding;
  DateTime _lastGuidanceTime = DateTime.now();
  
  // Configuration
  static const double _waypointReachedThresholdDefault = 0.88; 
  static const double _offTrackThreshold = 0.4; 
  static const Duration _guidanceInterval = Duration(seconds: 1);
  static const Duration _repositioningTimeout = Duration(seconds: 10);
  
  // Dynamic threshold and audio management
  double _currentWaypointThreshold = 0.88;
  bool _peopleDetectedInLastFrame = false;
  String? _lastSpokenInstruction;
  DateTime? _lastInstructionTime;
  
  // Off-track management for VIP users
  int _consecutiveOffTrackCount = 0;
  static const int _offTrackThreshold3Times = 3;
  
  // Callbacks
  final Function(NavigationState state)? onStateChanged;
  final Function(String message)? onStatusUpdate;
  final Function(NavigationInstruction instruction)? onInstructionUpdate;
  final Function(String error)? onError;
  final Function(String debugInfo)? onDebugUpdate; // 🐛 Debug display callback

  RealTimeNavigationService({
    required ClipService clipService,
    this.onStateChanged,
    this.onStatusUpdate,
    this.onInstructionUpdate,
    this.onError,
    this.onDebugUpdate, 
  }) : _clipService = clipService, _tts = FlutterTts() {
    _initializeTTS();
    // TEMPORARILY DISABLED: Step counter for testing
    // _initializeStepCounter();
    _updateDebugDisplay('STEP COUNTER DISABLED\n✅ Using visual-only navigation\n👁️ Only visual similarity required');
  }

  // Public getters
  NavigationState get state => _state;
  NavigationRoute? get currentRoute => _currentRoute;
  int get currentWaypointIndex => _currentWaypointIndex;
  double get progressPercentage => _currentRoute != null 
      ? ((_currentWaypointIndex + 1) / _currentRoute!.waypoints.length) * 100 
      : 0.0;
  
  /// Get the current compass heading (null if not available)
  double? get currentHeading => _currentHeading;
  
  /// Get the target heading for initial orientation (null if not in orientation phase)
  double? get targetHeading {
    if (_state != NavigationState.initialOrientation || _currentRoute == null) {
      return null;
    }
    final firstWaypoint = _getWaypointBySequence(0);
    return firstWaypoint?.heading;
  }

  /// Start navigation along the selected route
  /// 
  /// This will first enter an initial orientation phase where the user is guided
  /// to face the correct direction for the first waypoint using compass readings.
  /// Once properly oriented, actual navigation begins.
  /// 
  /// The orientation phase can be skipped by calling [skipOrientationAndStartNavigation].
  Future<void> startNavigation(NavigationRoute route) async {
    if (_state == NavigationState.navigating || _state == NavigationState.initialOrientation) {
      onError?.call('Navigation already in progress');
      return;
    }

    try {
      _currentRoute = route;
      _currentWaypointIndex = 0;
      _currentSequenceNumber = 0;
      
      // Reset audio tracking for new navigation session
      _lastSpokenInstruction = null;
      _lastInstructionTime = null;
      _peopleDetectedInLastFrame = false;
      _currentWaypointThreshold = _waypointReachedThresholdDefault;
      
      // Reset off-track counter for new navigation session
      _consecutiveOffTrackCount = 0;
      
      // START WITH INITIAL ORIENTATION instead of direct navigation
      _setState(NavigationState.initialOrientation);
      
      // Initialize step counter for this navigation session
      // DON'T set baseline immediately - wait for first step count reading
      print('🚀 Navigation started - Starting orientation phase');
      print('⏳ Waiting for compass reading to guide initial direction...');
      
      // 🐛 Send navigation start info to screen
      _updateDebugDisplay('🚀 NAVIGATION STARTED\n🧭 ORIENTATION PHASE\n⏳ Waiting for compass...\n🎯 Destination: ${route.endNodeName}');
      
      onStatusUpdate?.call('Starting navigation to ${route.endNodeName}');
      await _speak('Navigation started. Let me help you face the right direction first.');
      
      // Initialize compass
      await _initializeCompass();
      
      // Start orientation guidance instead of navigation
      await _startInitialOrientation();
      
    } catch (e) {
      onError?.call('Failed to start navigation: $e');
    }
  }

  /// Stop navigation
  Future<void> stopNavigation() async {
    _navigationTimer?.cancel();
    _compassSubscription?.cancel();
    _stepCountSubscription?.cancel();
    _pedestrianStatusSubscription?.cancel();
    
    if (_currentRoute != null) {
      await _speak('Navigation stopped');
    }
    
    _currentRoute = null;
    _currentWaypointIndex = 0;
    _currentSequenceNumber = 0; 
    
    // Reset audio tracking and people detection state
    _lastSpokenInstruction = null;
    _lastInstructionTime = null;
    _peopleDetectedInLastFrame = false;
    _currentWaypointThreshold = _waypointReachedThresholdDefault;
    
    // Reset off-track counter
    _consecutiveOffTrackCount = 0;
    
    // Reset step counter state
    _stepsAtLastWaypoint = 0;
    _isUserWalking = false;
    
    _setState(NavigationState.idle);
    
    onStatusUpdate?.call('Navigation stopped');
  }

  /// 🧭 Start initial orientation phase - guide user to face the first waypoint direction
  Future<void> _startInitialOrientation() async {
    if (_currentRoute == null || _currentRoute!.waypoints.isEmpty) {
      onError?.call('No route or waypoints available for orientation');
      return;
    }

    // Get the first waypoint (sequence 0)
    final firstWaypoint = _getWaypointBySequence(0);
    if (firstWaypoint == null) {
      onError?.call('Cannot find first waypoint for orientation');
      return;
    }

    print('🧭 Starting initial orientation phase');
    print('🎯 Target heading for first waypoint: ${firstWaypoint.heading.toStringAsFixed(1)}°');
    
    _updateDebugDisplay('🧭 INITIAL ORIENTATION\n🎯 Target: ${firstWaypoint.heading.toStringAsFixed(1)}°\n⏳ Waiting for your compass reading...');
    
    await _speak('Please turn slowly until I tell you to stop. I will guide you to face the right direction.');
    onStatusUpdate?.call('Turn slowly - finding correct direction');
    
    // Start periodic orientation checking
    _navigationTimer = Timer.periodic(Duration(seconds: 1), (_) => _checkOrientation());
  }

  /// 🧭 Check if user is facing the correct direction for the first waypoint
  Future<void> _checkOrientation() async {
    if (_state != NavigationState.initialOrientation || _currentRoute == null) return;
    
    // Need compass reading
    if (_currentHeading == null) {
      print('⏳ Waiting for compass reading...');
      _updateDebugDisplay('🧭 ORIENTATION GUIDANCE:\n⏳ Waiting for compass reading...\n📱 Please ensure location services are enabled');
      return;
    }

    final firstWaypoint = _getWaypointBySequence(0);
    if (firstWaypoint == null) {
      print('❌ No first waypoint found');
      return;
    }

    final targetHeading = firstWaypoint.heading;
    final currentHeading = _currentHeading!;
    
    // Calculate the shortest angular difference
    final headingDifference = _calculateHeadingDifference(currentHeading, targetHeading);
    final absoluteDifference = headingDifference.abs();
    
    // Enhanced debugging
    print('🧭 ORIENTATION CHECK:');
    print('   📍 Current: ${currentHeading.toStringAsFixed(1)}°');
    print('   🎯 Target: ${targetHeading.toStringAsFixed(1)}°');
    print('   ↔️ Difference: ${headingDifference.toStringAsFixed(1)}° (abs: ${absoluteDifference.toStringAsFixed(1)}°)');
    print('   ✅ Within tolerance (≤5°): ${absoluteDifference <= 5.0}');
    
    // Update debug display with real-time orientation info
    _updateDebugDisplay('''
      🧭 ORIENTATION GUIDANCE:
      ━━━━━━━━━━━━━━━━━━━━
      📍 Current: ${currentHeading.toStringAsFixed(1)}°
      🎯 Target: ${targetHeading.toStringAsFixed(1)}°
      ↔️ Raw diff: ${headingDifference.toStringAsFixed(1)}°
      📐 Abs diff: ${absoluteDifference.toStringAsFixed(1)}°
      ${_getOrientationStatus(absoluteDifference)}
      ━━━━━━━━━━━━━━━━━━━━
    ''');
    
    // Check if user is facing the right direction (within 1° tolerance for exact precision)
    if (absoluteDifference <= 1.0) {
      print('✅ User is facing the correct direction! (diff: ${absoluteDifference.toStringAsFixed(1)}°)');
      await _orientationComplete();
    } else {
      // Provide turning guidance
      print('🔄 Need adjustment: ${headingDifference > 0 ? "turn right" : "turn left"} by ${absoluteDifference.toStringAsFixed(1)}°');
      await _provideOrientationGuidance(headingDifference, absoluteDifference);
    }
  }

  /// Calculate the shortest angular difference between current and target heading
  double _calculateHeadingDifference(double current, double target) {
    // Ensure both headings are normalized [0, 360)
    current = _normalizeHeading(current);
    target = _normalizeHeading(target);
    
    double difference = target - current;
    
    // Normalize to [-180, 180] range for shortest path
    if (difference > 180) {
      difference -= 360;
    } else if (difference < -180) {
      difference += 360;
    }
    
    // Debug the calculation
    print('🧮 HEADING CALCULATION:');
    print('   Current (normalized): ${current.toStringAsFixed(1)}°');
    print('   Target (normalized): ${target.toStringAsFixed(1)}°'); 
    print('   Raw difference: ${(target - current).toStringAsFixed(1)}°');
    print('   Normalized difference: ${difference.toStringAsFixed(1)}°');
    
    return difference;
  }

  double _normalizeHeading(double heading) {
    double normalized = heading % 360;
    if (normalized < 0) normalized += 360;
    return normalized;
  }

  /// Get user-friendly orientation status text
  String _getOrientationStatus(double absoluteDifference) {
    if (absoluteDifference <= 1) {
      return '✅ PERFECT! Ready to start (${absoluteDifference.toStringAsFixed(1)}° off)';
    } else if (absoluteDifference <= 5) {
      return '🔶 VERY CLOSE - fine adjustment needed (${absoluteDifference.toStringAsFixed(1)}° off)';
    } else if (absoluteDifference <= 15) {
      return '🔄 CLOSE - keep adjusting (${absoluteDifference.toStringAsFixed(1)}° off)';
    } else if (absoluteDifference <= 45) {
      return '🔄 TURNING - keep going (${absoluteDifference.toStringAsFixed(1)}° off)';
    } else {
      return '🔄 MAJOR TURN - continue turning (${absoluteDifference.toStringAsFixed(1)}° off)';
    }
  }

  /// Provide audio guidance for orientation
  Future<void> _provideOrientationGuidance(double headingDifference, double absoluteDifference) async {
    String guidance;
    
    if (absoluteDifference > 90) {
      // Large turn needed
      if (headingDifference > 0) {
        guidance = 'Turn right more';
      } else {
        guidance = 'Turn left more';
      }
    } else if (absoluteDifference > 45) {
      // Medium turn
      if (headingDifference > 0) {
        guidance = 'Turn right';
      } else {
        guidance = 'Turn left';
      }
    } else if (absoluteDifference > 5) {
      // Fine adjustment
      if (headingDifference > 0) {
        guidance = 'Turn right a little';
      } else {
        guidance = 'Turn left a little';
      }
    } else if (absoluteDifference > 1) {
      // Very fine adjustment
      if (headingDifference > 0) {
        guidance = 'Turn right just a tiny bit';
      } else {
        guidance = 'Turn left just a tiny bit';
      }
    } else {
      return; // Already handled in _checkOrientation
    }
    
    // Use smart speaking to avoid repetition
    await _speakSmart(guidance);
    onStatusUpdate?.call(guidance);
  }

  /// Called when user is correctly oriented - transition to actual navigation
  Future<void> _orientationComplete() async {
    _navigationTimer?.cancel(); // Stop orientation timer
    
    // First, tell the user they're correctly oriented and wait
    await _speak('Perfect! You are facing the right direction.');
    onStatusUpdate?.call('Direction confirmed - preparing navigation');
    
    print('✅ User is correctly oriented - confirming before navigation');
    _updateDebugDisplay('✅ ORIENTATION COMPLETE\n⏳ Preparing navigation...\n� Getting ready to start...');
    
    // Give user a moment to process the confirmation, then start navigation
    Timer(Duration(seconds: 2), () async {
      _setState(NavigationState.navigating);
      
      await _speak('Starting navigation now.');
      onStatusUpdate?.call('Navigation started');
      
      print('🚀 Starting actual navigation after orientation confirmation');
      _updateDebugDisplay('�🚀 NAVIGATION STARTED\n📍 Moving to waypoint guidance...');
      
      // Give initial navigation instruction
      await _updateNavigationInstruction();
      
      // Start periodic navigation guidance
      _navigationTimer = Timer.periodic(_guidanceInterval, (_) => _checkProgress());
    });
  }

  /// Allow user to skip orientation if they're confident about their direction
  /// 
  /// This can only be called during the initialOrientation state.
  /// Use this if the user already knows which direction to face.
  Future<void> skipOrientationAndStartNavigation() async {
    if (_state != NavigationState.initialOrientation) {
      onError?.call('Can only skip orientation during orientation phase');
      return;
    }
    
    print('⏩ User chose to skip orientation - starting navigation directly');
    await _speak('Skipping orientation. Starting navigation.');
    
    await _orientationComplete();
  }

  /// Process current camera frame for navigation guidance
  Future<void> processNavigationFrame(File imageFile) async {
    // Only process frames during actual navigation, not during orientation
    if (_state != NavigationState.navigating || _currentRoute == null) return;

    try {
      // Get current target waypoint by SEQUENCE NUMBER first to access people_detected info
      final targetWaypoint = _getWaypointBySequence(_currentSequenceNumber);
      if (targetWaypoint == null) {
        print('No waypoint found for sequence $_currentSequenceNumber');
        return;
      }
      
      // First, detect if people are present in the current frame
      final peopleDetection = await _clipService.detectPeople(imageFile);
      _peopleDetectedInLastFrame = peopleDetection.peopleDetected;
      
      // 🎯 SMART THRESHOLD ADJUSTMENT: Use waypoint's people_detected field for dynamic threshold
      // 🚪 HALLWAY FIX: Higher thresholds for waypoints BEFORE turns to prevent premature turn instructions
      final nextWaypoint = _getWaypointBySequence(_currentSequenceNumber + 1); // Look ahead to next waypoint
      _currentWaypointThreshold = _calculateDynamicThreshold(
        waypointHadPeople: targetWaypoint.peopleDetected,
        waypointPeopleCount: targetWaypoint.peopleCount,
        currentFrameHasPeople: peopleDetection.peopleDetected,
        currentFramePeopleCount: peopleDetection.peopleCount,
        nextWaypointTurnType: nextWaypoint?.turnType, // Check if NEXT waypoint requires turning
      );
      
      print('🎯 Navigation frame: Sequence $_currentSequenceNumber (landmark: ${targetWaypoint.landmarkDescription ?? 'No description'})');
      print('👥 Waypoint people info: ${targetWaypoint.peopleDetected} (${targetWaypoint.peopleCount} people when recorded)');
      print('👥 Current frame people: ${peopleDetection.peopleDetected} (count: ${peopleDetection.peopleCount})');
      print('🚪 Current waypoint: ${targetWaypoint.turnType.toString().split('.').last}, Next waypoint: ${nextWaypoint?.turnType.toString().split('.').last ?? 'none'} ${nextWaypoint?.turnType == TurnType.left || nextWaypoint?.turnType == TurnType.right || nextWaypoint?.turnType == TurnType.uTurn ? "(HALLWAY FIX APPLIED)" : ""}');
      print('🎯 Dynamic threshold: ${_currentWaypointThreshold.toStringAsFixed(2)} ${_getThresholdReason(targetWaypoint.peopleDetected, peopleDetection.peopleDetected, nextWaypoint?.turnType)}');
      
      // Generate embedding for current view WITHOUT people inpainting (faster for navigation)
      final currentEmbedding = await _clipService.generateNavigationEmbedding(imageFile);
      _lastCapturedEmbedding = currentEmbedding;
      
      // Calculate similarity with target waypoint
      final similarity = _calculateCosineSimilarity(currentEmbedding, targetWaypoint.embedding);
      print(' Similarity: ${similarity.toStringAsFixed(3)} (threshold: ${_currentWaypointThreshold.toStringAsFixed(2)})');
      
      // STEP COUNTER SOLUTION: Multi-condition waypoint validation
      final hasVisualMatch = similarity >= _currentWaypointThreshold;
      // TEMPORARILY DISABLED: Step validation for testing
      // final hasSufficientSteps = _hasWalkedSufficientSteps(targetWaypoint);
      final hasSufficientSteps = true; // Always true for testing
      
      print('🔍 Waypoint validation for sequence $_currentSequenceNumber:');
      print('   👁️ Visual match (≥${_currentWaypointThreshold.toStringAsFixed(2)}): $hasVisualMatch (${similarity.toStringAsFixed(3)})');
      print('   🚶 Sufficient steps: $hasSufficientSteps');
      print('   🎯 Target: ${targetWaypoint.landmarkDescription ?? 'No description'}, Turn: ${targetWaypoint.turnType}');
      print('   📍 Target sequence: ${targetWaypoint.sequenceNumber}');
      
      // Send enhanced debug information to screen (visible on phone)
      final validationInfo = '''
          🔍 WAYPOINT MATCHING:
          ━━━━━━━━━━━━━━━━━━━━
          📍 Target: ${targetWaypoint.landmarkDescription ?? 'No landmark'} (Seq ${_currentSequenceNumber})
          � Turn: ${targetWaypoint.turnType.toString().split('.').last.toUpperCase()} ${targetWaypoint.turnType == TurnType.left || targetWaypoint.turnType == TurnType.right || targetWaypoint.turnType == TurnType.uTurn ? "⚡HALLWAY FIX" : ""}
          �👥 When Recorded: ${targetWaypoint.peopleDetected ? "👥 YES (${targetWaypoint.peopleCount} people)" : "✅ NO people"}
          👥 Now Detecting: ${_peopleDetectedInLastFrame ? "👥 YES (${peopleDetection.peopleCount})" : "✅ NO people"} 
          🎯 Threshold: ${_currentWaypointThreshold.toStringAsFixed(2)} ${_getThresholdReason(targetWaypoint.peopleDetected, peopleDetection.peopleDetected, nextWaypoint?.turnType)}
          👁️ Similarity: ${similarity.toStringAsFixed(3)}
          ${hasVisualMatch ? "✅ MATCH!" : "❌ Too low"} (need ≥${_currentWaypointThreshold.toStringAsFixed(2)})
          🔍 Embedding: ${_lastCapturedEmbedding?.length ?? 0} dims
          ━━━━━━━━━━━━━━━━━━━━
      ''';

       _updateDebugDisplay(validationInfo);
      
      // Check if user has reached the waypoint (visual match only)
      if (hasVisualMatch && hasSufficientSteps) {
        print('✅ All conditions met - Waypoint reached!');
        // Reset off-track counter on successful waypoint match
        _consecutiveOffTrackCount = 0;
        await _waypointReached();
      } else if (similarity < _offTrackThreshold) {
        print('Off track - similarity too low (${similarity.toStringAsFixed(3)} < $_offTrackThreshold)');
        await _handleOffTrack();
      } else {
        // Provide guidance toward the target
        print('Conditions not met:');
        if (!hasVisualMatch) print('Visual similarity too low: ${similarity.toStringAsFixed(3)} (need ≥${_currentWaypointThreshold.toStringAsFixed(2)})');
        // DISABLED: Step validation
        // if (!hasSufficientSteps) print('Not enough steps walked');
        
        // Reset off-track counter when making progress (similarity above off-track threshold)
        _consecutiveOffTrackCount = 0;
        
        // DISABLED: Step-based guidance
        // if (hasVisualMatch && !hasSufficientSteps) {
        //   print('👀 Visual match but need more steps - Continue walking');
        // }
        await _provideGuidance(targetWaypoint, similarity);
      }
      
    } catch (e) {
      onError?.call('Error processing navigation frame: $e');
    }
  }

  /// Handle manual repositioning when user is lost
  Future<void> requestRepositioning() async {
    // Can't reposition during initial orientation
    if (_state == NavigationState.initialOrientation) {
      await _speak('Please complete the initial direction guidance first');
      return;
    }
    
    _setState(NavigationState.reorientingUser);
    
    await _speak('Let me help you get back on track. Please look around slowly.');
    onStatusUpdate?.call('Repositioning - look around slowly');
    
    // Give user time to reorient
    Timer(_repositioningTimeout, () {
      if (_state == NavigationState.reorientingUser) {
        _setState(NavigationState.navigating);
        onStatusUpdate?.call('Continue navigation');
      }
    });
  }

  // Private methods

  void _setState(NavigationState newState) {
    if (_state != newState) {
      _state = newState;
      onStateChanged?.call(_state);
    }
  }

  /// 🐛 Build debug information string for on-screen display
  String _buildDebugInfo() {
    final buffer = StringBuffer();
    buffer.writeln('🐛 NAVIGATION DEBUG:');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('State: $_state');
    
    if (_state == NavigationState.initialOrientation) {
      buffer.writeln('Phase: Initial Orientation');
      if (_currentHeading != null) {
        buffer.writeln('Current Heading: ${_currentHeading!.toStringAsFixed(1)}°');
      } else {
        buffer.writeln('Current Heading: Reading...');
      }
    } else {
      buffer.writeln('Current Sequence: $_currentSequenceNumber');
      buffer.writeln('Mode: Visual-only (Steps disabled)');
    }
    
    if (_currentRoute != null) {
      buffer.writeln('Route: ${_currentRoute!.endNodeName}');
      buffer.writeln('Total Waypoints: ${_currentRoute!.waypoints.length}');
      if (_state != NavigationState.initialOrientation) {
        final progress = ((_currentSequenceNumber / _getTotalSequenceNumbers()) * 100).round();
        buffer.writeln('Progress: $progress%');
      }
    }
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━');
    
    return buffer.toString();
  }

  /// Update debug display
  void _updateDebugDisplay(String additionalInfo) {
    if (onDebugUpdate == null) return;
    
    final debugInfo = _buildDebugInfo() + '\n' + additionalInfo;
    onDebugUpdate!(debugInfo);
  }

  Future<void> _initializeTTS() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.8);
    await _tts.setVolume(0.88);
    await _tts.setPitch(1.0);
  }

  Future<void> _initializeCompass() async {
    try {
      // Cancel any existing compass subscription
      _compassSubscription?.cancel();
      
      if (FlutterCompass.events != null) {
        print('🧭 Initializing compass...');
        _compassSubscription = FlutterCompass.events!.listen(
          (event) {
            if (event.heading != null) {
              final normalizedHeading = _normalizeHeading(event.heading!);
              _currentHeading = normalizedHeading;
              print('🧭 Raw heading: ${event.heading!.toStringAsFixed(1)}°, Normalized: ${normalizedHeading.toStringAsFixed(1)}°');
            } else {
              print('🧭 Compass reading is null');
            }
          },
          onError: (error) {
            print('🧭 Compass error: $error');
            onError?.call('Compass error: $error');
          },
        );
      } else {
        print('🧭 FlutterCompass.events is null - compass not available');
        onError?.call('Compass not available on this device');
      }
    } catch (e) {
      print('🧭 Failed to initialize compass: $e');
      onError?.call('Failed to initialize compass: $e');
    }
  }

  Future<void> _checkProgress() async {
    if (_currentRoute == null || _state != NavigationState.navigating) return;
    
    // Get current waypoint by sequence number (not array index!)
    final targetWaypoint = _getWaypointBySequence(_currentSequenceNumber);
    if (targetWaypoint == null) {
      print('No waypoint found for sequence $_currentSequenceNumber');
      return;
    }

    print('Current target: Sequence $_currentSequenceNumber (landmark: ${targetWaypoint.landmarkDescription ?? 'No description'})');
    
    // Periodically remind user of current instruction if no recent progress
    final timeSinceLastGuidance = DateTime.now().difference(_lastGuidanceTime);
    
    // Increased reminder interval from 15 to 30 seconds to reduce repetition
    if (timeSinceLastGuidance > Duration(seconds: 30)) {
      await _provideGuidance(targetWaypoint, 0.5); // Provide reminder
    }
  }

  /// Find waypoint by sequence number (proper navigation logic)
  PathWaypoint? _getWaypointBySequence(int sequenceNumber) {
    if (_currentRoute?.waypoints == null) return null;
    
    try {
      return _currentRoute!.waypoints.firstWhere(
        (waypoint) => waypoint.sequenceNumber == sequenceNumber,
      );
    } catch (e) {
      return null; // No waypoint found with this sequence number
    }
  }

  /// Get total number of waypoints in route (max sequence number)
  int _getTotalSequenceNumbers() {
    if (_currentRoute?.waypoints == null || _currentRoute!.waypoints.isEmpty) return 0;
    
    return _currentRoute!.waypoints
        .map((waypoint) => waypoint.sequenceNumber)
        .reduce((a, b) => a > b ? a : b);
  }

  // � REMOVED: _hasWalkedSufficientSteps() - using visual-only navigation mode



  Future<void> _waypointReached() async {
    _setState(NavigationState.approachingWaypoint);
    
    //Get current waypoint by sequence number
    final currentWaypoint = _getWaypointBySequence(_currentSequenceNumber);
    if (currentWaypoint == null) {
      print('Error: No waypoint found for sequence $_currentSequenceNumber');
      return;
    }
    
    //Confirm waypoint reached (silent for VIP users)
    print('✅ Waypoint ${_currentSequenceNumber} reached - moving to next');
    
    // NO AUDIO: Removed "waypoint reached" audio to reduce noise for VIP users
    // await _speak(message);
    // onStatusUpdate?.call(message);
    
    // CLEAR LAST SPOKEN INSTRUCTION so next waypoint instruction will always play
    _lastSpokenInstruction = null;
    _lastInstructionTime = null;
    
    // DISABLED: Step counter reset
    // _stepsAtLastWaypoint = _currentTotalSteps;
    // print('🔄 Step counter reset: Steps at waypoint = $_stepsAtLastWaypoint');
    print('🔄 Waypoint progression (visual-only mode)');
    
    // Move to NEXT SEQUENCE NUMBER, not array index!
    _currentSequenceNumber++;
    print('Moving to next sequence: $_currentSequenceNumber');
    
    // Check if there's a next waypoint
    final nextWaypoint = _getWaypointBySequence(_currentSequenceNumber);
    if (nextWaypoint == null) {
      // Destination reached - no more waypoints
      await _destinationReached();
    } else {
      // Continue to next waypoint
      _setState(NavigationState.navigating);
      await _updateNavigationInstruction();
    }
  }

  Future<void> _destinationReached() async {
    _setState(NavigationState.destinationReached);
    
    await _speak('Destination reached');
    onStatusUpdate?.call('Destination reached');
    
    // Auto-stop navigation
    await stopNavigation();
  }

  /// Simple VIP-friendly off-track handling: Ask user to walk back after 3 consecutive off-track detections
  Future<void> _handleOffTrack() async {
    _consecutiveOffTrackCount++;
    print('📊 Off-track count: $_consecutiveOffTrackCount/$_offTrackThreshold3Times');
    
    // Only trigger recovery action after 3 consecutive off-track detections
    if (_consecutiveOffTrackCount >= _offTrackThreshold3Times) {
      _setState(NavigationState.offTrack);
      
      // VIP-friendly: Simple instruction to walk back a few steps
      await _speak('You seem to have gone off course. Please stop and walk back a few steps slowly, then continue.');
      onStatusUpdate?.call('Off track - walk back a few steps');
      
      // Reset counter after providing guidance
      _consecutiveOffTrackCount = 0;
      
      // Return to navigation after brief pause
      Timer(Duration(seconds: 2), () {
        if (_state == NavigationState.offTrack) {
          _setState(NavigationState.navigating);
          onStatusUpdate?.call('Continue navigation');
        }
      });
    } else {
      // Just log the off-track detection but don't alarm the user yet
      print('⚠️ Off-track detection ${_consecutiveOffTrackCount}/$_offTrackThreshold3Times - continuing without user alert');
    }
  }

  Future<void> _provideGuidance(PathWaypoint targetWaypoint, double similarity) async {
    final now = DateTime.now();
    final timeSinceLastGuidance = now.difference(_lastGuidanceTime);
    
    // Don't provide guidance too frequently - set to 5 seconds for better audio spacing
    if (timeSinceLastGuidance < Duration(seconds: 5)) return;
    
    _lastGuidanceTime = now;
    
    // Create navigation instruction
    final instruction = await _createNavigationInstruction(targetWaypoint, similarity);
    onInstructionUpdate?.call(instruction);
    
    // Speak the instruction using smart speaking to prevent repetition
    await _speakSmart(instruction.spokenInstruction);
    
    // Update status
    onStatusUpdate?.call(instruction.displayText);
  }

  Future<NavigationInstruction> _createNavigationInstruction(
    PathWaypoint targetWaypoint, 
    double similarity
  ) async {
    // 🚨 FIX: Display waypoint number = sequence + 1 (user-friendly)
    final waypointNumber = _currentSequenceNumber + 1;  // Show 1,2,3... to user
    final totalWaypoints = _getTotalSequenceNumbers() + 1;  // Total count for display
    
    String displayText;
    String spokenInstruction;
    InstructionType instructionType;
    
    // 🎯 SIMPLIFIED: Only 3 commands - continue straight, turn left, turn right
    switch (targetWaypoint.turnType) {
      case TurnType.straight:
        instructionType = InstructionType.continue_;
        displayText = 'Continue straight';
        spokenInstruction = 'Continue straight';
        break;
      case TurnType.left:
        instructionType = InstructionType.turnLeft;
        displayText = 'Turn left';
        spokenInstruction = 'Turn left';
        break;
      case TurnType.right:
        instructionType = InstructionType.turnRight;
        displayText = 'Turn right';
        spokenInstruction = 'Turn right';
        break;
      case TurnType.uTurn:
        instructionType = InstructionType.turnLeft;
        displayText = 'Turn left';
        spokenInstruction = 'Turn left';
        break;
    }
    
    return NavigationInstruction(
      type: instructionType,
      displayText: displayText,
      spokenInstruction: spokenInstruction,
      targetHeading: targetWaypoint.heading,
      confidence: similarity,
      distanceToTarget: targetWaypoint.distanceFromPrevious,
      waypointNumber: waypointNumber,
      totalWaypoints: totalWaypoints,
    );
  }

  Future<void> _updateNavigationInstruction() async {
    if (_currentRoute == null) return;
    
    // Get waypoint by sequence number, not array index
    final targetWaypoint = _getWaypointBySequence(_currentSequenceNumber);
    if (targetWaypoint == null) {
      print('No waypoint found for sequence $_currentSequenceNumber');
      return;
    }
    
    final instruction = await _createNavigationInstruction(targetWaypoint, 0.5);
    
    onInstructionUpdate?.call(instruction);
    await _speakSmart(instruction.spokenInstruction);
  }

  Future<void> _speak(String text) async {
    try {
      await _tts.speak(text);
    } catch (e) {
      print('Error speaking: $e');
    }
  }

  /// Smart speak method that prevents repeated instructions for VIP convenience
  Future<void> _speakSmart(String text) async {
    final now = DateTime.now();
    
    // Check if this is the same instruction as last time
    if (_lastSpokenInstruction == text && _lastInstructionTime != null) {
      final timeSinceLastInstruction = now.difference(_lastInstructionTime!);
      
      // Only repeat the instruction if enough time has passed (15 seconds instead of 5)
      // This prevents confusion when the app gives "turn right" multiple times
      if (timeSinceLastInstruction < Duration(seconds: 15)) {
        print('🔇 Skipping repeated instruction: "$text" (last spoken ${timeSinceLastInstruction.inSeconds}s ago)');
        return;
      }
    }
    
    // Speak the instruction and update tracking
    print('Speaking: "$text"');
    _lastSpokenInstruction = text;
    _lastInstructionTime = now;
    await _speak(text);
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

  // Calculate dynamic threshold based on waypoint people_detected field vs current frame
  // HALLWAY FIX: Higher thresholds for waypoints BEFORE turns to prevent premature turn instructions
  double _calculateDynamicThreshold({
    required bool waypointHadPeople,
    required int waypointPeopleCount,
    required bool currentFrameHasPeople,
    required int currentFramePeopleCount,
    required TurnType? nextWaypointTurnType, // Check if NEXT waypoint requires turning
  }) {
    // HALLWAY FIX: Base threshold adjustment based on what's coming NEXT
    double baseThresholdBoost = 0.0;
    
    // Higher thresholds for waypoints that come BEFORE turning waypoints
    if (nextWaypointTurnType != null) {
      switch (nextWaypointTurnType) {
        case TurnType.left:
        case TurnType.right:
          baseThresholdBoost = 0.04; // Add 6% to threshold before turns
          print('🚪 Hallway fix: Adding +0.06 threshold boost - next waypoint requires ${nextWaypointTurnType.toString().split('.').last} turn');
          break;
        case TurnType.uTurn:
          baseThresholdBoost = 0.04; // Add 8% before U-turns (more critical)
          print('🚪 Hallway fix: Adding +0.08 threshold boost - next waypoint requires U-turn');
          break;
        case TurnType.straight:
          baseThresholdBoost = 0.0; // No boost before straight waypoints
          break;
      }
    } else {
      // No next waypoint (probably final waypoint) - no boost needed
      baseThresholdBoost = 0.0;
      print('🚪 No next waypoint found - using standard threshold');
    }
    
    // Case 1: Waypoint was recorded with people → Lower base threshold but still apply hallway fix
    if (waypointHadPeople) {
      // The waypoint embedding was processed with people inpainting (cleaner)
      // Current frame may or may not have people (raw processing)
      double baseThreshold = 0.75; // Lower base threshold
      
      // Further reduce based on people count in recording
      double reduction = (waypointPeopleCount * 0.02).clamp(0.0, 0.08);
      double peopleAdjustedThreshold = (baseThreshold - reduction).clamp(0.65, 0.80);
      
      // Apply hallway fix boost and ensure it doesn't go below minimum safe threshold
      double finalThreshold = (peopleAdjustedThreshold + baseThresholdBoost).clamp(0.70, 0.95);
      
      return finalThreshold;
    }
    
    // Case 2: Waypoint was recorded clean (no people) → Higher threshold + hallway fix
    else {
      double cleanBaseThreshold;
      if (currentFrameHasPeople) {
        // Clean waypoint vs people in current frame → Need lower threshold
        cleanBaseThreshold = 0.78;
      } else {
        // Clean waypoint vs clean current frame → Can use higher threshold
        cleanBaseThreshold = 0.88;
      }
      
      // Apply hallway fix boost and ensure reasonable upper limit
      double finalThreshold = (cleanBaseThreshold + baseThresholdBoost).clamp(0.75, 0.98);
      
      return finalThreshold;
    }
  }

  // Get readable explanation for threshold reasoning (for debug display)
  String _getThresholdReason(bool waypointHadPeople, bool currentFrameHasPeople, TurnType? nextTurnType) {
    String baseReason;
    if (waypointHadPeople && currentFrameHasPeople) {
      baseReason = "(people→people)";
    } else if (waypointHadPeople && !currentFrameHasPeople) {
      baseReason = "(people→clean, lowered)";
    } else if (!waypointHadPeople && currentFrameHasPeople) {
      baseReason = "(clean→people, lowered)";
    } else {
      baseReason = "(clean→clean, standard)";
    }
    
    // Add hallway fix indication for waypoints BEFORE turning waypoints
    if (nextTurnType != null) {
      switch (nextTurnType) {
        case TurnType.left:
        case TurnType.right:
          return baseReason + " +BEFORE_TURN";
        case TurnType.uTurn:
          return baseReason + " +BEFORE_UTURN";
        case TurnType.straight:
          return baseReason;
      }
    } else {
      return baseReason + " (final)";
    }
  }

  void dispose() {
    stopNavigation();
    _tts.stop();
  }

  /// 🧪 Test method to check if step counter is working
  void testStepCounter() {
    print('🧪 Testing step counter...');
    _updateDebugDisplay('🧪 TESTING STEP COUNTER\n📊 Current total: $_currentTotalSteps\n🔄 Check if this number changes when you walk');
    
    // Force a debug update to show current state
    final testInfo = '''
      🧪 STEP COUNTER TEST:
      Current total: $_currentTotalSteps
      Baseline: $_stepsAtLastWaypoint
      Since last: ${_currentTotalSteps - _stepsAtLastWaypoint}
      State: $_state
      Walking: $_isUserWalking

      🚶 Walk 5-10 steps and check if numbers change!''';
          _updateDebugDisplay(testInfo);
  }

  // Test method to check compass readings
  void testCompass() {
    print('Testing compass readings...');
    
    final compassInfo = '''
      COMPASS TEST:
      Current heading: ${_currentHeading?.toStringAsFixed(1) ?? 'null'}°
      Compass available: ${FlutterCompass.events != null}
      Navigation state: $_state

      Real-time compass readings will show in console...
      Turn your device and watch the heading changes.
    ''';
    
    _updateDebugDisplay(compassInfo);
    
    // Start a test timer to show compass readings every second
    Timer.periodic(Duration(seconds: 1), (timer) {
      if (_state != NavigationState.initialOrientation) {
        timer.cancel();
        return;
      }
      
      if (_currentHeading != null) {
        print('🧭 Test compass: ${_currentHeading!.toStringAsFixed(1)}°');
      } else {
        print('🧭 Test compass: No reading');
      }
    });
  }

  /// 🧪 Manual override for compass testing (for debugging only)
  void setManualHeading(double heading) {
    _currentHeading = _normalizeHeading(heading);
    print('🧪 Manual heading set to: ${_currentHeading!.toStringAsFixed(1)}°');
    _updateDebugDisplay('🧪 MANUAL HEADING SET\n📍 Current: ${_currentHeading!.toStringAsFixed(1)}°\n⚠️ This overrides real compass readings');
  }
}

/// Represents a navigation instruction
class NavigationInstruction {
  final InstructionType type;
  final String displayText;
  final String spokenInstruction;
  final double targetHeading;
  final double confidence;
  final double? distanceToTarget;
  final int waypointNumber;
  final int totalWaypoints;

  NavigationInstruction({
    required this.type,
    required this.displayText,
    required this.spokenInstruction,
    required this.targetHeading,
    required this.confidence,
    this.distanceToTarget,
    required this.waypointNumber,
    required this.totalWaypoints,
  });
}
