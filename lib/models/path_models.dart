// Models for path recording and navigation

enum TurnType {
  straight,
  left,
  right,
  uTurn,
}

enum InstructionType {
  continue_,
  approach,
  turnLeft,
  turnRight,
  arrive,
  relocate,
}

class PathWaypoint {
  final String id;
  final List<double> embedding;
  final double heading;
  final double headingChange;
  final TurnType turnType;
  final bool isDecisionPoint;
  final String? landmarkDescription;
  final double? distanceFromPrevious;
  final DateTime timestamp;
  final int sequenceNumber;

  PathWaypoint({
    required this.id,
    required this.embedding,
    required this.heading,
    required this.headingChange,
    required this.turnType,
    required this.isDecisionPoint,
    this.landmarkDescription,
    this.distanceFromPrevious,
    required this.timestamp,
    required this.sequenceNumber,
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
      'timestamp': timestamp.toIso8601String(),
      'sequence_number': sequenceNumber,
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
      timestamp: DateTime.parse(json['timestamp']),
      sequenceNumber: json['sequence_number'],
    );
  }
}

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

class NavigationInstruction {
  final String text;
  final InstructionType type;
  final double? expectedHeading;
  final List<double>? confirmationEmbedding;
  final String? landmarkBefore;
  final String? landmarkAfter;
  final double? distanceToNext;

  NavigationInstruction(
    this.text,
    this.type, {
    this.expectedHeading,
    this.confirmationEmbedding,
    this.landmarkBefore,
    this.landmarkAfter,
    this.distanceToNext,
  });
}

enum TurnStatus {
  notTurning,
  inProgress,
  completed,
  correction,
}

class TurnStatusResult {
  final TurnStatus status;
  final String? message;

  TurnStatusResult(this.status, [this.message]);

  factory TurnStatusResult.correction(String message) =>
      TurnStatusResult(TurnStatus.correction, message);
}
