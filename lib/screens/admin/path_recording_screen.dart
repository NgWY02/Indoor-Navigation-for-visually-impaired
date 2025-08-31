import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/supabase_service.dart';
import '../../services/clip_service.dart';
import '../../services/continuous_path_recorder.dart';
import '../../models/path_models.dart';
import 'package:uuid/uuid.dart';

class PathRecordingScreen extends StatefulWidget {
  final CameraDescription camera;
  final String startLocationId;
  final String endLocationId;
  final String startLocationName;
  final String endLocationName;

  const PathRecordingScreen({
    Key? key,
    required this.camera,
    required this.startLocationId,
    required this.endLocationId,
    required this.startLocationName,
    required this.endLocationName,
  }) : super(key: key);

  @override
  _PathRecordingScreenState createState() => _PathRecordingScreenState();
}

class _PathRecordingScreenState extends State<PathRecordingScreen> {
  late CameraController _cameraController;
  late ClipService _clipService;
  late ContinuousPathRecorder _pathRecorder;
  late FlutterTts _flutterTts;
  
  bool _isLoading = true;
  bool _isClipServerReady = false;
  String _statusMessage = "Initializing...";
  int _waypointCount = 0;
  bool _isRecording = false;
  bool _isProcessing = false; // Track when waypoints are being processed
  
  // Path info
  final TextEditingController _pathNameController = TextEditingController();
  
  // Current heading for display
  double? _currentHeading;
  StreamSubscription<CompassEvent>? _compassSubscription;

  @override
  void initState() {
    super.initState();
    _initializeComponents();
  }

