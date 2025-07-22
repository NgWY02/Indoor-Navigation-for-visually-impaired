import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as thumb;
import 'package:image/image.dart' as img;
import 'package:flutter_compass/flutter_compass.dart';
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
  
  // Direction state
  double? entranceDirection;
  Stream<CompassEvent>? compassStream;
  
  VideoProcessorService(this._supabaseService) {
    // Initialize the compass stream if available on the device
    compassStream = FlutterCompass.events;
  }
  
  // Method to get current compass heading
  Future<double?> getCurrentHeading() async {
    try {
      // If the compass stream is not available, return null
      if (compassStream == null) {
        debugPrint('Compass not available on this device');
        return null;
      }
      
      // Listen for a single compass event
      final CompassEvent? event = await compassStream!.first;
      return event?.heading;
    } catch (e) {
      debugPrint('Error getting compass heading: $e');
      return null;
    }
  }
  
  // Save the current compass heading as entrance direction
  Future<void> captureEntranceDirection() async {
    entranceDirection = await getCurrentHeading();
    debugPrint('Captured entrance direction: $entranceDirection°');
  }
  
  Future<void> loadModel() async {
    try {
      print('VideoProcessor: Starting model loading...');
      _interpreter = await Interpreter.fromAsset('assets/models/feature_extractor.tflite');
      _isModelLoaded = true;
      print('VideoProcessor: Model loaded successfully');
    } catch (e) {
      print('VideoProcessor: Error loading model: $e');
      _isModelLoaded = false;
      throw Exception('Failed to load TensorFlow Lite model: $e');
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
    double? referenceDirection, // Add optional reference direction
  }) async {
    print('VideoProcessor: Starting video processing...');
    print('VideoProcessor: Model loaded: $_isModelLoaded');
    print('VideoProcessor: Video file path: ${videoFile.path}');
    print('VideoProcessor: Video exists: ${await File(videoFile.path).exists()}');
    
    if (!_isModelLoaded) {
      print('VideoProcessor: Model not loaded, cannot process video');
      onProgressUpdate(0.0, 'Error: Model not loaded.');
      return;
    }

    // Use the provided reference direction or the captured entrance direction
    final double? directionToSave = referenceDirection ?? entranceDirection;

    isProcessingVideo = true;
    processingProgress = 0.0;
    processingMessage = 'Extracting frames...';
    extractedFrames = [];
    
    onProgressUpdate(processingProgress, processingMessage);
    
    try {
      // Create temp directory to store frames
      final tempDir = await getTemporaryDirectory();
      final outputDir = Directory('${tempDir.path}/frames');
      print('VideoProcessor: Creating temp directory: ${outputDir.path}');
      
      if (await outputDir.exists()) {
        await outputDir.delete(recursive: true);
        print('VideoProcessor: Deleted existing temp directory');
      }
      await outputDir.create();
      print('VideoProcessor: Created temp directory');
      
      // Extract frames from the video
      final videoFilePath = File(videoFile.path);
      final videoInfo = videoPlayerController.value;
      final duration = videoInfo.duration.inMilliseconds;
      
      print('VideoProcessor: Video duration: ${duration}ms');
      
      // Extract a frame every second (1000 ms)
      final frameInterval = 700; // milliseconds
      int frameCount = (duration / frameInterval).ceil();
      
      print('VideoProcessor: Will extract $frameCount frames');
      
      // Use a more robust frame extraction approach
      for (int i = 0; i < frameCount; i++) {
        int timeMs = i * frameInterval;
        
        print('VideoProcessor: Extracting frame $i at ${timeMs}ms');
        
        // Try multiple approaches for frame extraction
        bool frameExtracted = false;
        int maxRetries = 3;
        
        for (int retry = 0; retry < maxRetries && !frameExtracted; retry++) {
          try {
            String? thumbnailPath;
            
            // Try different extraction approaches
            if (retry == 0) {
              // Standard approach
              thumbnailPath = await thumb.VideoThumbnail.thumbnailFile(
                video: videoFilePath.path,
                thumbnailPath: '${outputDir.path}/frame_$i.jpg',
                imageFormat: thumb.ImageFormat.JPEG,
                quality: 50,
                timeMs: timeMs,
              );
            } else if (retry == 1) {
              // Try with slightly different timestamp
              int adjustedTimeMs = timeMs + 50; // Add 50ms offset
              if (adjustedTimeMs >= duration) adjustedTimeMs = duration - 100;
              
              thumbnailPath = await thumb.VideoThumbnail.thumbnailFile(
                video: videoFilePath.path,
                thumbnailPath: '${outputDir.path}/frame_${i}_retry.jpg',
                imageFormat: thumb.ImageFormat.JPEG,
                quality: 75, // Higher quality on retry
                timeMs: adjustedTimeMs,
              );
            } else {
              // Try with even more different timestamp
              int adjustedTimeMs = timeMs - 100; // Subtract 100ms
              if (adjustedTimeMs < 0) adjustedTimeMs = 50;
              
              thumbnailPath = await thumb.VideoThumbnail.thumbnailFile(
                video: videoFilePath.path,
                thumbnailPath: '${outputDir.path}/frame_${i}_retry2.jpg',
                imageFormat: thumb.ImageFormat.JPEG,
                quality: 90, // Even higher quality
                timeMs: adjustedTimeMs,
              );
            }
            
            if (thumbnailPath != null) {
              final frameFile = File(thumbnailPath);
              if (await frameFile.exists()) {
                // Verify the file is valid by checking its size
                final fileSize = await frameFile.length();
                if (fileSize > 1000) { // Must be at least 1KB
                  extractedFrames.add(frameFile);
                  frameExtracted = true;
                  print('VideoProcessor: Successfully extracted frame $i: $thumbnailPath (${fileSize} bytes) on attempt ${retry + 1}');
                } else {
                  print('VideoProcessor: Frame $i file too small (${fileSize} bytes), retrying...');
                  await frameFile.delete().catchError((_) {}); // Clean up small file
                }
              } else {
                print('VideoProcessor: Frame $i path returned but file does not exist: $thumbnailPath');
              }
            } else {
              print('VideoProcessor: Failed to extract frame $i on attempt ${retry + 1} - thumbnailPath is null');
            }
          } catch (frameError) {
            print('VideoProcessor: Error extracting frame $i on attempt ${retry + 1}: $frameError');
            if (retry == maxRetries - 1) {
              print('VideoProcessor: Giving up on frame $i after $maxRetries attempts');
            }
          }
          
          // Small delay between retries
          if (!frameExtracted && retry < maxRetries - 1) {
            await Future.delayed(Duration(milliseconds: 100));
          }
        }
        
        processingProgress = (i + 1) / frameCount;
        processingMessage = 'Extracted frame ${i + 1} of $frameCount${frameExtracted ? '' : ' (failed)'}';
        onProgressUpdate(processingProgress, processingMessage);
      }
      
      print('VideoProcessor: Frame extraction complete. Total frames: ${extractedFrames.length}');
      
      // If we didn't get enough frames, try to extract more from different positions
      if (extractedFrames.length < 3 && duration > 1000) {
        print('VideoProcessor: Only got ${extractedFrames.length} frames, attempting additional extraction...');
        
        // Try to extract frames from different positions
        List<int> additionalTimestamps = [];
        
        // Add timestamps at quarter positions
        if (duration > 2000) {
          additionalTimestamps.addAll([
            (duration * 0.25).round(),
            (duration * 0.5).round(),
            (duration * 0.75).round(),
          ]);
        }
        
        // Add timestamp near the end
        if (duration > 1000) {
          additionalTimestamps.add(duration - 500);
        }
        
        for (int timestamp in additionalTimestamps) {
          if (extractedFrames.length >= 6) break; // Stop if we have enough frames
          
          try {
            print('VideoProcessor: Attempting additional frame extraction at ${timestamp}ms');
            
            final thumbnailPath = await thumb.VideoThumbnail.thumbnailFile(
              video: videoFilePath.path,
              thumbnailPath: '${outputDir.path}/additional_frame_${timestamp}.jpg',
              imageFormat: thumb.ImageFormat.JPEG,
              quality: 80,
              timeMs: timestamp,
            );
            
            if (thumbnailPath != null) {
              final frameFile = File(thumbnailPath);
              if (await frameFile.exists()) {
                final fileSize = await frameFile.length();
                if (fileSize > 1000) {
                  extractedFrames.add(frameFile);
                  print('VideoProcessor: Successfully extracted additional frame at ${timestamp}ms: $thumbnailPath (${fileSize} bytes)');
                }
              }
            }
          } catch (e) {
            print('VideoProcessor: Failed to extract additional frame at ${timestamp}ms: $e');
          }
        }
        
        print('VideoProcessor: Additional extraction complete. Total frames now: ${extractedFrames.length}');
      }
      
      // Process the extracted frames
      await processExtractedFrames(
        nodeName: nodeName,
        mapId: mapId,
        positionX: positionX,
        positionY: positionY,
        onProgressUpdate: onProgressUpdate,
        nodeId: nodeId, // Pass nodeId to processExtractedFrames
        referenceDirection: directionToSave, // Pass the direction
      );
      
    } catch (e) {
      print('VideoProcessor: Critical error processing video: $e');
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
    double? referenceDirection, // Add optional reference direction
  }) async {
    print('VideoProcessor: Processing ${extractedFrames.length} extracted frames');
    
    if (extractedFrames.isEmpty) {
      print('VideoProcessor: No frames were extracted from the video');
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
        print('VideoProcessor: Updating existing node: $nodeId');
        // Update existing node details (name/position might have changed)
        await _supabaseService.updateMapNode(
          nodeId, 
          nodeName, 
          positionX, 
          positionY,
          referenceDirection: referenceDirection,
        );
        finalNodeId = nodeId;
        print("VideoProcessor: Updated existing node: $finalNodeId" + (referenceDirection != null ? " with direction: $referenceDirection°" : ""));
      } else {
        print('VideoProcessor: Creating new node');
        // Create new node
        finalNodeId = await _supabaseService.createMapNode(
          mapId, 
          nodeName, 
          positionX, 
          positionY,
          referenceDirection: referenceDirection,
        );
        print("VideoProcessor: Created new node: $finalNodeId" + (referenceDirection != null ? " with direction: $referenceDirection°" : ""));
      }
      
      // Process each frame and save embeddings
      int successCount = 0;
      
      for (int i = 0; i < extractedFrames.length; i++) {
        print('VideoProcessor: Processing frame ${i + 1}/${extractedFrames.length}');
        
        processingProgress = (i + 1) / extractedFrames.length;
        processingMessage = 'Processing frame ${i + 1} of ${extractedFrames.length}';
        onProgressUpdate(processingProgress, processingMessage);
        
        // Use the original nodeName for all frames without adding a suffix
        final String frameNodeName = nodeName;
        
        try {
          // Extract embedding
          print('VideoProcessor: Extracting embedding for frame ${i + 1}');
          final embedding = await extractEmbedding(extractedFrames[i]);
          
          print('VideoProcessor: Embedding extracted, length: ${embedding.length}');
          
          // Save to Supabase
          print('VideoProcessor: Saving embedding to database');
          final id = await _supabaseService.saveEmbedding(
            frameNodeName, 
            embedding,
            nodeId: finalNodeId // Pass finalNodeId to saveEmbedding
          );
          
          if (id != null) {
            successCount++;
            print('VideoProcessor: Successfully saved embedding ${i + 1} with ID: $id');
          } else {
            print('VideoProcessor: Failed to save embedding ${i + 1}');
          }
        } catch (frameProcessingError) {
          print('VideoProcessor: Error processing frame ${i + 1}: $frameProcessingError');
        }
      }
      
      print('VideoProcessor: Processing complete. Success: $successCount/${extractedFrames.length}');
      processingMessage = 'Saved $successCount/${extractedFrames.length} embeddings successfully!';
      isProcessingVideo = false;
      onProgressUpdate(processingProgress, processingMessage);
      
    } catch (e) {
      print('VideoProcessor: Error processing extracted frames: $e');
      processingMessage = 'Error saving embeddings: ${e.toString()}';
      isProcessingVideo = false;
      onProgressUpdate(processingProgress, processingMessage);
    }
  }
  
  Future<List<double>> extractEmbedding(File imageFile) async {
    print('VideoProcessor: Starting embedding extraction for: ${imageFile.path}');
    
    try {
      // Check if file exists
      if (!await imageFile.exists()) {
        print('VideoProcessor: Image file does not exist: ${imageFile.path}');
        return List.filled(1280, 0.0);
      }
      
      // Read and decode image
      final bytes = await imageFile.readAsBytes();
      print('VideoProcessor: Read ${bytes.length} bytes from image file');
      
      final img.Image? image = img.decodeImage(bytes);
      
      if (image == null) {
        print('VideoProcessor: Failed to decode image from bytes');
        return List.filled(1280, 0.0); // Return zeros if image couldn't be decoded
      }
      
      print('VideoProcessor: Decoded image: ${image.width}x${image.height}');
      
      // Resize image
      final resizedImage = img.copyResize(image, width: 224, height: 224);
      print('VideoProcessor: Resized image to 224x224');
      
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
      
      print('VideoProcessor: Prepared input tensor');
      
      // Prepare output buffer (1, 1280) for MobileNetV2
      var output = List.filled(1 * 1280, 0.0).reshape([1, 1280]);
      
      // Run inference
      print('VideoProcessor: Running model inference');
      _interpreter.run(input, output);
      print('VideoProcessor: Model inference complete');
      
      final embedding = List<double>.from(output[0]);
      print('VideoProcessor: Generated embedding with ${embedding.length} dimensions');
      
      return embedding;
    } catch (e) {
      print('VideoProcessor: Error in extractEmbedding: $e');
      return List.filled(1280, 0.0);
    }
  }
  
  void dispose() {
    _interpreter.close();
  }
}