import 'dart:io';
import 'package:flutter/material.dart';
import 'supabase_service.dart';

/// Helper service for managing reference images for VLM verification
class ReferenceImageHelper {
  static final SupabaseService _supabase = SupabaseService();
  static Future<String?> uploadReferenceImage({
    required String nodeId,
    required File imageFile,
  }) async {
    try {
      debugPrint('Uploading reference image for node: $nodeId');
      
      // Use node_id directly for reliable linking
      final fileName = '${nodeId}_reference.jpg';
      
      // Upload to reference-images bucket
      final bytes = await imageFile.readAsBytes();
      await _supabase.client.storage
          .from('reference-images')
          .uploadBinary(fileName, bytes);
      
      // Get public URL
      final url = _supabase.client.storage
          .from('reference-images')
          .getPublicUrl(fileName);
      
      debugPrint('Reference image uploaded for node $nodeId: $url');
      return url;
      
    } catch (e) {
      debugPrint('Failed to upload reference image for node $nodeId: $e');
      return null;
    }
  }
  
  static Future<Map<String, String?>> uploadBatchReferenceImages(
    Map<String, File> nodeImageMap,
  ) async {
    final results = <String, String?>{};
    
    debugPrint('📸 Batch uploading ${nodeImageMap.length} reference images...');
    
    for (final entry in nodeImageMap.entries) {
      final nodeId = entry.key;
      final imageFile = entry.value;
      
      final url = await uploadReferenceImage(
        nodeId: nodeId,
        imageFile: imageFile,
      );
      
      results[nodeId] = url;
      
      // Small delay to avoid overwhelming the server
      await Future.delayed(const Duration(milliseconds: 500));
    }
    
    final successCount = results.values.where((url) => url != null).length;
    debugPrint('Batch upload complete: $successCount/${nodeImageMap.length} successful');
    
    return results;
  }
  
  /// Check if reference image exists for a node
  static Future<bool> hasReferenceImage(String nodeId) async {
    try {
      final fileName = '${nodeId}_reference.jpg';
      
      final files = await _supabase.client.storage
          .from('reference-images')
          .list();
      
      return files.any((file) => file.name == fileName);
    } catch (e) {
      debugPrint('Error checking reference image for node $nodeId: $e');
      return false;
    }
  }
  
  /// Get all node IDs that have reference images
  static Future<List<String>> getNodesWithReferenceImages() async {
    try {
      final files = await _supabase.client.storage
          .from('reference-images')
          .list();
      
      return files
          .where((file) => file.name.endsWith('_reference.jpg'))
          .map((file) => file.name.replaceAll('_reference.jpg', ''))
          .toList();
    } catch (e) {
      debugPrint('Error listing nodes with reference images: $e');
      return [];
    }
  }
  
  /// Get summary of all reference images with node info
  static Future<List<Map<String, String>>> listReferenceImagesWithInfo() async {
    try {
      final files = await _supabase.client.storage
          .from('reference-images')
          .list();
      
      final results = <Map<String, String>>[];
      
      // Get node info for each reference image
      for (final file in files) {
        if (file.name.endsWith('_reference.jpg')) {
          final nodeId = file.name.replaceAll('_reference.jpg', '');
          
          // Try to get place name from database
          try {
            final response = await _supabase.client
                .from('place_embeddings')
                .select('place_name')
                .eq('node_id', nodeId)
                .maybeSingle();
            
            final placeName = response?['place_name'] ?? 'Unknown Place';
            
            results.add({
              'nodeId': nodeId,
              'placeName': placeName,
              'fileName': file.name,
            });
          } catch (e) {
            results.add({
              'nodeId': nodeId,
              'placeName': 'Unknown Place',
              'fileName': file.name,
            });
          }
        }
      }
      
      return results;
    } catch (e) {
      debugPrint('Error listing reference images with info: $e');
      return [];
    }
  }
}
