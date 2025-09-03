import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import '../models/path_models.dart';

class ClipService {
  static const String _defaultServerUrl = 'http://192.168.0.102:8000'; 
  final String serverUrl;
  
  ClipService({this.serverUrl = _defaultServerUrl});
  
  /// Check if CLIP server is running and accessible
  Future<bool> isServerAvailable() async {
    try {
      final response = await http.get(
        Uri.parse('$serverUrl/health'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 5));
      
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('CLIP server not available: $e');
      return false;
    }
  }
  
  /// Generate embeddings for an image file using CLIP (no preprocessing)
  Future<List<double>> generateImageEmbedding(File imageFile) async {
    return _generateEmbedding(imageFile, '/encode');
  }

  /// Generate embeddings without preprocessing - for recording
  Future<List<double>> generatePreprocessedEmbedding(File imageFile) async {
    return _generateEmbedding(imageFile, '/encode/preprocessed');
  }

  /// Generate embeddings for navigation (raw DINOv2, no inpainting) - for real-time navigation
  Future<List<double>> generateNavigationEmbedding(File imageFile) async {
    return _generateEmbedding(imageFile, '/encode/navigation');
  }

  /// Generate embeddings for navigation with inpainting (for real-time navigation accuracy)
  Future<List<double>> generateNavigationEmbeddingInpainted(File imageFile) async {
    return _generateEmbedding(imageFile, '/encode/inpainted');
  }

  /// Combined navigation method with inpainting: detect people + generate inpainted embedding + calculate threshold
  Future<NavigationEmbeddingResult> generateNavigationEmbeddingWithInpainting(
    File imageFile, {
    required double cleanSceneThreshold,
    required double peoplePresentThreshold,
    required double crowdedSceneThreshold,
  }) async {
    try {
      // Run people detection and inpainted embedding generation in parallel for speed
      final futures = await Future.wait([
        detectPeople(imageFile),
        generateNavigationEmbeddingInpainted(imageFile),
      ]);
      
      final peopleResult = futures[0] as PeopleDetectionResult;
      final embedding = futures[1] as List<double>;
      
      // Calculate dynamic threshold based on people presence with configurable values
      double threshold = _calculateNavigationThreshold(
        peopleResult.peopleCount, 
        peopleResult.confidenceScores,
        cleanSceneThreshold: cleanSceneThreshold,
        peoplePresentThreshold: peoplePresentThreshold,
        crowdedSceneThreshold: crowdedSceneThreshold,
      );
      
      return NavigationEmbeddingResult(
        embedding: embedding,
        peopleDetected: peopleResult.peopleDetected,
        peopleCount: peopleResult.peopleCount,
        confidenceScores: peopleResult.confidenceScores,
        recommendedThreshold: threshold,
      );
      
    } catch (e) {
      debugPrint('ClipService: Error in navigation embedding with inpainting: $e');
      // Return safe defaults using the provided threshold values
      return NavigationEmbeddingResult(
        embedding: List.filled(768, 0.0),
        peopleDetected: false,
        peopleCount: 0,
        confidenceScores: [],
        recommendedThreshold: cleanSceneThreshold, // Use the provided clean scene threshold
      );
    }
  }

  /// Smart navigation method: uses stored waypoint people info for optimal threshold
  Future<NavigationEmbeddingResult> generateSmartNavigationEmbedding(
    File imageFile,
    PathWaypoint targetWaypoint, {
    required double fixedThreshold,
  }) async {
    try {
      // Only generate embedding - NO people detection during navigation for consistent threshold
      final embedding = await generateNavigationEmbedding(imageFile);
      
      // Use configurable fixed threshold
      double threshold = fixedThreshold;
      
      debugPrint('Fixed threshold for waypoint: ${threshold.toStringAsFixed(2)} (no YOLO detection during recording)');
      
      return NavigationEmbeddingResult(
        embedding: embedding,
        peopleDetected: false, // Not detecting during navigation
        peopleCount: 0, // Not detecting during navigation  
        confidenceScores: [],
        recommendedThreshold: threshold,
      );
      
    } catch (e) {
      debugPrint('ClipService: Error in smart navigation embedding: $e');
      // Return safe defaults using the provided threshold
      return NavigationEmbeddingResult(
        embedding: List.filled(768, 0.0),
        peopleDetected: false,
        peopleCount: 0,
        confidenceScores: [],
        recommendedThreshold: fixedThreshold, // Use the provided threshold
      );
    }
  }

  /// Calculate FIXED navigation threshold based only on recording people info
  double calculateFixedNavigationThreshold({
    required bool recordingHadPeople,
    required int recordingPeopleCount,
    required double fixedThreshold,
  }) {
    // Since recording no longer uses inpainting, both recording and navigation use raw images
    // Use consistent threshold regardless of people presence
    double threshold = fixedThreshold;
    debugPrint('Raw-to-raw threshold: ${threshold.toStringAsFixed(2)}');
    return threshold;
  }

