import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'dart:async';
import 'package:flutter_compass/flutter_compass.dart';

class StepIndicator extends StatelessWidget {
  final int step;
  final String label;
  final bool isComplete;
  final bool isActive;

  const StepIndicator({
    Key? key,
    required this.step,
    required this.label,
    required this.isComplete,
    required this.isActive,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isComplete
                  ? Colors.green
                  : isActive
                      ? Theme.of(context).primaryColor
                      : Colors.grey,
            ),
            child: Center(
              child: isComplete
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : Text(
                      '$step',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: isComplete ? Colors.green : null,
            ),
          ),
        ],
      ),
    );
  }
}

class MapSelectionView extends StatelessWidget {
  final Map<String, dynamic> mapData;
  final ui.Image mapImage;
  final Offset? selectedPosition;
  final double imageScale;
  final Offset imageOffset;
  final TextEditingController nodeNameController;
  final Function(Offset position) onPositionSelected;
  final List<Map<String, dynamic>> existingNodes;
  final bool showDirectionCapture; // New parameter to control whether to show direction capture

  const MapSelectionView({
    Key? key,
    required this.mapData,
    required this.mapImage,
    required this.selectedPosition,
    required this.imageScale,
    required this.imageOffset,
    required this.nodeNameController,
    required this.onPositionSelected,
    required this.existingNodes,
    this.showDirectionCapture = false, // Default to false
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Calculate aspect ratio of the map image
    final double mapAspectRatio = mapImage.width / mapImage.height;
    
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Map: ${mapData['name']}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '1. Tap on the map to select node position',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            
            // Map with gesture detector
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
              ),
              // Use LayoutBuilder to get available width and maintain aspect ratio
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Calculate height based on available width and aspect ratio
                  final containerWidth = constraints.maxWidth;
                  final containerHeight = containerWidth / mapAspectRatio;
                  
                  // Calculate scale factors for node positioning
                  final scaleX = containerWidth / mapImage.width;
                  final scaleY = containerHeight / mapImage.height;
                  
                  return SizedBox(
                    width: containerWidth,
                    height: containerHeight,
                    child: InteractiveViewer(
                      boundaryMargin: const EdgeInsets.all(20.0),
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: GestureDetector(
                        onTapDown: (TapDownDetails details) {
                          // Adjust tap position based on scale
                          final adjustedPosition = Offset(
                            details.localPosition.dx / scaleX,
                            details.localPosition.dy / scaleY
                          );
                          onPositionSelected(adjustedPosition);
                        },
                        child: Stack(
                          children: [
                            // Map Image
                            SizedBox(
                              width: containerWidth,
                              height: containerHeight,
                              child: RawImage(
                                image: mapImage,
                                fit: BoxFit.fill, // Use fill to ensure the image fills the container
                                width: containerWidth,
                                height: containerHeight,
                              ),
                            ),
                            
                            // Markers for existing nodes
                            ...existingNodes.map((node) {
                              // Get original coordinates from database
                              final double x = (node['x_position'] as num?)?.toDouble() ?? 0.0;
                              final double y = (node['y_position'] as num?)?.toDouble() ?? 0.0;
                              
                              // Scale coordinates to current view
                              final double displayX = x * scaleX;
                              final double displayY = y * scaleY;
                              
                              return Positioned(
                                left: displayX - 10, // Adjust offset for marker
                                top: displayY - 10,  // Adjust offset for marker
                                child: Tooltip(
                                  message: node['name'] ?? 'Existing Node', 
                                  child: const Icon(
                                    Icons.circle,
                                    color: Colors.blue,
                                    size: 20,
                                  ),
                                ),
                              );
                            }).toList(),

                            // Marker for the currently selected new position
                            if (selectedPosition != null)
                              Positioned(
                                left: selectedPosition!.dx * scaleX - 15,
                                top: selectedPosition!.dy * scaleY - 30,
                                child: const Icon(
                                  Icons.location_on,
                                  color: Colors.red,
                                  size: 30,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Node name input
            if (selectedPosition != null) ...[
              const Text(
                '2. Enter name for this location',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nodeNameController,
                decoration: const InputDecoration(
                  labelText: 'Location Name',
                  hintText: 'e.g., Reception, Room 101',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// New widget for compass direction
class CompassDirectionView extends StatefulWidget {
  final VoidCallback? onCaptureDirection;
  final double? capturedDirection;

  const CompassDirectionView({
    Key? key,
    this.onCaptureDirection,
    this.capturedDirection,
  }) : super(key: key);

  @override
  State<CompassDirectionView> createState() => _CompassDirectionViewState();
}

class _CompassDirectionViewState extends State<CompassDirectionView> {
  StreamSubscription<CompassEvent>? _compassSubscription;
  double? _currentHeading;
  bool _showCaptureSuccess = false; // Add state for temporary success indicator
  Timer? _feedbackTimer; // Timer to control the visibility of the success indicator
  
  @override
  void initState() {
    super.initState();
    _initializeCompass();
  }
  
  void _initializeCompass() {
    // Check if compass is available on this device
    if (FlutterCompass.events == null) {
      return;
    }
    
    _compassSubscription = FlutterCompass.events!.listen((event) {
      if (mounted && event.heading != null) {
        setState(() {
          _currentHeading = event.heading;
        });
      }
    });
  }

  // Handle capture with temporary feedback
  void _handleCapture() {
    if (widget.onCaptureDirection != null) {
      widget.onCaptureDirection!();
      
      // Show temporary success indicator for 1 second
      setState(() {
        _showCaptureSuccess = true;
      });
      
      // Clear any existing timer
      _feedbackTimer?.cancel();
      
      // Set timer to hide the success indicator after 1 second
      _feedbackTimer = Timer(const Duration(seconds: 1), () {
        if (mounted) {
          setState(() {
            _showCaptureSuccess = false;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _compassSubscription?.cancel();
    _feedbackTimer?.cancel(); // Cancel timer when disposing
    super.dispose();
  }

  // Helper to get cardinal direction
  String _getCardinalDirection(double? heading) {
    if (heading == null) return 'N/A';
    
    const List<String> cardinalDirections = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    int index = ((heading + 22.5) % 360 / 45).floor();
    return cardinalDirections[index % 8];
  }

  @override
  Widget build(BuildContext context) {
    final bool isCompassAvailable = FlutterCompass.events != null;
    final bool hasCapturedDirection = widget.capturedDirection != null;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          // Compass visualization
          SizedBox(
            height: 120,
            child: isCompassAvailable 
              ? Stack(
                  alignment: Alignment.center,
                  children: [
                    // Compass housing  
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.blue.shade50,
                        border: Border.all(color: Colors.blue.shade300),
                      ),
                      child: Center(
                        child: Text(
                          // Show either captured direction or current heading
                          hasCapturedDirection
                              ? "${widget.capturedDirection!.toStringAsFixed(1)}° (${_getCardinalDirection(widget.capturedDirection)})"
                              : _currentHeading != null 
                                  ? "${_currentHeading!.toStringAsFixed(1)}° (${_getCardinalDirection(_currentHeading)})"
                                  : "Waiting...",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: hasCapturedDirection ? Colors.green : Colors.blue,
                          ),
                        ),
                      ),
                    ),
                    
                    // Temporary capture success indicator
                    if (_showCaptureSuccess)
                      Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.green.withOpacity(0.3),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.check_circle_outline,
                            color: Colors.green,
                            size: 50,
                          ),
                        ),
                      ),
                    
                    // Direction indicator
                    if (_currentHeading != null)
                      Transform.rotate(
                        angle: ((_currentHeading! * math.pi) / 180) * -1,
                        child: Container(
                          width: 120,
                          height: 120,
                          alignment: Alignment.topCenter,
                          child: Icon(
                            Icons.arrow_upward,
                            color: hasCapturedDirection ? Colors.grey : Colors.red,
                            size: 32,
                          ),
                        ),
                      ),
                      
                    // If we have a captured direction, also show it as a fixed marker
                    if (hasCapturedDirection)
                      Transform.rotate(
                        angle: ((widget.capturedDirection! * math.pi) / 180) * -1,
                        child: Container(
                          width: 120,
                          height: 120,
                          alignment: Alignment.topCenter,
                          child: const Icon(
                            Icons.assistant_navigation,
                            color: Colors.green,
                            size: 32,
                          ),
                        ),
                      ),
                  ],
                )
              : const Center(
                  child: Text(
                    'Compass sensor not available on this device',
                    textAlign: TextAlign.center,
                  ),
                ),
          ),
          
          const SizedBox(height: 16),
          
          // Capture/Refresh buttons
          if (isCompassAvailable) 
            hasCapturedDirection
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Success text 
                    const Icon(Icons.check_circle, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Direction Captured',
                      style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 16),
                    // Refresh button to recapture
                    ElevatedButton.icon(
                      onPressed: _handleCapture, // Use the handle method instead
                      icon: const Icon(Icons.refresh),
                      label: const Text('Recapture'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                )
              : ElevatedButton.icon(
                  onPressed: _handleCapture, // Use the handle method instead
                  icon: const Icon(Icons.camera),
                  label: const Text('Capture Current Direction'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
        ],
      ),
    );
  }
}

class VideoPreview extends StatelessWidget {
  final VideoPlayerController videoPlayerController;
  final VoidCallback onPlayPause;
  final VoidCallback onReplay;

  const VideoPreview({
    Key? key,
    required this.videoPlayerController,
    required this.onPlayPause,
    required this.onReplay,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Preview Recorded Video',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: AspectRatio(
            aspectRatio: videoPlayerController.value.aspectRatio,
            child: VideoPlayer(videoPlayerController),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(
                  videoPlayerController.value.isPlaying
                      ? Icons.pause
                      : Icons.play_arrow,
                ),
                onPressed: onPlayPause,
              ),
              IconButton(
                icon: const Icon(Icons.replay),
                onPressed: onReplay,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ProcessingView extends StatelessWidget {
  final String processingMessage;
  final double processingProgress;

  const ProcessingView({
    Key? key,
    required this.processingMessage,
    required this.processingProgress,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              processingMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: processingProgress),
            Text(
              '${(processingProgress * 100).round()}%',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class ActionButton extends StatelessWidget {
  final bool isVideoLoaded;
  final VoidCallback? onVideoLoaded;
  final String buttonText; // NEW: Dynamic button text for different modes
  final bool isNamedPositionSelected;
  final VoidCallback? onResetVideo;
  final String resetButtonText; // NEW: Dynamic text for reset button
  final bool isPositionSelected;
  final bool isNameEntered;
  final bool isDirectionCaptured; // Add this parameter for direction capture
  final VoidCallback? onProceedToCamera;
  final bool isReadyForCameraView;
  final VoidCallback? onLaunchCamera;
  final bool canSaveWithoutVideo; // NEW: For edit mode to save without new video
  final VoidCallback? onSaveWithoutVideo; // NEW: Callback for saving edits without video

  const ActionButton({
    Key? key,
    required this.isVideoLoaded,
    this.onVideoLoaded,
    this.buttonText = 'Process Video', // Default text
    required this.isNamedPositionSelected,
    this.onResetVideo,
    this.resetButtonText = 'Record Again', // Default text
    required this.isPositionSelected,
    required this.isNameEntered,
    required this.isDirectionCaptured, // Add direction parameter
    this.onProceedToCamera,
    required this.isReadyForCameraView,
    this.onLaunchCamera,
    this.canSaveWithoutVideo = false, // Default to false
    this.onSaveWithoutVideo,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 1. Video is loaded - Show Process/Update button
    if (isVideoLoaded) {
      return Row(
        children: [
          // Optional: Add Record Again button
          if (onResetVideo != null)
            Expanded(
              child: OutlinedButton(
                onPressed: onResetVideo,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: Text(resetButtonText), // Use dynamic text
              ),
            ),
          if (onResetVideo != null) const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton(
              onPressed: onVideoLoaded,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
              ),
              child: Text(
                buttonText, // Use dynamic text
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      );
    }

    // NEW: For edit mode - Show 'Save Changes' button without requiring new video
    if (canSaveWithoutVideo && onSaveWithoutVideo != null) {
      return Row(
        children: [
          // Option to record video if desired
          Expanded(
            child: OutlinedButton(
              onPressed: onLaunchCamera,
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
              onPressed: onSaveWithoutVideo,
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
    }

    // 2. Ready for camera view (AFTER clicking Next or in edit mode), but no video loaded yet - Show Record button
    if (isReadyForCameraView && !isVideoLoaded && onLaunchCamera != null) {
      return ElevatedButton(
        onPressed: onLaunchCamera,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          minimumSize: const Size(double.infinity, 50),
          backgroundColor: Colors.red, // Use red color for recording action
          foregroundColor: Colors.white,
        ),
        child: const Text(
          'Record 360° Video',
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    // 3. Position selected, name entered, and direction captured - Show Next button
    if (isPositionSelected && isNameEntered && isDirectionCaptured && onProceedToCamera != null && !isReadyForCameraView) {
      return ElevatedButton(
        onPressed: onProceedToCamera,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          minimumSize: const Size(double.infinity, 50),
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
        ),
        child: const Text(
          'Next',
          style: TextStyle(color: Colors.white),
        ),
      );
    }
    
    // 4. Default/Fallback - Show nothing or disabled button
    return const SizedBox.shrink();
  }
}

// New widget for dedicated direction capture screen
class DirectionCaptureView extends StatelessWidget {
  final String locationName;
  final VoidCallback? onCaptureDirection;
  final double? capturedDirection;

  const DirectionCaptureView({
    Key? key,
    required this.locationName,
    this.onCaptureDirection,
    this.capturedDirection,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Center(
              child: Text(
                'Set Entrance Direction for "$locationName"',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            
            // Instructions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Instructions:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '1. Stand still and face the location',
                    style: TextStyle(fontSize: 14),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '2. Hold your phone in a natural position in front of you',
                    style: TextStyle(fontSize: 14),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '3. Tap the "Capture Current Direction" button',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Compass
            const Text(
              'Direction Capture',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            CompassDirectionView(
              onCaptureDirection: onCaptureDirection,
              capturedDirection: capturedDirection,
            ),
            
            // Status message
            if (capturedDirection != null) ...[
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Direction captured successfully! You can continue to the next step.',
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ] else ...[
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Please capture the entrance direction to continue.',
                  style: TextStyle(
                    color: Colors.orange.shade800,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// New widget for video recording instructions
class VideoInstructionsView extends StatelessWidget {
  final String locationName;
  final double? direction;
  final VoidCallback? onRecordVideo;

  const VideoInstructionsView({
    Key? key,
    required this.locationName,
    this.direction,
    this.onRecordVideo,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Format direction for display
    final String directionText = direction != null 
        ? '${direction!.toStringAsFixed(1)}°' 
        : 'Not set';
    
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Center(
              child: Text(
                'Record Video for "$locationName"',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            
            // Location details
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Location Details:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Name: ', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(locationName),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Text('Entrance Direction: ', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(directionText),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Video recording instructions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Recording Instructions:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '1. Stand at the exact location you marked on the map',
                    style: TextStyle(fontSize: 14),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '2. Hold your phone steadily and press the Record button',
                    style: TextStyle(fontSize: 14),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '3. Slowly rotate 360° to capture the entire surroundings',
                    style: TextStyle(fontSize: 14),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '4. Try to maintain a consistent speed while rotating',
                    style: TextStyle(fontSize: 14),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '5. The video should be 30 seconds long',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Visual guide
            Center(
              child: Column(
                children: const [
                  Icon(
                    Icons.videocam,
                    size: 64,
                    color: Colors.red,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Press the Record button below when ready',
                    style: TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
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