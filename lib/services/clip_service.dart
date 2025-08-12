import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';

class ClipService {
  static const String _defaultServerUrl = 'http://192.168.0.103:8000'; // HTTP Gateway for CLIP ViT-L/14 server
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

  /// Generate embeddings with people removal preprocessing (YOLO+SAM+Stable Diffusion)
  Future<List<double>> generatePreprocessedEmbedding(File imageFile) async {
    return _generateEmbedding(imageFile, '/encode/preprocessed');
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
      // Return a zero vector as fallback (384 dimensions for DINOv2, 768 for ViT-L/14)
      // The server will tell us the actual dimensions in the response
      return List.filled(384, 0.0);
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
      return List.filled(384, 0.0);
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