  /// Calculate smart navigation threshold based on recording vs navigation people presence
  double calculateSmartNavigationThreshold({
    required bool recordingHadPeople,
    required int recordingPeopleCount,
    required int navigationPeopleCount,
    required List<double> navigationConfidenceScores,
    required double cleanSceneThreshold,
    required double peoplePresentThreshold,
    required double mixedSceneThreshold,
  }) {
    debugPrint('Smart threshold: recording_people=$recordingPeopleCount, navigation_people=$navigationPeopleCount');
    
    // Since both recording and navigation use raw images now, adjust thresholds accordingly
    
    // Case 1: Both have no people (ideal case)
    if (!recordingHadPeople && navigationPeopleCount == 0) {
      debugPrint('Raw-clean-to-raw-clean case: threshold=${cleanSceneThreshold.toStringAsFixed(2)}');
      return cleanSceneThreshold; // High confidence for clean comparisons
    }
    
    // Case 2: Both have people
    else if (recordingHadPeople && navigationPeopleCount > 0) {
      // Both sides have people, moderate threshold
      double avgConfidence = navigationConfidenceScores.isNotEmpty 
          ? navigationConfidenceScores.reduce((a, b) => a + b) / navigationConfidenceScores.length 
          : 0.5;
      double threshold = peoplePresentThreshold - (avgConfidence * 0.03);
      debugPrint('Raw-people-to-raw-people case: threshold=${threshold.toStringAsFixed(2)}');
      return threshold.clamp(0.65, 0.80);
    }
    
    // Case 3: Recording has no people, navigation has people
    else if (!recordingHadPeople && navigationPeopleCount > 0) {
      // Clean recording, people in navigation - need lower threshold
      debugPrint('Raw-clean-to-raw-people case: threshold=${mixedSceneThreshold.toStringAsFixed(2)}');
      return mixedSceneThreshold;
    }
    
    // Case 4: Recording has people, navigation has no people
    else {
      // People in recording, clean navigation - need lower threshold
      debugPrint('Raw-people-to-raw-clean case: threshold=${mixedSceneThreshold.toStringAsFixed(2)}');
      return mixedSceneThreshold;
    }
  }

  /// Calculate dynamic navigation threshold based on people presence (configurable)
  double _calculateNavigationThreshold(
    int peopleCount, 
    List<double> confidenceScores, {
    required double cleanSceneThreshold,
    required double peoplePresentThreshold,
    required double crowdedSceneThreshold,
  }) {
    if (peopleCount == 0) {
      return cleanSceneThreshold; // Configurable clean scene threshold
    } else if (peopleCount <= 2) {
      // Moderate reduction for 1-2 people
      double avgConfidence = confidenceScores.isNotEmpty 
          ? confidenceScores.reduce((a, b) => a + b) / confidenceScores.length 
          : 0.5;
      return peoplePresentThreshold - (avgConfidence * 0.05); // Use configurable base
    } else {
      // Significant reduction for crowds
      return crowdedSceneThreshold; // Configurable crowded scene threshold
    }
  }

