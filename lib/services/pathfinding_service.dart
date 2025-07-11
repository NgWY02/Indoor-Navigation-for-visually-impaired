import 'dart:math';
import 'package:collection/collection.dart';

class NavigationNode {
  final String id;
  final String name;
  final String description;
  final double x;
  final double y;
  final int floor;
  final Map<String, dynamic> metadata;

  NavigationNode({
    required this.id,
    required this.name,
    required this.description,
    required this.x,
    required this.y,
    required this.floor,
    this.metadata = const {},
  });

  factory NavigationNode.fromJson(Map<String, dynamic> json) {
    return NavigationNode(
      id: json['id'],
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      x: (json['x'] ?? 0.0).toDouble(),
      y: (json['y'] ?? 0.0).toDouble(),
      floor: json['floor'] ?? 0,
      metadata: json['metadata'] ?? {},
    );
  }
}

class NavigationConnection {
  final String id;
  final String nodeAId;
  final String nodeBId;
  final double? distanceMeters;
  final int? steps;
  final double? averageHeading;
  final String? customInstruction;
  final List<Map<String, dynamic>>? confirmationObjects;

  NavigationConnection({
    required this.id,
    required this.nodeAId,
    required this.nodeBId,
    this.distanceMeters,
    this.steps,
    this.averageHeading,
    this.customInstruction,
    this.confirmationObjects,
  });

  factory NavigationConnection.fromJson(Map<String, dynamic> json) {
    return NavigationConnection(
      id: json['id'],
      nodeAId: json['node_a_id'],
      nodeBId: json['node_b_id'],
      distanceMeters: json['distance_meters']?.toDouble(),
      steps: json['steps'],
      averageHeading: json['average_heading']?.toDouble(),
      customInstruction: json['custom_instruction'],
      confirmationObjects: json['confirmation_objects'] != null 
        ? List<Map<String, dynamic>>.from(json['confirmation_objects'])
        : null,
    );
  }
}

class NavigationStep {
  final NavigationNode fromNode;
  final NavigationNode toNode;
  final NavigationConnection connection;
  final String instruction;
  final double? heading;
  final double distanceMeters;
  final int stepCount;
  final List<Map<String, dynamic>> confirmationObjects;

  NavigationStep({
    required this.fromNode,
    required this.toNode,
    required this.connection,
    required this.instruction,
    this.heading,
    required this.distanceMeters,
    required this.stepCount,
    this.confirmationObjects = const [],
  });

  String get directionText {
    if (heading == null) return '';
    
    // Convert heading to cardinal direction
    double normalizedHeading = heading! % 360;
    if (normalizedHeading < 0) normalizedHeading += 360;
    
    if (normalizedHeading < 22.5 || normalizedHeading >= 337.5) return 'north';
    if (normalizedHeading < 67.5) return 'northeast';
    if (normalizedHeading < 112.5) return 'east';
    if (normalizedHeading < 157.5) return 'southeast';
    if (normalizedHeading < 202.5) return 'south';
    if (normalizedHeading < 247.5) return 'southwest';
    if (normalizedHeading < 292.5) return 'west';
    return 'northwest';
  }

  String get detailedInstruction {
    String baseInstruction = connection.customInstruction ?? 
        'Walk ${directionText} towards ${toNode.name}';
    
    if (confirmationObjects.isNotEmpty) {
      List<String> objectDescriptions = confirmationObjects
          .map((obj) => '${obj['type']} on your ${obj['side']}')
          .toList();
      baseInstruction += '. Look for ${objectDescriptions.join(', ')} to confirm you\'re on the right path.';
    }
    
    return baseInstruction;
  }
}

class NavigationRoute {
  final List<NavigationStep> steps;
  final double totalDistance;
  final int totalSteps;
  final Duration estimatedDuration;

  NavigationRoute({
    required this.steps,
    required this.totalDistance,
    required this.totalSteps,
    required this.estimatedDuration,
  });

  NavigationStep? get currentStep => steps.isNotEmpty ? steps.first : null;
  NavigationStep? get nextStep => steps.length > 1 ? steps[1] : null;
  bool get isComplete => steps.isEmpty;
  bool get hasNextStep => steps.length > 1;

