import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import 'node_capture.dart'; // Import NodeCapture screen
import 'map_service.dart'; // Import MapService for image loading
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
  
  // Connection mode state
  bool _isConnectionMode = false;
  String? _selectedStartNodeId;
  String? _selectedEndNodeId;
  List<Map<String, dynamic>> _connections = [];
  bool _isLoadingConnections = false;

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
    setState(() {
      _isLoadingConnections = true;
    });
    
    try {
      final navigationData = await _supabaseService.getNavigationData(widget.mapId);
      if (mounted) {
        setState(() {
          _connections = List<Map<String, dynamic>>.from(navigationData['connections'] ?? []);
          _isLoadingConnections = false;
        });
      }
    } catch (e) {
      print('Error loading connections: $e');
      if (mounted) {
        setState(() {
          _isLoadingConnections = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading connections: $e')),
        );
      }
    }
  }

  Future<void> _navigateToNodeCapture({String? nodeId}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NodeCapture(
          mapId: widget.mapId,
          nodeId: nodeId,
        ),
      ),
    );
    
    if (result == true && mounted) {
      print("Node edit/add successful (result=true). Triggering refresh...");
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

  void _toggleConnectionMode() {
    setState(() {
      _isConnectionMode = !_isConnectionMode;
      _selectedStartNodeId = null;
      _selectedEndNodeId = null;
    });
  }

  void _onNodeTapped(String nodeId, String nodeName) {
    if (!_isConnectionMode) return;

    setState(() {
      if (_selectedStartNodeId == null) {
        _selectedStartNodeId = nodeId;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Start node selected: $nodeName. Now select destination node.'),
            duration: const Duration(seconds: 2),
          ),
        );
      } else if (_selectedEndNodeId == null && nodeId != _selectedStartNodeId) {
        _selectedEndNodeId = nodeId;
        _showConnectionDialog();
      } else if (nodeId == _selectedStartNodeId) {
        _selectedStartNodeId = null;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connection cancelled. Select start node again.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    });
  }

  void _showConnectionDialog() {
    final startNode = _currentMapData!['map_nodes'].firstWhere((node) => node['id'] == _selectedStartNodeId);
    final endNode = _currentMapData!['map_nodes'].firstWhere((node) => node['id'] == _selectedEndNodeId);
    
    showDialog(
      context: context,
      builder: (context) => ConnectionDialog(
        startNodeName: startNode['name'],
        endNodeName: endNode['name'],
        onCreateBasic: () async {
          await _createConnection(null, null, null);
        },
        onRecordPath: () async {
          Navigator.of(context).pop(); // Close dialog first
          await _startPathRecording();
        },
      ),
    );
  }

  Future<void> _createConnection(double? distance, int? steps, String? instruction) async {
    try {
      await _supabaseService.createNodeConnection(
        mapId: widget.mapId,
        nodeAId: _selectedStartNodeId!,
        nodeBId: _selectedEndNodeId!,
        distanceMeters: distance,
        steps: steps,
        customInstruction: instruction,
      );
      
      if (mounted) {
        setState(() {
          _selectedStartNodeId = null;
          _selectedEndNodeId = null;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connection created successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        
        _loadConnections();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating connection: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteConnection(String connectionId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: const Text('Are you sure you want to delete this connection? This action cannot be undone.'),
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
        await _supabaseService.deleteNodeConnection(connectionId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Connection deleted successfully.')),
          );
          _loadConnections();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting connection: $e')),
          );
        }
      }
    }
  }

  Future<void> _startPathRecording() async {
    if (_selectedStartNodeId == null || _selectedEndNodeId == null) return;
    
    // Get node details for the recording
    final startNode = _currentMapData!['map_nodes'].firstWhere((node) => node['id'] == _selectedStartNodeId);
    final endNode = _currentMapData!['map_nodes'].firstWhere((node) => node['id'] == _selectedEndNodeId);
    
    // Show a placeholder message for path recording
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Path recording from ${startNode['name']} to ${endNode['name']} will be implemented later'),
        duration: Duration(seconds: 3),
      ),
    );
    
    // Reset selection for now
    if (mounted) {
      setState(() {
        _selectedStartNodeId = null;
        _selectedEndNodeId = null;
      });
      _loadConnections();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Path recorded successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isTablet = screenSize.width > 600;
    
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
            icon: Icon(_isConnectionMode ? Icons.link_off : Icons.link),
            tooltip: _isConnectionMode ? 'Exit Connection Mode' : 'Connection Mode',
            onPressed: _toggleConnectionMode,
          ),
          IconButton(
            icon: const Icon(Icons.add_location_alt),
            tooltip: 'Add New Node',
            onPressed: () {
              _navigateToNodeCapture();
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

          if (isTablet) {
            // Tablet layout - side by side
            return Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _buildMapView(nodes, context),
                ),
                Expanded(
                  flex: 1,
                  child: _buildDetailsPanel(nodes, context),
                ),
              ],
            );
          } else {
            // Mobile layout - stacked
          return Column(
            children: [
                if (_isConnectionMode)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12.0),
                    color: Colors.orange.withOpacity(0.1),
                    child: Text(
                      _selectedStartNodeId == null 
                        ? 'Connection Mode: Tap a node to select start point'
                        : 'Connection Mode: Tap another node to create connection',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                Expanded(
                  flex: 2,
                  child: _buildMapView(nodes, context),
                ),
                Expanded(
                  flex: 3,
                  child: _buildDetailsPanel(nodes, context),
                ),
              ],
            );
          }
        },
      ),
    );
  }

  Widget _buildMapView(List<dynamic> nodes, BuildContext context) {
    if (_mapService.mapUIImage == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Container(
                    padding: const EdgeInsets.all(8.0),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final double mapAspectRatio = _mapService.mapUIImage!.width / _mapService.mapUIImage!.height;
                        
                        final containerWidth = constraints.maxWidth;
                        final containerHeight = constraints.maxHeight;
                        
                        final double targetWidth, targetHeight;
                        if (containerWidth / containerHeight > mapAspectRatio) {
                          targetHeight = containerHeight;
                          targetWidth = containerHeight * mapAspectRatio;
                        } else {
                          targetWidth = containerWidth;
                          targetHeight = containerWidth / mapAspectRatio;
                        }
                        
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
                    // Map image with connections
                                  SizedBox(
                                    width: targetWidth,
                                    height: targetHeight,
                      child: CustomPaint(
                        painter: MapWithConnectionsPainter(
                          mapImage: _mapService.mapUIImage!,
                          nodes: nodes,
                          connections: _connections,
                        ),
                        child: Container(),
                                    ),
                                  ),
                                  
                    // Interactive node markers
                                  for (int i = 0; i < nodes.length; i++) 
                                    _buildNodeMarker(nodes[i], i + 1, scaleX, scaleY),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }

  Widget _buildDetailsPanel(List<dynamic> nodes, BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
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
            child: const TabBar(
              tabs: [
                Tab(text: 'Nodes', icon: Icon(Icons.location_on)),
                Tab(text: 'Connections', icon: Icon(Icons.link)),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildNodesTab(nodes),
                _buildConnectionsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNodesTab(List<dynamic> nodes) {
    if (nodes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('No nodes added to this map yet.'),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
                          itemCount: nodes.length,
                          itemBuilder: (context, index) {
                            final node = nodes[index];
                            final nodeName = node['name'] ?? 'Unnamed Node';
                            final nodeId = node['id'];

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
          child: ListTile(
                              leading: CircleAvatar(
              backgroundColor: _isConnectionMode && nodeId == _selectedStartNodeId
                  ? Colors.orange
                  : Colors.blue,
                                child: Text((index + 1).toString()),
                              ),
                              title: Text(nodeName),
            trailing: _isConnectionMode 
              ? const Icon(Icons.touch_app, color: Colors.orange)
              : SizedBox(
                  width: 96,
                  child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit, color: Colors.blue),
                                    tooltip: 'Edit Node',
                                    onPressed: () {
                          _navigateToNodeCapture(nodeId: nodeId);
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete, color: Colors.red),
                                    tooltip: 'Delete Node',
                                    onPressed: () => _deleteNode(nodeId, nodeName),
                                  ),
                                ],
                              ),
                ),
            onTap: _isConnectionMode 
              ? () => _onNodeTapped(nodeId, nodeName)
              : null,
          ),
                            );
                          },
    );
  }

  Widget _buildConnectionsTab() {
    if (_isLoadingConnections) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_connections.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.link_off, size: 48, color: Colors.grey),
              SizedBox(height: 16),
              Text('No connections created yet.'),
              SizedBox(height: 8),
              Text(
                'Use Connection Mode to create paths between nodes.',
                style: TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
          );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: _connections.length,
      itemBuilder: (context, index) {
        final connection = _connections[index];
        final nodeA = _currentMapData!['map_nodes'].firstWhere(
          (node) => node['id'] == connection['node_a_id'],
          orElse: () => {'name': 'Unknown'},
        );
        final nodeB = _currentMapData!['map_nodes'].firstWhere(
          (node) => node['id'] == connection['node_b_id'],
          orElse: () => {'name': 'Unknown'},
        );

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
          child: ListTile(
            leading: const Icon(Icons.link, color: Colors.blue),
            title: Text('${nodeA['name']} → ${nodeB['name']}'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (connection['distance_meters'] != null)
                  Text('Distance: ${connection['distance_meters'].toStringAsFixed(1)}m'),
                if (connection['steps'] != null)
                  Text('Steps: ${connection['steps']}'),
                if (connection['custom_instruction'] != null)
                  Text('Note: ${connection['custom_instruction']}'),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              tooltip: 'Delete Connection',
              onPressed: () => _deleteConnection(connection['id']),
            ),
            isThreeLine: true,
          ),
        );
      },
    );
  }

  Widget _buildNodeMarker(dynamic node, int index, double scaleX, double scaleY) {
    final double x = (node['x_position'] as num).toDouble();
    final double y = (node['y_position'] as num).toDouble();
    final String nodeId = node['id'];
    
    final double displayX = x * scaleX;
    final double displayY = y * scaleY;
    
    bool isSelected = _isConnectionMode && nodeId == _selectedStartNodeId;
    
    return Positioned(
      left: displayX - 15,
      top: displayY - 15,
      child: GestureDetector(
        onTap: () => _onNodeTapped(nodeId, node['name'] ?? 'Node $index'),
      child: Tooltip(
          message: node['name'] ?? 'Node $index',
          child: Container(
            width: 30,
            height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
              color: isSelected ? Colors.orange : Colors.blue,
              border: Border.all(
                color: Colors.white,
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
            ),
              ],
            ),
            child: Center(
              child: Text(
              '$index',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
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

  MapWithConnectionsPainter({
    required this.mapImage,
    required this.nodes,
    required this.connections,
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
    final connectionPaint = Paint()
      ..color = Colors.blue.withOpacity(0.7)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

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

        canvas.drawLine(
          Offset(x1, y1),
          Offset(x2, y2),
          connectionPaint,
        );

        // Draw arrow in the middle
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

// Connection dialog widget
class ConnectionDialog extends StatelessWidget {
  final String startNodeName;
  final String endNodeName;
  final VoidCallback onCreateBasic;
  final VoidCallback onRecordPath;

  const ConnectionDialog({
    Key? key,
    required this.startNodeName,
    required this.endNodeName,
    required this.onCreateBasic,
    required this.onRecordPath,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isTablet = screenSize.width > 600;
    
    return AlertDialog(
      title: const Text('Create Connection'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('From: $startNodeName'),
          Text('To: $endNodeName'),
          const SizedBox(height: 20),
          const Text(
            'How would you like to create this connection?',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onRecordPath,
              icon: const Icon(Icons.directions_walk),
              label: const Text('Record Path'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                  vertical: isTablet ? 16 : 12,
                  horizontal: 16,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Walk the path and automatically record distance, steps, and objects',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onCreateBasic,
              icon: const Icon(Icons.link),
              label: const Text('Basic Connection'),
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.symmetric(
                  vertical: isTablet ? 16 : 12,
                  horizontal: 16,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Create a simple connection without recorded data',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}