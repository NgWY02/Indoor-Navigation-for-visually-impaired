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
  bool _isPaused = false;
  
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
      _statusMessage = "Ready to record path";
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
      _isPaused = false;
    });
  }

  Future<void> _stopRecording() async {
    await _pathRecorder.stopRecording();
    setState(() {
      _isRecording = false;
      _isPaused = false;
    });
    
    if (_pathRecorder.waypointCount > 0) {
      _showSavePathDialog();
    }
  }

  Future<void> _pauseRecording() async {
    await _pathRecorder.pauseRecording();
    setState(() {
      _isPaused = true;
    });
  }

  Future<void> _resumeRecording() async {
    await _pathRecorder.resumeRecording();
    setState(() {
      _isPaused = false;
    });
  }

  void _addManualWaypoint() {
    _showManualWaypointDialog();
  }

  void _showManualWaypointDialog() {
    final TextEditingController controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Manual Waypoint'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Describe this location (e.g., "Door to cafeteria")',
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                _pathRecorder.addManualWaypoint(controller.text);
                Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
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
        print('❌ Save path error: $saveError');

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
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    final isTablet = screenWidth > 600;
    final isLandscape = screenWidth > screenHeight;
    final bottomSafeArea = mediaQuery.padding.bottom;
    final hasBottomNavigation = bottomSafeArea > 0;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            'Path Recording',
            style: TextStyle(fontSize: isTablet ? 22 : 20),
          ),
          backgroundColor: Colors.teal,
        ),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text("Initializing path recording..."),
            ],
          ),
        ),
      );
    }

    if (!_cameraController.value.isInitialized) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            'Path Recording',
            style: TextStyle(fontSize: isTablet ? 22 : 20),
          ),
          backgroundColor: Colors.teal,
        ),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text("Initializing camera..."),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isTablet ? '${widget.startLocationName} → ${widget.endLocationName}' : 'Record Path',
          style: TextStyle(fontSize: isTablet ? 20 : 18),
        ),
        backgroundColor: Colors.teal,
        actions: [
          if (_isRecording && !_isPaused)
            IconButton(
              icon: const Icon(Icons.pause),
              onPressed: _pauseRecording,
              tooltip: 'Pause Recording',
            ),
          if (_isRecording && _isPaused)
            IconButton(
              icon: const Icon(Icons.play_arrow),
              onPressed: _resumeRecording,
              tooltip: 'Resume Recording',
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Camera preview - responsive flex ratios
            Expanded(
              flex: isLandscape ? 2 : (isTablet ? 3 : 3),
              child: Stack(
                children: [
                  CameraPreview(_cameraController),
                
                // Recording overlay
                if (_isRecording)
                  Container(
                    color: Colors.red.withOpacity(0.1),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isPaused ? Icons.pause_circle : Icons.fiber_manual_record,
                            color: _isPaused ? Colors.orange : Colors.red,
                            size: isTablet ? 80 : 60,
                          ),
                          SizedBox(height: isTablet ? 16 : 10),
                          Text(
                            _isPaused ? 'PAUSED' : 'RECORDING',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isTablet ? 22 : 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Status overlay (top-left)
                Positioned(
                  top: isTablet ? 24 : 20,
                  left: isTablet ? 24 : 20,
                  child: Container(
                    padding: EdgeInsets.all(isTablet ? 16 : 12),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(isTablet ? 16 : 10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Waypoints: $_waypointCount",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: isTablet ? 16 : 14,
                          ),
                        ),
                        Text(
                          "Heading: ${_getDirectionName(_currentHeading)}",
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: isTablet ? 14 : 12,
                          ),
                        ),
                        if (_currentHeading != null)
                          Text(
                            "${_currentHeading!.round()}°",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: isTablet ? 14 : 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                ],
              ),
            ),

            // Route info
            Container(
              padding: EdgeInsets.all(isTablet ? 20 : 16),
              color: Colors.teal.shade50,
              width: double.infinity,
              child: Column(
                children: [
                  Text(
                    "From: ${widget.startLocationName}",
                    style: TextStyle(
                      fontSize: isTablet ? 18 : 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Icon(
                    Icons.arrow_downward,
                    color: Colors.teal,
                    size: isTablet ? 28 : 24,
                  ),
                  Text(
                    "To: ${widget.endLocationName}",
                    style: TextStyle(
                      fontSize: isTablet ? 18 : 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            // Status message
            Container(
              padding: EdgeInsets.all(isTablet ? 20 : 16),
              color: Colors.teal.shade100,
              width: double.infinity,
              child: Text(
                _statusMessage,
                style: TextStyle(fontSize: isTablet ? 18 : 16),
                textAlign: TextAlign.center,
              ),
            ),

            // Control buttons
            Padding(
              padding: EdgeInsets.only(
                left: isTablet ? 24 : 16,
                right: isTablet ? 24 : 16,
                top: isTablet ? 24 : 16,
                bottom: hasBottomNavigation ? (isTablet ? 32 : 24) : (isTablet ? 24 : 16),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      if (!_isRecording)
                        ElevatedButton.icon(
                          icon: Icon(Icons.play_arrow, size: isTablet ? 24 : 20),
                          label: Text(
                            "Start Recording",
                            style: TextStyle(fontSize: isTablet ? 16 : 14),
                          ),
                          onPressed: _isClipServerReady ? _startRecording : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              horizontal: isTablet ? 24 : 20,
                              vertical: isTablet ? 16 : 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(isTablet ? 12 : 8),
                            ),
                          ),
                        ),
                      
                      if (_isRecording)
                        ElevatedButton.icon(
                          icon: Icon(Icons.stop, size: isTablet ? 24 : 20),
                          label: Text(
                            "Stop Recording",
                            style: TextStyle(fontSize: isTablet ? 16 : 14),
                          ),
                          onPressed: _stopRecording,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              horizontal: isTablet ? 24 : 20,
                              vertical: isTablet ? 16 : 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(isTablet ? 12 : 8),
                            ),
                          ),
                        ),
                      
                      if (_isRecording)
                        ElevatedButton.icon(
                          icon: Icon(Icons.add_location, size: isTablet ? 24 : 20),
                          label: Text(
                            "Add Landmark",
                            style: TextStyle(fontSize: isTablet ? 16 : 14),
                          ),
                          onPressed: _addManualWaypoint,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              horizontal: isTablet ? 24 : 20,
                              vertical: isTablet ? 16 : 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(isTablet ? 12 : 8),
                            ),
                          ),
                        ),
                    ],
                  ),
                  
                  if (!_isRecording && _waypointCount > 0)
                    Padding(
                      padding: EdgeInsets.only(top: isTablet ? 16 : 12),
                      child: ElevatedButton.icon(
                        icon: Icon(Icons.save, size: isTablet ? 24 : 20),
                        label: Text(
                          "Save Path",
                          style: TextStyle(fontSize: isTablet ? 16 : 14),
                        ),
                        onPressed: () => _showSavePathDialog(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            horizontal: isTablet ? 24 : 20,
                            vertical: isTablet ? 16 : 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(isTablet ? 12 : 8),
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
    );
  }
}
