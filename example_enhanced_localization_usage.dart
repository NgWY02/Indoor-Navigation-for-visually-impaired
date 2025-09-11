// Example: How to use the enhanced localization system
// Add this to your navigation screen

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'lib/services/clip_service.dart';

class EnhancedLocalizationExample extends StatefulWidget {
  @override
  _EnhancedLocalizationExampleState createState() => _EnhancedLocalizationExampleState();
}

class _EnhancedLocalizationExampleState extends State<EnhancedLocalizationExample> {
  CameraController? _cameraController;
  String _statusMessage = 'Ready to start enhanced localization';
  String _result = '';
  bool _isProcessing = false;
  
  final ClipService _clipService = ClipService();
  
  // TODO: Replace with your actual OpenAI API key from .env
  final String? _gptApiKey = 'sk-your-openai-api-key-here'; // Or load from dotenv
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Enhanced Localization')),
      body: Column(
        children: [
          // Camera preview (if you have one)
          Expanded(
            flex: 3,
            child: _cameraController?.value.isInitialized == true
                ? CameraPreview(_cameraController!)
                : Center(child: Text('Camera not initialized')),
          ),
          
          // Status and results
          Expanded(
            flex: 2,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(_statusMessage, style: TextStyle(fontSize: 16)),
                  SizedBox(height: 16),
                  Text(_result, style: TextStyle(fontSize: 14, color: Colors.green)),
                  SizedBox(height: 16),
                  
                  // Action buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: _isProcessing ? null : _performEnhancedLocalization,
                        child: Text(_isProcessing ? 'Processing...' : 'Start Enhanced Scan'),
                      ),
                      ElevatedButton(
                        onPressed: _isProcessing ? null : _performQuickLocalization,
                        child: Text('Quick Localization'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  /// Full enhanced localization with VLM verification
  Future<void> _performEnhancedLocalization() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      setState(() => _statusMessage = 'Camera not ready');
      return;
    }
    
    setState(() {
      _isProcessing = true;
      _result = '';
    });
    
    try {
      final result = await _clipService.performEnhancedLocalization(
        cameraController: _cameraController!,
        gptApiKey: _gptApiKey, // Optional - if null, skips VLM verification
        onStatusUpdate: (message) {
          setState(() => _statusMessage = message);
        },
      );
      
      setState(() {
        if (result.success) {
          _result = 'Location: ${result.detectedLocation}\n'
                  'Confidence: ${((result.confidence ?? 0) * 100).toStringAsFixed(1)}%\n'
                  'Frames: ${result.capturedFrameCount} → ${result.qualifiedFrameCount} qualified\n'
                  '${result.vlmConfidence != null ? "VLM: ${result.vlmConfidence!.toStringAsFixed(1)}%" : "No VLM verification"}';
          _statusMessage = 'Enhanced localization complete!';
        } else {
          _result = 'Failed: ${result.errorMessage}';
          _statusMessage = 'Localization failed';
        }
      });
      
    } catch (e) {
      setState(() {
        _result = 'Error: $e';
        _statusMessage = 'Localization error';
      });
    }
    
    setState(() => _isProcessing = false);
  }
  
  /// Quick localization (simplified usage)
  Future<void> _performQuickLocalization() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      setState(() => _statusMessage = 'Camera not ready');
      return;
    }
    
    setState(() {
      _isProcessing = true;
      _result = '';
    });
    
    try {
      final result = await _clipService.performQuickLocalization(
        cameraController: _cameraController!,
        gptApiKey: _gptApiKey,
        onStatusUpdate: (message) {
          setState(() => _statusMessage = message);
        },
      );
      
      setState(() {
        _result = result;
        _statusMessage = 'Quick localization complete!';
      });
      
    } catch (e) {
      setState(() {
        _result = 'Error: $e';
        _statusMessage = 'Localization error';
      });
    }
    
    setState(() => _isProcessing = false);
  }
}

// Alternative: Simple integration into existing navigation flow
class SimpleIntegration {
  static Future<String> getLocationNow(CameraController cameraController) async {
    final clipService = ClipService();
    
    // Simple one-line localization
    return await clipService.performQuickLocalization(
      cameraController: cameraController,
      gptApiKey: 'your-openai-api-key', // Optional
    );
  }
}
