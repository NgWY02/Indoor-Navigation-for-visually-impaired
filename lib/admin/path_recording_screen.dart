import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:camera/camera.dart';
import 'package:flutter_vision/flutter_vision.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'models/path_models.dart';
import 'services/path_recording_service.dart';
import 'checkpoint_review_screen.dart';

class PathRecordingScreen extends StatefulWidget {
  final String mapId;
  final String startNodeId;
  final String endNodeId;
  final String startNodeName;
  final String endNodeName;

  const PathRecordingScreen({
    Key? key,
    required this.mapId,
    required this.startNodeId,
    required this.endNodeId,
    required this.startNodeName,
    required this.endNodeName,
  }) : super(key: key);

  @override
  _PathRecordingScreenState createState() => _PathRecordingScreenState();
}

class _PathRecordingScreenState extends State<PathRecordingScreen> {
  // Core services
  final PathRecordingService _recordingService = PathRecordingService();
  
  // Camera and YOLO
  CameraController? _cameraController;
  late FlutterVision _vision;
  List<Map<String, dynamic>> _yoloResults = [];
  CameraImage? _cameraImage;
  bool _isCameraInitialized = false;
  bool _isYoloLoaded = false;
  
  // UI state
  String _statusMessage = 'Initializing...';
  bool _isInitializing = true;
  GlobalKey _cameraKey = GlobalKey();
  
  // Checkpoint drawing state
  bool _isDrawingCustomLandmark = false;
  Offset? _drawingStart;
  Offset? _drawingEnd;

  @override
  void initState() {
    super.initState();
    _recordingService.addListener(_onRecordingServiceUpdate);
    _initializeEverything();
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }

  Future<void> _initializeEverything() async {
    try {
      await _requestPermissions();
      await _initializeCamera();
      await _initializeYolo();
      
      setState(() {
        _isInitializing = false;
        _statusMessage = 'Ready to start recording path';
      });
    } catch (e) {
      setState(() {
        _isInitializing = false;
        _statusMessage = 'Initialization error: $e';
      });
    }
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.camera,
      Permission.activityRecognition,
      Permission.sensors,
    ].request();
  }

  Future<void> _initializeCamera() async {
    setState(() {
      _statusMessage = 'Initializing camera...';
    });

    try {
      final cameras = await availableCameras();
      final camera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
      
      print('✅ Camera initialized successfully');
    } catch (e) {
      print('❌ Camera initialization error: $e');
      throw Exception('Camera initialization failed: $e');
    }
  }

  Future<void> _initializeYolo() async {
    setState(() {
      _statusMessage = 'Loading YOLO model...';
    });
    
    try {
      _vision = FlutterVision();
      
      await _vision.loadYoloModel(
        labels: 'assets/models/labels.txt',
        modelPath: 'assets/models/yolo11n.tflite', // Fixed model path
        modelVersion: "yolov8",
        numThreads: 4,
        useGpu: true,
      );
      
      setState(() {
        _isYoloLoaded = true;
      });
      
      print('✅ YOLO model loaded successfully');
    } catch (e) {
      print('❌ YOLO initialization error: $e');
      throw Exception('YOLO initialization failed: $e');
    }
  }

  Future<void> _startRecording() async {
    print('🎬 Starting recording - Camera: $_isCameraInitialized, YOLO: $_isYoloLoaded');
    
    if (!_isCameraInitialized || !_isYoloLoaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Camera or YOLO not ready')),
      );
      return;
    }

    try {
      print('🎬 Starting recording session...');
      await _recordingService.startRecordingSession();
      
      print('🎬 Starting camera stream...');
      await _startCameraStream();
      
      print('✅ Recording started successfully');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Recording started! Walk to your first checkpoint.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      print('❌ Failed to start recording: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start recording: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _startCameraStream() async {
    if (_cameraController?.value.isStreamingImages == true) return;
    
    if (_cameraController?.value.isInitialized != true) {
      print('❌ Camera not initialized, cannot start stream');
      return;
    }

    try {
      await _cameraController!.startImageStream((CameraImage image) async {
        if (_recordingService.isRecording) {
          _cameraImage = image;
          await _processYoloFrame(image);
        }
      });
      print('✅ Camera stream started successfully');
    } catch (e) {
      print('❌ Error starting camera stream: $e');
    }
  }

  Future<void> _processYoloFrame(CameraImage image) async {
    try {
      final result = await _vision.yoloOnFrame(
        bytesList: image.planes.map((plane) => plane.bytes).toList(),
        imageHeight: image.height,
        imageWidth: image.width,
        iouThreshold: 0.4,
        confThreshold: 0.5,
        classThreshold: 0.6,
      );

      if (result.isNotEmpty && mounted) {
        setState(() {
          _yoloResults = result;
        });

        // Add high-confidence detections to recording service
        for (var detection in result) {
          final confidence = detection['box'][4];
          if (confidence > 0.7) {
            final boundingBox = _convertYoloBoxToRect(detection['box']);
            
            _recordingService.addDetectedObject(
              label: detection['tag'],
              confidence: confidence,
              boundingBox: boundingBox,
              imageFrame: await _captureCurrentFrame(),
            );
          }
        }
      }
    } catch (e) {
      print('❌ YOLO processing error: $e');
    }
  }

  ui.Rect _convertYoloBoxToRect(List<dynamic> box) {
    // YOLO box format: [x1, y1, x2, y2, confidence]
    // Store the raw coordinates as they come from YOLO
    return ui.Rect.fromLTRB(
      box[0].toDouble(),
      box[1].toDouble(),
      box[2].toDouble(),
      box[3].toDouble(),
    );
  }

  Future<Uint8List?> _captureCurrentFrame() async {
    try {
      if (_cameraController?.value.isInitialized == true) {
        final image = await _cameraController!.takePicture();
        return await image.readAsBytes();
      }
    } catch (e) {
      print('❌ Frame capture error: $e');
    }
    return null;
  }

  Future<void> _markCheckpoint() async {
    if (!_recordingService.isRecording) return;

    try {
      // Capture frozen frame BEFORE stopping the stream
      final frozenFrame = await _captureCurrentFrame();
      if (frozenFrame == null) {
        throw Exception('Failed to capture frame');
      }

      // Get current YOLO detections for the frozen frame (copy current results)
      final frameObjects = _yoloResults.map((detection) => DetectedObject(
        label: detection['tag'],
        confidence: detection['box'][4],
        boundingBox: _convertYoloBoxToRect(detection['box']),
        imageFrame: frozenFrame,
        stepCount: _recordingService.currentSession?.relativeStepCount ?? 0,
        distance: _recordingService.currentSession?.currentDistance ?? 0.0,
        timestamp: DateTime.now(),
      )).toList();

      // Now stop camera stream after capturing
      if (_cameraController?.value.isStreamingImages == true) {
        await _cameraController!.stopImageStream();
      }

      await _recordingService.markCheckpoint(
        frozenFrame: frozenFrame,
        frameObjects: frameObjects,
      );

      print('✅ Checkpoint marked with ${frameObjects.length} detected objects');
      print('📸 Frozen frame size: ${frozenFrame.length} bytes');
      for (var obj in frameObjects) {
        print('🎯 Object: ${obj.label} at ${obj.boundingBox}');
      }

    } catch (e) {
      print('❌ Mark checkpoint error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to mark checkpoint: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _selectYoloObject(DetectedObject object) {
    _showTurnDirectionDialog(
      landmark: _recordingService.createLandmarkFromObject(
        object: object,
        type: LandmarkType.yolo,
      ),
    );
  }

  void _drawCustomLandmark() {
    setState(() {
      _isDrawingCustomLandmark = true;
      _drawingStart = null;
      _drawingEnd = null;
    });
  }

  void _onDrawingPanUpdate(DragUpdateDetails details) {
    if (!_isDrawingCustomLandmark) return;
    
    setState(() {
      if (_drawingStart == null) {
        _drawingStart = details.localPosition;
      }
      _drawingEnd = details.localPosition;
    });
  }

  void _onDrawingPanEnd(DragEndDetails details) {
    if (!_isDrawingCustomLandmark || _drawingStart == null || _drawingEnd == null) return;

    final rect = ui.Rect.fromPoints(_drawingStart!, _drawingEnd!);
    _showCustomLandmarkDialog(rect);
  }

  void _showCustomLandmarkDialog(ui.Rect boundingBox) {
    final TextEditingController labelController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Custom Landmark'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Enter a name for this landmark:'),
            SizedBox(height: 16),
            TextField(
              controller: labelController,
              decoration: InputDecoration(
                hintText: 'e.g., Red Door, Pillar, Painting',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _isDrawingCustomLandmark = false;
                _drawingStart = null;
                _drawingEnd = null;
              });
              Navigator.pop(context);
            },
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (labelController.text.trim().isNotEmpty) {
                final landmark = _recordingService.createCustomLandmark(
                  label: labelController.text.trim(),
                  boundingBox: boundingBox,
                  imageFrame: _recordingService.currentSession?.frozenFrame ?? Uint8List(0),
                );
                
                setState(() {
                  _isDrawingCustomLandmark = false;
                  _drawingStart = null;
                  _drawingEnd = null;
                });
                Navigator.pop(context);
                _showTurnDirectionDialog(landmark: landmark);
              }
            },
            child: Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showTurnDirectionDialog({required Landmark landmark}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Turn Direction'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('What happens at ${landmark.label}?'),
            SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _completeSegment(landmark, TurnDirection.left);
                  },
                  icon: Icon(Icons.turn_left),
                  label: Text('Turn Left'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _completeSegment(landmark, TurnDirection.right);
                  },
                  icon: Icon(Icons.turn_right),
                  label: Text('Turn Right'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                ),
              ],
            ),
            SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _completeSegment(landmark, TurnDirection.straight);
              },
              icon: Icon(Icons.straight),
              label: Text('Go Straight'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            ),
          ],
        ),
      ),
    );
  }

  void _completeSegment(Landmark landmark, TurnDirection action) {
    _recordingService.completeSegment(
      landmark: landmark,
      action: action,
    );

    // Resume camera stream
    Future.delayed(Duration(milliseconds: 500), () {
      _startCameraStream();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Checkpoint saved! Continue to next checkpoint.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _cancelCheckpoint() {
    _recordingService.cancelCheckpoint();
    
    // Resume camera stream with delay
    Future.delayed(Duration(milliseconds: 500), () {
      _startCameraStream();
    });
    
    setState(() {
      _isDrawingCustomLandmark = false;
      _drawingStart = null;
      _drawingEnd = null;
    });
  }

  void _finishRecording() {
    if (_recordingService.currentSession?.segments.isEmpty == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cannot finish: No checkpoints recorded'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    _recordingService.finishRecording();
    
    // Navigate to checkpoint review screen
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => CheckpointReviewScreen(
          mapId: widget.mapId,
          startNodeId: widget.startNodeId,
          endNodeId: widget.endNodeId,
          startNodeName: widget.startNodeName,
          endNodeName: widget.endNodeName,
        ),
      ),
    );
  }

  void _cancelRecording() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cancel Recording'),
        content: Text('Are you sure you want to cancel? All recorded data will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Continue Recording'),
          ),
          ElevatedButton(
            onPressed: () {
              _recordingService.cancelRecording();
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Close recording screen
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Cancel Recording'),
          ),
        ],
      ),
    );
  }

  void _cleanup() {
    _cameraController?.dispose();
    _recordingService.removeListener(_onRecordingServiceUpdate);
  }

  void _onRecordingServiceUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isInitializing
          ? _buildInitializingView()
          : _buildMainView(),
    );
  }

  Widget _buildInitializingView() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 20),
            Text(
              _statusMessage,
              style: TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainView() {
    final session = _recordingService.currentSession;
    
    if (!_recordingService.hasActiveSession) {
      return _buildStartView();
    }

    if (_recordingService.isInCheckpoint) {
      return _buildCheckpointView();
    }

    return _buildRecordingView();
  }

  Widget _buildStartView() {
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          // Camera preview
          if (_isCameraInitialized)
            Positioned.fill(
              child: CameraPreview(_cameraController!),
            ),
          
          // Start recording overlay
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.7),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.route,
                      size: 80,
                      color: Colors.white,
                    ),
                    SizedBox(height: 20),
                    Text(
                      'Record Path',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'From: ${widget.startNodeName}',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                    Text(
                      'To: ${widget.endNodeName}',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                    SizedBox(height: 40),
                    ElevatedButton.icon(
                      onPressed: _startRecording,
                      icon: Icon(Icons.play_arrow),
                      label: Text('Start Recording'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                        textStyle: TextStyle(fontSize: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Back button
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 10,
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(Icons.arrow_back, color: Colors.white, size: 30),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordingView() {
    final session = _recordingService.currentSession;
    if (session == null) return Container();

    return Scaffold(
      body: Stack(
        children: [
          // Full-screen camera with YOLO overlay
          Positioned.fill(
            child: _isCameraInitialized
                ? Stack(
                    children: [
                      CameraPreview(_cameraController!),
                      ..._buildYoloDetectionBoxes(),
                    ],
                  )
                : Container(color: Colors.black),
          ),
          
          // Top overlay with stats
          Positioned(
            top: MediaQuery.of(context).padding.top,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withOpacity(0.8), Colors.transparent],
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Steps: ${session.relativeStepCount}',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Distance: ${_recordingService.formatDistance(session.currentDistance)}',
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, color: Colors.white, size: 8),
                        SizedBox(width: 6),
                        Text('RECORDING', style: TextStyle(color: Colors.white, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Bottom controls
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black.withOpacity(0.8), Colors.transparent],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: _markCheckpoint,
                    icon: Icon(Icons.place),
                    label: Text('Mark Checkpoint'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                  if (session.segments.isNotEmpty)
                    ElevatedButton.icon(
                      onPressed: _finishRecording,
                      icon: Icon(Icons.save),
                      label: Text('Finish Path'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                    ),
                  ElevatedButton.icon(
                    onPressed: _cancelRecording,
                    icon: Icon(Icons.cancel),
                    label: Text('Cancel'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckpointView() {
    final session = _recordingService.currentSession;
    if (session?.frozenFrame == null) return Container();

    return Scaffold(
      appBar: AppBar(
        title: Text('Define Checkpoint'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: Stack(
        children: [
          // Frozen camera frame
          Positioned.fill(
            child: GestureDetector(
              onPanUpdate: _onDrawingPanUpdate,
              onPanEnd: _onDrawingPanEnd,
              child: Container(
                color: Colors.black,
                                  child: Stack(
                    children: [
                      // Display frozen frame
                      if (session?.frozenFrame != null)
                        Positioned.fill(
                          child: Image.memory(
                            session!.frozenFrame!,
                            fit: BoxFit.cover,
                          ),
                        )
                      else
                        Center(
                          child: Text(
                            'No frame captured',
                            style: TextStyle(color: Colors.white),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      
                      // YOLO detection boxes from frozen frame
                      if (session?.frozenFrameObjects != null)
                        ...session!.frozenFrameObjects!.map((obj) => 
                          _buildSelectableObjectBox(obj)
                        ).toList(),
                      
                      // Debug info overlay
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Objects: ${session?.frozenFrameObjects?.length ?? 0}',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ),
                    
                    // Custom drawing overlay
                    if (_isDrawingCustomLandmark && _drawingStart != null && _drawingEnd != null)
                      Positioned(
                        left: _drawingStart!.dx,
                        top: _drawingStart!.dy,
                        child: Container(
                          width: (_drawingEnd!.dx - _drawingStart!.dx).abs(),
                          height: (_drawingEnd!.dy - _drawingStart!.dy).abs(),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.yellow, width: 2),
                            color: Colors.yellow.withOpacity(0.2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          
          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.all(20),
              color: Colors.black.withOpacity(0.8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Tap a detected object or draw a custom landmark',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _drawCustomLandmark,
                        icon: Icon(Icons.crop_free),
                        label: Text('Draw Custom'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.yellow,
                          foregroundColor: Colors.black,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: _cancelCheckpoint,
                        icon: Icon(Icons.arrow_back),
                        label: Text('Back'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey,
                          foregroundColor: Colors.white,
                        ),
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

  Widget _buildSelectableObjectBox(DetectedObject object) {
    // Use the same coordinate conversion as live YOLO detection
    final size = MediaQuery.of(context).size;
    double factorX = size.width / (_cameraImage?.height ?? 1);
    double factorY = size.height / (_cameraImage?.width ?? 1);
    
    return Positioned(
      left: object.boundingBox.left * factorX,
      top: object.boundingBox.top * factorY,
      width: (object.boundingBox.right - object.boundingBox.left) * factorX,
      height: (object.boundingBox.bottom - object.boundingBox.top) * factorY,
      child: GestureDetector(
        onTap: () => _selectYoloObject(object),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.green, width: 3),
            color: Colors.green.withOpacity(0.2),
          ),
          child: Container(
            padding: EdgeInsets.all(4),
            child: Text(
              "${object.label} ${(object.confidence * 100).toStringAsFixed(0)}%",
              style: TextStyle(
                backgroundColor: Colors.green,
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildYoloDetectionBoxes() {
    if (_yoloResults.isEmpty || _cameraImage == null) return [];

    final size = MediaQuery.of(context).size;
    double factorX = size.width / (_cameraImage?.height ?? 1);
    double factorY = size.height / (_cameraImage?.width ?? 1);

    return _yoloResults.map((result) {
      return Positioned(
        left: result["box"][0] * factorX,
        top: result["box"][1] * factorY,
        width: (result["box"][2] - result["box"][0]) * factorX,
        height: (result["box"][3] - result["box"][1]) * factorY,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.pink, width: 2),
          ),
          child: Container(
            padding: const EdgeInsets.all(4),
            child: Text(
              "${result['tag']} ${(result['box'][4] * 100).toStringAsFixed(0)}%",
              style: TextStyle(
                background: Paint()..color = const Color.fromARGB(255, 50, 233, 30),
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      );
    }).toList();
  }
} 