  /// Detect people in an image without full preprocessing
  Future<PeopleDetectionResult> detectPeople(File imageFile) async {
    try {
      debugPrint('ClipService: Detecting people in ${imageFile.path}');
      
      // Check if server is available
      if (!await isServerAvailable()) {
        throw Exception('CLIP server is not available. Please start the server first.');
      }
      
      // Read original image bytes
      final originalBytes = await imageFile.readAsBytes();
      
      // Prepare request
      final request = http.MultipartRequest('POST', Uri.parse('$serverUrl/detect/people'));
      request.files.add(http.MultipartFile.fromBytes('image', originalBytes, filename: 'image.jpg'));
      
      // Send request
      final streamedResponse = await request.send().timeout(const Duration(seconds: 15));
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        
        final result = PeopleDetectionResult(
          peopleDetected: responseData['people_detected'] ?? false,
          peopleCount: responseData['people_count'] ?? 0,
          confidenceScores: List<double>.from(responseData['confidence_scores'] ?? []),
        );
        
        // DEBUG: Check server response
        debugPrint('DEBUG ClipService.detectPeople: ${result.toString()}');
        return result;
      } else {
        throw Exception('CLIP server error: ${response.statusCode} - ${response.body}');
      }
      
    } catch (e) {
      debugPrint('ClipService: Error detecting people: $e');
      // Return default (no people detected) as fallback
      return PeopleDetectionResult(
        peopleDetected: false,
        peopleCount: 0,
        confidenceScores: [],
      );
    }
  }

  /// Internal method for embedding generation with different endpoints
  Future<List<double>> _generateEmbedding(File imageFile, String endpoint) async {
    try {
      debugPrint('ClipService: Generating embedding for ${imageFile.path} via $endpoint');
      
      // Check if server is available
      if (!await isServerAvailable()) {
        throw Exception('CLIP server is not available. Please start the server first.');
      }
      
      // Read original image bytes (server will handle resize + preprocessing)
      final originalBytes = await imageFile.readAsBytes();
      
      // Prepare request
      final request = http.MultipartRequest('POST', Uri.parse('$serverUrl$endpoint'));
      request.files.add(http.MultipartFile.fromBytes('image', originalBytes, filename: 'image.jpg'));
      
      // Send request
      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        
        // Extract embedding from response
        if (responseData['embedding'] != null) {
          final embedding = List<double>.from(responseData['embedding']);
          debugPrint('ClipService: Generated ${embedding.length}-dimensional embedding');
          return embedding;
        } else {
          throw Exception('No embedding in response');
        }
      } else {
        throw Exception('CLIP server error: ${response.statusCode} - ${response.body}');
      }
      
    } catch (e) {
      debugPrint('ClipService: Error generating embedding: $e');
      // Return a zero vector as fallback (768 dimensions for both DINOv2-base and ViT-L/14)
      // The server will tell us the actual dimensions in the response
      return List.filled(768, 0.0);
    }
  }
  
  /// Generate embeddings for multiple images in batch
  Future<List<List<double>>> generateBatchImageEmbeddings(List<File> imageFiles) async {
    try {
      debugPrint('ClipService: Generating embeddings for ${imageFiles.length} images');
      
      // Check if server is available
      if (!await isServerAvailable()) {
        throw Exception('CLIP server is not available. Please start the server first.');
      }
      
      final embeddings = <List<double>>[];
      
      // Process images in smaller batches to avoid memory issues
      const batchSize = 5;
      for (int i = 0; i < imageFiles.length; i += batchSize) {
        final batch = imageFiles.skip(i).take(batchSize).toList();
        
        for (final imageFile in batch) {
          final embedding = await generateImageEmbedding(imageFile);
          embeddings.add(embedding);
          
          // Small delay to prevent overwhelming the server
          await Future.delayed(const Duration(milliseconds: 100));
        }
        
        debugPrint('ClipService: Processed batch ${(i / batchSize).floor() + 1}/${(imageFiles.length / batchSize).ceil()}');
      }
      
      return embeddings;
      
    } catch (e) {
      debugPrint('ClipService: Error in batch processing: $e');
      rethrow;
    }
  }
  
  /// Generate text embedding (useful for future semantic search features)
  Future<List<double>> generateTextEmbedding(String text) async {
    try {
      debugPrint('ClipService: Generating text embedding for: "$text"');
      
      if (!await isServerAvailable()) {
        throw Exception('CLIP server is not available');
      }
      
      final response = await http.post(
        Uri.parse('$serverUrl/encode/text'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'text': text}),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        
        if (responseData['embedding'] != null) {
          final embedding = List<double>.from(responseData['embedding']);
          debugPrint('ClipService: Generated ${embedding.length}-dimensional text embedding');
          return embedding;
        } else {
          throw Exception('No embedding in response');
        }
      } else {
        throw Exception('CLIP server error: ${response.statusCode}');
      }
      
    } catch (e) {
      debugPrint('ClipService: Error generating text embedding: $e');
      return List.filled(768, 0.0);
    }
  }
  
  /// Calculate cosine similarity between two embeddings
  static double calculateCosineSimilarity(List<double> vec1, List<double> vec2) {
    if (vec1.length != vec2.length) {
      debugPrint('ClipService: Vector dimension mismatch! ${vec1.length} vs ${vec2.length}');
      return 0.0;
    }
    
    double dotProduct = 0.0;
    double norm1 = 0.0;
    double norm2 = 0.0;
    
    for (int i = 0; i < vec1.length; i++) {
      dotProduct += vec1[i] * vec2[i];
      norm1 += vec1[i] * vec1[i];
      norm2 += vec2[i] * vec2[i];
    }
    
    if (norm1 == 0.0 || norm2 == 0.0) {
      return 0.0;
    }
    
    final similarity = dotProduct / (sqrt(norm1) * sqrt(norm2));
    return similarity.clamp(-1.0, 1.0);
  }
  
  /// Sqrt implementation (since dart:math might not be imported everywhere)
  static double sqrt(double x) {
    if (x < 0) return double.nan;
    if (x == 0) return 0;
    
    double guess = x / 2;
    double prev = 0;
    
    while ((guess - prev).abs() > 0.000001) {
      prev = guess;
      guess = (guess + x / guess) / 2;
    }
    
    return guess;
  }
}

/// Result from people detection
class PeopleDetectionResult {
  final bool peopleDetected;
  final int peopleCount;
  final List<double> confidenceScores;

  PeopleDetectionResult({
    required this.peopleDetected,
    required this.peopleCount,
    required this.confidenceScores,
  });

  @override
  String toString() {
    return 'PeopleDetectionResult(detected: $peopleDetected, count: $peopleCount, scores: $confidenceScores)';
  }
}

/// Result from navigation embedding with dynamic threshold
class NavigationEmbeddingResult {
  final List<double> embedding;
  final bool peopleDetected;
  final int peopleCount;
  final List<double> confidenceScores;
  final double recommendedThreshold;

  NavigationEmbeddingResult({
    required this.embedding,
    required this.peopleDetected,
    required this.peopleCount,
    required this.confidenceScores,
    required this.recommendedThreshold,
  });

  @override
  String toString() {
    return 'NavigationEmbeddingResult(people: $peopleCount, threshold: ${recommendedThreshold.toStringAsFixed(2)}, embedding: ${embedding.length}d)';
  }
}
