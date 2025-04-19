import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'services/supabase_service.dart';

class RecognitionScreen extends StatefulWidget {
  final CameraDescription camera;
  
  const RecognitionScreen({Key? key, required this.camera}) : super(key: key);

  @override
  _RecognitionScreenState createState() => _RecognitionScreenState();
}

class _RecognitionScreenState extends State<RecognitionScreen> {
  late CameraController _cameraController;
  late Interpreter _interpreter;
  Map<String, List<double>> _storedEmbeddings = {};
  String _recognizedPlace = "Scanning...";
  double _confidence = 0.0;
  bool _isProcessing = false;
  Timer? _processingTimer;
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _loadModel();
    _loadEmbeddingsFromSupabase();
  }
  
  Future<void> _initializeCamera() async {
    // Create the controller (flashMode isn't a constructor parameter)
    _cameraController = CameraController(
      widget.camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg
    );
    
    await _cameraController.initialize();
    
    // Set flash mode after initialization
    try {
      await _cameraController.setFlashMode(FlashMode.off);
    } catch (e) {
      print('Error turning off flash: $e');
    }
    
    if (mounted) {
      setState(() {});
      
      // Process frames every 1 second
      _processingTimer = Timer.periodic(Duration(seconds: 1), (timer) {
        if (mounted && !_isProcessing && !_isLoading) {
          _processFrame();
        }
      });
    }
  }
  
  Future<void> _loadModel() async {
    _interpreter = await Interpreter.fromAsset('assets/models/feature_extractor.tflite');
  }
  
  Future<void> _loadEmbeddingsFromSupabase() async {
    try {
      setState(() {
        _isLoading = true;
        _recognizedPlace = "Loading locations...";
      });
      
      final supabaseService = SupabaseService();
      _storedEmbeddings = await supabaseService.getAllEmbeddings();
      
      setState(() {
        _isLoading = false;
        _recognizedPlace = _storedEmbeddings.isEmpty 
            ? "No locations found. Add some first!" 
            : "Scanning...";
      });
    } catch (e) {
      print('Error loading embeddings from Supabase: $e');
      setState(() {
        _isLoading = false;
        _recognizedPlace = "Error loading locations";
      });
    }
  }
  
  Future<void> _processFrame() async {
    if (!_cameraController.value.isInitialized || _isProcessing) return;
    
    _isProcessing = true;
    
    try {
      // Ensure flash is off before taking picture
      await _cameraController.setFlashMode(FlashMode.off);
      
      // Capture image
      final XFile file = await _cameraController.takePicture();
      
      // Process image
      final embedding = await _extractEmbedding(File(file.path));
      
      // Find best match
      final result = _findBestMatch(embedding);
      
      setState(() {
        _recognizedPlace = result.keys.first;
        _confidence = result.values.first;
      });
      
      // Delete the temporary file
      await File(file.path).delete();
      
      // Extra precaution - ensure flash is off after taking picture
      await _cameraController.setFlashMode(FlashMode.off);
      
    } catch (e) {
      print('Error processing frame: $e');
    } finally {
      _isProcessing = false;
    }
  }
  
  Future<List<double>> _extractEmbedding(File imageFile) async {
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
  
  Map<String, double> _findBestMatch(List<double> queryEmbedding) {
    String bestMatch = "Unknown";
    double highestSimilarity = 0.0;
    
    _storedEmbeddings.forEach((place, storedEmbedding) {
      final similarity = _cosineSimilarity(queryEmbedding, storedEmbedding);
      
      if (similarity > highestSimilarity && similarity > 0.7) { // Adjust threshold as needed
        highestSimilarity = similarity;
        bestMatch = place;
      }
    });
    
    return {bestMatch: highestSimilarity};
  }
  
  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    
    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    
    normA = sqrt(normA);
    normB = sqrt(normB);
    
    return dotProduct / (normA * normB);
  }

  // Refresh embeddings from Supabase
  Future<void> _refreshEmbeddings() async {
    await _loadEmbeddingsFromSupabase();
  }
  
  @override
  void dispose() {
    // Cancel the timer to prevent memory leaks
    _processingTimer?.cancel();
    
    // Turn off flash before disposing camera
    try {
      _cameraController.setFlashMode(FlashMode.off);
    } catch (e) {
      print('Error turning off flash during disposal: $e');
    }
    
    _cameraController.dispose();
    _interpreter.close();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    if (!_cameraController.value.isInitialized) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Place Recognition'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _refreshEmbeddings,
            tooltip: 'Refresh Locations',
          ),
        ],
      ),
      body: OrientationBuilder(
        builder: (context, orientation) {
          return Column(
            children: [
              // Camera preview with proper aspect ratio
              Expanded(
                child: Container(
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.center,
                      child: FittedBox(
                        fit: BoxFit.fitWidth,
                        child: Container(
                          width: MediaQuery.of(context).size.width,
                          height: MediaQuery.of(context).size.width * 
                            _cameraController.value.aspectRatio,
                          child: CameraPreview(_cameraController),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              
              // Results display
              Container(
                padding: EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                ),
                width: double.infinity,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _recognizedPlace,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 5),
                    if (_recognizedPlace != "Unknown" && 
                        _recognizedPlace != "Scanning..." && 
                        _recognizedPlace != "Loading locations..." &&
                        _recognizedPlace != "No locations found. Add some first!" &&
                        _recognizedPlace != "Error loading locations")
                      Text(
                        'Confidence: ${(_confidence * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}