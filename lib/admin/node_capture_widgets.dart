import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'dart:ui' as ui;

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

    // 3. Position selected and name entered, BEFORE clicking Next - Show Next button
    if (isPositionSelected && isNameEntered && onProceedToCamera != null && !isReadyForCameraView) {
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