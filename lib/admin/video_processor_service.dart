import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as thumb;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import '../services/supabase_service.dart';

class VideoProcessorService {
  final SupabaseService _supabaseService;
  late Interpreter _interpreter;
  bool _isModelLoaded = false;

  // Processing state
  bool isProcessingVideo = false;
  double processingProgress = 0.0;
  String processingMessage = '';
  List<File> extractedFrames = [];
  
  VideoProcessorService(this._supabaseService);
  
  Future<void> loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/models/feature_extractor.tflite');
      _isModelLoaded = true;
      debugPrint('Model loaded successfully');
    } catch (e) {
      debugPrint('Error loading model: $e');
    }
  }
  
  Future<void> processVideo({
    required XFile videoFile, 
    required VideoPlayerController videoPlayerController,
    required String nodeName,
    required String mapId,
    required double positionX,
    required double positionY,
    required Function(double progress, String message) onProgressUpdate,
    String? nodeId, // Add optional nodeId for updates
  }) async {
    if (!_isModelLoaded) {
      onProgressUpdate(0.0, 'Error: Model not loaded.');
      return;
    }

    isProcessingVideo = true;
    processingProgress = 0.0;
    processingMessage = 'Extracting frames...';
    extractedFrames = [];
    
    onProgressUpdate(processingProgress, processingMessage);
    
    try {
      // Create temp directory to store frames
      final tempDir = await getTemporaryDirectory();
      final outputDir = Directory('${tempDir.path}/frames');
      if (await outputDir.exists()) {
        await outputDir.delete(recursive: true);
      }
      await outputDir.create();
      
      // Extract frames from the video
      final videoFilePath = File(videoFile.path);
      final videoInfo = videoPlayerController.value;
      final duration = videoInfo.duration.inMilliseconds;
      
      // Extract a frame every second (1000 ms)
      final frameInterval = 1000; // milliseconds
      int frameCount = (duration / frameInterval).ceil();
      
      for (int i = 0; i < frameCount; i++) {
        int timeMs = i * frameInterval;
        
        final thumbnailPath = await thumb.VideoThumbnail.thumbnailFile(
          video: videoFilePath.path,
          thumbnailPath: '${outputDir.path}/frame_$i.jpg',
          imageFormat: thumb.ImageFormat.JPEG,
          quality: 50,
          timeMs: timeMs,
        );
        
        if (thumbnailPath != null) {
          extractedFrames.add(File(thumbnailPath));
        }
        
        processingProgress = (i + 1) / frameCount;
        processingMessage = 'Extracted frame ${i + 1} of $frameCount';
        onProgressUpdate(processingProgress, processingMessage);
      }
      
      // Process the extracted frames
      await processExtractedFrames(
        nodeName: nodeName,
        mapId: mapId,
        positionX: positionX,
        positionY: positionY,
        onProgressUpdate: onProgressUpdate,
        nodeId: nodeId, // Pass nodeId to processExtractedFrames
      );
      
    } catch (e) {
      processingMessage = 'Error processing video: ${e.toString()}';
      isProcessingVideo = false;
      onProgressUpdate(processingProgress, processingMessage);
    }
  }
  
  Future<void> processExtractedFrames({
    required String nodeName,
    required String mapId,
    required double positionX,
    required double positionY,
    required Function(double progress, String message) onProgressUpdate,
    String? nodeId, // Add optional nodeId for updates
  }) async {
    if (extractedFrames.isEmpty) {
      processingMessage = 'No frames were extracted from the video';
      isProcessingVideo = false;
      onProgressUpdate(processingProgress, processingMessage);
      return;
    }
    
    processingProgress = 0.0;
    processingMessage = 'Generating embeddings for frames...';
    onProgressUpdate(processingProgress, processingMessage);
    
    try {
      // Use nodeId if provided (editing), otherwise create new node
      String finalNodeId;
      if (nodeId != null) {
        // Update existing node details (name/position might have changed)
        await _supabaseService.updateMapNode(nodeId, nodeName, positionX, positionY);
        finalNodeId = nodeId;
        print("Updating existing node: $finalNodeId");
      } else {
        // Create new node
        finalNodeId = await _supabaseService.createMapNode(mapId, nodeName, positionX, positionY);
        print("Created new node: $finalNodeId");
      }
      
      // Process each frame and save embeddings
      int successCount = 0;
      
      for (int i = 0; i < extractedFrames.length; i++) {
        processingProgress = (i + 1) / extractedFrames.length;
        processingMessage = 'Processing frame ${i + 1} of ${extractedFrames.length}';
        onProgressUpdate(processingProgress, processingMessage);
        
        // Add a suffix for multiple frames
        final String frameNodeName = extractedFrames.length > 1 
          ? '$nodeName (${i + 1})' 
          : nodeName;
          
        // Extract embedding
        final embedding = await extractEmbedding(extractedFrames[i]);
        
        // Save to Supabase
        final id = await _supabaseService.saveEmbedding(
          frameNodeName, 
          embedding,
          nodeId: finalNodeId // Pass finalNodeId to saveEmbedding
        );
        
        if (id != null) {
          successCount++;
        }
      }
      
      processingMessage = 'Saved $successCount/${extractedFrames.length} embeddings successfully!';
      isProcessingVideo = false;
      onProgressUpdate(processingProgress, processingMessage);
      
    } catch (e) {
      processingMessage = 'Error saving embeddings: ${e.toString()}';
      isProcessingVideo = false;
      onProgressUpdate(processingProgress, processingMessage);
    }
  }
  
  Future<List<double>> extractEmbedding(File imageFile) async {
    // Read and decode image
    final bytes = await imageFile.readAsBytes();
    final img.Image? image = img.decodeImage(bytes);
    
    if (image == null) {
      return List.filled(1280, 0.0); // Return zeros if image couldn't be decoded
    }
    
    // Resize image
    final resizedImage = img.copyResize(image, width: 224, height: 224);
    
    // Convert to input tensor (1, 224, 224, 3)
    var input = List.generate(
      1,
      (_) => List.generate(
        224,
        (_) => List.generate(
          224,
          (_) => List<double>.filled(3, 0),
        ),
      ),
    );
    
    // Fill with normalized pixel values
    for (int y = 0; y < 224; y++) {
      for (int x = 0; x < 224; x++) {
        final pixel = resizedImage.getPixel(x, y);
        // Extract RGB values from Pixel object and normalize
        input[0][y][x][0] = (pixel.r.toDouble()) / 127.5 - 1; // Red component
        input[0][y][x][1] = (pixel.g.toDouble()) / 127.5 - 1; // Green component
        input[0][y][x][2] = (pixel.b.toDouble()) / 127.5 - 1; // Blue component
      }
    }
    
    // Prepare output buffer (1, 1280) for MobileNetV2
    var output = List.filled(1 * 1280, 0.0).reshape([1, 1280]);
    
    // Run inference
    _interpreter.run(input, output);
    
    return List<double>.from(output[0]);
  }
  
  void dispose() {
    _interpreter.close();
  }
}