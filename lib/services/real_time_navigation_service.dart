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
  
  // 🚶 STEP COUNTER SOLUTION: Movement validation with REAL distances
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
  static const double _waypointReachedThresholdDefault = 0.85; // Default waypoint threshold
  static const double _waypointReachedThresholdWithPeople = 0.8; // Lower threshold when people detected
  static const double _offTrackThreshold = 0.4; // Lowered from 0.5 for testing
  static const Duration _guidanceInterval = Duration(seconds: 2);
  static const Duration _repositioningTimeout = Duration(seconds: 10);
  
  // Dynamic threshold and audio management
  double _currentWaypointThreshold = 0.9;
  bool _peopleDetectedInLastFrame = false;
  String? _lastSpokenInstruction;
  DateTime? _lastInstructionTime;
  
  // 🚶 STEP COUNTER CONFIGURATION
  // Note: Now uses real step-based distances from path recording
  
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
    this.onDebugUpdate, // 🐛 Debug display callback
  }) : _clipService = clipService, _tts = FlutterTts() {
    _initializeTTS();
    // TEMPORARILY DISABLED: Step counter for testing
    // _initializeStepCounter();
    _updateDebugDisplay('🚨 STEP COUNTER DISABLED\n✅ Using visual-only navigation\n👁️ Only visual similarity required');
  }

  // Public getters
  NavigationState get state => _state;
  NavigationRoute? get currentRoute => _currentRoute;
  int get currentWaypointIndex => _currentWaypointIndex;
  double get progressPercentage => _currentRoute != null 
      ? ((_currentWaypointIndex + 1) / _currentRoute!.waypoints.length) * 100 
      : 0.0;

  /// Start navigation along the selected route
  Future<void> startNavigation(NavigationRoute route) async {
    if (_state == NavigationState.navigating) {
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
      
      _setState(NavigationState.navigating);
      
      // Initialize step counter for this navigation session
      // DON'T set baseline immediately - wait for first step count reading
      print('🚀 Navigation started - Starting at sequence: $_currentSequenceNumber');
      print('⏳ Waiting for first step count reading to set baseline...');
      
      // 🐛 Send navigation start info to screen
      _updateDebugDisplay('🚀 NAVIGATION STARTED\n📍 Starting sequence: $_currentSequenceNumber\n⏳ Waiting for step baseline...\n🎯 Destination: ${route.endNodeName}');
      
      onStatusUpdate?.call('Starting navigation to ${route.endNodeName}');
      await _speak('Navigation started. Destination: ${route.endNodeName}');
      
      // Initialize compass
      await _initializeCompass();
      
      // Give initial instruction
      await _updateNavigationInstruction();
      
      // Start periodic guidance
      _navigationTimer = Timer.periodic(_guidanceInterval, (_) => _checkProgress());
      
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
    _currentSequenceNumber = 0;  // 🚨 FIX: Reset to 0, not 1!
    
    // Reset audio tracking and people detection state
    _lastSpokenInstruction = null;
    _lastInstructionTime = null;
    _peopleDetectedInLastFrame = false;
    _currentWaypointThreshold = _waypointReachedThresholdDefault;
    
    // 🚶 Reset step counter state
    _stepsAtLastWaypoint = 0;
    _isUserWalking = false;
    
    _setState(NavigationState.idle);
    
    onStatusUpdate?.call('Navigation stopped');
  }

  /// Process current camera frame for navigation guidance
  Future<void> processNavigationFrame(File imageFile) async {
    if (_state != NavigationState.navigating || _currentRoute == null) return;

    try {
      // First, detect if people are present in the frame
      final peopleDetection = await _clipService.detectPeople(imageFile);
      _peopleDetectedInLastFrame = peopleDetection.peopleDetected;
      
      // Adjust threshold based on people detection
      _currentWaypointThreshold = _peopleDetectedInLastFrame 
          ? _waypointReachedThresholdWithPeople 
          : _waypointReachedThresholdDefault;
      
      print('👥 People detection: ${peopleDetection.peopleDetected} (count: ${peopleDetection.peopleCount})');
      print('🎯 Using threshold: ${_currentWaypointThreshold.toStringAsFixed(2)} ${_peopleDetectedInLastFrame ? "(people detected)" : "(normal)"}');
      
      // Generate embedding for current view with people removal preprocessing
      final currentEmbedding = await _clipService.generatePreprocessedEmbedding(imageFile);
      _lastCapturedEmbedding = currentEmbedding;
      
      // 🚨 FIX: Get current target waypoint by SEQUENCE NUMBER, not array index!
      final targetWaypoint = _getWaypointBySequence(_currentSequenceNumber);
      if (targetWaypoint == null) {
        print('❌ No waypoint found for sequence $_currentSequenceNumber');
        return;
      }
      
      print('🎯 Navigation frame: Sequence $_currentSequenceNumber (landmark: ${targetWaypoint.landmarkDescription ?? 'No description'})');
      
      // Calculate similarity with target waypoint
      final similarity = _calculateCosineSimilarity(currentEmbedding, targetWaypoint.embedding);
      print('📊 Similarity: ${similarity.toStringAsFixed(3)} (threshold: ${_currentWaypointThreshold.toStringAsFixed(2)})');
      
      // 🚶 STEP COUNTER SOLUTION: Multi-condition waypoint validation
      final hasVisualMatch = similarity >= _currentWaypointThreshold;
      // 🚨 TEMPORARILY DISABLED: Step validation for testing
      // final hasSufficientSteps = _hasWalkedSufficientSteps(targetWaypoint);
      final hasSufficientSteps = true; // Always true for testing
      
      print('🔍 Waypoint validation for sequence $_currentSequenceNumber:');
      print('   👁️ Visual match (≥${_currentWaypointThreshold.toStringAsFixed(2)}): $hasVisualMatch (${similarity.toStringAsFixed(3)})');
      print('   🚶 Sufficient steps: $hasSufficientSteps');
      print('   🎯 Target: ${targetWaypoint.landmarkDescription ?? 'No description'}, Turn: ${targetWaypoint.turnType}');
      print('   📍 Target sequence: ${targetWaypoint.sequenceNumber}');
      
      // Send navigation validation info to screen
      final validationInfo = '''
        🔍 VALIDATION (Seq $_currentSequenceNumber):
        👥 People: ${_peopleDetectedInLastFrame ? "YES" : "NO"} (${peopleDetection.peopleCount})
        👁️ Visual: ${similarity.toStringAsFixed(3)} (need ≥${_currentWaypointThreshold.toStringAsFixed(2)})
        ${hasVisualMatch ? "✅" : "❌"} Visual Match
        ✅ Steps DISABLED (testing mode)
        🎯 ${targetWaypoint.landmarkDescription ?? 'No landmark'}
      ''';

       _updateDebugDisplay(validationInfo);
      
      // Check if user has reached the waypoint (visual match only)
      if (hasVisualMatch && hasSufficientSteps) {
        print('✅ All conditions met - Waypoint reached!');
        await _waypointReached();
      } else if (similarity < _offTrackThreshold) {
        print('❌ Off track - similarity too low (${similarity.toStringAsFixed(3)} < $_offTrackThreshold)');
        await _handleOffTrack();
      } else {
        // Provide guidance toward the target
        print('⏳ Conditions not met:');
        if (!hasVisualMatch) print('   ❌ Visual similarity too low: ${similarity.toStringAsFixed(3)} (need ≥${_currentWaypointThreshold.toStringAsFixed(2)})');
        // 🚨 DISABLED: Step validation
        // if (!hasSufficientSteps) print('   ❌ Not enough steps walked');
        
        // 🚨 DISABLED: Step-based guidance
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
    buffer.writeln('🐛 DEBUG INFO:');
    buffer.writeln('State: $_state');
    buffer.writeln('Sequence: $_currentSequenceNumber');
    buffer.writeln('STEPS: DISABLED');
    buffer.writeln('Mode: Visual-only');
    
    if (_currentRoute != null) {
      buffer.writeln('Route: ${_currentRoute!.endNodeName}');
      buffer.writeln('Waypoints: ${_currentRoute!.waypoints.length}');
    }
    
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
    await _tts.setVolume(0.9);
    await _tts.setPitch(1.0);
  }

  Future<void> _initializeCompass() async {
    if (FlutterCompass.events != null) {
      _compassSubscription = FlutterCompass.events!.listen((event) {
        if (event.heading != null) {
          _currentHeading = _normalizeHeading(event.heading!);
        }
      });
    }
  }

  // � REMOVED: _initializeStepCounter() - using visual-only navigation mode

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
    
    if (timeSinceLastGuidance > Duration(seconds: 15)) {
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
    
    //Confirm waypoint reached
    String message = 'Waypoint reached';
    
    await _speak(message);
    onStatusUpdate?.call(message);
    
    // 🚨 DISABLED: Step counter reset
    // _stepsAtLastWaypoint = _currentTotalSteps;
    // print('🔄 Step counter reset: Steps at waypoint = $_stepsAtLastWaypoint');
    print('🔄 Waypoint progression (visual-only mode)');
    
    // 🚨 FIX: Move to NEXT SEQUENCE NUMBER, not array index!
    _currentSequenceNumber++;
    print('📍 Moving to next sequence: $_currentSequenceNumber');
    
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

  Future<void> _handleOffTrack() async {
    _setState(NavigationState.offTrack);
    
    await _speak('Off track');
    onStatusUpdate?.call('Off track');
    
    // Automatically return to navigation after a moment
    Timer(Duration(seconds: 1), () {
      if (_state == NavigationState.offTrack) {
        _setState(NavigationState.navigating);
      }
    });
  }

  Future<void> _provideGuidance(PathWaypoint targetWaypoint, double similarity) async {
    final now = DateTime.now();
    final timeSinceLastGuidance = now.difference(_lastGuidanceTime);
    
    // Don't provide guidance too frequently
    if (timeSinceLastGuidance < Duration(seconds: 2)) return;
    
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
      
      // Only repeat the instruction if enough time has passed (5 seconds)
      // This prevents confusion when the app gives "turn right" multiple times
      if (timeSinceLastInstruction < Duration(seconds: 5)) {
        print('🔇 Skipping repeated instruction: "$text" (last spoken ${timeSinceLastInstruction.inSeconds}s ago)');
        return;
      }
    }
    
    // Speak the instruction and update tracking
    print('🔊 Speaking: "$text"');
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

  double _normalizeHeading(double heading) {
    double normalized = heading % 360;
    if (normalized < 0) normalized += 360;
    return normalized;
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
