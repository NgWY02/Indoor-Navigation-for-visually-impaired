import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';
import 'node_capture.dart'; 
import '../../services/map_service.dart'; 
import 'dart:ui' as ui;
import 'dart:math';

class MapDetailsScreen extends StatefulWidget {
  final String mapId;

  const MapDetailsScreen({Key? key, required this.mapId}) : super(key: key);

  @override
  _MapDetailsScreenState createState() => _MapDetailsScreenState();
}

class _MapDetailsScreenState extends State<MapDetailsScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  late MapService _mapService;
  late Future<Map<String, dynamic>> _mapDetailsFuture;
  Map<String, dynamic>? _currentMapData;
  
  List<Map<String, dynamic>> _connections = [];
  String? _selectedConnectionId;
  
  // Node repositioning state
  bool _isRepositioningMode = false;
  String? _repositioningNodeId;
  String? _repositioningNodeName;

  // Map rotation state
  int _rotationDegrees = 0; // 0, 90, 180, 270 degrees

  @override
  void initState() {
    super.initState();
    _mapService = MapService(SupabaseService());
    _loadMapDetails();
    _loadConnections();
  }

  void _loadMapDetails() {
    _mapService = MapService(SupabaseService());
    
    print('Fetching fresh map details for map ID: ${widget.mapId}');
    _mapDetailsFuture = _supabaseService.getMapDetails(widget.mapId);
    
    _mapDetailsFuture.then((data) {
      print('Map details loaded with ${data['map_nodes']?.length ?? 0} nodes');
      if (mounted) {
        setState(() {
          _currentMapData = data;
        });
        _mapService.loadMapImage(data['image_url'], context).then((success) {
          if (success && mounted) {
            setState(() {});
            print('Map image loaded successfully');
            // Load connections after map image is loaded
            _loadConnections();
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

  Future<void> _loadConnections() async {
    print('=== _loadConnections() called ===');
    try {
      // Ensure we have current map data
      if (_currentMapData == null) {
        print('Current map data is null, loading fresh map data...');
        final mapData = await _supabaseService.getMapDetails(widget.mapId);
        _currentMapData = mapData;
        print('Fresh map data loaded with ${_currentMapData?['map_nodes']?.length ?? 0} nodes');
      } else {
        print('Using existing map data with ${_currentMapData?['map_nodes']?.length ?? 0} nodes');
      }
      
      // Load only recorded navigation paths
      print('Loading all navigation paths...');
      final allPaths = await _supabaseService.loadAllPaths();
      print('Loaded ${allPaths.length} navigation paths from database');
      
      for (int i = 0; i < allPaths.length; i++) {
        final path = allPaths[i];
        print('Path $i: ${path.name} (${path.startLocationId} -> ${path.endLocationId})');
      }
      
      if (mounted) {
        setState(() {
          _connections = [];
          
          // Add navigation_paths (recorded paths) that have start/end nodes in current map
          final currentMapNodes = _currentMapData?['map_nodes'] ?? [];
          print('Current map has ${currentMapNodes.length} nodes');
          
          for (final node in currentMapNodes) {
            print('  Node: ${node['id']} (${node['name']})');
          }
          
          int matchedPaths = 0;
          for (final path in allPaths) {
            print('Checking path: ${path.name}');
            print('  Looking for start node with ID: ${path.startLocationId}');
            print('  Looking for end node with ID: ${path.endLocationId}');
            
            // Check if this path connects nodes from current map by node ID
            final startNode = currentMapNodes.firstWhere(
              (node) {
                bool matches = node['id'].toString() == path.startLocationId.toString();
                print('    Node ${node['id']} vs start ${path.startLocationId}: $matches');
                return matches;
              },
              orElse: () => null,
            );
            final endNode = currentMapNodes.firstWhere(
              (node) {
                bool matches = node['id'].toString() == path.endLocationId.toString();
                print('    Node ${node['id']} vs end ${path.endLocationId}: $matches');
                return matches;
              },
              orElse: () => null,
            );
            
            print('  Start node found: ${startNode != null} ${startNode != null ? '(${startNode['name']})' : ''}');
            print('  End node found: ${endNode != null} ${endNode != null ? '(${endNode['name']})' : ''}');
            
            if (startNode != null && endNode != null) {
              print('  ✅ Adding connection for path: ${path.name}');
              matchedPaths++;
              _connections.add({
                'id': path.id,
                'node_a_id': startNode['id'],
                'node_b_id': endNode['id'],
                'custom_instruction': 'Recorded Path: ${path.name}',
                'connection_type': 'recorded', 
                'created_at': path.createdAt.toIso8601String(),
              });
            } else {
              print('Path not matched - nodes not found in current map');
            }
          }
          
          print('Total matched paths for this map: $matchedPaths');
          print('Total connections to display: ${_connections.length}');
        });
      }
    } catch (e) {
      print('Error loading connections: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading connections: $e')),
        );
      }
    }
  }

  Future<void> _showEditNameDialog(String nodeId, String currentName) async {
    final TextEditingController nameController = TextEditingController(text: currentName);

    final String? newName = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Edit Node Name'),
          content: TextField(
            controller: nameController,
            decoration: InputDecoration(
              labelText: 'Node Name',
              hintText: 'Enter new node name',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isNotEmpty) {
                  Navigator.of(context).pop(name);
                }
              },
              child: Text('Save'),
            ),
          ],
        );
      },
    );

    if (newName != null && newName != currentName) {
      try {
        // Get current node data to preserve position
        final currentNode = _currentMapData?['map_nodes']?.firstWhere(
          (node) => node['id'] == nodeId,
          orElse: () => null,
        );

        if (currentNode == null) {
          throw Exception('Node not found');
        }

        final x = currentNode['x_position'];
        final y = currentNode['y_position'];

        await _supabaseService.updateMapNode(nodeId, newName, x, y);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Node name updated successfully')),
          );
          _loadMapDetails();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating node name: $e')),
          );
        }
      }
    }
  }

  Future<void> _navigateToPathRecording({String? nodeId}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NodeCapture(
          mapId: widget.mapId,
          nodeId: nodeId,
          startInVideoMode: true,
        ),
      ),
    );

    if (result == true && mounted) {
      print("Video recording successful (result=true). Triggering refresh...");
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
          _loadMapDetails();
          _loadConnections(); // Refresh connections as well
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

  void _startNodeRepositioning(String nodeId, String nodeName) {
    setState(() {
      _isRepositioningMode = true;
      _repositioningNodeId = nodeId;
      _repositioningNodeName = nodeName;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Tap on the map to set new position for "$nodeName"'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _cancelNodeRepositioning() {
    setState(() {
      _isRepositioningMode = false;
      _repositioningNodeId = null;
      _repositioningNodeName = null;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Node repositioning cancelled')),
    );
  }

  void _rotateMap() {
    setState(() {
      _rotationDegrees = (_rotationDegrees + 90) % 360;
    });
  }

  Future<void> _updateNodePosition(String nodeId, double newX, double newY) async {
    try {
      // Get the current node data to preserve the name
      final currentNode = _currentMapData?['map_nodes']?.firstWhere(
        (node) => node['id'] == nodeId,
        orElse: () => null,
      );

      if (currentNode == null) {
        throw Exception('Node not found');
      }

      final nodeName = currentNode['name'] ?? 'Unnamed Node';
      await _supabaseService.updateMapNode(nodeId, nodeName, newX, newY);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Node position updated successfully')),
        );
        _loadMapDetails();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating node position: $e')),
        );
      }
    }
  }

  void _onNodeTapped(String nodeId, String nodeName) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Node Options'),
          content: Text('What would you like to do with "$nodeName"?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _startNodeRepositioning(nodeId, nodeName);
              },
              child: Text('Move Position'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showEditNameDialog(nodeId, nodeName);
              },
              child: Text('Edit Name'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _navigateToPathRecording(nodeId: nodeId);
              },
              child: Text('Record Video'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteNode(nodeId, nodeName);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text('Delete'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _onMapTapped(TapUpDetails details, double mapWidth, double mapHeight, double scaleX, double scaleY) {
    final tapPosition = details.localPosition;
    
    // Handle repositioning mode
    if (_isRepositioningMode && _repositioningNodeId != null) {
      // Convert tap position to map coordinates
      final mapX = tapPosition.dx / scaleX;
      final mapY = tapPosition.dy / scaleY;
      
      // Update node position
      _updateNodePosition(_repositioningNodeId!, mapX, mapY);
      
      // Exit repositioning mode
      setState(() {
        _isRepositioningMode = false;
        _repositioningNodeId = null;
        _repositioningNodeName = null;
      });
      
      return;
    }
    
    // Check if tap is near any connection line
    for (final connection in _connections) {
      final nodeA = _currentMapData!['map_nodes'].firstWhere(
        (node) => node['id'] == connection['node_a_id'],
        orElse: () => null,
      );
      final nodeB = _currentMapData!['map_nodes'].firstWhere(
        (node) => node['id'] == connection['node_b_id'],
        orElse: () => null,
      );

      if (nodeA != null && nodeB != null) {
        final double x1 = (nodeA['x_position'] as num).toDouble() * scaleX;
        final double y1 = (nodeA['y_position'] as num).toDouble() * scaleY;
        final double x2 = (nodeB['x_position'] as num).toDouble() * scaleX;
        final double y2 = (nodeB['y_position'] as num).toDouble() * scaleY;

        // Calculate distance from tap to line
        final distance = _distanceToLineSegment(
          tapPosition, 
          Offset(x1, y1), 
          Offset(x2, y2),
        );

        if (distance < 20) { // 20 pixel tolerance
          _showConnectionOptions(connection);
          return;
        }
      }
    }
    
    // Clear selection if tapped on empty area
    setState(() {
      _selectedConnectionId = null;
    });
  }

  double _distanceToLineSegment(Offset point, Offset lineStart, Offset lineEnd) {
    final double A = point.dx - lineStart.dx;
    final double B = point.dy - lineStart.dy;
    final double C = lineEnd.dx - lineStart.dx;
    final double D = lineEnd.dy - lineStart.dy;

    final double dot = A * C + B * D;
    final double lenSq = C * C + D * D;
    double param = -1;
    if (lenSq != 0) {
      param = dot / lenSq;
    }

    double xx, yy;

    if (param < 0) {
      xx = lineStart.dx;
      yy = lineStart.dy;
    } else if (param > 1) {
      xx = lineEnd.dx;
      yy = lineEnd.dy;
    } else {
      xx = lineStart.dx + param * C;
      yy = lineStart.dy + param * D;
    }

    final double dx = point.dx - xx;
    final double dy = point.dy - yy;
    return sqrt(dx * dx + dy * dy);
  }

  void _showConnectionOptions(Map<String, dynamic> connection) {
    final nodeA = _currentMapData!['map_nodes'].firstWhere(
      (node) => node['id'] == connection['node_a_id'],
      orElse: () => {'name': 'Unknown'},
    );
    final nodeB = _currentMapData!['map_nodes'].firstWhere(
      (node) => node['id'] == connection['node_b_id'],
      orElse: () => {'name': 'Unknown'},
    );

    setState(() {
      _selectedConnectionId = connection['id'];
    });

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connection Options'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('From: ${nodeA['name']}'),
            Text('To: ${nodeB['name']}'),
            if (connection['custom_instruction'] != null)
              Text('Note: ${connection['custom_instruction']}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() {
                _selectedConnectionId = null;
              });
            },
            child: const Text('Close'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () {
              Navigator.of(context).pop();
              _deleteConnection(connection['id']);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    ).then((_) {
      setState(() {
        _selectedConnectionId = null;
      });
    });
  }

  Future<void> _deleteConnection(String connectionId) async {
    // Check if the connection exists
    try {
      _connections.firstWhere((conn) => conn['id'] == connectionId);
    } catch (e) {
      return; // Connection not found
    }
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: const Text('Are you sure you want to delete this recorded path? This action cannot be undone.'),
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
        // Delete the recorded path from navigation_paths table
        await _supabaseService.deleteNavigationPath(connectionId);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Recorded path deleted successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          
          setState(() {
            _selectedConnectionId = null;
          });
          
          _loadConnections();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting recorded path: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    
    return Scaffold(
      appBar: AppBar(
        title: FutureBuilder<Map<String, dynamic>>(
          future: _mapDetailsFuture,
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              return Text(
                snapshot.data!['name'] ?? 'Map Details',
                style: TextStyle(
                  fontSize: 18,
                ),
              );
            }
            return Text(
              'Map Details',
              style: TextStyle(
                fontSize: 18,
              ),
            );
          },
        ),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: _buildResponsiveActions(),
      ),
      body: SafeArea(
        child: FutureBuilder<Map<String, dynamic>>(
          future: _mapDetailsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Error: ${snapshot.error}',
                    style: TextStyle(fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            if (!snapshot.hasData) {
              return Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Map details not found.',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              );
            }

                final mapData = snapshot.data!;
                final List<dynamic> nodes = mapData['map_nodes'] ?? [];

                // Mobile layout only
                return Stack(
                  children: [
                    Column(
                      children: [
                        _buildInstructionHeader(),
                        Expanded(
                          child: _buildMapView(nodes, context),
                        ),
                        SizedBox(height: bottomPadding),
                      ],
                    ),
                    if (_isRepositioningMode)
                      Positioned(
                        top: 16,
                        left: 16,
                        right: 16,
                        child: Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.location_on, color: Colors.white),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Tap on map to reposition "${_repositioningNodeName ?? "node"}"',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ),
                              TextButton(
                                onPressed: _cancelNodeRepositioning,
                                child: Text(
                                  'Cancel',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
  }

  List<Widget> _buildResponsiveActions() {
    return [
      IconButton(
        icon: Icon(Icons.rotate_right, color: Colors.white),
        onPressed: _rotateMap,
        tooltip: 'Rotate Map',
      ),
    ];
  }

  Widget _buildInstructionHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      color: Colors.teal.withValues(alpha: 0.1),
      child: const Text(
        'Tap node to edit • Tap edge to delete',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.teal,
          fontSize: 14,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildMapView(List<dynamic> nodes, BuildContext context) {
    if (_mapService.mapUIImage == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Container(
      padding: EdgeInsets.all(8.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Adjust aspect ratio based on rotation
          final bool isRotated = _rotationDegrees == 90 || _rotationDegrees == 270;
          final double originalWidth = _mapService.mapUIImage!.width.toDouble();
          final double originalHeight = _mapService.mapUIImage!.height.toDouble();
          
          // For rotation, we need to consider the effective dimensions
          final double effectiveWidth = isRotated ? originalHeight : originalWidth;
          final double effectiveHeight = isRotated ? originalWidth : originalHeight;
          final double mapAspectRatio = effectiveWidth / effectiveHeight;
          
          final containerWidth = constraints.maxWidth;
          final containerHeight = constraints.maxHeight;
          
          final double targetWidth, targetHeight;
          
          // Calculate the natural size (1:1 pixel ratio) for the rotated image
          final double naturalWidth = effectiveWidth;
          final double naturalHeight = effectiveHeight;
          
          // If natural size fits within container, use natural size
          if (naturalWidth <= containerWidth && naturalHeight <= containerHeight) {
            targetWidth = naturalWidth;
            targetHeight = naturalHeight;
          } 
          // If natural size is too big, scale down to fit
          else {
            if (containerWidth / containerHeight > mapAspectRatio) {
              targetHeight = containerHeight;
              targetWidth = containerHeight * mapAspectRatio;
            } else {
              targetWidth = containerWidth;
              targetHeight = containerWidth / mapAspectRatio;
            }
          }
          
          final scaleX = targetWidth / _mapService.mapUIImage!.width;
          final scaleY = targetHeight / _mapService.mapUIImage!.height;
          
          return Center(
            child: SizedBox(
              width: targetWidth,
              height: targetHeight,
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 3.0,
                child: RotatedBox(
                  quarterTurns: _rotationDegrees ~/ 90,
                  child: Stack(
                    children: [
                      // Map image with connections
                      SizedBox(
                        width: originalWidth,
                        height: originalHeight,
                        child: GestureDetector(
                          onTapUp: (details) => _onMapTapped(details, targetWidth, targetHeight, scaleX, scaleY),
                          child: CustomPaint(
                            painter: MapWithConnectionsPainter(
                              mapImage: _mapService.mapUIImage!,
                              nodes: nodes,
                              connections: _connections,
                              selectedConnectionId: _selectedConnectionId,
                            ),
                            child: Container(),
                          ),
                        ),
                      ),
                      
                      // Interactive node markers
                      for (int i = 0; i < nodes.length; i++) 
                        _buildNodeMarker(nodes[i], i + 1, scaleX, scaleY),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNodeMarker(dynamic node, int index, double scaleX, double scaleY) {
    final double x = (node['x_position'] as num).toDouble();
    final double y = (node['y_position'] as num).toDouble();
    final String nodeId = node['id'];
    
    final double displayX = x * scaleX;
    final double displayY = y * scaleY;
    
    return Positioned(
      left: displayX - 8,
      top: displayY - 8,
      child: GestureDetector(
        onTap: () => _onNodeTapped(nodeId, node['name'] ?? 'Node $index'),
        child: Tooltip(
          message: node['name'] ?? 'Node $index',
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.blue,
              border: Border.all(
                color: Colors.white,
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Custom painter for map with connections
class MapWithConnectionsPainter extends CustomPainter {
  final ui.Image mapImage;
  final List<dynamic> nodes;
  final List<Map<String, dynamic>> connections;
  final String? selectedConnectionId;

  MapWithConnectionsPainter({
    required this.mapImage,
    required this.nodes,
    required this.connections,
    this.selectedConnectionId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw the map image
    canvas.drawImageRect(
      mapImage,
      Rect.fromLTWH(0, 0, mapImage.width.toDouble(), mapImage.height.toDouble()),
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint(),
    );

    // Scale factors
    final double scaleX = size.width / mapImage.width;
    final double scaleY = size.height / mapImage.height;

    // Draw connections
    for (final connection in connections) {
      final nodeA = nodes.firstWhere(
        (node) => node['id'] == connection['node_a_id'],
        orElse: () => null,
      );
      final nodeB = nodes.firstWhere(
        (node) => node['id'] == connection['node_b_id'],
        orElse: () => null,
      );

      if (nodeA != null && nodeB != null) {
        final double x1 = (nodeA['x_position'] as num).toDouble() * scaleX;
        final double y1 = (nodeA['y_position'] as num).toDouble() * scaleY;
        final double x2 = (nodeB['x_position'] as num).toDouble() * scaleX;
        final double y2 = (nodeB['y_position'] as num).toDouble() * scaleY;

        // Different styling based on selection state
        final bool isSelected = connection['id'] == selectedConnectionId;
        
        late final Paint connectionPaint;
        
        if (isSelected) {
          connectionPaint = Paint()
            ..color = Colors.red.withValues(alpha:0.8)
            ..strokeWidth = 4.0
            ..style = PaintingStyle.stroke;
        } else {
          // All connections are recorded paths - use green
          connectionPaint = Paint()
            ..color = Colors.green.withValues(alpha: 0.7)
            ..strokeWidth = 3.5
            ..style = PaintingStyle.stroke;
        }

        // Draw connection line
        canvas.drawLine(
          Offset(x1, y1),
          Offset(x2, y2),
          connectionPaint,
        );

        // Draw arrow in the middle pointing from A to B
        final double midX = (x1 + x2) / 2;
        final double midY = (y1 + y2) / 2;
        final double angle = atan2(y2 - y1, x2 - x1);
        
        _drawArrow(canvas, Offset(midX, midY), angle, connectionPaint);
      }
    }
  }

  void _drawArrow(Canvas canvas, Offset center, double angle, Paint paint) {
    const double arrowSize = 8.0;
    final Path arrowPath = Path();
    
    arrowPath.moveTo(
      center.dx + arrowSize * cos(angle),
      center.dy + arrowSize * sin(angle),
      );
    arrowPath.lineTo(
      center.dx + arrowSize * cos(angle + 2.5),
      center.dy + arrowSize * sin(angle + 2.5),
    );
    arrowPath.lineTo(
      center.dx + arrowSize * cos(angle - 2.5),
      center.dy + arrowSize * sin(angle - 2.5),
    );
    arrowPath.close();
    
    canvas.drawPath(arrowPath, paint..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Connection dialog widget - simplified to only record paths
class ConnectionDialog extends StatelessWidget {
  final String startNodeName;
  final String endNodeName;
  final VoidCallback onRecordPath;

  const ConnectionDialog({
    Key? key,
    required this.startNodeName,
    required this.endNodeName,
    required this.onRecordPath,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenSize = MediaQuery.of(context).size;
        final isMobile = screenSize.width < 600;
        
        return AlertDialog(
          title: Text(
            'Record Navigation Path',
            style: TextStyle(fontSize: isMobile ? 18 : 20),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'From: $startNodeName',
                style: TextStyle(fontSize: isMobile ? 14 : 16),
              ),
              Text(
                'To: $endNodeName',
                style: TextStyle(fontSize: isMobile ? 14 : 16),
              ),
              SizedBox(height: isMobile ? 16 : 20),
              Text(
                'Ready to record your navigation path?',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: isMobile ? 14 : 16,
                ),
              ),
              SizedBox(height: isMobile ? 12 : 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onRecordPath,
                  icon: Icon(
                    Icons.directions_walk,
                    size: isMobile ? 18 : 20,
                  ),
                  label: Text(
                    'Start Recording Path',
                    style: TextStyle(fontSize: isMobile ? 14 : 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                      vertical: isMobile ? 12 : 16,
                      horizontal: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(isMobile ? 8 : 12),
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(fontSize: isMobile ? 14 : 16),
              ),
            ),
          ],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(isMobile ? 12 : 16),
          ),
          contentPadding: EdgeInsets.all(isMobile ? 16 : 24),
        );
      },
    );
  }
}