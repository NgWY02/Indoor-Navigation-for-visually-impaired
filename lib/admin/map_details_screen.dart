import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import 'node_capture.dart'; // Import NodeCapture screen
import 'map_service.dart'; // Import MapService for image loading
import 'dart:ui' as ui;

class MapDetailsScreen extends StatefulWidget {
  final String mapId;

  const MapDetailsScreen({Key? key, required this.mapId}) : super(key: key);

  @override
  _MapDetailsScreenState createState() => _MapDetailsScreenState();
}

class _MapDetailsScreenState extends State<MapDetailsScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  late MapService _mapService; // Remove final keyword to allow reassignment
  late Future<Map<String, dynamic>> _mapDetailsFuture;
  Map<String, dynamic>? _currentMapData; // Store current map data

  @override
  void initState() {
    super.initState();
    _mapService = MapService(SupabaseService()); // Initialize here
    _loadMapDetails();
  }

  void _loadMapDetails() {
    // Clear any cached data
    _mapService = MapService(SupabaseService()); // Re-initialize map service
    
    // Add no-cache options to force fresh data
    print('Fetching fresh map details for map ID: ${widget.mapId}');
    _mapDetailsFuture = _supabaseService.getMapDetails(widget.mapId);
    
    // Also load the map image using MapService
    _mapDetailsFuture.then((data) {
      print('Map details loaded with ${data['map_nodes']?.length ?? 0} nodes');
      if (mounted) {
        setState(() {
          _currentMapData = data; // Store data for easy access
        });
        _mapService.loadMapImage(data['image_url'], context).then((success) {
          if (success && mounted) {
            setState(() {}); // Trigger rebuild when image is loaded
            print('Map image loaded successfully');
          }
        });
      }
    }).catchError((error) {
       print('Error loading map details: $error');
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Error loading map details: $error')),
         );
       }
    });
  }

  Future<void> _navigateToNodeCapture({String? nodeId}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NodeCapture(
          mapId: widget.mapId,
          nodeId: nodeId, // Pass nodeId for editing, null for creating new
        ),
      ),
    );
    
    // Refresh map details if node was added/edited
    if (result == true && mounted) {
      print("Node edit/add successful (result=true). Triggering refresh...");
      // Simply call _loadMapDetails which handles re-initialization and fetching
      _loadMapDetails(); 
    }
  }

  Future<void> _deleteNode(String nodeId, String nodeName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: Text('Are you sure you want to delete the node "$nodeName"? This action cannot be undone.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      try {
        await _supabaseService.deleteMapNode(nodeId);
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Node "$nodeName" deleted successfully.')),
          );
          _loadMapDetails(); // Refresh the list
        }
      } catch (e) {
         if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting node: $e')),
          );
         }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: FutureBuilder<Map<String, dynamic>>(
          future: _mapDetailsFuture,
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              return Text(snapshot.data!['name'] ?? 'Map Details');
            }
            return const Text('Map Details');
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_location_alt),
            tooltip: 'Add New Node',
            onPressed: () {
              _navigateToNodeCapture(); // No nodeId = create new
            },
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _mapDetailsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: Text('Map details not found.'));
          }

          final mapData = snapshot.data!;
          final List<dynamic> nodes = mapData['map_nodes'] ?? [];

          return Column(
            children: [
              // Display Map Image with existing nodes
              if (_mapService.mapUIImage != null)
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.all(8.0),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // Calculate aspect ratio of the map image
                        final double mapAspectRatio = _mapService.mapUIImage!.width / _mapService.mapUIImage!.height;
                        
                        // Calculate dimensions based on available width and aspect ratio
                        final containerWidth = constraints.maxWidth;
                        final containerHeight = constraints.maxHeight;
                        
                        // Determine if we should fit by width or height
                        final double targetWidth, targetHeight;
                        if (containerWidth / containerHeight > mapAspectRatio) {
                          // Available space is wider than the image aspect ratio
                          targetHeight = containerHeight;
                          targetWidth = containerHeight * mapAspectRatio;
                        } else {
                          // Available space is taller than the image aspect ratio
                          targetWidth = containerWidth;
                          targetHeight = containerWidth / mapAspectRatio;
                        }
                        
                        // Calculate scale factors for node positioning
                        final scaleX = targetWidth / _mapService.mapUIImage!.width;
                        final scaleY = targetHeight / _mapService.mapUIImage!.height;
                        
                        return Center(
                          child: SizedBox(
                            width: targetWidth,
                            height: targetHeight,
                            child: InteractiveViewer(
                              minScale: 0.5,
                              maxScale: 4.0,
                              child: Stack(
                                children: [
                                  // Map image as background
                                  SizedBox(
                                    width: targetWidth,
                                    height: targetHeight,
                                    child: RawImage(
                                      image: _mapService.mapUIImage!,
                                      fit: BoxFit.fill,
                                      width: targetWidth,
                                      height: targetHeight,
                                    ),
                                  ),
                                  
                                  // Draw nodes on the map
                                  for (int i = 0; i < nodes.length; i++) 
                                    _buildNodeMarker(nodes[i], i + 1, scaleX, scaleY),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                )
              else
                const Expanded(
                  flex: 2,
                  child: Center(child: CircularProgressIndicator())
                ),

              // List of Nodes
              Expanded(
                flex: 3,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, -2),
                      ),
                    ],
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16.0),
                      topRight: Radius.circular(16.0),
                    ),
                  ),
                  child: nodes.isEmpty
                      ? const Center(child: Text('No nodes added to this map yet.'))
                      : ListView.builder(
                          padding: const EdgeInsets.only(top: 8.0),
                          itemCount: nodes.length,
                          itemBuilder: (context, index) {
                            final node = nodes[index];
                            final nodeName = node['name'] ?? 'Unnamed Node';
                            final nodeId = node['id'];

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.blue,
                                child: Text((index + 1).toString()),
                              ),
                              title: Text(nodeName),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.blue),
                                    tooltip: 'Edit Node',
                                    onPressed: () {
                                      _navigateToNodeCapture(nodeId: nodeId); // Pass nodeId for editing
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    tooltip: 'Delete Node',
                                    onPressed: () => _deleteNode(nodeId, nodeName),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // Helper method to build node markers on the map
  Widget _buildNodeMarker(dynamic node, int index, double scaleX, double scaleY) {
    // Get original coordinates from database
    final double x = (node['x_position'] as num).toDouble();
    final double y = (node['y_position'] as num).toDouble();
    
    // Scale coordinates to current view
    final double displayX = x * scaleX;
    final double displayY = y * scaleY;
    
    return Positioned(
      left: displayX - 10, // Adjust for marker center
      top: displayY - 10,  // Adjust for marker center
      child: Tooltip(
        message: node['name'] ?? 'Node ${index}',
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Circle background
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blue,
              ),
            ),
            // Node number
            Text(
              '$index',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Custom painter to draw map with nodes
class _MapWithNodesPainter extends CustomPainter {
  final ui.Image mapImage;
  final List<dynamic> nodes;

  _MapWithNodesPainter({required this.mapImage, required this.nodes});

  @override
  void paint(Canvas canvas, Size size) {
    // Draw the map image
    canvas.drawImageRect(
      mapImage,
      Rect.fromLTWH(0, 0, mapImage.width.toDouble(), mapImage.height.toDouble()),
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint(),
    );

    // Draw the nodes
    for (int i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final double x = (node['x_position'] as num).toDouble();
      final double y = (node['y_position'] as num).toDouble();
      
      // Scale coordinates if needed based on image-to-canvas ratio
      final double scaleX = size.width / mapImage.width;
      final double scaleY = size.height / mapImage.height;
      final double scaledX = x * scaleX;
      final double scaledY = y * scaleY;

      // Draw a dot for the node
      canvas.drawCircle(
        Offset(scaledX, scaledY),
        8.0, // Radius of the dot
        Paint()..color = Colors.blue,
      );

      // Draw the number
      final textStyle = TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.bold,
      );
      final textSpan = TextSpan(
        text: '${i + 1}',
        style: textStyle,
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          scaledX - textPainter.width / 2,
          scaledY - textPainter.height / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}