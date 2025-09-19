import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../models/path_models.dart';
import 'supabase_service.dart';
import 'gpt_service.dart';

class ClipService {
  static const String _defaultServerUrl = 'http://172.16.38.229:8000'; 
  final String serverUrl;
  
  // Performance optimization: Cache reference images
  static final Map<String, String> _referenceImageCache = {};
  
  // GPT service instance
  final GPTService _gptService = GPTService();
  
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
  Future<List<double>> generateNavigationEmbeddingInpainted(File imageFile, {bool disableYolo = false}) async {
    return _generateEmbedding(imageFile, '/encode/inpainted', disableYolo: disableYolo);
  }

  /// Combined navigation method with inpainting: detect people + generate inpainted embedding + calculate threshold
  Future<NavigationEmbeddingResult> generateNavigationEmbeddingWithInpainting(
    File imageFile, {
    required double cleanSceneThreshold,
    required double peoplePresentThreshold,
    required double crowdedSceneThreshold,
    bool disableYolo = false,
  }) async {
    try {
      if (disableYolo) {
        // When YOLO is disabled, use regular navigation embedding (no inpainting needed)
        debugPrint('ClipService: YOLO disabled - using regular navigation embedding');
        final embedding = await generateNavigationEmbedding(imageFile);
        
        return NavigationEmbeddingResult(
          embedding: embedding,
          peopleDetected: false,
          peopleCount: 0,
          confidenceScores: [],
          recommendedThreshold: cleanSceneThreshold, // Use clean scene threshold when YOLO disabled
        );
      }
      
      // When YOLO is enabled, run people detection and inpainted embedding generation in parallel
      final futures = await Future.wait([
        detectPeople(imageFile, disableYolo: false),
        generateNavigationEmbeddingInpainted(imageFile, disableYolo: false),
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
  Future<PeopleDetectionResult> detectPeople(File imageFile, {bool disableYolo = false}) async {
    try {
      debugPrint('ClipService: Detecting people in ${imageFile.path} (YOLO ${disableYolo ? 'DISABLED' : 'ENABLED'})');
      
      // Return no people if YOLO is disabled
      if (disableYolo) {
        return PeopleDetectionResult(
          peopleDetected: false,
          peopleCount: 0,
          confidenceScores: [],
        );
      }
      
      // Check if server is available
      if (!await isServerAvailable()) {
        throw Exception('CLIP server is not available. Please start the server first.');
      }
      
      // Read original image bytes
      final originalBytes = await imageFile.readAsBytes();
      
      // Prepare request with optional disableYolo parameter  
      final uri = Uri.parse('$serverUrl/detect/people').replace(
        queryParameters: disableYolo ? {'disable_yolo': 'true'} : {},
      );
      final request = http.MultipartRequest('POST', uri);
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
  Future<List<double>> _generateEmbedding(File imageFile, String endpoint, {bool disableYolo = false}) async {
    try {
      debugPrint('ClipService: Generating embedding for ${imageFile.path} via $endpoint');
      
      // Check if server is available
      if (!await isServerAvailable()) {
        throw Exception('CLIP server is not available. Please start the server first.');
      }
      
      // Read original image bytes (server will handle resize + preprocessing)
      final originalBytes = await imageFile.readAsBytes();
      
      // Prepare request with optional disableYolo parameter
      final uri = Uri.parse('$serverUrl$endpoint').replace(
        queryParameters: disableYolo ? {'disable_yolo': 'true'} : {},
      );
      final request = http.MultipartRequest('POST', uri);
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
  
  /// Enhanced localization with VLM verification - automated scanning + validation
  Future<EnhancedLocalizationResult> performEnhancedLocalization({
    required CameraController cameraController,
    required Function(String) onStatusUpdate,
    String? gptApiKey,
    bool disableYolo = false,
  }) async {
    try {
      onStatusUpdate('Starting 8-second automated scan...');
      debugPrint('🎯 Enhanced Localization: YOLO Detection ${disableYolo ? 'DISABLED' : 'ENABLED'}');
      
      final capturedFrames = <CapturedFrame>[];
      
      // Automated scanning: 8 seconds, 1 frame per second
      for (int i = 0; i < 8; i++) {
        if (!cameraController.value.isInitialized) {
          throw Exception('Camera not initialized');
        }
        
        onStatusUpdate('Capturing frame ${i + 1}/8...');
        
        final image = await cameraController.takePicture();
        final imageFile = File(image.path);
        
        // Generate embedding for this frame with optional YOLO detection
        final embedding = disableYolo
          ? await generateNavigationEmbedding(imageFile)
          : (await generateNavigationEmbeddingWithInpainting(
              imageFile,
              cleanSceneThreshold: 0.9,
              peoplePresentThreshold: 0.75,
              crowdedSceneThreshold: 0.7,
              disableYolo: disableYolo,
            )).embedding;
        
        capturedFrames.add(CapturedFrame(
          imageFile: imageFile,
          embedding: embedding,
          timestamp: DateTime.now(),
          frameIndex: i,
        ));
        
        // Wait 1 second before next capture (except for last frame)
        if (i < 7) {
          await Future.delayed(const Duration(seconds: 1));
        }
      }
      
      onStatusUpdate('Processing embeddings with 0.8 threshold...');
      
      // Filter frames with embedding similarity > 0.8
      final qualifiedFrames = await _filterFramesByEmbeddingSimilarity(
        capturedFrames,
        threshold: 0.8,
        onStatusUpdate: onStatusUpdate,
      );
      
      if (qualifiedFrames.isEmpty) {
        // Clean up captured frames
        for (final frame in capturedFrames) {
          try {
            await frame.imageFile.delete();
          } catch (e) {
            debugPrint('Warning: Could not delete frame: $e');
          }
        }
        
        return EnhancedLocalizationResult(
          success: false,
          nodeId: null,
          errorMessage: 'No qualifying matches found (similarity > 0.8)',
          capturedFrameCount: capturedFrames.length,
          qualifiedFrameCount: 0,
        );
      }
      
      onStatusUpdate('Found ${qualifiedFrames.length} qualified matches. Starting batch VLM verification...');

      // VLM verification for qualified frames (batch all at once)
      final verificationResults = <VLMVerificationResult>[];

      if (gptApiKey != null && qualifiedFrames.isNotEmpty) {
        onStatusUpdate('Batch VLM verification for ${qualifiedFrames.length} frames...');

        // Prepare image pairs for batch verification
        final imagePairs = qualifiedFrames.map((qualified) => {
          'capturedImage': qualified.frame.imageFile,
          'referenceImageUrl': qualified.referenceImageUrl,
          'embeddingMatch': qualified.bestMatch,
        }).toList();

        // Perform batch VLM verification (single API call for all pairs)
        final batchResults = await _gptService.performBatchVLMVerification(
          imagePairs,
          gptApiKey,
        );

        verificationResults.addAll(batchResults);

        debugPrint('✅ Batch VLM verification completed: ${batchResults.length} results from 1 API call');

        // Note: No delay needed since it's one API call instead of multiple
      }
      
      // Apply decision logic
      final finalResult = _applyDecisionLogic(qualifiedFrames, verificationResults);
      
      // Clean up captured frames
      for (final frame in capturedFrames) {
        try {
          await frame.imageFile.delete();
        } catch (e) {
          debugPrint('Warning: Could not delete frame: $e');
        }
      }
      
      return finalResult;
      
    } catch (e) {
      debugPrint('Enhanced localization error: $e');
      return EnhancedLocalizationResult(
        success: false,
        nodeId: null,
        errorMessage: 'Enhanced localization failed: $e',
        capturedFrameCount: 0,
        qualifiedFrameCount: 0,
      );
    }
  }
  
  /// Filter captured frames by embedding similarity threshold
  Future<List<QualifiedFrame>> _filterFramesByEmbeddingSimilarity(
    List<CapturedFrame> frames,
    {
    required double threshold,
    required Function(String) onStatusUpdate,
  }) async {
    final qualifiedFrames = <QualifiedFrame>[];
    
    try {
      // Get all place embeddings with full info (node_id, place_name, etc.)
      final allEmbeddingsInfo = await _getCachedEmbeddingsWithInfo();
      
      for (final frame in frames) {
        EmbeddingMatch? bestMatch;
        double bestSimilarity = 0.0;
        
        // Compare with all stored embeddings
        allEmbeddingsInfo.forEach((embeddingId, embeddingInfo) {
          final similarity = calculateCosineSimilarity(frame.embedding, embeddingInfo.embedding);
          
          if (similarity > bestSimilarity) {
            bestSimilarity = similarity;
            bestMatch = EmbeddingMatch(
              placeName: embeddingInfo.placeName,
              similarity: similarity,
              embeddingId: embeddingId, // Use embedding_id for precise reference image linking!
              nodeId: embeddingInfo.nodeId,
              organizationId: embeddingInfo.organizationId,
            );
          }
        });
        
        // Only include frames that meet the threshold
        if (bestMatch != null && bestSimilarity > threshold) {
          // Use embedding_id for precise reference image linking (each embedding has its own reference image)
          final referenceImageUrl = await _getReferenceImageByEmbeddingId(bestMatch!.embeddingId);
          
          qualifiedFrames.add(QualifiedFrame(
            frame: frame,
            bestMatch: bestMatch!,
            referenceImageUrl: referenceImageUrl,
          ));
          
          debugPrint('Frame ${frame.frameIndex}: ${bestMatch!.placeName} (${bestSimilarity.toStringAsFixed(3)}) → Embedding: ${bestMatch!.embeddingId} ✅');
        } else {
          debugPrint('Frame ${frame.frameIndex}: Best similarity ${bestSimilarity.toStringAsFixed(3)} ❌ (< $threshold)');
        }
      }
      
      return qualifiedFrames;
      
    } catch (e) {
      debugPrint('Error filtering frames by similarity: $e');
      return [];
    }
  }
  
  /// Get cached embeddings with performance optimization  
  /// Returns map with node_id as key for better reference image linking
  Future<Map<String, EmbeddingInfo>> _getCachedEmbeddingsWithInfo() async {
    // For now, always fetch fresh data (caching can be added later if needed)
    debugPrint('Fetching detailed embeddings from database...');
    final supabaseService = SupabaseService();
    
    try {
      // Get detailed embeddings with node_id and place_name
      final response = await supabaseService.client
          .from('place_embeddings')
          .select('id, node_id, place_name, embedding, organization_id');
      
      final embeddingInfoMap = <String, EmbeddingInfo>{};
      
      for (final row in response) {
        final embeddingId = row['id'] as String?;
        final nodeId = row['node_id'] as String?; 
        final placeName = row['place_name'] as String?;
        final embeddingData = row['embedding'];
        
        if (embeddingId != null && nodeId != null && placeName != null && embeddingData != null) {
          // Handle embedding data - it might be stored as JSON string or already as List
          List<double> embedding;
          try {
            if (embeddingData is String) {
              // Parse JSON string first, then convert to List<double>
              final parsed = json.decode(embeddingData);
              embedding = List<double>.from(parsed);
            } else if (embeddingData is List) {
              // Already a list, just convert to List<double>
              embedding = List<double>.from(embeddingData);
            } else {
              debugPrint('⚠️ Unknown embedding data type: ${embeddingData.runtimeType}');
              continue;
            }
            
            embeddingInfoMap[embeddingId] = EmbeddingInfo(
              embeddingId: embeddingId,
              nodeId: nodeId,
              placeName: placeName,
              embedding: embedding,
              organizationId: row['organization_id'] as String?,
            );
            
            debugPrint('✅ Processed embedding $embeddingId: ${placeName} (${embedding.length}D)');
            
          } catch (e) {
            debugPrint('❌ Error processing embedding for $embeddingId: $e');
            continue;
          }
        }
      }
      
      debugPrint('Fetched ${embeddingInfoMap.length} detailed embeddings');
      return embeddingInfoMap;
      
    } catch (e) {
      debugPrint('Error fetching detailed embeddings: $e');
      return {};
    }
  }
  
  
  /// Get reference image URL by embedding_id (precise 1:1 linking approach)
  Future<String?> _getReferenceImageByEmbeddingId(String? embeddingId) async {
    if (embeddingId == null) return null;
    
    // Use embedding_id as cache key
    if (_referenceImageCache.containsKey(embeddingId)) {
      return _referenceImageCache[embeddingId];
    }
    
    try {
      final supabaseService = SupabaseService();
      // Use embedding_id directly for filename - this creates precise 1:1 linking
      final url = supabaseService.client.storage
          .from('reference-images')
          .getPublicUrl('${embeddingId}_reference.jpg');
      
      // Cache the URL
      _referenceImageCache[embeddingId] = url;
      
      debugPrint('✅ Found reference image for embedding $embeddingId');
      return url;
    } catch (e) {
      debugPrint('❌ Could not get reference image URL for embedding $embeddingId: $e');
      return null;
    }
  }
  
  
  /// Apply decision logic combining embedding similarity + VLM verification
  EnhancedLocalizationResult _applyDecisionLogic(
    List<QualifiedFrame> qualifiedFrames,
    List<VLMVerificationResult> vlmResults,
  ) {
    if (qualifiedFrames.isEmpty) {
      return EnhancedLocalizationResult(
        success: false,
        nodeId: null,
        errorMessage: 'No qualified frames to process',
        capturedFrameCount: 0,
        qualifiedFrameCount: 0,
      );
    }
    
    final validResults = <CombinedResult>[];
    
    // Combine embedding and VLM results
    for (int i = 0; i < qualifiedFrames.length; i++) {
      final qualified = qualifiedFrames[i];
      VLMVerificationResult? vlmResult;
      
      if (i < vlmResults.length) {
        vlmResult = vlmResults[i];
        
        // Only include results where VLM confirms match with >70% confidence
        if (vlmResult.isMatch && vlmResult.confidence > 80) {
          final combinedScore = _calculateCombinedScore(
            qualified.bestMatch.similarity,
            vlmResult.confidence / 100,
          );
          
          validResults.add(CombinedResult(
            qualified: qualified,
            vlmResult: vlmResult,
            combinedScore: combinedScore,
          ));
        }
      } else {
        // If no VLM verification, use embedding similarity only
        validResults.add(CombinedResult(
          qualified: qualified,
          vlmResult: null,
          combinedScore: qualified.bestMatch.similarity,
        ));
      }
    }
    
    if (validResults.isEmpty) {
      return EnhancedLocalizationResult(
        success: false,
        nodeId: null,
        errorMessage: 'No results passed VLM verification (>70% confidence)',
        capturedFrameCount: qualifiedFrames.length,
        qualifiedFrameCount: qualifiedFrames.length,
        vlmVerificationCount: vlmResults.length,
      );
    }
    
    // Sort by combined score and pick the best
    validResults.sort((a, b) => b.combinedScore.compareTo(a.combinedScore));
    final bestResult = validResults.first;

    // Check minimum combined score threshold (e.g., 0.7 = 70%)
    const double minCombinedScoreThreshold = 0.7; // Configurable threshold

    if (bestResult.combinedScore < minCombinedScoreThreshold) {
      return EnhancedLocalizationResult(
        success: false,
        nodeId: null,
        errorMessage: 'Best match confidence too low: ${(bestResult.combinedScore * 100).toStringAsFixed(1)}% (minimum required: 70.0%)',
        capturedFrameCount: qualifiedFrames.length + (qualifiedFrames.length > 8 ? 0 : 8 - qualifiedFrames.length),
        qualifiedFrameCount: qualifiedFrames.length,
        vlmVerificationCount: vlmResults.length,
      );
    }

    return EnhancedLocalizationResult(
      success: true,
      detectedLocation: bestResult.qualified.bestMatch.placeName,
      nodeId: bestResult.qualified.bestMatch.nodeId,
      confidence: bestResult.combinedScore,
      embeddingSimilarity: bestResult.qualified.bestMatch.similarity,
      vlmConfidence: bestResult.vlmResult?.confidence,
      vlmReasoning: bestResult.vlmResult?.reasoning,
      alternativeLocations: validResults.skip(1).take(2).map((r) => AlternativeLocation(
        placeName: r.qualified.bestMatch.placeName,
        confidence: r.combinedScore,
      )).toList(),
      capturedFrameCount: qualifiedFrames.length + (qualifiedFrames.length > 8 ? 0 : 8 - qualifiedFrames.length),
      qualifiedFrameCount: qualifiedFrames.length,
      vlmVerificationCount: vlmResults.length,
    );
  }
  
  /// Calculate combined score from embedding similarity and VLM confidence
  double _calculateCombinedScore(double embeddingSimilarity, double vlmConfidence) {
    // Weighted combination: 60% embedding + 40% VLM
    return (embeddingSimilarity * 0.6) + (vlmConfidence * 0.4);
  }
  
  /// Convenience method for integration with navigation screens
  /// Easy-to-use wrapper that handles the full enhanced localization flow
  Future<String> performQuickLocalization({
    required CameraController cameraController,
    Function(String)? onStatusUpdate,
    String? gptApiKey,
  }) async {
    final statusUpdate = onStatusUpdate ?? (message) => debugPrint('Localization: $message');
    
    try {
      final result = await performEnhancedLocalization(
        cameraController: cameraController,
        onStatusUpdate: statusUpdate,
        gptApiKey: gptApiKey,
      );
      
      if (result.success) {
        final confidence = ((result.confidence ?? 0) * 100).toStringAsFixed(1);
        final location = result.detectedLocation ?? 'Unknown';
        
        if (result.vlmConfidence != null) {
          return 'Located at: $location\nConfidence: $confidence%\nVLM Verified: ${result.vlmConfidence!.toStringAsFixed(1)}%\nReason: ${result.vlmReasoning ?? "No reasoning"}';
        } else {
          return 'Located at: $location\nConfidence: $confidence%\n(Embedding-based match)';
        }
      } else {
        return 'Localization failed: ${result.errorMessage ?? "Unknown error"}';
      }
      
    } catch (e) {
      return 'Localization error: $e';
    }
  }
  
  /// Clear performance caches (call when needed to free memory)
  static void clearCaches() {
    _referenceImageCache.clear();
    debugPrint('ClipService: Cleared all caches');
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

/// Enhanced localization data classes
class CapturedFrame {
  final File imageFile;
  final List<double> embedding;
  final DateTime timestamp;
  final int frameIndex;
  
  CapturedFrame({
    required this.imageFile,
    required this.embedding,
    required this.timestamp,
    required this.frameIndex,
  });
}

class EmbeddingMatch {
  final String placeName;
  final double similarity;
  final String? embeddingId; // Primary key for reference image linking
  final String? nodeId;
  final String? organizationId;
  
  EmbeddingMatch({
    required this.placeName,
    required this.similarity,
    this.embeddingId,
    this.nodeId,
    this.organizationId,
  });
}

class QualifiedFrame {
  final CapturedFrame frame;
  final EmbeddingMatch bestMatch;
  final String? referenceImageUrl;
  
  QualifiedFrame({
    required this.frame,
    required this.bestMatch,
    this.referenceImageUrl,
  });
}


class CombinedResult {
  final QualifiedFrame qualified;
  final VLMVerificationResult? vlmResult;
  final double combinedScore;
  
  CombinedResult({
    required this.qualified,
    this.vlmResult,
    required this.combinedScore,
  });
}

class AlternativeLocation {
  final String placeName;
  final double confidence;
  
  AlternativeLocation({
    required this.placeName,
    required this.confidence,
  });
}

class EmbeddingInfo {
  final String embeddingId; // Primary key
  final String nodeId;
  final String placeName;
  final List<double> embedding;
  final String? organizationId;
  
  EmbeddingInfo({
    required this.embeddingId,
    required this.nodeId,
    required this.placeName,
    required this.embedding,
    this.organizationId,
  });
}

class EnhancedLocalizationResult {
  final bool success;
  final String? detectedLocation;
  final String? nodeId; // Actual database node ID for route matching
  final double? confidence;
  final double? embeddingSimilarity;
  final double? vlmConfidence;
  final String? vlmReasoning;
  final String? errorMessage;
  final List<AlternativeLocation>? alternativeLocations;
  final int capturedFrameCount;
  final int qualifiedFrameCount;
  final int? vlmVerificationCount;
  
  EnhancedLocalizationResult({
    required this.success,
    this.detectedLocation,
    this.nodeId,
    this.confidence,
    this.embeddingSimilarity,
    this.vlmConfidence,
    this.vlmReasoning,
    this.errorMessage,
    this.alternativeLocations,
    required this.capturedFrameCount,
    required this.qualifiedFrameCount,
    this.vlmVerificationCount,
  });
  
  @override
  String toString() {
    if (success) {
      return 'EnhancedLocalizationResult(location: $detectedLocation, confidence: ${confidence?.toStringAsFixed(3)}, embedding: ${embeddingSimilarity?.toStringAsFixed(3)}, vlm: ${vlmConfidence?.toStringAsFixed(1)}%)';
    } else {
      return 'EnhancedLocalizationResult(failed: $errorMessage)';
    }
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
