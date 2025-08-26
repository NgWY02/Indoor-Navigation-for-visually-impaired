import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/supabase_service.dart';
import '../../services/map_service.dart';
import '../../services/video_processor_service.dart';
import '../../widgets/node_capture_widgets.dart';

class NodeCapture extends StatefulWidget {
  final String mapId;
  final String? nodeId; 

  const NodeCapture({
    Key? key, 
    required this.mapId,
    this.nodeId, 
  }) : super(key: key);

  @override
  _NodeCaptureState createState() => _NodeCaptureState();
}

class _NodeCaptureState extends State<NodeCapture> {
  final TextEditingController _nodeNameController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  
  // Services
  late SupabaseService _supabaseService;
  late MapService _mapService;
  late VideoProcessorService _videoProcessorService;
  
  // State variables
  Offset? _selectedPosition;
  double _imageScale = 1.0;
  Offset _imageOffset = Offset.zero;
  bool _isProcessingVideo = false;
  double _processingProgress = 0.0;
  String _processingMessage = '';
  XFile? _videoFile;
  VideoPlayerController? _videoPlayerController;
  bool _isVideoLoaded = false;
  
  // New state variables for edit mode
  bool _isEditMode = false;
  bool _isLoadingNodeData = false;
  
  // New state variable for direction
  double? _capturedDirection;
  
  // New state variable for current view
  int _currentStep = 1; // 1: Map/Name, 2: Direction, 3: Video
  
  // Data
  late Future<Map<String, dynamic>>? _mapFuture;
  
  @override
  void initState() {
    super.initState();
    
    // Check if we're in edit mode
    _isEditMode = widget.nodeId != null;
    
    // Services
    _supabaseService = SupabaseService();
    _mapService = MapService(_supabaseService);
    _videoProcessorService = VideoProcessorService(_supabaseService);
    
    // Initialize map future immediately to avoid late initialization error
    _mapFuture = _supabaseService.getMapDetails(widget.mapId);
    
    // Load the model and additional data asynchronously
    _initializeModelAndData();
    
    // Add listener to update UI when text changes
    _nodeNameController.addListener(() {
      setState(() {});
    });
    
    // Request location permission for compass
    _requestLocationPermission();
  }
  
