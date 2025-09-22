import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_compass/flutter_compass.dart';
import '../services/clip_service.dart';
import '../services/position_localization_service.dart';
import '../services/supabase_service.dart';
import '../models/path_models.dart';

enum NavigationState {
  idle,
  initialOrientation,
  navigating,
  approachingWaypoint,
  reorientingUser,
  destinationReached,
  awaitingManualCapture,
  manualCaptureInProgress,
  analyzingCapturedFrames,
  recoveryFailed,
}

class RealTimeNavigationService {
  final ClipService _clipService;
  final FlutterTts _tts;
  final SupabaseService _supabaseService = SupabaseService();
  
  // Navigation state
  NavigationRoute? _currentRoute;
  NavigationState _state = NavigationState.idle;
  int _currentWaypointIndex = 0;
  int _currentSequenceNumber = 0; 
  Timer? _navigationTimer;
  StreamSubscription<CompassEvent>? _compassSubscription;
  
  
  // Tracking
  double? _currentHeading;
  List<double>? _lastCapturedEmbedding;
  DateTime _lastGuidanceTime = DateTime.now();
  DateTime? _lastVisualMatchTime; // Track when we last had a visual match
  
  // YOLO toggle state
  bool _disableYolo = false;
  
  // Configuration - ALL threshold constants are centralized HERE
  // To change any threshold value, modify these constants only
  static const double _waypointReachedThresholdDefault = 0.87;  // Main navigation threshold
  static const double _cleanSceneThreshold = 0.87;  // For clean-to-clean comparisons
  static const double _peoplePresentThreshold = 0.75;  // For scenes with people
  static const double _crowdedSceneThreshold = 0.70;  // For crowded scenes
  static const double _turnWaypointThreshold = 0.9;  // Higher threshold for turn waypoints (left/right/U-turn)
  static const Duration _guidanceInterval = Duration(seconds: 1);
  static const Duration _repositioningTimeout = Duration(seconds: 10);  // Dynamic threshold and audio management
  double _currentWaypointThreshold = 0.87;
  String? _lastSpokenInstruction;
  DateTime? _lastInstructionTime;
  
  // Waypoint recovery system
  int _consecutiveWaypointFailures = 0;
  static const int _waypointFailureThreshold = 30;
  static const double _recoveryThreshold = 0.76;
  int _manualCaptureCount = 0;
  List<File> _capturedRecoveryFrames = [];
  int _recoveryAttempts = 0;
  static const int _maxRecoveryAttempts = 3;
  
  // Callbacks
  final Function(NavigationState state)? onStateChanged;
  final Function(String message)? onStatusUpdate;
  final Function(NavigationInstruction instruction)? onInstructionUpdate;
  final Function(String error)? onError;
  final Function(String debugInfo)? onDebugUpdate;
  final Function()? onRequestManualCapture;
  final Function(File imageFile)? onManualFrameCaptured;

  RealTimeNavigationService({
    required ClipService clipService,
    this.onStateChanged,
    this.onStatusUpdate,
    this.onInstructionUpdate,
    this.onError,
    this.onDebugUpdate,
    this.onRequestManualCapture,
    this.onManualFrameCaptured,
  }) : _clipService = clipService, _tts = FlutterTts() {
    _initializeTTS();
  }

  // Public getters
  NavigationState get state => _state;
  NavigationRoute? get currentRoute => _currentRoute;
  int get currentWaypointIndex => _currentWaypointIndex;
  double get progressPercentage => _currentRoute != null
      ? (_currentSequenceNumber / _currentRoute!.waypoints.length) * 100
      : 0.0;
  
  /// Get the current compass heading (null if not available)
  double? get currentHeading => _currentHeading;
  
  /// Set whether YOLO detection should be disabled
  void setDisableYolo(bool disable) {
    _disableYolo = disable;
    print('🎯 YOLO Detection: ${_disableYolo ? 'DISABLED' : 'ENABLED'}');
  }
  
  /// Get the target heading for initial orientation (null if not in orientation phase)
  double? get targetHeading {
    if (_state != NavigationState.initialOrientation || _currentRoute == null) {
      return null;
    }
    final firstWaypoint = _getWaypointBySequence(0);
    return firstWaypoint?.heading;
  }

