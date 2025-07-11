import 'dart:async';
import 'dart:math'; // Import dart:math for atan2
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../services/supabase_service.dart'; // Import SupabaseService

class TeachPathScreen extends StatefulWidget {
  final String connectionId;
  final String startNodeName;
  final String endNodeName;

  const TeachPathScreen({
    Key? key,
    required this.connectionId,
    required this.startNodeName,
    required this.endNodeName,
  }) : super(key: key);

  @override
  _TeachPathScreenState createState() => _TeachPathScreenState();
}

class _TeachPathScreenState extends State<TeachPathScreen> {
  final SupabaseService _supabaseService = SupabaseService(); // Add instance
  bool _isRecording = false;
  int _steps = 0;
  int _initialSteps = 0; // Add variable to store initial step count
  double _distance = 0.0;
  double _heading = 0.0;
  
  // Camera
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  List<Map<String, dynamic>> _confirmedLandmarks = [];

  // Sensor-related variables
  late StreamSubscription<StepCount> _stepCountSubscription;
  late StreamSubscription<PedestrianStatus> _pedestrianStatusSubscription;
  late StreamSubscription<MagnetometerEvent> _magnetometerSubscription;
  final List<double> _headings = [];
  String _pedometerStatus = '?';

  @override
  void initState() {
    super.initState();
    print('🎬 TeachPathScreen: initState called');
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    print('🚀 TeachPathScreen: Starting service initialization...');
    
    try {
      print('📷 Initializing camera...');
      await _initializeCamera();
      print('✅ Camera initialization complete');
      
      print('📱 Initializing platform sensors...');
      initPlatformState();
      print('✅ All services initialized successfully');
    } catch (e) {
      print('❌ Service initialization failed: $e');
      print('🔍 Stack trace: ${StackTrace.current}');
    }
  }

