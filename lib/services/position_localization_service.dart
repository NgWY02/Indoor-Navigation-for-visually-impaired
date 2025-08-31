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
      print('=== getAvailableRoutes() called ===');
      print('Looking for routes from node: $fromNodeId');

      // Get user profile to check organization
      final userProfile = await _supabaseService.getCurrentUserProfile();
      final userOrganizationId = userProfile?['organization_id'];
      print('👤 User organization ID: $userOrganizationId');

      if (userOrganizationId == null) {
        print('⚠️ WARNING: User has no organization assigned!');
        print('⚠️ This means they can only see paths they created themselves');
      }

      // Get all navigation paths that start from this node
      final paths = await _supabaseService.loadAllPaths();
      print('Found ${paths.length} total paths');

      final availableRoutes = <NavigationRoute>[];

      for (final path in paths) {
        print('Checking path: ${path.name} (ID: ${path.id})');
        print('  Start: ${path.startLocationId}, End: ${path.endLocationId}');
        print('  Current node: $fromNodeId');

        if (path.startLocationId == fromNodeId) {
          print('  ✅ Match found! Getting destination details...');

          // Get destination node details
          final destinationNode = await _getNodeDetails(path.endLocationId);

          if (destinationNode != null) {
            print('  ✅ Destination node found: ${destinationNode['name']}');

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

            print('  ✅ Route added: ${path.name}');
          } else {
            print('  ❌ Destination node not found');
          }
        } else {
          print('  ❌ No match for start node');
        }
      }

      print('Total available routes: ${availableRoutes.length}');
      return availableRoutes;
    } catch (e) {
      print('Error getting available routes: $e');
      return [];
    }
  }

  /// Localize position using multiple directional images
  Future<LocationMatch?> localizePositionFromDirections(List<File> directionImages) async {
    try {
      if (directionImages.isEmpty) {
        throw Exception('No direction images provided');
      }

      // Generate embeddings for all direction images
      final embeddings = <List<double>>[];
      for (final imageFile in directionImages) {
        final embedding = await _clipService.generatePreprocessedEmbedding(imageFile);
        embeddings.add(embedding);
      }

      // Average the embeddings for better accuracy
      final averageEmbedding = _calculateAverageEmbedding(embeddings);

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

      // Return match only if confidence is above threshold
      if (bestMatch != null && bestMatch.confidence >= _minimumConfidenceThreshold) {
        return bestMatch;
      }

      return null;
    } catch (e) {
      print('Error in directional position localization: $e');
      return null;
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
    try {
      // Get current user and their organization
      final userId = _supabaseService.currentUser?.id;
      if (userId == null) {
        print('❌ No user logged in for nodes query');
        return [];
      }

      // Get user's organization
      final userProfile = await _supabaseService.client
          .from('profiles')
          .select('organization_id')
          .eq('id', userId)
          .maybeSingle();

      final userOrganizationId = userProfile?['organization_id'];
      print('👤 User organization ID for nodes: $userOrganizationId');

      // Query nodes that have embeddings accessible to the user
      final embeddingsQuery = _supabaseService.client
          .from('place_embeddings')
          .select('node_id');

      final isAdminUser = await _supabaseService.isAdmin();

      if (isAdminUser) {
        // Admin users can see ALL content from their organization (including other admins' content)
        if (userOrganizationId != null) {
          embeddingsQuery.or('organization_id.eq.$userOrganizationId,organization_id.is.null');
          print('🔍 Admin user - filtering nodes by organization: $userOrganizationId (including null org for compatibility)');
        } else {
          // Admin with no organization can only see their own content
          embeddingsQuery.eq('user_id', userId);
          print('⚠️ Admin user (no organization) - filtering nodes by user: $userId');
        }
      } else {
        // Regular users can see content from their organization OR null organization_id (backward compatibility)
        if (userOrganizationId != null) {
          embeddingsQuery.or('organization_id.eq.$userOrganizationId,organization_id.is.null');
          print('🔍 Regular user - filtering nodes by organization: $userOrganizationId (including null org for compatibility)');
        } else {
          // Users without organization can only see their own content
          embeddingsQuery.eq('user_id', userId);
          print('⚠️ Regular user (no organization) - filtering nodes by user: $userId');
        }
      }

      final embeddingsResponse = await embeddingsQuery;
      final nodeIds = (embeddingsResponse as List)
          .map((item) => item['node_id'] as String)
          .toSet() // Remove duplicates
          .toList();

      if (nodeIds.isEmpty) {
        print('📊 No nodes with accessible embeddings found');
        return [];
      }

      // Get node details for these node IDs
      final nodesResponse = await _supabaseService.client
          .from('map_nodes')
          .select('id, name, map_id')
          .inFilter('id', nodeIds);

      print('📊 Found ${nodesResponse.length} nodes with accessible embeddings');
      return List<Map<String, dynamic>>.from(nodesResponse);
    } catch (e) {
      print('❌ Error getting nodes with embeddings: $e');
      return [];
    }
  }
  
  Future<List<List<double>>> _getNodeEmbeddings(String nodeId) async {
    try {
      // Get current user and their organization
      final userId = _supabaseService.currentUser?.id;
      if (userId == null) {
        print('❌ No user logged in for embedding query');
        return [];
      }

      // Get user's organization
      final userProfile = await _supabaseService.client
          .from('profiles')
          .select('organization_id')
          .eq('id', userId)
          .maybeSingle();

      final userOrganizationId = userProfile?['organization_id'];
      print('👤 User organization ID for embeddings: $userOrganizationId');

      // Query embeddings with organization filtering
      final query = _supabaseService.client
          .from('place_embeddings')
          .select('embedding')
          .eq('node_id', nodeId);

      final isAdminUser = await _supabaseService.isAdmin();

      final response;
      if (isAdminUser) {
        // Admin users can see ALL content from their organization (including other admins' content)
        if (userOrganizationId != null) {
          response = await query.or('organization_id.eq.$userOrganizationId,organization_id.is.null');
          print('🔍 Admin user - filtering embeddings by organization: $userOrganizationId (including null org for compatibility)');
        } else {
          // Admin with no organization can only see their own content
          response = await query.eq('user_id', userId);
          print('⚠️ Admin user (no organization) - filtering embeddings by user: $userId');
        }
      } else {
        // Regular users can see content from their organization OR null organization_id (backward compatibility)
        if (userOrganizationId != null) {
          response = await query.or('organization_id.eq.$userOrganizationId,organization_id.is.null');
          print('🔍 Regular user - filtering embeddings by organization: $userOrganizationId (including null org for compatibility)');
        } else {
          // Users without organization can only see their own content
          response = await query.eq('user_id', userId);
          print('⚠️ Regular user (no organization) - filtering embeddings by user: $userId');
        }
      }

      final embeddings = <List<double>>[];
      for (final item in response as List) {
        final embeddingStr = item['embedding'] as String;
        // Parse embedding string to List<double>
        final embedding = _parseEmbeddingString(embeddingStr);
        if (embedding.isNotEmpty) {
          embeddings.add(embedding);
        }
      }

      print('📊 Found ${embeddings.length} embeddings for node $nodeId');
      return embeddings;
    } catch (e) {
      print('❌ Error getting node embeddings: $e');
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