  NavigationRoute removeFirstStep() {
    if (steps.isEmpty) return this;
    
    List<NavigationStep> remainingSteps = steps.sublist(1);
    double remainingDistance = remainingSteps.fold(0.0, (sum, step) => sum + step.distanceMeters);
    int remainingStepCount = remainingSteps.fold(0, (sum, step) => sum + step.stepCount);
    Duration remainingDuration = Duration(seconds: (remainingDistance * 1.2).round()); // ~1.2 seconds per meter
    
    return NavigationRoute(
      steps: remainingSteps,
      totalDistance: remainingDistance,
      totalSteps: remainingStepCount,
      estimatedDuration: remainingDuration,
    );
  }
}

class PathfindingService {
  late Map<String, NavigationNode> _nodes;
  late List<NavigationConnection> _connections;
  late Map<String, List<NavigationConnection>> _nodeConnections;

  void initialize(List<NavigationNode> nodes, List<NavigationConnection> connections) {
    _nodes = {for (var node in nodes) node.id: node};
    _connections = connections;
    
    // Build adjacency list for efficient pathfinding
    _nodeConnections = {};
    for (var connection in connections) {
      _nodeConnections.putIfAbsent(connection.nodeAId, () => []).add(connection);
      _nodeConnections.putIfAbsent(connection.nodeBId, () => []).add(connection);
    }
    
    print('PathfindingService: Initialized with ${nodes.length} nodes and ${connections.length} connections');
  }

  NavigationRoute? findRoute(String startNodeId, String endNodeId) {
    if (!_nodes.containsKey(startNodeId) || !_nodes.containsKey(endNodeId)) {
      print('PathfindingService: Start or end node not found');
      return null;
    }

    if (startNodeId == endNodeId) {
      print('PathfindingService: Start and end nodes are the same');
      return NavigationRoute(steps: [], totalDistance: 0, totalSteps: 0, estimatedDuration: Duration.zero);
    }

    // Use Dijkstra's algorithm to find shortest path
    Map<String, double> distances = {};
    Map<String, String?> previous = {};
    PriorityQueue<String> queue = PriorityQueue<String>((a, b) => 
        distances[a]!.compareTo(distances[b]!));

    // Initialize distances
    for (String nodeId in _nodes.keys) {
      distances[nodeId] = nodeId == startNodeId ? 0.0 : double.infinity;
      previous[nodeId] = null;
      queue.add(nodeId);
    }

    while (queue.isNotEmpty) {
      String currentNodeId = queue.removeFirst();
      
      if (currentNodeId == endNodeId) break;
      if (distances[currentNodeId] == double.infinity) break;

      // Check all neighboring nodes
      List<NavigationConnection> connections = _nodeConnections[currentNodeId] ?? [];
      
      for (NavigationConnection connection in connections) {
        String neighborId = connection.nodeAId == currentNodeId 
            ? connection.nodeBId 
            : connection.nodeAId;

        // Calculate distance (prefer actual measured distance, fallback to Euclidean)
        double connectionDistance = connection.distanceMeters ?? 
            _calculateEuclideanDistance(currentNodeId, neighborId);
            
        double alternativeDistance = distances[currentNodeId]! + connectionDistance;

        if (alternativeDistance < distances[neighborId]!) {
          distances[neighborId] = alternativeDistance;
          previous[neighborId] = currentNodeId;
          
          // Re-sort queue (simple re-add, PriorityQueue will handle sorting)
          queue.remove(neighborId);
          queue.add(neighborId);
        }
      }
    }

    // Reconstruct path
    List<String> path = [];
    String? currentNodeId = endNodeId;
    
    while (currentNodeId != null) {
      path.insert(0, currentNodeId);
      currentNodeId = previous[currentNodeId];
    }

    if (path.first != startNodeId) {
      print('PathfindingService: No path found from $startNodeId to $endNodeId');
      return null;
    }

    // Convert path to navigation steps
    List<NavigationStep> steps = [];
    double totalDistance = 0;
    int totalSteps = 0;

    for (int i = 0; i < path.length - 1; i++) {
      String fromNodeId = path[i];
      String toNodeId = path[i + 1];
      
      NavigationConnection? connection = _findConnection(fromNodeId, toNodeId);
      if (connection == null) {
        print('PathfindingService: Connection not found between $fromNodeId and $toNodeId');
        return null;
      }

      NavigationNode fromNode = _nodes[fromNodeId]!;
      NavigationNode toNode = _nodes[toNodeId]!;

      double stepDistance = connection.distanceMeters ?? 
          _calculateEuclideanDistance(fromNodeId, toNodeId);
      int stepCount = connection.steps ?? (stepDistance * 1.4).round(); // ~1.4 steps per meter

      String instruction = _generateInstruction(fromNode, toNode, connection);

      steps.add(NavigationStep(
        fromNode: fromNode,
        toNode: toNode,
        connection: connection,
        instruction: instruction,
        heading: connection.averageHeading,
        distanceMeters: stepDistance,
        stepCount: stepCount,
        confirmationObjects: connection.confirmationObjects ?? [],
      ));

      totalDistance += stepDistance;
      totalSteps += stepCount;
    }

    Duration estimatedDuration = Duration(seconds: (totalDistance * 1.2).round());

    print('PathfindingService: Found route with ${steps.length} steps, ${totalDistance.toStringAsFixed(1)}m total');

    return NavigationRoute(
      steps: steps,
      totalDistance: totalDistance,
      totalSteps: totalSteps,
      estimatedDuration: estimatedDuration,
    );
  }