  Future<void> _initializeModelAndData() async {
    try {
      print('NodeCapture: Initializing model and loading data...');
      
      // Load the model first
      await _videoProcessorService.loadModel();
      print('NodeCapture: Model loaded successfully');
      
      // If editing, load the node data
      if (_isEditMode) {
        await _loadNodeData();
      }
    } catch (e) {
      print('NodeCapture: Error during initialization: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Initialization error: $e')),
        );
      }
    }
  }
  
  // Request location permission for compass on Android
  Future<void> _requestLocationPermission() async {
    if (Platform.isAndroid) {
      await Permission.location.request();
    }
  }
  
  // Load existing node data when in edit mode
  Future<void> _loadNodeData() async {
    if (!_isEditMode) return;
    
    setState(() {
      _isLoadingNodeData = true;
    });
    
    try {
      // Fetch node details
      final nodeData = await _supabaseService.getMapNodeDetails(widget.nodeId!);
      
      if (mounted) {
        setState(() {
          // Set node name in text controller
          _nodeNameController.text = nodeData['name'] ?? '';
          
          // Set position on map
          final double x = (nodeData['x_position'] as num?)?.toDouble() ?? 0.0;
          final double y = (nodeData['y_position'] as num?)?.toDouble() ?? 0.0;
          _selectedPosition = Offset(x, y);
          
          // Set reference direction if available
          _capturedDirection = (nodeData['reference_direction'] as num?)?.toDouble();
          
          _isLoadingNodeData = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading node data: $e');
      if (mounted) {
        setState(() {
          _isLoadingNodeData = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading node data: $e')),
        );
      }
    }
  }
  
  // Capture current direction from compass
  Future<void> _captureEntranceDirection() async {
    try {
      await _videoProcessorService.captureEntranceDirection();
      setState(() {
        _capturedDirection = _videoProcessorService.entranceDirection;
      });
      
      // Show feedback for 1 second
      if (mounted && _capturedDirection != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Direction captured: ${_capturedDirection!.toStringAsFixed(1)}°'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error capturing direction: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error capturing direction: $e'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    }
  }
  
  void _selectPosition(Offset position) {
    // Store the original coordinates based on the actual image dimensions
    // This ensures positions are stored relative to the image itself, not the display container
    setState(() {
      _selectedPosition = position;
    });
  }

  Future<void> _recordVideoWithNativeCamera() async {
    try {
      final XFile? pickedFile = await _picker.pickVideo(source: ImageSource.camera);
      if (pickedFile != null) {
        setState(() {
          _videoFile = pickedFile;
        });
        await _initializeVideoPlayer(); // Initialize preview
      } else {
        debugPrint('Video picking cancelled.');
      }
    } catch (e) {
      debugPrint('Error picking video: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error launching camera: $e')),
        );
      }
    }
  }

  Future<void> _initializeVideoPlayer() async {
    if (_videoFile == null) return;
    
    if (_videoPlayerController != null) {
      await _videoPlayerController!.dispose();
    }
    
    _videoPlayerController = VideoPlayerController.file(File(_videoFile!.path));
    
    try {
      await _videoPlayerController!.initialize();
      setState(() {
        _isVideoLoaded = true;
      });
    } catch (e) {
      debugPrint("Error Initializing Video Player: $e");
      setState(() {
        _isVideoLoaded = false;
        _videoFile = null;
      });
       if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading video preview: $e')),
        );
      }
    }
  }
  
  Future<void> _processVideo() async {
    // In edit mode, we may not have a new video but still want to update name/position
    bool hasValidVideo = _videoFile != null && _videoPlayerController != null && _isVideoLoaded;
    
    // For edit mode without new video, just update the node without video processing
    if (_isEditMode && !hasValidVideo) {
      _updateNodeWithoutVideo();
      return;
    }
    
    // For new nodes or editing with new video, process normally
    if (!hasValidVideo || _selectedPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please record a video first')),
      );
      return;
    }
    
    setState(() {
      _isProcessingVideo = true;
    });
    
    await _videoProcessorService.processVideo(
      videoFile: _videoFile!,
      videoPlayerController: _videoPlayerController!,
      nodeName: _nodeNameController.text.trim(),
      mapId: widget.mapId,
      positionX: _selectedPosition!.dx,
      positionY: _selectedPosition!.dy,
      nodeId: widget.nodeId, // Pass nodeId if editing
      referenceDirection: _capturedDirection, // Pass captured direction
      onProgressUpdate: (progress, message) {
        if (mounted) {
          setState(() {
            _processingProgress = progress;
            _processingMessage = message;
          });
        }
      },
    );
    
    if (!mounted) return; 

    // Set completion message
    setState(() {
      _processingMessage = _isEditMode ? 'Node updated successfully!' : 'Node created successfully!';
      _processingProgress = 1.0;
    });

    // Go back to map screen after a delay
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) {
      Navigator.of(context).pop(true); // Return true to indicate success
    }
  }
  
  // Method for updating node without processing video
  Future<void> _updateNodeWithoutVideo() async {
    if (!_isEditMode || _selectedPosition == null) return;
    
    setState(() {
      _isProcessingVideo = true;
      _processingProgress = 0.0;
      _processingMessage = 'Updating node details...';
    });
    
    try {
      // Add debug log to see what we're sending
      final String nodeId = widget.nodeId!;
      final String nodeName = _nodeNameController.text.trim();
      final double posX = _selectedPosition!.dx;
      final double posY = _selectedPosition!.dy;
      
      print("DEBUG: Updating node $nodeId:");
      print("  - Name: '$nodeName'");
      print("  - Position: ($posX, $posY)");
      print("  - Direction: ${_capturedDirection != null ? '${_capturedDirection!.toStringAsFixed(1)}°' : 'Not set'}");
      
      // Update node name, position, and direction
      await _supabaseService.updateMapNode(
        nodeId,
        nodeName,
        posX,
        posY,
        referenceDirection: _capturedDirection,
      );
      
      // Verify the update by fetching the node data again
      print("Verifying node update...");
      try {
        final updatedNode = await _supabaseService.getMapNodeDetails(nodeId);
        final String updatedName = updatedNode['name'] ?? '';
        
        print("Verification: Node name in database is now: '$updatedName'");
        if (updatedName != nodeName) {
          print("WARNING: Node name verification failed! Expected: '$nodeName', Got: '$updatedName'");
        } else {
          print("Verification succeeded: Node name matches expected value");
        }
      } catch (verifyError) {
        print("Error verifying node update: $verifyError");
      }
      
      if (!mounted) return;
      
      setState(() {
        _processingProgress = 1.0;
        _processingMessage = 'Node updated successfully!';
      });
      
      // Go back to map screen after a delay
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        Navigator.of(context).pop(true); // Return true to indicate success
      }
    } catch (e) {
      if (!mounted) return;
      
      setState(() {
        _isProcessingVideo = false;
      });
      
      print("ERROR updating node: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating node: $e')),
      );
    }
  }
  
  // Move to next step in the workflow
  void _nextStep() {
    setState(() {
      _currentStep++;
    });
  }
  
  // Go back to previous step
  void _previousStep() {
    if (_currentStep > 1) {
      setState(() {
        _currentStep--;
      });
    }
  }
  
  @override
  void dispose() {
    _nodeNameController.dispose();
    _videoPlayerController?.dispose();
    _videoProcessorService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Change title based on mode and step
        title: Text(_isEditMode ? 'Edit Location Node' : 'Add Location Node'),
        leading: _currentStep > 1 
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _previousStep,
              ) 
            : null,
      ),
      body: _isLoadingNodeData
          ? const Center(child: CircularProgressIndicator()) // Show loading when fetching node data
          : _isProcessingVideo
              ? ProcessingView(
                  processingMessage: _processingMessage,
                  processingProgress: _processingProgress,
                )
              : FutureBuilder<Map<String, dynamic>>(
                  future: _mapFuture,
                  builder: (context, snapshot) {
                    // Handle case where _mapFuture might be null during initialization
                    if (_mapFuture == null) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    
                    if (snapshot.hasError) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error, size: 48, color: Colors.red),
                            const SizedBox(height: 16),
                            Text('Error loading map: ${snapshot.error}'),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _mapFuture = _supabaseService.getMapDetails(widget.mapId);
                                });
                              },
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      );
                    }
                    
                    if (!snapshot.hasData) {
                      return const Center(child: Text('Map not found'));
                    }
                    
                    final mapData = snapshot.data!;
                    
                    // Filter out the node being edited from the displayed nodes
                    final List<Map<String, dynamic>> existingNodes = 
                        List<Map<String, dynamic>>.from(mapData['map_nodes'] ?? [])
                        .where((node) => node['id'] != widget.nodeId)
                        .toList();
                    
                    if (_mapService.mapUIImage == null) {
                      _mapService.loadMapImage(mapData['image_url'], context).then((success) {
                        if (success && mounted) {
                          setState(() {});
                        }
                      });
                      return const Center(child: CircularProgressIndicator());
                    }

                    // Determine which view to show based on current step
                    Widget currentView;
                    
                    if (_isVideoLoaded && _videoPlayerController != null) {
                      // Show video preview if loaded
                      currentView = VideoPreview(
                        videoPlayerController: _videoPlayerController!,
                        onPlayPause: () {
                          setState(() {
                            if (_videoPlayerController!.value.isPlaying) {
                              _videoPlayerController!.pause();
                            } else {
                              _videoPlayerController!.play();
                            }
                          });
                        },
                        onReplay: () {
                          _videoPlayerController!.seekTo(Duration.zero);
                        },
                      );
                    } else if (_currentStep == 1) {
                      // Step 1: Map selection and naming
                      currentView = MapSelectionView(
                        mapData: mapData,
                        mapImage: _mapService.mapUIImage!,
                        selectedPosition: _selectedPosition,
                        imageScale: _imageScale,
                        imageOffset: _imageOffset,
                        nodeNameController: _nodeNameController,
                        onPositionSelected: _selectPosition,
                        existingNodes: existingNodes,
                        showDirectionCapture: false, // Don't show direction capture here
                      );
                    } else if (_currentStep == 2) {
                      // Step 2: Direction capture screen
                      currentView = DirectionCaptureView(
                        locationName: _nodeNameController.text,
                        onCaptureDirection: _captureEntranceDirection,
                        capturedDirection: _capturedDirection,
                      );
                    } else {
                      // Step 3: Video recording
                      currentView = VideoInstructionsView(
                        locationName: _nodeNameController.text,
                        direction: _capturedDirection,
                        onRecordVideo: _recordVideoWithNativeCamera,
                      );
                    }
                    
                    return Column(
                      children: [
                        // Step indicator
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              StepIndicator(
                                step: 1,
                                label: 'Map & Name',
                                isComplete: _selectedPosition != null && _nodeNameController.text.isNotEmpty,
                                isActive: _currentStep == 1,
                              ),
                              const SizedBox(width: 4),
                              StepIndicator(
                                step: 2,
                                label: 'Set Direction',
                                isComplete: _capturedDirection != null,
                                isActive: _currentStep == 2,
                              ),
                              const SizedBox(width: 4),
                              StepIndicator(
                                step: 3,
                                label: 'Record Video',
                                isComplete: _videoFile != null,
                                isActive: _currentStep == 3,
                              ),
                            ],
                          ),
                        ),
                        
                        Expanded(child: currentView),
                        
                        // Bottom action bar
                        SafeArea(
                          child: Container(
                            padding: const EdgeInsets.all(16.0),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black12,
                                  offset: const Offset(0, -1),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: _buildActionButton(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
    );
  }
  
  Widget _buildActionButton() {
    // In edit mode, we can save changes even without recording a new video
    bool canSaveEdits = _isEditMode && 
                       _selectedPosition != null && 
                       _nodeNameController.text.isNotEmpty;
    
    // Show different buttons based on current step
    if (_currentStep == 1) {
      // Step 1: Show Next button if position and name are entered
      bool canProceed = _selectedPosition != null && _nodeNameController.text.isNotEmpty;
      return ElevatedButton(
        onPressed: canProceed ? _nextStep : null,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          minimumSize: const Size(double.infinity, 50),
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
        ),
        child: const Text(
          'Next: Set Direction',
          style: TextStyle(color: Colors.white),
        ),
      );
    } else if (_currentStep == 2) {
      // Step 2: Show Next button if direction is captured
      return ElevatedButton(
        onPressed: _capturedDirection != null ? _nextStep : null,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          minimumSize: const Size(double.infinity, 50),
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
        ),
        child: const Text(
          'Next: Record Video',
          style: TextStyle(color: Colors.white),
        ),
      );
    } else if (_isVideoLoaded) {
      // Video is loaded - Show Process/Update button
      return Row(
        children: [
          // Add Record Again button
          Expanded(
            child: OutlinedButton(
              onPressed: () {
        setState(() {
          _videoFile = null;
          _isVideoLoaded = false;
          _videoPlayerController?.dispose();
          _videoPlayerController = null;
        });
      },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                minimumSize: const Size(double.infinity, 50),
              ),
              child: const Text("Record Again"),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton(
              onPressed: _processVideo,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
              ),
              child: Text(
                _isEditMode ? 'Update Node' : 'Process Video',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      );
    } else if (canSaveEdits) {
      // Edit mode - can save without new video
      return Row(
        children: [
          // Option to record video if desired
          Expanded(
            child: OutlinedButton(
              onPressed: _recordVideoWithNativeCamera,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                minimumSize: const Size(double.infinity, 50),
              ),
              child: const Text('Record New Video'),
            ),
          ),
          const SizedBox(width: 8),
          // Save changes without new video
          Expanded(
            child: ElevatedButton(
              onPressed: _updateNodeWithoutVideo,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text(
                'Save Changes',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      );
    } else {
      // Step 3: Record video button
      return ElevatedButton(
        onPressed: _recordVideoWithNativeCamera,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          minimumSize: const Size(double.infinity, 50),
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
        ),
        child: const Text(
          'Record 360° Video',
          style: TextStyle(color: Colors.white),
        ),
    );
    }
  }
}