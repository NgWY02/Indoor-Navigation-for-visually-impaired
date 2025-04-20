import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../services/supabase_service.dart';
import 'map_service.dart';
import 'video_processor_service.dart';
import 'node_capture_widgets.dart';

class NodeCapture extends StatefulWidget {
  final String mapId;
  final String? nodeId; // Add optional nodeId parameter for editing

  const NodeCapture({
    Key? key, 
    required this.mapId,
    this.nodeId, // Optional - if provided, we're in edit mode
  }) : super(key: key);

  @override
  _NodeCaptureState createState() => _NodeCaptureState();
}

class _NodeCaptureState extends State<NodeCapture> {
  final TextEditingController _nodeNameController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  
  // Services
  final SupabaseService _supabaseService = SupabaseService();
  late MapService _mapService;
  late VideoProcessorService _videoProcessorService;
  
  // State variables
  Offset? _selectedPosition;
  double _imageScale = 1.0;
  Offset _imageOffset = Offset.zero;
  bool _readyForCameraView = false;
  bool _isProcessingVideo = false;
  double _processingProgress = 0.0;
  String _processingMessage = '';
  XFile? _videoFile;
  VideoPlayerController? _videoPlayerController;
  bool _isVideoLoaded = false;
  
  // New state variables for edit mode
  bool _isEditMode = false;
  bool _isLoadingNodeData = false;
  Map<String, dynamic>? _existingNodeData;
  
  // Map loading
  late Future<Map<String, dynamic>> _mapFuture;
  
  @override
  void initState() {
    super.initState();
    
    // Check if we're in edit mode
    _isEditMode = widget.nodeId != null;
    
    // Initialize services
    _mapService = MapService(_supabaseService);
    _videoProcessorService = VideoProcessorService(_supabaseService);
    
    // Initialize data
    _mapFuture = _mapService.loadMapDetails(widget.mapId);
    _videoProcessorService.loadModel();
    
    // If editing, load existing node data
    if (_isEditMode) {
      _loadExistingNodeData();
    }

    // Add listener to update UI when text changes
    _nodeNameController.addListener(() {
      setState(() {});
    });
  }
  
  // Load existing node data when in edit mode
  Future<void> _loadExistingNodeData() async {
    if (!_isEditMode) return;
    
    setState(() {
      _isLoadingNodeData = true;
    });
    
    try {
      // Fetch node details
      final nodeData = await _supabaseService.getMapNodeDetails(widget.nodeId!);
      
      if (mounted) {
        setState(() {
          _existingNodeData = nodeData;
          
          // Set node name in text controller
          _nodeNameController.text = nodeData['name'] ?? '';
          
          // Set position on map
          final double x = (nodeData['x_position'] as num?)?.toDouble() ?? 0.0;
          final double y = (nodeData['y_position'] as num?)?.toDouble() ?? 0.0;
          _selectedPosition = Offset(x, y);
          
          // In edit mode, we're ready to record right away if needed
          _readyForCameraView = true;
          
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
  
  void _selectPosition(Offset position) {
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
          _readyForCameraView = false; // Ready for preview/process
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
  
  // New method for updating node without processing video
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
      
      // Update node name and position only
      await _supabaseService.updateMapNode(
        nodeId,
        nodeName,
        posX,
        posY,
      );
      
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
        // Change title based on mode
        title: Text(_isEditMode ? 'Edit Location Node' : 'Add Location Node'),
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
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    
                    if (snapshot.hasError) {
                      return Center(
                        child: Text('Error: ${snapshot.error}'),
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

                    // Determine which view to show
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
                    } else {
                      // Otherwise, show map selection view
                      currentView = MapSelectionView(
                        mapData: mapData,
                        mapImage: _mapService.mapUIImage!,
                        selectedPosition: _selectedPosition,
                        imageScale: _imageScale,
                        imageOffset: _imageOffset,
                        nodeNameController: _nodeNameController,
                        onPositionSelected: _selectPosition,
                        existingNodes: existingNodes,
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
                                label: 'Select Position',
                                isComplete: _selectedPosition != null,
                                isActive: _selectedPosition == null,
                              ),
                              const SizedBox(width: 4),
                              StepIndicator(
                                step: 2,
                                label: 'Name Node',
                                isComplete: _nodeNameController.text.isNotEmpty,
                                isActive: _selectedPosition != null && _nodeNameController.text.isEmpty,
                              ),
                              const SizedBox(width: 4),
                              StepIndicator(
                                step: 3,
                                label: _isEditMode ? 'Record New Video' : 'Record 360° Video',
                                isComplete: _videoFile != null,
                                isActive: _selectedPosition != null && _nodeNameController.text.isNotEmpty && _videoFile == null,
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
    bool canSaveEdits = _isEditMode && _selectedPosition != null && _nodeNameController.text.isNotEmpty;
    
    return ActionButton(
      isVideoLoaded: _isVideoLoaded,
      onVideoLoaded: _processVideo,
      buttonText: _isEditMode ? 'Update Node' : 'Process Video', // Change button text based on mode
      isNamedPositionSelected: _nodeNameController.text.isNotEmpty && _selectedPosition != null,
      onLaunchCamera: _recordVideoWithNativeCamera,
      onResetVideo: _videoFile != null ? () {
        setState(() {
          _videoFile = null;
          _isVideoLoaded = false;
          _videoPlayerController?.dispose();
          _videoPlayerController = null;
          _readyForCameraView = true;
        });
      } : null,
      resetButtonText: "Record Again",
      isPositionSelected: _selectedPosition != null,
      isNameEntered: _nodeNameController.text.isNotEmpty,
      onProceedToCamera: () {
        setState(() {
          _readyForCameraView = true;
        });
      },
      isReadyForCameraView: _readyForCameraView,
      // New prop: Allow saving in edit mode without recording new video
      canSaveWithoutVideo: canSaveEdits,
      onSaveWithoutVideo: canSaveEdits ? _updateNodeWithoutVideo : null,
    );
  }
}