  Future<void> _initializeCamera() async {
    _cameras = await availableCameras();
    if (_cameras != null && _cameras!.isNotEmpty) {
      _cameraController = CameraController(
        _cameras![0], 
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420 // Use YUV format for streaming
      );
      await _cameraController!.initialize();
      if (!mounted) return;
      setState(() {
        _isCameraInitialized = true;
      });
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _stepCountSubscription.cancel();
    _pedestrianStatusSubscription.cancel();
    _magnetometerSubscription.cancel();
    super.dispose();
  }

  void initPlatformState() {
    _pedestrianStatusSubscription = Pedometer.pedestrianStatusStream.listen(_onPedestrianStatusChanged);
    _stepCountSubscription = Pedometer.stepCountStream.listen(_onStepCount);
    _magnetometerSubscription = magnetometerEvents.listen(_onMagnetometer);
    _magnetometerSubscription.pause(); // Start in a paused state
  }

  void _onStepCount(StepCount event) {
    if (_isRecording) {
      // If this is the first event after starting, set the initial step count
      if (_initialSteps == 0) {
        _initialSteps = event.steps;
      }
      
      // Calculate steps taken during this session
      final sessionSteps = event.steps - _initialSteps;

      setState(() {
        _steps = sessionSteps;
      });
      // Simple distance calculation: average step length = 0.762 meters
      _updateDistance(_steps * 0.762);
    }
  }

  void _onPedestrianStatusChanged(PedestrianStatus event) {
    setState(() {
      _pedometerStatus = event.status;
    });
  }

  void _onMagnetometer(MagnetometerEvent event) {
    if (_isRecording) {
      // This is a simplified calculation. A real app would use a more robust algorithm.
      double heading = (atan2(event.y, event.x) * (180 / pi)) % 360;
      if(heading < 0) heading += 360;

      setState(() {
         _headings.add(heading);
         _heading = _headings.reduce((a, b) => a + b) / _headings.length;
      });
    }
  }

  void _updateDistance(double newDistance) {
    setState(() {
      _distance = newDistance;
    });
  }

  void _updateHeading(double newHeading) {
    setState(() {
      _heading = newHeading;
    });
  }

  Future<void> _startTeaching() async {
    if (_isRecording) return;
    
    print('🎯 Starting path teaching session...');
    
    // Reset values for a new recording session
    _resetPathData();

    setState(() {
      _isRecording = true;
    });

    _magnetometerSubscription.resume();
    
    // Start simple recording
    print('📹 Starting simple path recording...');
    _startSimpleRecording();
  }

  void _startSimpleRecording() {
    print('🔄 Starting simple path recording...');
    // Simple recording without object detection
    print('✅ Recording step count and distance only');
  }

  Future<void> _stopTeaching() async {
    if (!_isRecording) return;
    
    _magnetometerSubscription.pause();
    
    setState(() {
      _isRecording = false;
    });
    
    // Present the results in a dialog
    if (_steps > 0 || _distance > 0) {
      _showSaveDialog();
    }
  }

  void _resetPathData() {
    setState(() {
      _steps = 0;
      _initialSteps = 0;
      _distance = 0.0;
      _heading = 0.0;
      _headings.clear();
      _confirmedLandmarks.clear();
      _pedometerStatus = '?';
    });
  }

  void _showSaveDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Path Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Steps: $_steps'),
            Text('Distance: ${_distance.toStringAsFixed(2)}m'),
            Text('Avg. Heading: ${_heading.toStringAsFixed(1)}°'),
            Text('Landmarks Found: ${_confirmedLandmarks.length}'),
            const SizedBox(height: 16),
            const Text('Save these details to the path?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Discard'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final success = await _supabaseService.updateNodeConnection(
                  connectionId: widget.connectionId,
                  steps: _steps,
                  distanceMeters: _distance,
                  averageHeading: _heading,
                  confirmationObjects: _confirmedLandmarks,
                );
                if (success && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Path details saved!')),
                  );
                  Navigator.of(context).pop(); // Close dialog
                  Navigator.of(context).pop(); // Go back from TeachPathScreen
                } else {
                   throw Exception('Failed to save path details.');
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error saving details: $e')),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: AppBar(
        title: Text('Teach Path: ${widget.startNodeName} to ${widget.endNodeName}'),
      ),
      body: Stack(
        children: [
          // Camera Preview Section - Full screen with proper aspect ratio
          Positioned.fill(
            child: _isCameraInitialized && _cameraController != null
                ? AspectRatio(
                    aspectRatio: _cameraController!.value.aspectRatio,
                    child: CameraPreview(_cameraController!),
                  )
                : Container(
                    color: Colors.black,
                    alignment: Alignment.center,
                    child: const CircularProgressIndicator(),
                  ),
            ),
          
          // Compact info overlay - Top right
          Positioned(
            top: 20,
            right: 20,
            child: Container(
              padding: EdgeInsets.all(screenWidth * 0.03),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _buildCompactInfoRow(Icons.directions_walk, '${_steps}', 'steps'),
                  SizedBox(height: 8),
                  _buildCompactInfoRow(Icons.straighten, '${_distance.toStringAsFixed(1)}m', 'distance'),
                  SizedBox(height: 8),
                  _buildCompactInfoRow(Icons.explore, '${_heading.toStringAsFixed(0)}°', 'heading'),
                ],
              ),
            ),
          ),
          
          // Recording button - Bottom center
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(40),
                ),
                child: ElevatedButton.icon(
                  onPressed: _isRecording ? _stopTeaching : _startTeaching,
                  icon: Icon(
                    _isRecording ? Icons.stop : Icons.school,
                    size: 24,
                  ),
                  label: Text(
                    _isRecording ? 'Stop Teaching' : 'Start Teaching',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isRecording ? Colors.red : Colors.green,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                      horizontal: screenWidth * 0.08,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactInfoRow(IconData icon, String value, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: 16),
        SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ],
    );
  }
} 