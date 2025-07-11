import 'dart:async';
import 'dart:math';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:pedometer/pedometer.dart';
import 'package:sensors_plus/sensors_plus.dart';

class Position {
  final double x;
  final double y;
  final double heading;
  final DateTime timestamp;
  final double confidence; // 0.0 to 1.0, how confident we are in this position

  Position({
    required this.x,
    required this.y,
    required this.heading,
    required this.timestamp,
    required this.confidence,
  });

  Position copyWith({
    double? x,
    double? y,
    double? heading,
    DateTime? timestamp,
    double? confidence,
  }) {
    return Position(
      x: x ?? this.x,
      y: y ?? this.y,
      heading: heading ?? this.heading,
      timestamp: timestamp ?? this.timestamp,
      confidence: confidence ?? this.confidence,
    );
  }

  double distanceTo(Position other) {
    return sqrt(pow(other.x - x, 2) + pow(other.y - y, 2));
  }

  @override
  String toString() => 'Position(x: ${x.toStringAsFixed(2)}, y: ${y.toStringAsFixed(2)}, heading: ${heading.toStringAsFixed(1)}°, confidence: ${confidence.toStringAsFixed(2)})';
}

class MovementData {
  final int stepCount;
  final double distance;
  final double averageHeading;
  final Duration duration;
  final double velocity; // meters per second

  MovementData({
    required this.stepCount,
    required this.distance,
    required this.averageHeading,
    required this.duration,
    required this.velocity,
  });
}

class DeadReckoningService {
  // Configuration constants
  static const double _averageStepLength = 0.7; // meters per step
  static const double _headingDecayFactor = 0.1; // How quickly confidence decreases over time
  static const Duration _maxConfidenceTime = Duration(seconds: 30); // Max time before confidence drops significantly
  
  // State variables
  Position? _currentPosition;
  Position? _lastKnownPosition;
  int _stepCountOffset = 0;
  int _lastStepCount = 0;
  double _lastHeading = 0.0;
  List<double> _recentHeadings = [];
  DateTime? _lastUpdateTime;
  
  // Streams and subscriptions
  late StreamSubscription<StepCount> _stepSubscription;
  late StreamSubscription<CompassEvent> _compassSubscription;
  late StreamSubscription<AccelerometerEvent> _accelerometerSubscription;
  
  // Controllers for external listening
  final StreamController<Position> _positionController = StreamController.broadcast();
  final StreamController<MovementData> _movementController = StreamController.broadcast();
  
  // Public streams
  Stream<Position> get positionStream => _positionController.stream;
  Stream<MovementData> get movementStream => _movementController.stream;
  
  // Getters
  Position? get currentPosition => _currentPosition;
  bool get isTracking => _currentPosition != null;

  Future<bool> initialize() async {
    try {
      print('DeadReckoningService: Initializing sensors...');
      
      // Initialize pedometer
      _stepSubscription = Pedometer.stepCountStream.listen(
        _onStepCount,
        onError: (error) => print('DeadReckoningService: Pedometer error: $error'),
      );
      
      // Initialize compass
      _compassSubscription = FlutterCompass.events!.listen(
        _onCompassUpdate,
        onError: (error) => print('DeadReckoningService: Compass error: $error'),
      );
      
      // Initialize accelerometer for additional movement detection
      _accelerometerSubscription = accelerometerEvents.listen(
        _onAccelerometerUpdate,
        onError: (error) => print('DeadReckoningService: Accelerometer error: $error'),
      );
      
      print('DeadReckoningService: Initialized successfully');
      return true;
    } catch (e) {
      print('DeadReckoningService: Initialization failed: $e');
      return false;
    }
  }

  void startTracking(Position initialPosition) {
    _currentPosition = initialPosition;
    _lastKnownPosition = initialPosition;
    _lastUpdateTime = DateTime.now();
    _stepCountOffset = _lastStepCount; // Reset step counting from current position
    
    print('DeadReckoningService: Started tracking from $initialPosition');
  }

  void updateKnownPosition(Position confirmedPosition) {
    _lastKnownPosition = confirmedPosition;
    _currentPosition = confirmedPosition;
    _lastUpdateTime = DateTime.now();
    _stepCountOffset = _lastStepCount; // Reset step counting from confirmed position
    
    print('DeadReckoningService: Updated to confirmed position: $confirmedPosition');
    _positionController.add(confirmedPosition);
  }

  void _onStepCount(StepCount stepCount) {
    if (_currentPosition == null) return;
    
    int currentStepCount = stepCount.steps;
    int stepsTaken = currentStepCount - _stepCountOffset;
    
    if (stepsTaken > 0) {
      _updatePositionFromSteps(stepsTaken);
    }
    
    _lastStepCount = currentStepCount;
  }

  void _onCompassUpdate(CompassEvent compassEvent) {
    if (compassEvent.heading != null) {
      double heading = compassEvent.heading!;
      
      // Smooth heading using moving average
      _recentHeadings.add(heading);
      if (_recentHeadings.length > 5) {
        _recentHeadings.removeAt(0);
      }
      
      _lastHeading = _calculateAverageHeading(_recentHeadings);
    }
  }

  void _onAccelerometerUpdate(AccelerometerEvent event) {
    // Could be used for additional movement validation
    // For now, we primarily rely on pedometer and compass
  }