  NavigationConnection? _findConnection(String nodeAId, String nodeBId) {
    return _connections.firstWhereOrNull((connection) =>
        (connection.nodeAId == nodeAId && connection.nodeBId == nodeBId) ||
        (connection.nodeAId == nodeBId && connection.nodeBId == nodeAId));
  }

  double _calculateEuclideanDistance(String nodeAId, String nodeBId) {
    NavigationNode nodeA = _nodes[nodeAId]!;
    NavigationNode nodeB = _nodes[nodeBId]!;
    
    return sqrt(pow(nodeB.x - nodeA.x, 2) + pow(nodeB.y - nodeA.y, 2));
  }

  String _generateInstruction(
    NavigationNode fromNode,
    NavigationNode toNode,
    NavigationConnection connection
  ) {
    if (connection.customInstruction != null && connection.customInstruction!.isNotEmpty) {
      return connection.customInstruction!;
    }

    // Generate basic direction instruction
    String direction = '';
    if (connection.averageHeading != null) {
      double heading = connection.averageHeading!;
      if (heading >= 315 || heading < 45) direction = 'north';
      else if (heading < 135) direction = 'east';
      else if (heading < 225) direction = 'south';
      else direction = 'west';
    }

    double distance = connection.distanceMeters ?? 
        _calculateEuclideanDistance(fromNode.id, toNode.id);

    return 'Head $direction towards ${toNode.name} for ${distance.toStringAsFixed(0)} meters';
  }

  // Find nodes within a certain radius for potential destination selection
  List<NavigationNode> findNearbyNodes(String centerNodeId, double radiusMeters) {
    if (!_nodes.containsKey(centerNodeId)) return [];

    NavigationNode centerNode = _nodes[centerNodeId]!;
    List<NavigationNode> nearbyNodes = [];

    for (NavigationNode node in _nodes.values) {
      if (node.id == centerNodeId) continue;
      
      double distance = sqrt(
        pow(node.x - centerNode.x, 2) + pow(node.y - centerNode.y, 2)
      );
      
      if (distance <= radiusMeters) {
        nearbyNodes.add(node);
      }
    }

    nearbyNodes.sort((a, b) {
      double distanceA = sqrt(pow(a.x - centerNode.x, 2) + pow(a.y - centerNode.y, 2));
      double distanceB = sqrt(pow(b.x - centerNode.x, 2) + pow(b.y - centerNode.y, 2));
      return distanceA.compareTo(distanceB);
    });

    return nearbyNodes;
  }

  // Get all possible destinations from current location
  List<NavigationNode> getAllDestinations(String currentNodeId) {
    List<NavigationNode> destinations = _nodes.values
        .where((node) => node.id != currentNodeId)
        .toList();
        
    destinations.sort((a, b) => a.name.compareTo(b.name));
    return destinations;
  }
} 