import 'dart:io';
import 'package:flutter/material.dart';
import 'supabase_service.dart';

/// Helper service for managing reference images for VLM verification
class ReferenceImageHelper {
  static final SupabaseService _supabase = SupabaseService();
  
  /// Upload a reference image for a specific place
  /// 
  /// Example usage:
  /// ```dart
  /// await ReferenceImageHelper.uploadReferenceImage(
  ///   placeName: "University Main Entrance",
  ///   imageFile: File('path/to/reference/image.jpg'),
  /// );
  /// ```
  static Future<String?> uploadReferenceImage({
    required String placeName,
    required File imageFile,
  }) async {
    try {
      debugPrint('Uploading reference image for: $placeName');
      
      // Sanitize place name for file naming
      final sanitizedName = placeName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final fileName = '${sanitizedName}_reference.jpg';
      
      // Upload to reference-images bucket
      final bytes = await imageFile.readAsBytes();
      await _supabase.client.storage
          .from('reference-images')
          .uploadBinary(fileName, bytes);
      
      // Get public URL
      final url = _supabase.client.storage
          .from('reference-images')
          .getPublicUrl(fileName);
      
      debugPrint('✅ Reference image uploaded: $url');
      return url;
      
    } catch (e) {
      debugPrint('❌ Failed to upload reference image for $placeName: $e');
      return null;
    }
  }
  
  /// Upload multiple reference images at once
  /// 
  /// Example usage:
  /// ```dart
  /// await ReferenceImageHelper.uploadBatchReferenceImages({
  ///   "University Main Entrance": File('entrance.jpg'),
  ///   "Library Ground Floor": File('library.jpg'),
  ///   "Cafeteria": File('cafeteria.jpg'),
  /// });
  /// ```
  static Future<Map<String, String?>> uploadBatchReferenceImages(
    Map<String, File> placeImageMap,
  ) async {
    final results = <String, String?>{};
    
    debugPrint('📸 Batch uploading ${placeImageMap.length} reference images...');
    
    for (final entry in placeImageMap.entries) {
      final placeName = entry.key;
      final imageFile = entry.value;
      
      final url = await uploadReferenceImage(
        placeName: placeName,
        imageFile: imageFile,
      );
      
      results[placeName] = url;
      
      // Small delay to avoid overwhelming the server
      await Future.delayed(const Duration(milliseconds: 500));
    }
    
    final successCount = results.values.where((url) => url != null).length;
    debugPrint('✅ Batch upload complete: $successCount/${placeImageMap.length} successful');
    
    return results;
  }
  
  /// Check if reference image exists for a place
  static Future<bool> hasReferenceImage(String placeName) async {
    try {
      final sanitizedName = placeName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final fileName = '${sanitizedName}_reference.jpg';
      
      final files = await _supabase.client.storage
          .from('reference-images')
          .list();
      
      return files.any((file) => file.name == fileName);
    } catch (e) {
      debugPrint('Error checking reference image for $placeName: $e');
      return false;
    }
  }
  
  /// List all available reference images
  static Future<List<String>> listReferenceImages() async {
    try {
      final files = await _supabase.client.storage
          .from('reference-images')
          .list();
      
      return files
          .where((file) => file.name.endsWith('_reference.jpg'))
          .map((file) => file.name.replaceAll('_reference.jpg', '').replaceAll('_', ' '))
          .toList();
    } catch (e) {
      debugPrint('Error listing reference images: $e');
      return [];
    }
  }
}
