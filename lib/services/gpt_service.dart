import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// VLM verification result data class
class VLMVerificationResult {
  final bool isMatch;
  final double confidence;
  final String reasoning;
  final dynamic embeddingMatch;

  VLMVerificationResult({
    required this.isMatch,
    required this.confidence,
    required this.reasoning,
    required this.embeddingMatch,
  });

  @override
  String toString() {
    return 'VLMVerificationResult(isMatch: $isMatch, confidence: $confidence, reasoning: $reasoning)';
  }
}

/// Service for handling OpenAI GPT-4-mini API interactions
class GPTService {
  static final GPTService _instance = GPTService._internal();
  factory GPTService() => _instance;
  GPTService._internal();

  /// Perform VLM verification using GPT-4-mini
  /// Batch VLM verification - compare multiple image pairs in one API call
  Future<List<VLMVerificationResult>> performBatchVLMVerification(
    List<Map<String, dynamic>> imagePairs, // [{capturedImage: File, referenceImageUrl: String, embeddingMatch: dynamic}]
    String apiKey,
  ) async {
    try {
      if (imagePairs.isEmpty) {
        return [];
      }

      debugPrint('🧠 Starting batch VLM verification for ${imagePairs.length} image pairs...');

      // Build the content array with alternating captured and reference images
      final List<dynamic> content = [
        {
          'type': 'text',
          'text': 'Compare each pair of images (captured + reference) and determine if they show the same location. '
              'Images are arranged as pairs: captured1, reference1, captured2, reference2, etc. '
              'For each pair, analyze architectural features, objects, layout, and spatial relationships. '
              'Respond with a JSON array where each element corresponds to one image pair. '
              'Format: [{"match": true, "confidence": 85, "reasoning": "explanation"}, ...]',
        },
      ];

      // Add all image pairs (captured + reference for each pair)
      for (final pair in imagePairs) {
        final capturedImage = pair['capturedImage'] as File?;
        final refUrl = pair['referenceImageUrl'] as String?;

        if (capturedImage != null) {
          // Convert captured image to base64 and add it
          final bytes = await capturedImage.readAsBytes();
          final base64Image = base64Encode(bytes);
          content.add({
            'type': 'image_url',
            'image_url': {
              'url': 'data:image/jpeg;base64,$base64Image',
            },
          });
        }

        if (refUrl != null && refUrl.isNotEmpty) {
          // Add reference image
          content.add({
            'type': 'image_url',
            'image_url': {
              'url': refUrl,
            },
          });
        }
      }

      // Make single API call with all images
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: json.encode({
          'model': 'gpt-4.1-mini',
          'messages': [
            {
              'role': 'user',
              'content': content,
            },
          ],
          'max_completion_tokens': 1200, // Increased for multiple results
        }),
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final rawContent = responseData['choices']?[0]?['message']?['content'] as String? ?? '';

        debugPrint('🧠 Batch VLM Raw Response: $rawContent');

        // Parse the JSON array response
        final results = <VLMVerificationResult>[];

        try {
          // Clean the response
          String cleanContent = rawContent.trim();

          // Remove markdown if present
          if (cleanContent.startsWith('```json')) {
            cleanContent = cleanContent.replaceFirst('```json', '').trim();
          }
          if (cleanContent.startsWith('```')) {
            cleanContent = cleanContent.replaceFirst('```', '').trim();
          }
          if (cleanContent.endsWith('```')) {
            cleanContent = cleanContent.substring(0, cleanContent.lastIndexOf('```')).trim();
          }

          // Extract JSON array
          final jsonMatch = RegExp(r'\[.*\]', dotAll: true).firstMatch(cleanContent);
          if (jsonMatch != null) {
            cleanContent = jsonMatch.group(0)!;
          }

          debugPrint('🧠 Batch VLM Cleaned JSON: $cleanContent');

          final vlmArray = json.decode(cleanContent) as List;

          for (int i = 0; i < vlmArray.length && i < imagePairs.length; i++) {
            final vlmData = vlmArray[i] as Map<String, dynamic>;
            final pairData = imagePairs[i];

            results.add(VLMVerificationResult(
              isMatch: vlmData['match'] ?? false,
              confidence: (vlmData['confidence'] ?? 0).toDouble(),
              reasoning: vlmData['reasoning'] ?? 'Batch comparison result',
              embeddingMatch: pairData['embeddingMatch'],
            ));
          }

          debugPrint('✅ Batch VLM verification completed: ${results.length} results');
          return results;

        } catch (parseError) {
          debugPrint('❌ Failed to parse batch VLM response: $parseError');
          debugPrint('Raw content: $rawContent');

          // Fallback: return negative results for all image pairs
          return imagePairs.map((pair) => VLMVerificationResult(
            isMatch: false,
            confidence: 0,
            reasoning: 'Failed to parse VLM response',
            embeddingMatch: pair['embeddingMatch'],
          )).toList();
        }

      } else {
        throw Exception('Batch VLM API error: ${response.statusCode}');
      }

    } catch (e) {
      debugPrint('❌ Batch VLM verification failed: $e');

      // Return failed results for all image pairs
      return imagePairs.map((pair) => VLMVerificationResult(
        isMatch: false,
        confidence: 0,
        reasoning: 'VLM verification failed: $e',
        embeddingMatch: pair['embeddingMatch'],
      )).toList();
    }
  }
}
