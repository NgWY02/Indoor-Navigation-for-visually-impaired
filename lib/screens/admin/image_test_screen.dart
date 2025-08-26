import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

class ImageTestScreen extends StatefulWidget {
  const ImageTestScreen({Key? key}) : super(key: key);

  @override
  _ImageTestScreenState createState() => _ImageTestScreenState();
}

class _ImageTestScreenState extends State<ImageTestScreen> {
  File? _selectedImage;
  Uint8List? _processedImageBytes;
  bool _isProcessing = false;
  String _statusMessage = '';
  Map<String, dynamic>? _processingStats;
  final ImagePicker _picker = ImagePicker();
  
  // Server configuration - use network IP for mobile access
  static const String _serverHost = '192.168.0.101'; // Your PC's IP address
  static const int _serverPort = 8000; 

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Image Processing Test'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Info
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Icon(Icons.science, size: 48, color: Colors.blue),
                    const SizedBox(height: 8),
                    const Text(
                      'People Removal Test',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Upload an image to test the crowd removal AI',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Upload Button
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _pickImage,
              icon: const Icon(Icons.upload),
              label: const Text('Select Image'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Selected Image Preview
            if (_selectedImage != null) ...[
              const Text(
                'Original Image:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    _selectedImage!,
                    fit: BoxFit.contain,
                    width: double.infinity,
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Process Button
              ElevatedButton.icon(
                onPressed: _isProcessing ? null : _processImage,
                icon: _isProcessing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.auto_fix_high),
                label: Text(_isProcessing ? 'Processing...' : 'Remove People'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
            
            // Status Message
            if (_statusMessage.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _statusMessage.contains('Error') 
                      ? Colors.red.shade50 
                      : Colors.green.shade50,
                  border: Border.all(
                    color: _statusMessage.contains('Error') 
                        ? Colors.red.shade300 
                        : Colors.green.shade300,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _statusMessage,
                  style: TextStyle(
                    color: _statusMessage.contains('Error') 
                        ? Colors.red.shade700 
                        : Colors.green.shade700,
                  ),
                ),
              ),
            ],
            
            // Processing Stats
            if (_processingStats != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Processing Statistics:',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      _buildStatRow('Crowd Density', '${(_processingStats!['crowd_density'] * 100).toStringAsFixed(1)}%'),
                      _buildStatRow('Processing Mode', _processingStats!['processing_mode'].toString().toUpperCase()),
                      _buildStatRow('Processing Time', '${_processingStats!['processing_time'].toStringAsFixed(0)}ms'),
                      _buildStatRow('Average FPS', '${_processingStats!['average_fps'].toStringAsFixed(1)}'),
                    ],
                  ),
                ),
              ),
            ],
            
            // Processed Image Result
            if (_processedImageBytes != null) ...[
              const SizedBox(height: 20),
              const Text(
                'Processed Image (People Removed):',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.green.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    _processedImageBytes!,
                    fit: BoxFit.contain,
                    width: double.infinity,
                  ),
                ),
              ),
            ],
            
            const SizedBox(height: 20),
            
            // Clear Button
            if (_selectedImage != null || _processedImageBytes != null)
              OutlinedButton.icon(
                onPressed: _clearImages,
                icon: const Icon(Icons.clear),
                label: const Text('Clear All'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(color: Colors.blue)),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 90,
      );
      
      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
          _processedImageBytes = null;
          _statusMessage = '';
          _processingStats = null;
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error selecting image: $e';
      });
    }
  }

  Future<void> _processImage() async {
    if (_selectedImage == null) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Processing image...';
      _processedImageBytes = null;
      _processingStats = null;
    });

    try {
      // Test server connectivity first
      setState(() {
        _statusMessage = 'Testing server connection to $_serverHost:$_serverPort...';
      });
      
      print('Testing connection to: http://$_serverHost:$_serverPort/health');
      
      final healthResponse = await http.get(
        Uri.parse('http://$_serverHost:$_serverPort/health'),
      ).timeout(const Duration(seconds: 15));
      
      print('Health check response: ${healthResponse.statusCode}');
      
      if (healthResponse.statusCode != 200) {
        setState(() {
          _statusMessage = 'Error: Cannot connect to server. Status: ${healthResponse.statusCode}';
          _isProcessing = false;
        });
        return;
      }
      
      setState(() {
        _statusMessage = 'Server connected! Reading image...';
      });

      // Read image file
      final imageBytes = await _selectedImage!.readAsBytes();
      final base64Image = base64Encode(imageBytes);
      
      setState(() {
        _statusMessage = 'Sending image to server... (${imageBytes.length} bytes)';
      });

      print('Sending request to: http://$_serverHost:$_serverPort/inpaint/preview');
      print('Image size: ${imageBytes.length} bytes');
      print('Base64 size: ${base64Image.length} characters');

      // Send to processing server
      final response = await http.post(
        Uri.parse('http://$_serverHost:$_serverPort/inpaint/preview'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'image': base64Image,
        }),
      ).timeout(const Duration(seconds: 60));

      print('Response status: ${response.statusCode}');
      print('Response body length: ${response.body.length}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        print('Response data keys: ${data.keys.toList()}');
        
        // Check if processed_image exists
        if (!data.containsKey('processed_image')) {
          setState(() {
            _statusMessage = 'Error: Server response missing processed_image';
            _isProcessing = false;
          });
          return;
        }
        
        // Decode processed image
        final processedImageBytes = base64Decode(data['processed_image']);
        
        setState(() {
          _processedImageBytes = processedImageBytes;
          _processingStats = null;
          _statusMessage = 'Processing completed successfully!';
          _isProcessing = false;
        });
      } else {
        setState(() {
          _statusMessage = 'Error: Server returned ${response.statusCode}\nResponse: ${response.body}';
          _isProcessing = false;
        });
      }
    } catch (e) {
      print('Error processing image: $e');
      setState(() {
        _statusMessage = 'Error processing image: $e';
        _isProcessing = false;
      });
    }
  }

  void _clearImages() {
    setState(() {
      _selectedImage = null;
      _processedImageBytes = null;
      _statusMessage = '';
      _processingStats = null;
    });
  }
}