import 'dart:async';
import 'dart:io';
import 'dart:math';
import '../services/clip_service.dart';
import '../services/supabase_service.dart';
import '../models/path_models.dart';

class LocationMatch {
  final String nodeId;
  final String nodeName;
  final double confidence;
  final double similarity;
  final String mapId;

  LocationMatch({
    required this.nodeId,
    required this.nodeName,
    required this.confidence,
    required this.similarity,
    required this.mapId,
  });
}

class PositionLocalizationService {
  final ClipService _clipService;
  final SupabaseService _supabaseService;
  
  // Configuration
  static const double _minimumConfidenceThreshold = 0.6;
  static const int _maxSamplesForLocalization = 5;
  static const Duration _samplingInterval = Duration(seconds: 2);
  
  // State
  List<List<double>> _capturedEmbeddings = [];
  Timer? _samplingTimer;
  StreamController<String>? _statusController;
  
  PositionLocalizationService({
    required ClipService clipService,
    required SupabaseService supabaseService,
  }) : _clipService = clipService, _supabaseService = supabaseService;

  /// Start continuous sampling for position localization
  Stream<String> startLocalization() {
    _statusController = StreamController<String>();
    _capturedEmbeddings.clear();
    
    _statusController!.add('Starting position localization...');
    _statusController!.add('Please hold your camera steady and look around slowly');
    
    // Start sampling images at regular intervals
    _samplingTimer = Timer.periodic(_samplingInterval, (timer) {
      _captureSample();
      
      if (_capturedEmbeddings.length >= _maxSamplesForLocalization) {
        timer.cancel();
        _processLocalization();
      } else {
        _statusController!.add('Capturing sample ${_capturedEmbeddings.length + 1}/$_maxSamplesForLocalization...');
      }
    });
    
    return _statusController!.stream;
  }
  
  /// Stop localization process
  void stopLocalization() {
    _samplingTimer?.cancel();
    _statusController?.close();
    _capturedEmbeddings.clear();
  }
  
  /// Localize user position based on captured embeddings
  Future<LocationMatch?> localizePosition(File imageFile) async {
    try {
      // Generate embedding for the current image with people removal preprocessing
      final currentEmbedding = await _clipService.generatePreprocessedEmbedding(imageFile);
      
      // Get all available nodes with embeddings from database
      final allNodes = await _getAllNodesWithEmbeddings();
      
      if (allNodes.isEmpty) {
        throw Exception('No reference locations found in database');
      }
      
      // Find best matching location
      LocationMatch? bestMatch;
      double bestSimilarity = 0.0;
      
      for (final node in allNodes) {
        // Calculate similarity with each embedding for this node
        final nodeEmbeddings = await _getNodeEmbeddings(node['id']);
        
        for (final embedding in nodeEmbeddings) {
          final similarity = _calculateCosineSimilarity(currentEmbedding, embedding);
          
          if (similarity > bestSimilarity) {
            bestSimilarity = similarity;
            bestMatch = LocationMatch(
              nodeId: node['id'],
              nodeName: node['name'],
              confidence: _calculateConfidence(similarity),
              similarity: similarity,
              mapId: node['map_id'],
            );
          }
        }
      }
      
      // Return match only if confidence is above threshold
      if (bestMatch != null && bestMatch.confidence >= _minimumConfidenceThreshold) {
        return bestMatch;
      }
      
      return null;
    } catch (e) {
      print('Error in position localization: $e');
      return null;
    }
  }
  
  /// Get available routes from a specific location
  Future<List<NavigationRoute>> getAvailableRoutes(String fromNodeId) async {
    try {
      // Get all navigation paths that start from this node
      final paths = await _supabaseService.loadAllPaths();
      
      final availableRoutes = <NavigationRoute>[];
      
      for (final path in paths) {
        if (path.startLocationId == fromNodeId) {
          // Get destination node details
          final destinationNode = await _getNodeDetails(path.endLocationId);
          
          if (destinationNode != null) {
            availableRoutes.add(NavigationRoute(
              pathId: path.id,
              pathName: path.name,
              startNodeId: path.startLocationId,
              endNodeId: path.endLocationId,
              startNodeName: await _getNodeName(path.startLocationId),
              endNodeName: destinationNode['name'],
              estimatedDistance: path.estimatedDistance,
              estimatedSteps: path.estimatedSteps,
              estimatedDuration: _estimateDuration(path.estimatedDistance),
              waypoints: path.waypoints,
            ));
          }
        }
      }
      
      return availableRoutes;
    } catch (e) {
      print('Error getting available routes: $e');
      return [];
    }
  }
  
  // Private methods
  
  void _captureSample() async {
    try {
      // This would need camera access - for now, simulate
      // In real implementation, capture image and generate embedding
      _statusController!.add('Analyzing visual features...');
      
      // Placeholder for actual image capture and embedding generation
    } catch (e) {
      _statusController!.add('Error capturing sample: $e');
    }
  }
  