  /// Update debug display with navigation information
  void _updateDebugDisplay(String debugInfo) {
    onDebugUpdate?.call(debugInfo);
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
      _lastVisualMatchTime = null; // Reset visual match tracking
      _currentWaypointThreshold = _waypointReachedThresholdDefault;
      
      // Reset all failure counters for new navigation session
      _consecutiveWaypointFailures = 0;
      _recoveryAttempts = 0;
      
      // Clean up any leftover recovery data
      await _cleanupRecoveryFrames();
      
      // START WITH INITIAL ORIENTATION instead of direct navigation
      _setState(NavigationState.initialOrientation);
      
      // Initialize step counter for this navigation session
      // DON'T set baseline immediately - wait for first step count reading
      print('🚀 Navigation started - Starting orientation phase');
      print('⏳ Waiting for compass reading to guide initial direction...');
      
      _updateDebugDisplay('🚀 NAVIGATION STARTED\n🧭 ORIENTATION PHASE\n⏳ Waiting for compass...\n🎯 Destination: ${route.endNodeName}');
      
      // 🐛 Send navigation start info to screen
      
      onStatusUpdate?.call('Starting navigation to ${route.endNodeName}');
      await _speak('Navigation started. Face the right direction.');
      
      // Initialize compass
      await _initializeCompass();
      
      // Start orientation guidance instead of navigation
      await _startInitialOrientation();
      
    } catch (e) {
      onError?.call('Failed to start navigation: $e');
    }
  }

  /// Stop navigation
  Future<void> stopNavigation({bool silent = false}) async {
    _navigationTimer?.cancel();
    _compassSubscription?.cancel();
    
    if (_currentRoute != null && !silent) {
      await _speak('Navigation stopped.');
    }
    
    _currentRoute = null;
    _currentWaypointIndex = 0;
    _currentSequenceNumber = 0; 
    
    // Reset audio tracking and people detection state
    _lastSpokenInstruction = null;
    _lastInstructionTime = null;
    _lastVisualMatchTime = null;
    _currentWaypointThreshold = _waypointReachedThresholdDefault;
    
    // Reset all failure counters
    _consecutiveWaypointFailures = 0;
    _recoveryAttempts = 0;
    
    // Clean up recovery data
    await _cleanupRecoveryFrames();
    
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

    // Audio feedback for orientation start
    await _speak('Starting orientation. Please face the correct direction for navigation.');
    onStatusUpdate?.call('Starting orientation - face the correct direction');

    await _speak('Starting Orientation.Turn slowly until I say stop.');
    onStatusUpdate?.call('Turn slowly - finding correct direction');

    // Update debug display to show waiting period
    _updateDebugDisplay('🧭 GETTING READY\n⏳ Please wait while I prepare orientation...\n🎯 Keep your phone steady');
    onStatusUpdate?.call('Preparing orientation system...');

    // Wait a few seconds for user to process the initial instructions before starting orientation checking
    await Future.delayed(Duration(seconds: 3));

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
    await _speak('Perfect! You are now facing the correct direction.');
    onStatusUpdate?.call('Direction confirmed - preparing navigation');

    await _speak('Navigation will begin shortly. Keep facing this direction.');
    onStatusUpdate?.call('Preparing navigation...');
    
    print('✅ User is correctly oriented - confirming before navigation');
    _updateDebugDisplay('✅ ORIENTATION COMPLETE\n⏳ Preparing navigation...\n� Getting ready to start...');
    
    // Give user a moment to process the confirmation, then start navigation
    Timer(Duration(seconds: 2), () async {
      _setState(NavigationState.navigating);
      
      await _speak('Starting navigation.');
      onStatusUpdate?.call('Navigation started');
      
      print('🚀 Starting actual navigation after orientation confirmation');
      _updateDebugDisplay('''
🚀 NAVIGATION STARTED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📍 Orientation complete - ready for waypoint guidance
🎯 Waiting for first visual match with waypoint 0
⏳ Camera processing will provide turn-by-turn guidance
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
''');
      
      // Reset guidance time to prevent immediate guidance
      _lastGuidanceTime = DateTime.now();

      // DON'T provide waypoint instruction during orientation
      // Wait for first visual match before providing navigation guidance
      // Only compass guidance should be given during orientation phase

      // Start periodic navigation guidance
      _navigationTimer = Timer.periodic(_guidanceInterval, (_) => _checkProgress());

      // Provide initial guidance for the first waypoint
      final firstWaypoint = _getWaypointBySequence(0);
      if (firstWaypoint != null) {
        await _provideGuidance(firstWaypoint, 0.5);
      }
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
      
      // Use YOLO detection and dynamic threshold with inpainting for navigation accuracy
      final navigationResult = await _clipService.generateNavigationEmbeddingWithInpainting(
        imageFile,
        cleanSceneThreshold: _cleanSceneThreshold,
        peoplePresentThreshold: _peoplePresentThreshold,
        crowdedSceneThreshold: _crowdedSceneThreshold,
        disableYolo: _disableYolo,
      );
      _lastCapturedEmbedding = navigationResult.embedding;
      
      // HALLWAY FIX: Use higher threshold for waypoints BEFORE turns to prevent premature turn instructions
      // Also use higher threshold for final waypoint to ensure accurate destination reaching
      final nextWaypoint = _getWaypointBySequence(_currentSequenceNumber + 1);
      final isBeforeTurnWaypoint = nextWaypoint != null &&
                                 (nextWaypoint.turnType == TurnType.left ||
                                  nextWaypoint.turnType == TurnType.right);
      final isFinalWaypoint = nextWaypoint == null; // No next waypoint means this is the final one

      _currentWaypointThreshold = (isBeforeTurnWaypoint || isFinalWaypoint) ? _turnWaypointThreshold : navigationResult.recommendedThreshold;
      
      print('🎯 Navigation frame: Sequence $_currentSequenceNumber (landmark: ${targetWaypoint.landmarkDescription ?? 'No description'})');
      String thresholdReason = isFinalWaypoint ? 'FINAL WAYPOINT (0.9)' :
                              isBeforeTurnWaypoint ? 'BEFORE TURN (0.9)' :
                              'NORMAL (' + navigationResult.recommendedThreshold.toStringAsFixed(2) + ')';
      print('🎯 Dynamic threshold: ${_currentWaypointThreshold.toStringAsFixed(2)} ($thresholdReason)');
      print('🎯 YOLO Detection: ${_disableYolo ? 'DISABLED' : 'ENABLED'}');
      print('👥 People detected: ${navigationResult.peopleDetected ? 'YES (${navigationResult.peopleCount})' : 'NO'}');
      print('🎨 Inpainting: ${_disableYolo ? 'DISABLED BY USER' : navigationResult.peopleDetected ? 'Applied (people + carried objects removed)' : 'Skipped (no people detected)'}');
      
      // Calculate similarity with target waypoint
      final similarity = _calculateCosineSimilarity(navigationResult.embedding, targetWaypoint.embedding);
      print(' Similarity: ${similarity.toStringAsFixed(3)} (threshold: ${_currentWaypointThreshold.toStringAsFixed(2)})');
      
      // STEP COUNTER SOLUTION: Multi-condition waypoint validation
      final hasVisualMatch = similarity >= _currentWaypointThreshold;
      final hasSufficientSteps = true; // Visual-only navigation mode
      
      print('🔍 Waypoint validation for sequence $_currentSequenceNumber:');
      print('   👁️ Visual match (≥${_currentWaypointThreshold.toStringAsFixed(2)}): $hasVisualMatch (${similarity.toStringAsFixed(3)})');
      print('   🚶 Sufficient steps: $hasSufficientSteps');
      print('   🎯 Target: ${targetWaypoint.landmarkDescription ?? 'No description'}, Turn: ${targetWaypoint.turnType}');
      print('   📍 Target sequence: ${targetWaypoint.sequenceNumber}');
      
      // Log detailed waypoint matching information
      final validationInfo = '''
          🔍 WAYPOINT MATCHING:
          ━━━━━━━━━━━━━━━━━━━━
          📍 Target: ${targetWaypoint.landmarkDescription ?? 'No landmark'} (Seq ${_currentSequenceNumber})
          Turn: ${targetWaypoint.turnType.toString().split('.').last.toUpperCase()} ${isFinalWaypoint ? "FINAL WAYPOINT (0.9 threshold)" : isBeforeTurnWaypoint ? "BEFORE TURN WAYPOINT (0.9 threshold)" : ""}
          🎯 YOLO: ${_disableYolo ? 'DISABLED' : 'ENABLED'}
          When Recorded: ${targetWaypoint.peopleDetected ? "YES (${targetWaypoint.peopleCount} people)" : "NO people"}
          Now Detecting: ${navigationResult.peopleDetected ? "YES (${navigationResult.peopleCount} people)" : "NO people"} ${_disableYolo ? "(YOLO disabled)" : "(YOLO active)"}
          🎨 Inpainting: ${_disableYolo ? "DISABLED BY USER" : navigationResult.peopleDetected ? "Applied (people removed)" : "Not needed"}
          🎯 Threshold: ${_currentWaypointThreshold.toStringAsFixed(3)} (dynamic based on people detection)
          👁️ Similarity: ${similarity.toStringAsFixed(3)}
          ${hasVisualMatch ? "✅ MATCH!" : "❌ Too low"} (need ≥${_currentWaypointThreshold.toStringAsFixed(2)})
          🔍 Embedding: ${_lastCapturedEmbedding?.length ?? 0} dims
          ━━━━━━━━━━━━━━━━━━━━
      ''';

       _updateDebugDisplay(validationInfo);
      
      // Check if user has reached the waypoint (visual match only)
      if (hasVisualMatch && hasSufficientSteps) {
        print('✅ All conditions met - Waypoint reached!');
        // Reset failure counter on successful waypoint match
        _consecutiveWaypointFailures = 0;
        // Record visual match timestamp for guidance logic
        _lastVisualMatchTime = DateTime.now();

        // Provide guidance immediately when there's a visual match
        await _provideGuidance(targetWaypoint, similarity);

        await _waypointReached();
      } else {
        // Track consecutive waypoint progression failures
        print('Waypoint not reached - similarity: ${similarity.toStringAsFixed(3)} (need ≥${_currentWaypointThreshold.toStringAsFixed(2)})');
        await _handleWaypointFailure(targetWaypoint, similarity);
      }
      
    } catch (e) {
      onError?.call('Error processing navigation frame: $e');
    }
  }

  /// Handle manual repositioning when user is lost
  Future<void> requestRepositioning() async {
    // Can't reposition during initial orientation
    if (_state == NavigationState.initialOrientation) {
      await _speak('Complete direction guidance first');
      return;
    }

    // Reset visual match time when repositioning
    _lastVisualMatchTime = null;

    _setState(NavigationState.reorientingUser);

    await _speak('Look around slowly to get back on track.');
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

    // Guidance is now only provided when there's an actual visual match
    // This method is used for monitoring and recovery triggering only
    final now = DateTime.now();
    final timeSinceLastVisualMatch = _lastVisualMatchTime != null ?
                                   now.difference(_lastVisualMatchTime!) :
                                   Duration(days: 1); // If no match ever, set to a large duration

    print('📊 Monitoring: Last visual match ${timeSinceLastVisualMatch.inSeconds}s ago');

    // Could add recovery logic here if no visual match for too long
    // For now, just monitor without providing guidance
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
      // Provide initial guidance for the new waypoint
      await _updateNavigationInstruction();
    }
  }

  Future<void> _destinationReached() async {
    _setState(NavigationState.destinationReached);
    
    // Get destination direction guidance
    final directionMessage = await _getDestinationDirectionMessage();
    
    await _speak(directionMessage);
    onStatusUpdate?.call('Destination reached');
    
    // Auto-stop navigation (silent since we already spoke the destination message)
    await stopNavigation(silent: true);
  }

  /// Get destination direction message based on reference direction and last waypoint heading
  Future<String> _getDestinationDirectionMessage() async {
    try {
      if (_currentRoute == null) {
        return 'Destination reached.';
      }

      // Get destination node details
      final destinationNodeId = _currentRoute!.endNodeId;
      final destinationName = _currentRoute!.endNodeName;
      
      print('🎯 Getting direction for destination: $destinationName (ID: $destinationNodeId)');
      
      final nodeDetails = await _supabaseService.getMapNodeDetails(destinationNodeId);
      final referenceDirection = nodeDetails['reference_direction'] as double?;
      
      if (referenceDirection == null) {
        print('⚠️ No reference direction found for destination node');
        return 'Stop, you have reached $destinationName.';
      }

      // Get the last waypoint heading
      final lastWaypoint = _getLastWaypoint();
      if (lastWaypoint == null) {
        print('⚠️ No last waypoint found');
        return 'Stop, you have reached $destinationName.';
      }

      final lastWaypointHeading = lastWaypoint.heading;
      print('📍 Last waypoint heading: ${lastWaypointHeading.toStringAsFixed(1)}°');
      print('🏢 Destination reference direction: ${referenceDirection.toStringAsFixed(1)}°');

      // Calculate relative direction
      final relativeDirection = _calculateRelativeDirection(lastWaypointHeading, referenceDirection);
      
      return 'Stop, you have reached $destinationName. $destinationName is $relativeDirection.';
      
    } catch (e) {
      print('❌ Error getting destination direction: $e');
      return 'Stop, you have reached ${_currentRoute?.endNodeName ?? 'your destination'}.';
    }
  }

  /// Get the last waypoint in the route
  PathWaypoint? _getLastWaypoint() {
    if (_currentRoute?.waypoints == null || _currentRoute!.waypoints.isEmpty) {
      return null;
    }
    
    // Find waypoint with highest sequence number
    PathWaypoint? lastWaypoint;
    int maxSequence = -1;
    
    for (final waypoint in _currentRoute!.waypoints) {
      if (waypoint.sequenceNumber > maxSequence) {
        maxSequence = waypoint.sequenceNumber;
        lastWaypoint = waypoint;
      }
    }
    
    return lastWaypoint;
  }

  /// Calculate relative direction (front, left, right) based on waypoint heading and destination reference direction
  String _calculateRelativeDirection(double waypointHeading, double destinationDirection) {
    // Calculate the angular difference
    double angleDiff = destinationDirection - waypointHeading;
    
    // Normalize to [-180, 180] range
    while (angleDiff > 180) angleDiff -= 360;
    while (angleDiff < -180) angleDiff += 360;
    
    print('🧭 Angle difference: ${angleDiff.toStringAsFixed(1)}° (destination - waypoint)');
    
    // Determine direction based on angle difference
    if (angleDiff.abs() <= 45) {
      return 'in front of you';
    } else if (angleDiff > 45 && angleDiff <= 135) {
      return 'on your right';
    } else if (angleDiff < -45 && angleDiff >= -135) {
      return 'on your left';
    } else {
      // 135° to 180° or -135° to -180° (behind)
      return 'behind you';
    }
  }


  /// Handle consecutive waypoint progression failures and trigger recovery system
  Future<void> _handleWaypointFailure(PathWaypoint targetWaypoint, double similarity) async {
    _consecutiveWaypointFailures++;
    print('📊 Waypoint failure count: $_consecutiveWaypointFailures/$_waypointFailureThreshold');
    
    // Only trigger recovery after 5 consecutive failures
    if (_consecutiveWaypointFailures >= _waypointFailureThreshold) {
      print('🚨 5 consecutive waypoint failures - starting recovery system');
      await _startWaypointRecovery();
    } else {
      // Don't provide guidance on waypoint failure
      // Only provide guidance when there's an actual visual match
      print('⚠️ Waypoint failure ${_consecutiveWaypointFailures}/$_waypointFailureThreshold - waiting for visual match');
    }
  }

  /// Start the waypoint recovery system
  Future<void> _startWaypointRecovery() async {
    _setState(NavigationState.awaitingManualCapture);
    _manualCaptureCount = 0;
    _capturedRecoveryFrames.clear();
    // Reset visual match time when entering recovery
    _lastVisualMatchTime = null;
    
    await _speak('Having trouble finding waypoint. Stop and look forward. Capturing images to find location.');
    onStatusUpdate?.call('Recovery mode - preparing manual capture');
    
    // Request UI to start/restart manual capture process (resets UI state)
    onRequestManualCapture?.call();
    
    // Add small delay to ensure UI state is reset before proceeding
    await Future.delayed(Duration(milliseconds: 100));
    
    // Start manual capture process
    await _requestNextManualCapture();
  }

  /// Request next manual capture from user
  Future<void> _requestNextManualCapture() async {
    if (_manualCaptureCount >= 3) {
      // All frames captured, analyze them
      await _analyzeRecoveryFrames();
      return;
    }
    
    _setState(NavigationState.manualCaptureInProgress);
    _manualCaptureCount++;
    
    await _speak('Capture frame ${_manualCaptureCount} of 3. Point forward and tap capture.');
    onStatusUpdate?.call('Capture frame ${_manualCaptureCount} of 3');
  }

  /// Handle manually captured frame
  Future<void> processManualCapturedFrame(File imageFile) async {
    if (_state != NavigationState.manualCaptureInProgress) {
      print('⚠️ Unexpected manual capture - ignoring');
      return;
    }
    
    try {
      _capturedRecoveryFrames.add(imageFile);
      print('📸 Captured recovery frame ${_manualCaptureCount} of 3');
      
      onManualFrameCaptured?.call(imageFile);
      
      // Request next capture or start analysis
      await _requestNextManualCapture();
      
    } catch (e) {
      onError?.call('Error processing manual capture: $e');
    }
  }

  /// Analyze captured recovery frames and rediscover waypoint
  Future<void> _analyzeRecoveryFrames() async {
    _setState(NavigationState.analyzingCapturedFrames);
    
    await _speak('Analyzing frames.');
    onStatusUpdate?.call('Analyzing captured frames...');
    
    try {
      // Generate embeddings for all captured frames
      List<List<double>> frameEmbeddings = [];
      for (int i = 0; i < _capturedRecoveryFrames.length; i++) {
        final file = _capturedRecoveryFrames[i];
        print('🔍 Processing recovery frame ${i + 1}/${_capturedRecoveryFrames.length}...');
        
        final navigationResult = await _clipService.generateNavigationEmbeddingWithInpainting(
          file,
          cleanSceneThreshold: _cleanSceneThreshold,
          peoplePresentThreshold: _peoplePresentThreshold,
          crowdedSceneThreshold: _crowdedSceneThreshold,
          disableYolo: _disableYolo,
        );
        
        frameEmbeddings.add(navigationResult.embedding);
        print('✅ Generated embedding for frame ${i + 1} (${navigationResult.embedding.length} dims)');
      }
      
      // Compare against all waypoints in current route using majority voting
      final bestMatch = await _findBestWaypointMatch(frameEmbeddings);
      
      if (bestMatch != null && bestMatch['similarity'] >= _recoveryThreshold) {
        final matchedWaypoint = bestMatch['waypoint'] as PathWaypoint;
        final similarity = bestMatch['similarity'] as double;
        final votes = bestMatch['votes'] as int;
        
        print('✅ Recovery successful: Found waypoint ${matchedWaypoint.sequenceNumber}');
        print('   Similarity: ${similarity.toStringAsFixed(3)} (≥${_recoveryThreshold})');
        print('   Votes: $votes/${frameEmbeddings.length}');
        
        await _speak('Location found. Resuming navigation.');
        onStatusUpdate?.call('Location rediscovered - resuming navigation');
        
        // Update current position and resume navigation
        _currentSequenceNumber = matchedWaypoint.sequenceNumber;
        _consecutiveWaypointFailures = 0;
        _recoveryAttempts = 0;
        // Set visual match time to now since we found the location
        _lastVisualMatchTime = DateTime.now();

          _setState(NavigationState.navigating);
        // Provide guidance after successful recovery
        await _provideGuidance(matchedWaypoint, 0.5);
        
        // Clean up captured frames
        await _cleanupRecoveryFrames();
        
      } else {
        // Recovery failed - try moving backward
        await _handleRecoveryFailure();
      }
      
    } catch (e) {
      onError?.call('Error analyzing recovery frames: $e');
      await _handleRecoveryFailure();
    }
  }

  /// Find best waypoint match using majority voting
  Future<Map<String, dynamic>?> _findBestWaypointMatch(List<List<double>> frameEmbeddings) async {
    if (_currentRoute?.waypoints == null || frameEmbeddings.isEmpty) return null;
    
    // Track votes for each waypoint
    final waypointVotes = <int, int>{}; // sequenceNumber -> vote count
    final waypointSimilarities = <int, List<double>>{}; // sequenceNumber -> similarities
    
    print('🔍 Comparing ${frameEmbeddings.length} frames against ${_currentRoute!.waypoints.length} waypoints');
    
    // Compare each frame against all waypoints
    for (int frameIndex = 0; frameIndex < frameEmbeddings.length; frameIndex++) {
      final frameEmbedding = frameEmbeddings[frameIndex];
      
      double bestSimilarityForFrame = 0.0;
      int? bestWaypointForFrame;
      
      for (final waypoint in _currentRoute!.waypoints) {
        final similarity = _calculateCosineSimilarity(frameEmbedding, waypoint.embedding);
        
        // Initialize tracking for this waypoint
        waypointSimilarities.putIfAbsent(waypoint.sequenceNumber, () => []);
        waypointSimilarities[waypoint.sequenceNumber]!.add(similarity);
        
        // Check if this is the best match for this frame
        if (similarity > bestSimilarityForFrame && similarity >= _recoveryThreshold) {
          bestSimilarityForFrame = similarity;
          bestWaypointForFrame = waypoint.sequenceNumber;
        }
      }
      
      // Vote for the best waypoint for this frame
      if (bestWaypointForFrame != null) {
        waypointVotes[bestWaypointForFrame] = (waypointVotes[bestWaypointForFrame] ?? 0) + 1;
        print('  Frame ${frameIndex + 1}: Votes for waypoint $bestWaypointForFrame (similarity: ${bestSimilarityForFrame.toStringAsFixed(3)})');
    } else {
        print('  Frame ${frameIndex + 1}: No waypoint above threshold');
      }
    }
    
    // Find waypoint with most votes
    if (waypointVotes.isEmpty) return null;
    
    int bestSequenceNumber = 0;
    int maxVotes = 0;
    
    for (final entry in waypointVotes.entries) {
      if (entry.value > maxVotes) {
        maxVotes = entry.value;
        bestSequenceNumber = entry.key;
      }
    }
    
    // Check if we have majority (more than half)
    final majorityThreshold = (frameEmbeddings.length / 2).ceil();
    if (maxVotes < majorityThreshold) {
      print('❌ No majority: Best waypoint $bestSequenceNumber has $maxVotes votes (need ≥$majorityThreshold)');
      return null;
    }
    
    // Calculate average similarity for the winning waypoint
    final similarities = waypointSimilarities[bestSequenceNumber] ?? [];
    final averageSimilarity = similarities.isEmpty ? 0.0 : 
        similarities.reduce((a, b) => a + b) / similarities.length;
    
    // Find the waypoint object
    final waypoint = _currentRoute!.waypoints.firstWhere(
      (w) => w.sequenceNumber == bestSequenceNumber,
    );
    
    return {
      'waypoint': waypoint,
      'similarity': averageSimilarity,
      'votes': maxVotes,
    };
  }

  /// Handle recovery failure and request backward movement
  Future<void> _handleRecoveryFailure() async {
    _recoveryAttempts++;
    
    if (_recoveryAttempts >= _maxRecoveryAttempts) {
      // Max attempts reached - give up
      _setState(NavigationState.recoveryFailed);
      
      await _speak('Unable to find location. Use manual repositioning or restart.');
      onStatusUpdate?.call('Recovery failed - manual intervention needed');
      
      await _cleanupRecoveryFrames();
      return;
    }
    
    // Request user to move backward and try again
    await _speak('Location not found. Walk backward a few steps, then try again.');
    onStatusUpdate?.call('Recovery failed - please move backward and retry');
    
    // Wait for user to move backward, then retry
    Timer(Duration(seconds: 5), () async {
      if (_state == NavigationState.analyzingCapturedFrames) {
        await _speak('Try again. Stop and face forward.');
        await Future.delayed(Duration(seconds: 2));
        // Clean up any lingering recovery data before restarting
        await _cleanupRecoveryFrames();
        await _startWaypointRecovery();
      }
    });
  }

  /// Clean up captured recovery frames
  Future<void> _cleanupRecoveryFrames() async {
    try {
      for (final file in _capturedRecoveryFrames) {
        if (await file.exists()) {
          await file.delete();
        }
      }
      _capturedRecoveryFrames.clear();
      _manualCaptureCount = 0;
      
      print('🧹 Cleaned up ${_capturedRecoveryFrames.length} recovery frames');
    } catch (e) {
      print('⚠️ Error cleaning up recovery frames: $e');
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




  void dispose() {
    stopNavigation();
    _tts.stop();
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
