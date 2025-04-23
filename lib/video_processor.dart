import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'services/supabase_service.dart';

class VideoProcessor extends StatefulWidget {
  const VideoProcessor({Key? key}) : super(key: key);

  @override
  _VideoProcessorState createState() => _VideoProcessorState();
}

class _VideoProcessorState extends State<VideoProcessor> {
  File? _videoFile;
  VideoPlayerController? _videoController;
  bool _isProcessing = false;
  bool _isVideoLoaded = false;
  String _processingStatus = '';
  double _processingProgress = 0.0;
  List<File> _extractedFrames = [];
  List<Map<String, dynamic>> _processedResults = [];
  late Interpreter _interpreter;
  double _currentDirection = 0.0;
  double _normalizedDirection = 0.0; // Normalized direction (0-360)
  String _cardinalDirection = 'N';    // Cardinal direction (N, NE, E, etc.)
  final _supabaseService = SupabaseService();
  TextEditingController _placeNameController = TextEditingController();
  TextEditingController _manualDirectionController = TextEditingController();
  bool _saveWithDirection = true;
  bool _useManualDirection = false;
  
  @override
  void initState() {
    super.initState();
    _loadModel();
    _initializeCompass();
  }
  
  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/models/feature_extractor.tflite');
      setState(() {
        _processingStatus = 'Model loaded successfully';
      });
    } catch (e) {
      setState(() {
        _processingStatus = 'Error loading model: $e';
      });
      print('Error loading model: $e');
    }
  }
  
  Future<void> _initializeCompass() async {
    if (FlutterCompass.events != null) {
      FlutterCompass.events!.listen((CompassEvent event) {
        if (mounted) {
          // Get raw heading from compass
          final double rawHeading = event.heading ?? 0.0;
          
          // Normalize to 0-360 range
          final double normalized = (rawHeading + 360) % 360;
          
          // Determine cardinal direction
          final List<String> cardinalDirections = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW', 'N'];
          final int index = ((normalized / 45).round()) % 8;
          
          setState(() {
            _currentDirection = rawHeading;
            _normalizedDirection = normalized;
            _cardinalDirection = cardinalDirections[index];
            
            // Update manual direction text field if it's empty
            if (_manualDirectionController.text.isEmpty) {
              _manualDirectionController.text = normalized.toStringAsFixed(1);
            }
          });
          
          // Debug compass readings
          print('Compass Debug - Raw: ${rawHeading.toStringAsFixed(1)}°, '
                'Normalized: ${normalized.toStringAsFixed(1)}°, '
                'Cardinal: $_cardinalDirection');
        }
      });
    } else {
      print('Compass Error: FlutterCompass.events is null. Compass may not be available on this device.');
    }
  }
  
  Future<void> _pickVideo() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.video,
      );
      
      if (result != null) {
        final File file = File(result.files.single.path!);
        
        setState(() {
          _videoFile = file;
          _isProcessing = false;
          _extractedFrames = [];
          _processedResults = [];
          _processingProgress = 0.0;
          _processingStatus = 'Video selected: ${file.path.split('/').last}';
        });
        
        _initializeVideoPlayer(file);
      }
    } catch (e) {
      setState(() {
        _processingStatus = 'Error picking video: $e';
      });
      print('Error picking video: $e');
    }
  }
  
  void _initializeVideoPlayer(File videoFile) {
    if (_videoController != null) {
      _videoController!.dispose();
    }
    
    _videoController = VideoPlayerController.file(videoFile)
      ..initialize().then((_) {
        setState(() {
          _isVideoLoaded = true;
        });
      });
  }
  
  Future<void> _processVideo() async {
    if (_videoFile == null) return;
    
    setState(() {
      _isProcessing = true;
      _processingStatus = 'Processing video...';
      _processingProgress = 0.0;
      _extractedFrames = [];
      _processedResults = [];
    });
    
    try {
      // Extract frames from video
      await _extractFrames();
      
      // Process each frame to get embeddings
      await _processFrames();
      
      setState(() {
        _isProcessing = false;
        _processingStatus = 'Video processed. ${_extractedFrames.length} frames extracted and processed.';
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _processingStatus = 'Error processing video: $e';
      });
      print('Error processing video: $e');
    }
  }
  
  Future<void> _extractFrames() async {
    final directory = await getTemporaryDirectory();
    final frameDir = await Directory('${directory.path}/frames').create(recursive: true);
    
    // Clean previous frames if any
    final existingFrames = frameDir.listSync();
    for (var file in existingFrames) {
      if (file is File) {
        await file.delete();
      }
    }
    
    // Extract frames at regular intervals
    try {
      // Get video duration
      await _videoController!.initialize();
      final Duration duration = _videoController!.value.duration;
      final int totalMilliseconds = duration.inMilliseconds;
      
      // Extract one frame every second
      const int interval = 1000; // 1 second interval
      int framesCount = (totalMilliseconds / interval).ceil();
      
      List<File> frames = [];
      
      for (int i = 0; i < framesCount; i++) {
        final int timeMs = i * interval;
        final String thumbnailPath = await VideoThumbnail.thumbnailFile(
          video: _videoFile!.path,
          thumbnailPath: '${frameDir.path}/frame_$i.jpg',
          imageFormat: ImageFormat.JPEG,
          timeMs: timeMs,
        ) ?? '';
        
        if (thumbnailPath.isNotEmpty) {
          frames.add(File(thumbnailPath));
          
          setState(() {
            _processingProgress = (i + 1) / framesCount;
            _processingStatus = 'Extracting frames... ${(i + 1)}/$framesCount';
          });
        }
      }
      
      setState(() {
        _extractedFrames = frames;
        _processingStatus = 'Extracted ${frames.length} frames';
      });
    } catch (e) {
      print('Error extracting frames: $e');
      throw e;
    }
  }
  
  Future<void> _processFrames() async {
    if (_extractedFrames.isEmpty) return;
    
    List<Map<String, dynamic>> results = [];
    
    for (int i = 0; i < _extractedFrames.length; i++) {
      final embedding = await _extractEmbedding(_extractedFrames[i]);
      
      results.add({
        'frame': i,
        'embedding': embedding,
        'path': _extractedFrames[i].path,
      });
      
      setState(() {
        _processingProgress = (i + 1) / _extractedFrames.length;
        _processingStatus = 'Processing embeddings... ${(i + 1)}/${_extractedFrames.length}';
      });
    }
    
    setState(() {
      _processedResults = results;
      _processingStatus = 'All frames processed';
    });
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
  
  Future<void> _saveLocationEmbedding(int frameIndex) async {
    if (_placeNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a location name')),
      );
      return;
    }
    
    if (frameIndex >= 0 && frameIndex < _processedResults.length) {
      final result = _processedResults[frameIndex];
      final embedding = result['embedding'] as List<double>;
      final placeName = _placeNameController.text.trim();
      
      try {
        // Use manual direction if enabled, otherwise use normalized compass direction
        double? direction;
        if (_saveWithDirection) {
          if (_useManualDirection && _manualDirectionController.text.isNotEmpty) {
            direction = double.tryParse(_manualDirectionController.text);
          } else {
            direction = _normalizedDirection; // Use normalized direction
          }
        } else {
          direction = null;
        }
        
        print('Saving location "$placeName" with direction: ${direction?.toStringAsFixed(1) ?? "null"}°');
        
        final String? id = await _supabaseService.saveEmbedding(
          placeName, 
          embedding,
          direction: direction,
        );
        
        if (id != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Saved "$placeName" successfully' +
                  (direction != null ? ' with direction: ${direction.toStringAsFixed(1)}°' : '')),
              backgroundColor: Colors.green,
            ),
          );
          
          // Reset the form
          _placeNameController.clear();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to save location'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  @override
  void dispose() {
    _videoController?.dispose();
    _interpreter.close();
    _placeNameController.dispose();
    _manualDirectionController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Processor'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Compass Debug Card
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Compass Debug',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      SizedBox(height: 8),
                      Text('Raw: ${_currentDirection.toStringAsFixed(1)}°'),
                      Text('Normalized: ${_normalizedDirection.toStringAsFixed(1)}°'),
                      Text('Direction: $_cardinalDirection'),
                    ],
                  ),
                ),
              ),
              
              SizedBox(height: 16),
              
              ElevatedButton(
                onPressed: _pickVideo,
                child: const Text('Pick Video'),
              ),
              const SizedBox(height: 16),
              
              if (_isVideoLoaded && _videoController != null && _videoController!.value.isInitialized)
                AspectRatio(
                  aspectRatio: _videoController!.value.aspectRatio,
                  child: VideoPlayer(_videoController!),
                ),
              
              const SizedBox(height: 16),
              
              Text(
                _processingStatus,
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              
              if (_isProcessing)
                Column(
                  children: [
                    const SizedBox(height: 16),
                    LinearProgressIndicator(value: _processingProgress),
                    const SizedBox(height: 8),
                    Text('${(_processingProgress * 100).toStringAsFixed(1)}%'),
                  ],
                ),
              
              const SizedBox(height: 16),
              
              if (_isVideoLoaded && !_isProcessing)
                ElevatedButton(
                  onPressed: _processVideo,
                  child: const Text('Process Video'),
                ),
              
              const SizedBox(height: 24),
              
              if (_extractedFrames.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Extracted Frames',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 120,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _extractedFrames.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: GestureDetector(
                              onTap: () => _showFrameDetails(index),
                              child: Stack(
                                children: [
                                  Image.file(
                                    _extractedFrames[index],
                                    height: 120,
                                    width: 120,
                                    fit: BoxFit.cover,
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      color: Colors.black54,
                                      child: Text(
                                        'Frame ${index + 1}',
                                        style: const TextStyle(color: Colors.white, fontSize: 12),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Direction Information
                    Card(
                      color: Colors.green.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Direction Information',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            
                            const SizedBox(height: 8),
                            
                            Row(
                              children: [
                                Checkbox(
                                  value: _saveWithDirection,
                                  onChanged: (value) {
                                    setState(() {
                                      _saveWithDirection = value ?? true;
                                    });
                                  },
                                ),
                                Expanded(
                                  child: const Text('Save with direction information'),
                                ),
                              ],
                            ),
                            
                            if (_saveWithDirection) ...[
                              Row(
                                children: [
                                  Checkbox(
                                    value: _useManualDirection,
                                    onChanged: (value) {
                                      setState(() {
                                        _useManualDirection = value ?? false;
                                      });
                                    },
                                  ),
                                  Expanded(
                                    child: const Text('Use manual direction'),
                                  ),
                                ],
                              ),
                              
                              if (_useManualDirection)
                                TextField(
                                  controller: _manualDirectionController,
                                  decoration: InputDecoration(
                                    labelText: 'Direction (degrees)',
                                    hintText: 'Enter direction in degrees (0-360)',
                                    border: OutlineInputBorder(),
                                    suffixText: '°',
                                    helperText: '0° North, 90° East, 180° South, 270° West',
                                  ),
                                  keyboardType: TextInputType.number,
                                )
                              else
                                Text(
                                  'Current direction: ${_normalizedDirection.toStringAsFixed(1)}° ($_cardinalDirection)',
                                  style: TextStyle(fontSize: 16),
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    TextField(
                      controller: _placeNameController,
                      decoration: const InputDecoration(
                        labelText: 'Location Name',
                        hintText: 'Enter a name for this location',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
  
  void _showFrameDetails(int index) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Frame ${index + 1}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.file(_extractedFrames[index]),
              const SizedBox(height: 16),
              const Text('Use this frame to save a location?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _saveLocationEmbedding(index);
              },
              child: const Text('Save Location'),
            ),
          ],
        );
      },
    );
  }
} 