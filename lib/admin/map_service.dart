import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../services/supabase_service.dart';

class MapService {
  final SupabaseService _supabaseService;
  
  // Map image and positioning
  ui.Image? mapUIImage;
  
  MapService(this._supabaseService);
  
  Future<Map<String, dynamic>> loadMapDetails(String mapId) async {
    return await _supabaseService.getMapDetails(mapId);
  }
  
  Future<bool> loadMapImage(String imageUrl, BuildContext context) async {
    try {
      final completer = Completer<ui.Image>();
      
      if (imageUrl.startsWith('data:image')) {
        // Handle base64 encoded image
        debugPrint('Loading base64 image');
        // Extract the base64 data part
        final base64String = imageUrl.split(',')[1];
        final bytes = base64Decode(base64String);
        
        // Create an image from bytes
        final codec = await ui.instantiateImageCodec(bytes);
        final frameInfo = await codec.getNextFrame();
        completer.complete(frameInfo.image);
      } else {
        // Handle regular URL image
        debugPrint('Loading network image');
        final imageProvider = NetworkImage(imageUrl);
        final stream = imageProvider.resolve(const ImageConfiguration());
        
        stream.addListener(ImageStreamListener((info, _) {
          completer.complete(info.image);
        }, onError: (error, stackTrace) {
          completer.completeError(error);
        }));
      }
      
      mapUIImage = await completer.future;
      return true; // Success
    } catch (e) {
      debugPrint('Error loading map image: $e');
      // Show error in UI
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading map image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false; // Failed
    }
  }
}