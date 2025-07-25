import 'dart:async';
import 'dart:math';
import '../models/path_models.dart';

class NavigationGuide {
  // Navigation state
  NavigationPath? _currentPath;
  int _currentWaypointIndex = 0;
  bool _isNavigating = false;
  
  // Turn monitoring
  bool _isTurning = false;
  double _targetHeading = 0.0;
  List<double> _targetEmbedding = [];
  
  // Callbacks
  final Function(NavigationInstruction instruction)? onInstructionUpdate;
  final Function(String message)? onStatusUpdate;
  final Function(String error)? onError;

  NavigationGuide({
    this.onInstructionUpdate,
    this.onStatusUpdate,
    this.onError,
  });

  // Public methods
  bool get isNavigating => _isNavigating;
  NavigationPath? get currentPath => _currentPath;
  int get currentWaypointIndex => _currentWaypointIndex;
  double get progressPercentage => _currentPath != null 
      ? (_currentWaypointIndex / _currentPath!.waypoints.length) * 100 
      : 0.0;

  Future<void> startNavigation(NavigationPath path) async {
    if (_isNavigating) {
      onError?.call('Navigation already in progress');
      return;
    }

    _currentPath = path;
    _currentWaypointIndex = 0;
    _isNavigating = true;
    _isTurning = false;

    onStatusUpdate?.call('Starting navigation to ${path.endLocationId}');
    
    // Give initial instruction
    await _updateNavigationInstruction(null, 0.0);
  }

  Future<void> stopNavigation() async {
    _isNavigating = false;
    _currentPath = null;
    _currentWaypointIndex = 0;
    _isTurning = false;
    
    onStatusUpdate?.call('Navigation stopped');
  }

  Future<void> updatePosition(List<double> currentEmbedding, double currentHeading) async {
    if (!_isNavigating || _currentPath == null) return;

    try {
      // Find current position on path
      PathWaypoint? currentWaypoint = await _findCurrentPosition(currentEmbedding);
      
      if (currentWaypoint == null) {
        onStatusUpdate?.call('Searching for your location on the path...');
        return;
      }

      // Update waypoint index
      int waypointIndex = _currentPath!.waypoints.indexOf(currentWaypoint);
      if (waypointIndex > _currentWaypointIndex) {
        _currentWaypointIndex = waypointIndex;
        onStatusUpdate?.call('Progress: ${(_currentWaypointIndex / _currentPath!.waypoints.length * 100).round()}%');
      }

      // Check if we've reached the destination
      if (_currentWaypointIndex >= _currentPath!.waypoints.length - 1) {
        await _handleArrival();
        return;
      }

      // Handle turn monitoring
      if (_isTurning) {
        TurnStatusResult turnStatus = await _monitorTurn(currentHeading, currentEmbedding);
        await _handleTurnStatus(turnStatus);
      } else {
        // Normal navigation guidance
        await _updateNavigationInstruction(currentEmbedding, currentHeading);
      }

    } catch (e) {
      onError?.call('Navigation error: $e');
    }
  }

  // Private methods
  Future<PathWaypoint?> _findCurrentPosition(List<double> currentEmbedding) async {
    if (_currentPath == null) return null;

    double bestSimilarity = 0.0;
    PathWaypoint? bestMatch;
    
    // Search from current waypoint onwards (don't go backwards)
    for (int i = _currentWaypointIndex; i < _currentPath!.waypoints.length; i++) {
      double similarity = _calculateCosineSimilarity(
        currentEmbedding, 
        _currentPath!.waypoints[i].embedding
      );
      
      if (similarity > bestSimilarity && similarity > 0.6) {
        bestSimilarity = similarity;
        bestMatch = _currentPath!.waypoints[i];
      }
    }
    
    return bestMatch;
  }

  Future<void> _updateNavigationInstruction(List<double>? currentEmbedding, double currentHeading) async {
    if (_currentPath == null) return;

    PathWaypoint? nextTurnPoint = _findNextTurnPoint();
    
    if (nextTurnPoint == null) {
      // No more turns, head to destination
      NavigationInstruction instruction = NavigationInstruction(
        "Continue straight to your destination",
        InstructionType.continue_,
      );
      onInstructionUpdate?.call(instruction);
      return;
    }

    double distanceToTurn = _calculateDistanceToWaypoint(nextTurnPoint);
    
    if (distanceToTurn < 3.0) { // Close to turn point
      NavigationInstruction instruction = _generateTurnInstruction(nextTurnPoint);
      onInstructionUpdate?.call(instruction);
      
      // Start turn monitoring
      _isTurning = true;
      _targetHeading = nextTurnPoint.heading;
      _targetEmbedding = nextTurnPoint.embedding;
      
    } else {
      // Approaching turn
      String turnDirection = nextTurnPoint.turnType == TurnType.left ? "left" : 
                           nextTurnPoint.turnType == TurnType.right ? "right" : "ahead";
      
      NavigationInstruction instruction = NavigationInstruction(
        "Continue straight for ${distanceToTurn.round()} meters, then turn $turnDirection",
        InstructionType.approach,
        distanceToNext: distanceToTurn,
      );
      onInstructionUpdate?.call(instruction);
    }
  }

