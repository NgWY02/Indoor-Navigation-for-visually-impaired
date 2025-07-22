import 'dart:ui' show Rect;
import 'package:flutter/foundation.dart';

// Enum for turn directions
enum TurnDirection { left, right, straight }

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
      imageFrame: Uint8List(0), // Will be loaded separately
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