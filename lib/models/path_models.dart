import 'dart:ui' show Rect;
import 'package:flutter/foundation.dart';

// Enum for turn directions
enum TurnDirection { left, right, straight }

// Enum for turn types
enum TurnType {
  straight,
  left,
  right,
}

// Enum for landmark types
enum LandmarkType { yolo, custom }

// Enum for recording states
enum RecordingState { idle, recording, checkpoint, review }

// Data model for a detected object from YOLO
class DetectedObject {
  final String label;
  final double confidence;
  final Rect boundingBox;
  final Uint8List? imageFrame;
  final int stepCount;
  final double distance;
  final DateTime timestamp;

  DetectedObject({
    required this.label,
    required this.confidence,
    required this.boundingBox,
    this.imageFrame,
    required this.stepCount,
    required this.distance,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'confidence': confidence,
      'boundingBox': {
        'left': boundingBox.left,
        'top': boundingBox.top,
        'right': boundingBox.right,
        'bottom': boundingBox.bottom,
      },
      'stepCount': stepCount,
      'distance': distance,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory DetectedObject.fromJson(Map<String, dynamic> json) {
    final bbox = json['boundingBox'];
    return DetectedObject(
      label: json['label'],
      confidence: json['confidence'],
      boundingBox: Rect.fromLTRB(
        bbox['left'],
        bbox['top'],
        bbox['right'],
        bbox['bottom'],
      ),
      stepCount: json['stepCount'],
      distance: json['distance'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}

// Data model for a landmark (manual or auto-detected)
class Landmark {
  final String id;
  final LandmarkType type;
  final String label;
  final Rect boundingBox;
  final Uint8List imageFrame;
  final double confidence;
  final int stepCount;
  final double distance;
  final DateTime timestamp;
  final bool isSelected; // For review screen

  Landmark({
    required this.id,
    required this.type,
    required this.label,
    required this.boundingBox,
    required this.imageFrame,
    required this.confidence,
    required this.stepCount,
    required this.distance,
    required this.timestamp,
    this.isSelected = false,
  });

  Landmark copyWith({
    String? id,
    LandmarkType? type,
    String? label,
    Rect? boundingBox,
    Uint8List? imageFrame,
    double? confidence,
    int? stepCount,
    double? distance,
    DateTime? timestamp,
    bool? isSelected,
  }) {
    return Landmark(
      id: id ?? this.id,
      type: type ?? this.type,
      label: label ?? this.label,
      boundingBox: boundingBox ?? this.boundingBox,
      imageFrame: imageFrame ?? this.imageFrame,
      confidence: confidence ?? this.confidence,
      stepCount: stepCount ?? this.stepCount,
      distance: distance ?? this.distance,
      timestamp: timestamp ?? this.timestamp,
      isSelected: isSelected ?? this.isSelected,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.toString(),
      'label': label,
      'boundingBox': {
        'left': boundingBox.left,
        'top': boundingBox.top,
        'right': boundingBox.right,
        'bottom': boundingBox.bottom,
      },
      'confidence': confidence,
      'stepCount': stepCount,
      'distance': distance,
      'timestamp': timestamp.toIso8601String(),
      'isSelected': isSelected,
    };
  }

  factory Landmark.fromJson(Map<String, dynamic> json) {
    final bbox = json['boundingBox'];
    return Landmark(
      id: json['id'],
      type: LandmarkType.values.firstWhere(
        (e) => e.toString() == json['type'],
      ),
      label: json['label'],
      boundingBox: Rect.fromLTRB(
        bbox['left'],
        bbox['top'],
        bbox['right'],
        bbox['bottom'],
      ),
      imageFrame: Uint8List(0),
      confidence: json['confidence'],
      stepCount: json['stepCount'],
      distance: json['distance'],
      timestamp: DateTime.parse(json['timestamp']),
      isSelected: json['isSelected'] ?? false,
    );
  }
}

// Data model for a path segment
class PathSegment {
  final String id;
  final int startStepCount;
  final int endStepCount;
  final double distance;
  final Landmark? landmark;
  final TurnDirection action;
  final DateTime timestamp;

  PathSegment({
    required this.id,
    required this.startStepCount,
    required this.endStepCount,
    required this.distance,
    this.landmark,
    required this.action,
    required this.timestamp,
  });

  int get stepCount => endStepCount - startStepCount;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'startStepCount': startStepCount,
      'endStepCount': endStepCount,
      'distance': distance,
      'landmark': landmark?.toJson(),
      'action': action.toString(),
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory PathSegment.fromJson(Map<String, dynamic> json) {
    return PathSegment(
      id: json['id'],
      startStepCount: json['startStepCount'],
      endStepCount: json['endStepCount'],
      distance: json['distance'],
      landmark: json['landmark'] != null 
          ? Landmark.fromJson(json['landmark'])
          : null,
      action: TurnDirection.values.firstWhere(
        (e) => e.toString() == json['action'],
      ),
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}

// Data model for a complete recorded path
class RecordedPath {
  final String id;
  final String name;
  final String description;
  final List<PathSegment> segments;
  final List<Landmark> suggestedCheckpoints;
  final double totalDistance;
  final int totalSteps;
  final DateTime createdAt;
  final DateTime updatedAt;

  RecordedPath({
    required this.id,
    required this.name,
    required this.description,
    required this.segments,
    required this.suggestedCheckpoints,
    required this.totalDistance,
    required this.totalSteps,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'segments': segments.map((s) => s.toJson()).toList(),
      'suggestedCheckpoints': suggestedCheckpoints.map((c) => c.toJson()).toList(),
      'totalDistance': totalDistance,
      'totalSteps': totalSteps,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory RecordedPath.fromJson(Map<String, dynamic> json) {
    return RecordedPath(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      segments: (json['segments'] as List)
          .map((s) => PathSegment.fromJson(s))
          .toList(),
      suggestedCheckpoints: (json['suggestedCheckpoints'] as List)
          .map((c) => Landmark.fromJson(c))
          .toList(),
      totalDistance: json['totalDistance'],
      totalSteps: json['totalSteps'],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }
}

// Recording session state model
class RecordingSession {
  final String id;
  final RecordingState state;
  final List<PathSegment> segments;
  final List<DetectedObject> detectedObjects;
  final int currentStepCount;
  final double currentDistance;
  final int sessionStartSteps;
  final DateTime startTime;
  final Uint8List? frozenFrame;
  final List<DetectedObject>? frozenFrameObjects;

  RecordingSession({
    required this.id,
    required this.state,
    required this.segments,
    required this.detectedObjects,
    required this.currentStepCount,
    required this.currentDistance,
    required this.sessionStartSteps,
    required this.startTime,
    this.frozenFrame,
    this.frozenFrameObjects,
  });

  RecordingSession copyWith({
    String? id,
    RecordingState? state,
    List<PathSegment>? segments,
    List<DetectedObject>? detectedObjects,
    int? currentStepCount,
    double? currentDistance,
    int? sessionStartSteps,
    DateTime? startTime,
    Uint8List? frozenFrame,
    List<DetectedObject>? frozenFrameObjects,
  }) {
    return RecordingSession(
      id: id ?? this.id,
      state: state ?? this.state,
      segments: segments ?? this.segments,
      detectedObjects: detectedObjects ?? this.detectedObjects,
      currentStepCount: currentStepCount ?? this.currentStepCount,
      currentDistance: currentDistance ?? this.currentDistance,
      sessionStartSteps: sessionStartSteps ?? this.sessionStartSteps,
      startTime: startTime ?? this.startTime,
      frozenFrame: frozenFrame ?? this.frozenFrame,
      frozenFrameObjects: frozenFrameObjects ?? this.frozenFrameObjects,
    );
  }

  int get relativeStepCount => currentStepCount - sessionStartSteps;
}

// Additional models for navigation paths
class PathWaypoint {
  final String id;
  final List<double> embedding;
  final double heading;
  final double headingChange;
  final TurnType turnType;
  final bool isDecisionPoint;
  final String? landmarkDescription;
  final double? distanceFromPrevious;
  final int sequenceNumber;
  final DateTime timestamp;

  // People detection info from recording (for smart threshold adjustment)
  final bool peopleDetected;
  final int peopleCount;
  final List<double> peopleConfidenceScores;

  PathWaypoint({
    required this.id,
    required this.embedding,
    required this.heading,
    required this.headingChange,
    required this.turnType,
    required this.isDecisionPoint,
    this.landmarkDescription,
    this.distanceFromPrevious,
    required this.sequenceNumber,
    required this.timestamp,
    this.peopleDetected = false,
    this.peopleCount = 0,
    this.peopleConfidenceScores = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'embedding': embedding,
      'heading': heading,
      'heading_change': headingChange,
      'turn_type': turnType.name,
      'is_decision_point': isDecisionPoint,
      'landmark_description': landmarkDescription,
      'distance_from_previous': distanceFromPrevious,
      'sequence_number': sequenceNumber,
      'timestamp': timestamp.toIso8601String(),
      'people_detected': peopleDetected,
      'people_count': peopleCount,
      'people_confidence_scores': peopleConfidenceScores,
    };
  }

  factory PathWaypoint.fromJson(Map<String, dynamic> json) {
    return PathWaypoint(
      id: json['id'],
      embedding: List<double>.from(json['embedding']),
      heading: json['heading'].toDouble(),
      headingChange: json['heading_change'].toDouble(),
      turnType: TurnType.values.firstWhere((e) => e.name == json['turn_type']),
      isDecisionPoint: json['is_decision_point'],
      landmarkDescription: json['landmark_description'],
      distanceFromPrevious: json['distance_from_previous']?.toDouble(),
      sequenceNumber: json['sequence_number'],
      timestamp: DateTime.parse(json['timestamp']),
      peopleDetected: json['people_detected'] ?? false,
      peopleCount: json['people_count'] ?? 0,
      peopleConfidenceScores: json['people_confidence_scores'] != null
          ? List<double>.from(json['people_confidence_scores'])
          : [],
    );
  }
}

// Navigation path model for real-time navigation
class NavigationPath {
  final String id;
  final String name;
  final String startLocationId;
  final String endLocationId;
  final List<PathWaypoint> waypoints;
  final double estimatedDistance;
  final int estimatedSteps;
  final DateTime createdAt;
  final DateTime updatedAt;

  NavigationPath({
    required this.id,
    required this.name,
    required this.startLocationId,
    required this.endLocationId,
    required this.waypoints,
    required this.estimatedDistance,
    required this.estimatedSteps,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'start_location_id': startLocationId,
      'end_location_id': endLocationId,
      'waypoints': waypoints.map((w) => w.toJson()).toList(),
      'estimated_distance': estimatedDistance,
      'estimated_steps': estimatedSteps,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory NavigationPath.fromJson(Map<String, dynamic> json) {
    return NavigationPath(
      id: json['id'],
      name: json['name'],
      startLocationId: json['start_location_id'],
      endLocationId: json['end_location_id'],
      waypoints: (json['waypoints'] as List)
          .map((w) => PathWaypoint.fromJson(w))
          .toList(),
      estimatedDistance: json['estimated_distance'].toDouble(),
      estimatedSteps: json['estimated_steps'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }
}

// Navigation instruction enums and classes
enum InstructionType {
  continue_,
  approach,
  turnLeft,
  turnRight,
  arrive,
  relocate,
}

enum TurnStatus {
  notTurning,
  inProgress,
  completed,
  correction,
}

class NavigationInstruction {
  final String text;
  final InstructionType type;
  final double? distanceToNext;
  final double? expectedHeading;
  final List<double>? confirmationEmbedding;

  NavigationInstruction(
    this.text,
    this.type, {
    this.distanceToNext,
    this.expectedHeading,
    this.confirmationEmbedding,
  });

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'type': type.toString(),
      'distance_to_next': distanceToNext,
      'expected_heading': expectedHeading,
      'confirmation_embedding': confirmationEmbedding,
    };
  }

  factory NavigationInstruction.fromJson(Map<String, dynamic> json) {
    return NavigationInstruction(
      json['text'],
      InstructionType.values.firstWhere(
        (e) => e.toString() == json['type'],
        orElse: () => InstructionType.continue_,
      ),
      distanceToNext: json['distance_to_next']?.toDouble(),
      expectedHeading: json['expected_heading']?.toDouble(),
      confirmationEmbedding: json['confirmation_embedding']?.cast<double>(),
    );
  }
}

class TurnStatusResult {
  final TurnStatus status;
  final String? message;

  TurnStatusResult(this.status, {this.message});

  factory TurnStatusResult.correction(String message) {
    return TurnStatusResult(TurnStatus.correction, message: message);
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status.toString(),
      'message': message,
    };
  }

  factory TurnStatusResult.fromJson(Map<String, dynamic> json) {
    return TurnStatusResult(
      TurnStatus.values.firstWhere(
        (e) => e.toString() == json['status'],
        orElse: () => TurnStatus.notTurning,
      ),
      message: json['message'],
    );
  }
}
