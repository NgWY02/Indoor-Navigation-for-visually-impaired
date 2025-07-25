import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_compass/flutter_compass.dart';
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

  // Tracking
  double? _currentHeading;
  List<double>? _lastCapturedEmbedding;
  DateTime _lastGuidanceTime = DateTime.now();

  // Configuration
  static const double _waypointReachedThreshold = 0.9;
  static const double _offTrackThreshold = 0.5;
  static const Duration _guidanceInterval = Duration(seconds: 3);
  static const Duration _repositioningTimeout = Duration(seconds: 10);

  // Callbacks
  final Function(NavigationState state)? onStateChanged;
  final Function(String message)? onStatusUpdate;
  final Function(NavigationInstruction instruction)? onInstructionUpdate;
  final Function(String error)? onError;

  RealTimeNavigationService({
    required ClipService clipService,
    this.onStateChanged,
    this.onStatusUpdate,
    this.onInstructionUpdate,
    this.onError,
  })  : _clipService = clipService,
        _tts = FlutterTts() {
    _initializeTTS();
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
      _setState(NavigationState.navigating);

      onStatusUpdate?.call('Starting navigation to ${route.endNodeName}');
      await _speak('Navigation started. Destination: ${route.endNodeName}');

      // Initialize compass
      await _initializeCompass();

      // Give initial instruction
      await _updateNavigationInstruction();

      // Start periodic guidance
      _navigationTimer =
          Timer.periodic(_guidanceInterval, (_) => _checkProgress());
    } catch (e) {
      onError?.call('Failed to start navigation: $e');
    }
  }

  /// Stop navigation
  Future<void> stopNavigation() async {
    _navigationTimer?.cancel();
    _compassSubscription?.cancel();

    if (_currentRoute != null) {
      await _speak('Navigation stopped');
    }

    _currentRoute = null;
    _currentWaypointIndex = 0;
    _currentSequenceNumber = 0;
    _setState(NavigationState.idle);

    onStatusUpdate?.call('Navigation stopped');
  }

  /// Process current camera frame for navigation guidance
  Future<void> processNavigationFrame(File imageFile) async {
    if (_state != NavigationState.navigating || _currentRoute == null) return;

    try {
      // Generate embedding for current view
      final currentEmbedding =
          await _clipService.generateImageEmbedding(imageFile);
      _lastCapturedEmbedding = currentEmbedding;

      // 🚨 FIX: Get current target waypoint by SEQUENCE NUMBER, not array index!
      final targetWaypoint = _getWaypointBySequence(_currentSequenceNumber);
      if (targetWaypoint == null) {
        print('❌ No waypoint found for sequence $_currentSequenceNumber');
        return;
      }

      print(
          '🎯 Navigation frame: Sequence $_currentSequenceNumber (landmark: ${targetWaypoint.landmarkDescription ?? 'No description'})');

      // Calculate similarity with target waypoint
      final similarity = _calculateCosineSimilarity(
          currentEmbedding, targetWaypoint.embedding);
      print('📊 Similarity: ${similarity.toStringAsFixed(3)}');

      // Check if user has reached the waypoint
      if (similarity >= _waypointReachedThreshold) {
        await _waypointReached();
      } else if (similarity < _offTrackThreshold) {
        await _handleOffTrack();
      } else {
        // Provide guidance toward the target
        await _provideGuidance(targetWaypoint, similarity);
      }
    } catch (e) {
      onError?.call('Error processing navigation frame: $e');
    }
  }

  /// Handle manual repositioning when user is lost
  Future<void> requestRepositioning() async {
    _setState(NavigationState.reorientingUser);

    await _speak(
        'Let me help you get back on track. Please look around slowly.');
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

  Future<void> _checkProgress() async {
    if (_currentRoute == null || _state != NavigationState.navigating) return;

    // Get current waypoint by sequence number (not array index!)
    final targetWaypoint = _getWaypointBySequence(_currentSequenceNumber);
    if (targetWaypoint == null) {
      print('❌ No waypoint found for sequence $_currentSequenceNumber');
      return;
    }

    print(
        '🎯 Current target: Sequence $_currentSequenceNumber (landmark: ${targetWaypoint.landmarkDescription ?? 'No description'})');

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
    if (_currentRoute?.waypoints == null || _currentRoute!.waypoints.isEmpty)
      return 0;

    return _currentRoute!.waypoints
        .map((waypoint) => waypoint.sequenceNumber)
        .reduce((a, b) => a > b ? a : b);
  }

  Future<void> _waypointReached() async {
    _setState(NavigationState.approachingWaypoint);

    // 🚨 FIX: Get current waypoint by SEQUENCE NUMBER, not array index!
    final currentWaypoint = _getWaypointBySequence(_currentSequenceNumber);
    if (currentWaypoint == null) {
      print('❌ Error: No waypoint found for sequence $_currentSequenceNumber');
      return;
    }

    // Provide arrival confirmation
    String message = 'Waypoint reached';
    if (currentWaypoint.landmarkDescription != null) {
      message += ': ${currentWaypoint.landmarkDescription}';
    }

    await _speak(message);
    onStatusUpdate?.call(message);

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

    await _speak(
        'Destination reached: ${_currentRoute!.endNodeName}. Navigation complete.');
    onStatusUpdate?.call('Destination reached: ${_currentRoute!.endNodeName}');

    // Auto-stop navigation
    await stopNavigation();
  }

  Future<void> _handleOffTrack() async {
    _setState(NavigationState.offTrack);

    await _speak('You may be off track. Please look around to reorient.');
    onStatusUpdate?.call('Off track - please reorient');

    // Automatically return to navigation after a moment
    Timer(Duration(seconds: 5), () {
      if (_state == NavigationState.offTrack) {
        _setState(NavigationState.navigating);
      }
    });
  }

  Future<void> _provideGuidance(
      PathWaypoint targetWaypoint, double similarity) async {
    final now = DateTime.now();
    final timeSinceLastGuidance = now.difference(_lastGuidanceTime);

    // Don't provide guidance too frequently
    if (timeSinceLastGuidance < Duration(seconds: 2)) return;

    _lastGuidanceTime = now;

    // Create navigation instruction
    final instruction =
        await _createNavigationInstruction(targetWaypoint, similarity);
    onInstructionUpdate?.call(instruction);

    // Speak the instruction
    await _speak(instruction.spokenInstruction);

    // Update status
    onStatusUpdate?.call(instruction.displayText);
  }

  Future<NavigationInstruction> _createNavigationInstruction(
      PathWaypoint targetWaypoint, double similarity) async {
    // 🚨 FIX: Display waypoint number = sequence + 1 (user-friendly)
    final waypointNumber = _currentSequenceNumber + 1; // Show 1,2,3... to user
    final totalWaypoints =
        _getTotalSequenceNumbers() + 1; // Total count for display

    String displayText;
    String spokenInstruction;
    InstructionType instructionType;

    // Determine instruction based on waypoint type and current similarity
    if (similarity > 0.7) {
      instructionType = InstructionType.approach;
      displayText = 'Approaching waypoint $waypointNumber of $totalWaypoints';
      spokenInstruction = 'You are approaching the next waypoint';
    } else {
      // For low similarity, just guide towards the waypoint without turn instructions
      instructionType = InstructionType.continue_;
      displayText = 'Navigate to waypoint $waypointNumber of $totalWaypoints';
      spokenInstruction = 'Walk towards waypoint $waypointNumber';

      // Only give turn instructions when approaching the waypoint (similarity > 0.6)
      if (similarity > 0.6) {
        switch (targetWaypoint.turnType) {
          case TurnType.straight:
            displayText = 'Continue straight ahead';
            spokenInstruction = 'Continue walking straight ahead';
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
            displayText = 'Make a U-turn';
            spokenInstruction = 'Make a U-turn';
            break;
        }
      }
    }

    // Add landmark information if available
    if (targetWaypoint.landmarkDescription != null &&
        targetWaypoint.landmarkDescription!.isNotEmpty) {
      displayText += ' - ${targetWaypoint.landmarkDescription}';
      spokenInstruction += '. Look for ${targetWaypoint.landmarkDescription}';
    }

    // Add distance information if available
    if (targetWaypoint.distanceFromPrevious != null) {
      final distance = targetWaypoint.distanceFromPrevious!;
      if (distance > 0) {
        final distanceText = distance < 10
            ? '${distance.round()} meters'
            : 'about ${(distance / 10).round() * 10} meters';
        displayText += ' ($distanceText)';
        spokenInstruction += ', in $distanceText';
      }
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

    // 🚨 FIX: Get waypoint by SEQUENCE NUMBER, not array index!
    final targetWaypoint = _getWaypointBySequence(_currentSequenceNumber);
    if (targetWaypoint == null) {
      print('❌ No waypoint found for sequence $_currentSequenceNumber');
      return;
    }

    final instruction = await _createNavigationInstruction(targetWaypoint, 0.5);

    onInstructionUpdate?.call(instruction);
    await _speak(instruction.spokenInstruction);
  }

  Future<void> _speak(String text) async {
    try {
      await _tts.speak(text);
    } catch (e) {
      print('Error speaking: $e');
    }
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
