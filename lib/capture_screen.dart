import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'services/supabase_service.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({Key? key}) : super(key: key);

  @override
  _CaptureScreenState createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final ImagePicker _picker = ImagePicker();
  List<File> _imageFiles = [];
  int _currentImageIndex = 0;
  late Interpreter _interpreter;
  final TextEditingController _placeNameController = TextEditingController();
  bool _isProcessing = false;
  String _statusMessage = '';
  
  @override
  void initState() {
    super.initState();
    _loadModel();
  }
  
  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/models/feature_extractor.tflite');
      print('Model loaded successfully');
    } catch (e) {
      print('Error loading model: $e');
    }
  }
  
  Future<void> _takePicture() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      setState(() {
        _imageFiles.add(File(image.path));
        _currentImageIndex = _imageFiles.length - 1;
        _statusMessage = '${_imageFiles.length} images captured';
      });
    }
  }
  
  Future<void> _pickImages() async {
    final List<XFile> images = await _picker.pickMultiImage();
    if (images.isNotEmpty) {
      setState(() {
        _imageFiles.addAll(images.map((xFile) => File(xFile.path)).toList());
        _currentImageIndex = _imageFiles.length - 1;
        _statusMessage = '${_imageFiles.length} images selected';
      });
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
  
  Future<void> _processAndSave() async {
    if (_imageFiles.isEmpty) {
      setState(() {
        _statusMessage = 'Please capture or select images first';
      });
      return;
    }
    
    if (_placeNameController.text.trim().isEmpty) {
      setState(() {
        _statusMessage = 'Please enter a place name';
      });
      return;
    }
    
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Processing image 1/${_imageFiles.length}...';
    });
    
    try {
      final placeName = _placeNameController.text.trim();
      final supabaseService = SupabaseService();
      int successCount = 0;
      
      // Process each image and save to Supabase
      for (int i = 0; i < _imageFiles.length; i++) {
        setState(() {
          _statusMessage = 'Processing image ${i + 1}/${_imageFiles.length}...';
          _currentImageIndex = i;
        });
        
        // Add a slight suffix if multiple images for same place
        final String nameToSave = _imageFiles.length > 1 
          ? '$placeName (${i + 1})' 
          : placeName;
        
        // Extract embedding
        final embedding = await _extractEmbedding(_imageFiles[i]);
        
        // Save to Supabase
        final id = await supabaseService.saveEmbedding(nameToSave, embedding);
        
        if (id != null) {
          successCount++;
        }
      }
      
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Saved $successCount/${_imageFiles.length} locations successfully!';
        _placeNameController.clear();
        _imageFiles = [];
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Error: $e';
      });
    }
  }

  void _nextImage() {
    if (_currentImageIndex < _imageFiles.length - 1) {
      setState(() {
        _currentImageIndex++;
      });
    }
  }

  void _previousImage() {
    if (_currentImageIndex > 0) {
      setState(() {
        _currentImageIndex--;
      });
    }
  }
  
  void _removeCurrentImage() {
    if (_imageFiles.isEmpty) return;
    
    setState(() {
      _imageFiles.removeAt(_currentImageIndex);
      
      if (_imageFiles.isEmpty) {
        _statusMessage = 'No images selected';
      } else {
        if (_currentImageIndex >= _imageFiles.length) {
          _currentImageIndex = _imageFiles.length - 1;
        }
        _statusMessage = '${_imageFiles.length} images selected';
      }
    });
  }
  
  @override
  void dispose() {
    _interpreter.close();
    _placeNameController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Add New Location'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_imageFiles.isNotEmpty) ...[
                Stack(
                  children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                        ),
                        child: Image.file(_imageFiles[_currentImageIndex], fit: BoxFit.cover),
                      ),
                    ),
                    Positioned(
                      top: 10,
                      right: 10,
                      child: IconButton(
                        icon: Icon(Icons.delete, color: Colors.white),
                        onPressed: _removeCurrentImage,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black.withOpacity(0.5),
                        ),
                      ),
                    ),
                    if (_imageFiles.length > 1)
                      Positioned(
                        bottom: 10,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: Icon(Icons.arrow_back_ios, color: Colors.white),
                              onPressed: _currentImageIndex > 0 ? _previousImage : null,
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.black45,
                                disabledBackgroundColor: Colors.black12,
                              ),
                            ),
                            SizedBox(width: 20),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${_currentImageIndex + 1}/${_imageFiles.length}',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            SizedBox(width: 20),
                            IconButton(
                              icon: Icon(Icons.arrow_forward_ios, color: Colors.white),
                              onPressed: _currentImageIndex < _imageFiles.length - 1 ? _nextImage : null,
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.black45,
                                disabledBackgroundColor: Colors.black12,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                SizedBox(height: 16),
              ] else ...[
                AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text('No images selected'),
                    ),
                  ),
                ),
                SizedBox(height: 16),
              ],
              
              // Image count display
              if (_imageFiles.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    'Total Images: ${_imageFiles.length}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: _takePicture,
                    icon: Icon(Icons.camera_alt),
                    label: Text('Camera'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _pickImages,
                    icon: Icon(Icons.photo_library),
                    label: Text('Gallery'),
                  ),
                ],
              ),
              
              SizedBox(height: 16),
              
              TextField(
                controller: _placeNameController,
                decoration: InputDecoration(
                  labelText: 'Location Name',
                  border: OutlineInputBorder(),
                  hintText: 'E.g., Conference Room, Lobby, etc.',
                ),
              ),
              
              SizedBox(height: 16),
              
              ElevatedButton(
                onPressed: _isProcessing ? null : _processAndSave,
                child: _isProcessing
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 20, 
                            height: 20, 
                            child: CircularProgressIndicator(
                              strokeWidth: 2.0,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                          SizedBox(width: 10),
                          Text('Processing...'),
                        ],
                      )
                    : Text(_imageFiles.isEmpty 
                        ? 'Save Location' 
                        : _imageFiles.length > 1
                            ? 'Save All ${_imageFiles.length} Images' 
                            : 'Save Image'),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              
              if (_statusMessage.isNotEmpty) ...[
                SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.all(8),
                  color: _statusMessage.contains('Error')
                      ? Colors.red.shade100
                      : _statusMessage.contains('success') || _statusMessage.contains('Saved')
                          ? Colors.green.shade100
                          : Colors.blue.shade100,
                  child: Text(
                    _statusMessage,
                    style: TextStyle(
                      color: _statusMessage.contains('Error')
                          ? Colors.red.shade900
                          : _statusMessage.contains('success') || _statusMessage.contains('Saved')
                              ? Colors.green.shade900
                              : Colors.blue.shade900,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}