  void _processLocalization() async {
    _statusController!.add('Processing location data...');
    
    try {
      // Average the captured embeddings for better accuracy
      final averageEmbedding = _calculateAverageEmbedding(_capturedEmbeddings);
      
      // Find best matching location
      final allNodes = await _getAllNodesWithEmbeddings();
      LocationMatch? bestMatch;
      double bestSimilarity = 0.0;
      
      for (final node in allNodes) {
        final nodeEmbeddings = await _getNodeEmbeddings(node['id']);
        
        for (final embedding in nodeEmbeddings) {
          final similarity = _calculateCosineSimilarity(averageEmbedding, embedding);
          
          if (similarity > bestSimilarity) {
            bestSimilarity = similarity;
            bestMatch = LocationMatch(
              nodeId: node['id'],
              nodeName: node['name'],
              confidence: _calculateConfidence(similarity),
              similarity: similarity,
              mapId: node['map_id'],
            );
          }
        }
      }
      
      if (bestMatch != null && bestMatch.confidence >= _minimumConfidenceThreshold) {
        _statusController!.add('Location identified: ${bestMatch.nodeName} (${(bestMatch.confidence * 100).round()}% confidence)');
      } else {
        _statusController!.add('Unable to determine location. Please try from a different angle.');
      }
      
    } catch (e) {
      _statusController!.add('Error processing location: $e');
    }
    
    _statusController!.close();
  }
  
  Future<List<Map<String, dynamic>>> _getAllNodesWithEmbeddings() async {
    // Query all nodes that have associated embeddings
    return await _supabaseService.client
        .from('map_nodes')
        .select('id, name, map_id')
        .not('id', 'in', '()'); // Get all nodes
  }
  
  Future<List<List<double>>> _getNodeEmbeddings(String nodeId) async {
    try {
      // Get embeddings associated with this node from place_embeddings table
      final response = await _supabaseService.client
          .from('place_embeddings')
          .select('embedding')
          .eq('node_id', nodeId);
      
      final embeddings = <List<double>>[];
      for (final item in response as List) {
        final embeddingStr = item['embedding'] as String;
        // Parse embedding string to List<double>
        final embedding = _parseEmbeddingString(embeddingStr);
        if (embedding.isNotEmpty) {
          embeddings.add(embedding);
        }
      }
      
      return embeddings;
    } catch (e) {
      print('Error getting node embeddings: $e');
      return [];
    }
  }
  
  Future<Map<String, dynamic>?> _getNodeDetails(String nodeId) async {
    try {
      final response = await _supabaseService.client
          .from('map_nodes')
          .select('*')
          .eq('id', nodeId)
          .single();
      
      return response;
    } catch (e) {
      print('Error getting node details: $e');
      return null;
    }
  }
  
  Future<String> _getNodeName(String nodeId) async {
    try {
      final node = await _getNodeDetails(nodeId);
      return node?['name'] ?? 'Unknown Location';
    } catch (e) {
      return 'Unknown Location';
    }
  }
  
  List<double> _parseEmbeddingString(String embeddingStr) {
    try {
      // Remove brackets and split by comma
      final cleanString = embeddingStr.replaceAll('[', '').replaceAll(']', '');
      if (cleanString.isEmpty) return [];
      
      return cleanString.split(',').map((e) => double.parse(e.trim())).toList();
    } catch (e) {
      print('Error parsing embedding string: $e');
      return [];
    }
  }
  
  List<double> _calculateAverageEmbedding(List<List<double>> embeddings) {
    if (embeddings.isEmpty) return [];
    
    final dimensions = embeddings.first.length;
    final averageEmbedding = List<double>.filled(dimensions, 0.0);
    
    for (final embedding in embeddings) {
      for (int i = 0; i < dimensions; i++) {
        averageEmbedding[i] += embedding[i];
      }
    }
    
    for (int i = 0; i < dimensions; i++) {
      averageEmbedding[i] /= embeddings.length;
    }
    
    return averageEmbedding;
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
  
  double _calculateConfidence(double similarity) {
    // Convert similarity to confidence (0.0 to 1.0)
    // Apply some curve to make confidence more meaningful
    return pow(similarity, 0.5).toDouble().clamp(0.0, 1.0);
  }
  
  Duration _estimateDuration(double distanceMeters) {
    // Estimate walking time: average walking speed ~1.4 m/s
    final seconds = (distanceMeters / 1.4).round();
    return Duration(seconds: seconds);
  }
  
  void dispose() {
    stopLocalization();
  }
}

/// Represents an available navigation route
class NavigationRoute {
  final String pathId;
  final String pathName;
  final String startNodeId;
  final String endNodeId;
  final String startNodeName;
  final String endNodeName;
  final double estimatedDistance;
  final int estimatedSteps;
  final Duration estimatedDuration;
  final List<PathWaypoint> waypoints;

  NavigationRoute({
    required this.pathId,
    required this.pathName,
    required this.startNodeId,
    required this.endNodeId,
    required this.startNodeName,
    required this.endNodeName,
    required this.estimatedDistance,
    required this.estimatedSteps,
    required this.estimatedDuration,
    required this.waypoints,
  });
  
  String get formattedDistance {
    if (estimatedDistance < 1000) {
      return '${estimatedDistance.round()}m';
    } else {
      return '${(estimatedDistance / 1000).toStringAsFixed(1)}km';
    }
  }
  
  String get formattedDuration {
    final minutes = estimatedDuration.inMinutes;
    if (minutes < 60) {
      return '${minutes}min';
    } else {
      final hours = minutes ~/ 60;
      final remainingMinutes = minutes % 60;
      return '${hours}h ${remainingMinutes}min';
    }
  }
}