  void _updatePositionFromSteps(int stepsTaken) {
    if (_currentPosition == null) return;
    
    DateTime now = DateTime.now();
    Duration timeSinceLastUpdate = _lastUpdateTime != null 
        ? now.difference(_lastUpdateTime!) 
        : Duration.zero;
    
    // Calculate distance moved
    double distanceMoved = stepsTaken * _averageStepLength;
    
    // Calculate new position using current heading
    double headingRadians = _lastHeading * pi / 180;
    double deltaX = distanceMoved * sin(headingRadians);
    double deltaY = distanceMoved * cos(headingRadians);
    
    double newX = _currentPosition!.x + deltaX;
    double newY = _currentPosition!.y + deltaY;
    
    // Calculate confidence based on time since last confirmed position
    double confidence = _calculateConfidence(timeSinceLastUpdate);
    
    _currentPosition = Position(
      x: newX,
      y: newY,
      heading: _lastHeading,
      timestamp: now,
      confidence: confidence,
    );
    
    // Calculate velocity
    double velocity = timeSinceLastUpdate.inMilliseconds > 0 
        ? distanceMoved / (timeSinceLastUpdate.inMilliseconds / 1000.0)
        : 0.0;
    
    // Emit movement data
    MovementData movement = MovementData(
      stepCount: stepsTaken,
      distance: distanceMoved,
      averageHeading: _lastHeading,
      duration: timeSinceLastUpdate,
      velocity: velocity,
    );
    
    _lastUpdateTime = now;
    
    // Emit updates
    _positionController.add(_currentPosition!);
    _movementController.add(movement);
    
    print('DeadReckoningService: Updated position after $stepsTaken steps: $_currentPosition');
  }

  double _calculateAverageHeading(List<double> headings) {
    if (headings.isEmpty) return 0.0;
    
    // Handle circular nature of compass headings
    double sinSum = 0.0;
    double cosSum = 0.0;
    
    for (double heading in headings) {
      double radians = heading * pi / 180;
      sinSum += sin(radians);
      cosSum += cos(radians);
    }
    
    double averageRadians = atan2(sinSum / headings.length, cosSum / headings.length);
    double averageDegrees = averageRadians * 180 / pi;
    
    // Normalize to 0-360 range
    if (averageDegrees < 0) averageDegrees += 360;
    
    return averageDegrees;
  }

  double _calculateConfidence(Duration timeSinceLastConfirmed) {
    // Confidence decreases over time since last visual confirmation
    if (timeSinceLastConfirmed.inMilliseconds <= 0) return 1.0;
    
    double timeRatio = timeSinceLastConfirmed.inMilliseconds / _maxConfidenceTime.inMilliseconds;
    double confidence = max(0.1, 1.0 - (timeRatio * _headingDecayFactor));
    
    return min(1.0, confidence);
  }

  // Get estimated position at future time based on current movement
  Position? predictPosition(Duration futureTime) {
    if (_currentPosition == null) return null;
    
    // Simple prediction based on current heading and average velocity
    MovementData? lastMovement = _getLastMovement();
    if (lastMovement == null) return _currentPosition;
    
    double futureDistance = lastMovement.velocity * (futureTime.inMilliseconds / 1000.0);
    double headingRadians = _currentPosition!.heading * pi / 180;
    
    double deltaX = futureDistance * sin(headingRadians);
    double deltaY = futureDistance * cos(headingRadians);
    
    return Position(
      x: _currentPosition!.x + deltaX,
      y: _currentPosition!.y + deltaY,
      heading: _currentPosition!.heading,
      timestamp: _currentPosition!.timestamp.add(futureTime),
      confidence: max(0.1, _currentPosition!.confidence - 0.2), // Reduced confidence for prediction
    );
  }

  MovementData? _getLastMovement() {
    // This would store the last movement data
    // For simplicity, we'll calculate it on demand
    return null;
  }

  // Check if current position deviates significantly from expected position
  bool isPositionDeviation(Position expectedPosition, double toleranceMeters) {
    if (_currentPosition == null) return false;
    
    double deviation = _currentPosition!.distanceTo(expectedPosition);
    return deviation > toleranceMeters;
  }

  // Get movement summary since last known position
  MovementData? getMovementSinceLastKnown() {
    if (_currentPosition == null || _lastKnownPosition == null) return null;
    
    double distance = _lastKnownPosition!.distanceTo(_currentPosition!);
    Duration duration = _currentPosition!.timestamp.difference(_lastKnownPosition!.timestamp);
    double velocity = duration.inMilliseconds > 0 
        ? distance / (duration.inMilliseconds / 1000.0) 
        : 0.0;
    
    // Estimate step count based on distance
    int estimatedSteps = (distance / _averageStepLength).round();
    
    return MovementData(
      stepCount: estimatedSteps,
      distance: distance,
      averageHeading: _currentPosition!.heading,
      duration: duration,
      velocity: velocity,
    );
  }

  void pauseTracking() {
    // Stop updating position but keep sensors active
    _currentPosition = null;
    print('DeadReckoningService: Tracking paused');
  }

  void resumeTracking(Position resumePosition) {
    startTracking(resumePosition);
    print('DeadReckoningService: Tracking resumed');
  }

  void dispose() {
    _stepSubscription.cancel();
    _compassSubscription.cancel();
    _accelerometerSubscription.cancel();
    _positionController.close();
    _movementController.close();
    print('DeadReckoningService: Disposed');
  }
} 