  Future<void> _initializeComponents() async {
    await _requestPermissions();
    await _initializeCamera();
    await _initializeClipService();
    await _initializeTts();
    await _initializePathRecorder();
    _initializeCompass();
    
    setState(() {
      _isLoading = false;
      _statusMessage = "";
    });
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      await [
        Permission.camera,
        Permission.location,
        Permission.microphone,
      ].request();
    }
  }

  Future<void> _initializeCamera() async {
    _cameraController = CameraController(
      widget.camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await _cameraController.initialize();
      await _cameraController.setFlashMode(FlashMode.off);
    } catch (e) {
      setState(() {
        _statusMessage = "Camera error: $e";
      });
    }
  }

  Future<void> _initializeClipService() async {
    try {
      _clipService = ClipService();
      _isClipServerReady = await _clipService.isServerAvailable();
    } catch (e) {
      setState(() {
        _statusMessage = "CLIP service error: $e";
      });
    }
  }

  Future<void> _initializeTts() async {
    _flutterTts = FlutterTts();
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  Future<void> _initializePathRecorder() async {
    _pathRecorder = ContinuousPathRecorder(
      clipService: _clipService,
      cameraController: _cameraController,
      onStatusUpdate: (message) {
        setState(() {
          _statusMessage = message;
          // Detect when processing starts
          if (message.contains('Processing') || message.contains('Recording stopped. Processing')) {
            _isProcessing = true;
          }
          // Detect when processing ends
          else if (message.contains('Recording complete') || 
                   message.contains('Path saved') || 
                   message.contains('Error') ||
                   message.contains('Failed')) {
            _isProcessing = false;
          }
        });
        _speak(message);
      },
      onWaypointCaptured: (waypoint) {
        setState(() {
          _waypointCount = _pathRecorder.waypointCount;
        });
      },
      onError: (error) {
        setState(() {
          _statusMessage = "Error: $error";
        });
        _speak("Recording error occurred");
      },
    );
  }

  void _initializeCompass() {
    if (FlutterCompass.events != null) {
      _compassSubscription = FlutterCompass.events!.listen((event) {
        if (mounted && event.heading != null) {
          setState(() {
            _currentHeading = event.heading;
          });
        }
      });
    }
  }

  Future<void> _speak(String text) async {
    if (text.isNotEmpty) {
      await _flutterTts.speak(text);
    }
  }

  Future<void> _startRecording() async {
    if (!_isClipServerReady) {
      _speak("CLIP service not ready. Cannot start recording.");
      return;
    }

    const uuid = Uuid();
    String pathId = uuid.v4();
    
    await _pathRecorder.startRecording(pathId);
    setState(() {
      _isRecording = true;
      _isProcessing = false; // Reset processing state when starting new recording
    });
  }

  Future<void> _stopRecording() async {
    await _pathRecorder.stopRecording();
    setState(() {
      _isRecording = false;
      // Note: _isProcessing will be set to true by the status update callback
      // when processing starts, and reset when processing completes
    });
    
    if (_pathRecorder.waypointCount > 0) {
      _showSavePathDialog();
    }
  }

  void _showSavePathDialog() {
    // Pre-fill path name
        // Initialize default path name with node names
    _pathNameController.text = '${widget.startLocationName} to ${widget.endLocationName}';
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Save Recorded Path'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _pathNameController,
                decoration: const InputDecoration(
                  labelText: 'Path Name',
                  hintText: 'e.g., Main Entrance to Cafeteria',
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Recorded ${_pathRecorder.waypointCount} waypoints',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Optionally ask if they want to discard the recording
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await _savePath();
              Navigator.pop(context);
            },
            child: const Text('Save Path'),
          ),
        ],
      ),
    );
  }

  Future<void> _savePath() async {
    if (_pathNameController.text.isEmpty) {
      _speak("Please enter a path name");
      return;
    }

    try {
      setState(() {
        _statusMessage = "Saving path...";
      });

      NavigationPath path = _pathRecorder.createNavigationPath(
        name: _pathNameController.text,
        startLocationId: widget.startLocationId,
        endLocationId: widget.endLocationId,
      );

      // Save to Supabase with enhanced error handling
      final supabaseService = SupabaseService();

      try {
        await supabaseService.savePath(path);
      } catch (saveError) {
        print(' Save path error: $saveError');

        // Check if it's an RLS policy violation
        if (saveError.toString().contains('violates row-level security policy') ||
            saveError.toString().contains('Authentication error')) {

          // Try to refresh the session
          setState(() {
            _statusMessage = "Authentication issue detected. Refreshing session...";
          });

          final sessionRefreshed = await supabaseService.refreshSession();

          if (sessionRefreshed) {
            // Try saving again after session refresh
            setState(() {
              _statusMessage = "Session refreshed. Retrying save...";
            });

            try {
              await supabaseService.savePath(path);
            } catch (retryError) {
              setState(() {
                _statusMessage = "Failed to save path after session refresh. Please sign out and sign in again.";
              });
              _speak("Failed to save path. Please sign out and sign in again.");
              return;
            }
          } else {
            setState(() {
              _statusMessage = "Session refresh failed. Please sign out and sign in again.";
            });
            _speak("Authentication failed. Please sign out and sign in again.");
            return;
          }
        } else {
          // Re-throw other errors
          rethrow;
        }
      }

      setState(() {
        _statusMessage = "Path saved successfully!";
      });

      _speak("Path saved successfully");

      // Return to previous screen after a delay
      Future.delayed(const Duration(seconds: 2), () {
        Navigator.pop(context, path);
      });

    } catch (e) {
      setState(() {
        _statusMessage = "Error saving path: $e";
      });
      _speak("Error saving path");
    }
  }

  String _getDirectionName(double? heading) {
    if (heading == null) return "Unknown";
    
    int normalizedAngle = heading.round() % 360;
    if (normalizedAngle >= 348.75 || normalizedAngle < 11.25) return "North";
    if (normalizedAngle >= 11.25 && normalizedAngle < 33.75) return "North-Northeast";
    if (normalizedAngle >= 33.75 && normalizedAngle < 56.25) return "Northeast";
    if (normalizedAngle >= 56.25 && normalizedAngle < 78.75) return "East-Northeast";
    if (normalizedAngle >= 78.75 && normalizedAngle < 101.25) return "East";
    if (normalizedAngle >= 101.25 && normalizedAngle < 123.75) return "East-Southeast";
    if (normalizedAngle >= 123.75 && normalizedAngle < 146.25) return "Southeast";
    if (normalizedAngle >= 146.25 && normalizedAngle < 168.75) return "South-Southeast";
    if (normalizedAngle >= 168.75 && normalizedAngle < 191.25) return "South";
    if (normalizedAngle >= 191.25 && normalizedAngle < 213.75) return "South-Southwest";
    if (normalizedAngle >= 213.75 && normalizedAngle < 236.25) return "Southwest";
    if (normalizedAngle >= 236.25 && normalizedAngle < 258.75) return "West-Southwest";
    if (normalizedAngle >= 258.75 && normalizedAngle < 281.25) return "West";
    if (normalizedAngle >= 281.25 && normalizedAngle < 303.75) return "West-Northwest";
    if (normalizedAngle >= 303.75 && normalizedAngle < 326.25) return "Northwest";
    if (normalizedAngle >= 326.25 && normalizedAngle < 348.75) return "North-Northwest";
    return "$normalizedAngle°";
  }

  @override
  void dispose() {
    _pathRecorder.dispose();
    _compassSubscription?.cancel();
    _cameraController.dispose();
    _flutterTts.stop();
    _pathNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;
    final isPortrait = screenHeight > screenWidth;

    if (_isLoading) {
      return Scaffold(
        body: Container(
          color: Colors.teal,
          child: const SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 20),
                  Text(
                    "Initializing path recording...",
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (!_cameraController.value.isInitialized) {
      return Scaffold(
        body: Container(
          color: Colors.teal,
          child: const SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 20),
                  Text(
                    "Initializing camera...",
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Container(
        color: Colors.black,
        child: SafeArea(
          child: Column(
            children: [
              // Camera preview - responsive for phones
              Expanded(
                flex: isPortrait ? 5 : 3,
                child: Stack(
                  children: [
                    // Camera preview
                    Positioned.fill(
                      child: CameraPreview(_cameraController),
                    ),

                    // Compact route info overlay - responsive positioning
                    Positioned(
                      top: screenHeight * 0.02,
                      left: screenWidth * 0.05,
                      right: screenWidth * 0.05,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: screenWidth * 0.04,
                          vertical: screenHeight * 0.01,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                widget.startLocationName,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: screenWidth * 0.03,
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            SizedBox(width: screenWidth * 0.02),
                            Icon(
                              Icons.arrow_forward,
                              color: Colors.teal,
                              size: screenWidth * 0.04,
                            ),
                            SizedBox(width: screenWidth * 0.02),
                            Flexible(
                              child: Text(
                                widget.endLocationName,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: screenWidth * 0.03,
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Status overlay - responsive positioning
                    Positioned(
                      top: screenHeight * 0.08,
                      left: screenWidth * 0.05,
                      child: Container(
                        padding: EdgeInsets.all(screenWidth * 0.02),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Waypoints: $_waypointCount",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: screenWidth * 0.03,
                              ),
                            ),
                            Text(
                              "Heading: ${_getDirectionName(_currentHeading)}",
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: screenWidth * 0.025,
                              ),
                            ),
                            if (_currentHeading != null)
                              Text(
                                "${_currentHeading!.round()}°",
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: screenWidth * 0.025,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    // Status message overlay - responsive positioning
                    if (_statusMessage.isNotEmpty && !_isProcessing)
                      Positioned(
                        left: screenWidth * 0.05,
                        right: screenWidth * 0.05,
                        bottom: screenHeight * 0.02,
                        child: Container(
                          padding: EdgeInsets.all(screenWidth * 0.02),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _statusMessage,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: screenWidth * 0.03,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),

                    // Processing overlay - blocks interactions during waypoint processing
                    if (_isProcessing)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.8),
                          child: Center(
                            child: Container(
                              padding: EdgeInsets.all(screenWidth * 0.06),
                              margin: EdgeInsets.symmetric(horizontal: screenWidth * 0.1),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    blurRadius: 10,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Processing indicator
                                  SizedBox(
                                    width: screenWidth * 0.15,
                                    height: screenWidth * 0.15,
                                    child: const CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.teal),
                                      strokeWidth: 4,
                                    ),
                                  ),
                                  SizedBox(height: screenHeight * 0.02),
                                  // Processing title
                                  Text(
                                    "Processing Waypoints",
                                    style: TextStyle(
                                      fontSize: screenWidth * 0.045,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  SizedBox(height: screenHeight * 0.01),
                                  // Processing message
                                  Text(
                                    _statusMessage,
                                    style: TextStyle(
                                      fontSize: screenWidth * 0.035,
                                      color: Colors.black54,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  SizedBox(height: screenHeight * 0.02),
                                  // Processing hint
                                  Text(
                                    "Please wait while we process your recorded path...",
                                    style: TextStyle(
                                      fontSize: screenWidth * 0.03,
                                      color: Colors.black45,
                                      fontStyle: FontStyle.italic,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Bottom controls - responsive for phones
              Container(
                padding: EdgeInsets.all(screenWidth * 0.04),
                color: Colors.white,
                child: Column(
                  children: [
                    // Main control buttons - responsive sizing
                    if (!_isRecording)
                      Row(
                        children: [
                          // Cancel button - responsive
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: Icon(Icons.cancel, size: screenWidth * 0.045),
                              label: Text(
                                "Cancel",
                                style: TextStyle(fontSize: screenWidth * 0.03),
                              ),
                              onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _isProcessing ? Colors.grey[400] : Colors.grey[700],
                                side: BorderSide(color: _isProcessing ? Colors.grey[300]! : Colors.grey[400]!),
                                padding: EdgeInsets.symmetric(vertical: screenHeight * 0.015),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: screenWidth * 0.02),
                          // Start Recording button - responsive
                          Expanded(
                            flex: 2,
                            child: ElevatedButton.icon(
                              icon: Icon(Icons.play_arrow, size: screenWidth * 0.045),
                              label: Text(
                                "Start Recording",
                                style: TextStyle(fontSize: screenWidth * 0.03),
                              ),
                              onPressed: _isProcessing ? null : (_isClipServerReady ? _startRecording : null),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isProcessing ? Colors.grey[400] : Colors.green,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(vertical: screenHeight * 0.015),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                    if (_isRecording)
                      Row(
                        children: [
                          // Stop Recording button - responsive, full width
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: Icon(Icons.stop, size: screenWidth * 0.045),
                              label: Text(
                                "Stop Recording",
                                style: TextStyle(fontSize: screenWidth * 0.03),
                              ),
                              onPressed: _isProcessing ? null : _stopRecording,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isProcessing ? Colors.grey[400] : Colors.red,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(vertical: screenHeight * 0.015),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                    if (!_isRecording && _waypointCount > 0)
                      Padding(
                        padding: EdgeInsets.only(top: screenHeight * 0.015),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: Icon(Icons.save, size: screenWidth * 0.045),
                            label: Text(
                              "Save Path",
                              style: TextStyle(fontSize: screenWidth * 0.03),
                            ),
                            onPressed: _isProcessing ? null : () => _showSavePathDialog(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isProcessing ? Colors.grey[400] : Colors.teal,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: screenHeight * 0.015),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