  PathWaypoint? _findNextTurnPoint() {
    if (_currentPath == null) return null;
    
    // Find next decision point from current position
    for (int i = _currentWaypointIndex + 1; i < _currentPath!.waypoints.length; i++) {
      if (_currentPath!.waypoints[i].isDecisionPoint) {
        return _currentPath!.waypoints[i];
      }
    }
    return null;
  }

  double _calculateDistanceToWaypoint(PathWaypoint waypoint) {
    // Simplified distance calculation based on waypoint sequence
    double totalDistance = 0.0;
    int waypointIndex = _currentPath!.waypoints.indexOf(waypoint);
    
    for (int i = _currentWaypointIndex; i < waypointIndex; i++) {
      totalDistance += _currentPath!.waypoints[i].distanceFromPrevious ?? 3.0;
    }
    
    return totalDistance;
  }

  NavigationInstruction _generateTurnInstruction(PathWaypoint turnPoint) {
    String turnText;
    InstructionType instructionType;
    
    switch (turnPoint.turnType) {
      case TurnType.left:
        turnText = "Turn left now";
        instructionType = InstructionType.turnLeft;
        break;
      case TurnType.right:
        turnText = "Turn right now";
        instructionType = InstructionType.turnRight;
        break;
      case TurnType.uTurn:
        turnText = "Make a U-turn";
        instructionType = InstructionType.turnLeft; // Default to left for U-turn
        break;
      case TurnType.straight:
        turnText = "Continue straight";
        instructionType = InstructionType.continue_;
        break;
    }
    
    if (turnPoint.landmarkDescription != null) {
      turnText += ". ${turnPoint.landmarkDescription}";
    }

    return NavigationInstruction(
      turnText,
      instructionType,
      expectedHeading: turnPoint.heading,
      confirmationEmbedding: turnPoint.embedding,
    );
  }

  Future<TurnStatusResult> _monitorTurn(double currentHeading, List<double> currentEmbedding) async {
    // Check heading progress
    double headingDiff = _getAngleDifference(currentHeading, _targetHeading);
    
    // Check visual confirmation
    double visualSimilarity = _calculateCosineSimilarity(currentEmbedding, _targetEmbedding);
    
    if (headingDiff < 15.0 && visualSimilarity > 0.7) {
      return TurnStatusResult(TurnStatus.completed);
    } else if (headingDiff < 30.0) {
      return TurnStatusResult(TurnStatus.inProgress);
    } else {
      String direction = headingDiff > 0 ? 'right' : 'left';
      return TurnStatusResult.correction("Turn more $direction");
    }
  }

  Future<void> _handleTurnStatus(TurnStatusResult turnStatus) async {
    switch (turnStatus.status) {
      case TurnStatus.completed:
        _isTurning = false;
        onStatusUpdate?.call("Turn completed successfully");
        // Move to next waypoint
        _currentWaypointIndex++;
        break;
        
      case TurnStatus.inProgress:
        onStatusUpdate?.call("Keep turning...");
        break;
        
      case TurnStatus.correction:
        if (turnStatus.message != null) {
          NavigationInstruction correction = NavigationInstruction(
            turnStatus.message!,
            InstructionType.relocate,
          );
          onInstructionUpdate?.call(correction);
        }
        break;
        
      case TurnStatus.notTurning:
        // Should not happen during turn monitoring
        break;
    }
  }

  Future<void> _handleArrival() async {
    _isNavigating = false;
    
    NavigationInstruction arrivalInstruction = NavigationInstruction(
      "You have arrived at your destination: ${_currentPath!.endLocationId}",
      InstructionType.arrive,
    );
    
    onInstructionUpdate?.call(arrivalInstruction);
    onStatusUpdate?.call("Navigation completed successfully!");
  }

  double _getAngleDifference(double angle1, double angle2) {
    double diff = (angle1 - angle2).abs() % 360;
    return diff > 180 ? 360 - diff : diff;
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

  // Utility methods for path analysis
  List<PathWaypoint> getDecisionPoints() {
    if (_currentPath == null) return [];
    return _currentPath!.waypoints.where((w) => w.isDecisionPoint).toList();
  }

  List<PathWaypoint> getTurnPoints() {
    if (_currentPath == null) return [];
    return _currentPath!.waypoints.where((w) => 
      w.turnType != TurnType.straight).toList();
  }

  String getPathSummary() {
    if (_currentPath == null) return "No active path";
    
    int totalTurns = getTurnPoints().length;
    return "Path from ${_currentPath!.startLocationId} to ${_currentPath!.endLocationId}: "
           "${_currentPath!.estimatedSteps} steps, $totalTurns turns";
  }
}
