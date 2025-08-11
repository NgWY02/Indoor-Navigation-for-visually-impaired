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
  bool _showOverlayCompare = false;
  double _overlayOpacity = 0.5;
  
  // Server configuration - use network IP for mobile access
  static const String _serverHost = '192.168.0.104'; // Your PC's IP address
  static const int _serverPort = 8000; // Use the CLIP gateway port

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final isTablet = screenWidth > 600;
    final isLargeTablet = screenWidth > 900;
    
    // Calculate responsive values
    final horizontalPadding = isLargeTablet ? 48.0 : (isTablet ? 32.0 : 16.0);
    final verticalPadding = isTablet ? 24.0 : 16.0;
    final bottomSafeArea = mediaQuery.padding.bottom;
    final hasBottomNavigation = bottomSafeArea > 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Image Processing Test',
          style: TextStyle(
            fontSize: isTablet ? 22 : 20,
          ),
        ),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: horizontalPadding,
            right: horizontalPadding,
            top: verticalPadding,
            bottom: hasBottomNavigation ? verticalPadding + 16 : verticalPadding,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isLargeTablet ? 1000 : double.infinity,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header Info
                Card(
                  color: Colors.blue.shade50,
                  elevation: isTablet ? 4 : 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(isTablet ? 24.0 : 16.0),
                    child: Column(
                      children: [
                        Icon(Icons.science, size: isTablet ? 64 : 48, color: Colors.blue),
                        SizedBox(height: isTablet ? 12 : 8),
                        Text(
                          'People Removal Test',
                          style: TextStyle(
                            fontSize: isTablet ? 24 : 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                        SizedBox(height: isTablet ? 12 : 8),
                        Text(
                          'Upload an image to test SAM + LaMa inpainting',
                          style: TextStyle(
                            fontSize: isTablet ? 16 : 14,
                            color: Colors.grey.shade700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                
                SizedBox(height: isTablet ? 32 : 20),
                
                // Upload Button
                ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _pickImage,
                  icon: Icon(Icons.upload, size: isTablet ? 24 : 20),
                  label: Text(
                    'Select Image',
                    style: TextStyle(fontSize: isTablet ? 18 : 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                      vertical: isTablet ? 20 : 16,
                      horizontal: isTablet ? 24 : 16,
                    ),
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(isTablet ? 12 : 8),
                    ),
                  ),
                ),
            
            const SizedBox(height: 20),
            
            // Selected Image & Process Button
            if (_selectedImage != null) ...[
              // Side-by-side original and processed preview when available
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Original', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Container(
                          height: 200,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(_selectedImage!, fit: BoxFit.contain, width: double.infinity),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Processed', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Container(
                          height: 200,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.green.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: _processedImageBytes == null
                                ? Container(
                                    alignment: Alignment.center,
                                    child: Text(
                                      _isProcessing ? 'Processing…' : 'No result yet',
                                      style: TextStyle(color: Colors.grey.shade600),
                                    ),
                                  )
                                : Image.memory(_processedImageBytes!, fit: BoxFit.contain, width: double.infinity),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
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
            
            // Overlay compare (processed over original)
            if (_selectedImage != null && _processedImageBytes != null) ...[
              const SizedBox(height: 20),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Overlay compare'),
                subtitle: const Text('Blend processed over original to inspect differences'),
                value: _showOverlayCompare,
                onChanged: (v) => setState(() => _showOverlayCompare = v),
              ),
              if (_showOverlayCompare) ...[
                Slider(
                  value: _overlayOpacity,
                  onChanged: (v) => setState(() => _overlayOpacity = v),
                  min: 0.0,
                  max: 1.0,
                  divisions: 10,
                  label: 'Opacity: ${(_overlayOpacity * 100).round()}%'
                ),
                Container(
                  height: 220,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.blue.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(_selectedImage!, fit: BoxFit.contain),
                        Opacity(
                          opacity: _overlayOpacity,
                          child: Image.memory(_processedImageBytes!, fit: BoxFit.contain),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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
        _statusMessage = 'Testing server connection...';
      });
      
      final healthResponse = await http.get(
        Uri.parse('http://$_serverHost:$_serverPort/health'),
      ).timeout(const Duration(seconds: 5));
      
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

      // Send to inpaint preview endpoint
      final response = await http.post(
        Uri.parse('http://$_serverHost:$_serverPort/inpaint/preview'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'image': base64Image,
        }),
      ).timeout(const Duration(seconds: 120));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (!data.containsKey('processed_image')) {
          setState(() {
            _statusMessage = 'Error: Server response missing processed_image';
            _isProcessing = false;
          });
          return;
        }
        
        // Decode processed image
        final processedImageBytes = base64Decode(data['processed_image']);
        final usedFallback = (data['fallback'] == true);
        
        setState(() {
          _processedImageBytes = processedImageBytes;
          _processingStats = null;
          _statusMessage = usedFallback 
              ? 'Processing completed (fallback to original - inpainting unavailable).'
              : 'Processing completed successfully!';
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
