import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../services/supabase_service.dart';
import 'node_capture.dart'; // Import NodeCapture screen
import 'map_service.dart'; // Import MapService for image loading
import '../screens/admin/path_recording_screen.dart';
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
  String? _selectedConnectionId;

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
    setState(() {
      _isLoadingConnections = true;
    });
    
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
                'distance_meters': path.estimatedDistance,
                'steps': path.estimatedSteps,
                'custom_instruction': 'Recorded Path: ${path.name}',
                'connection_type': 'recorded', // Mark as recorded path
                'created_at': path.createdAt.toIso8601String(),
              });
            } else {
              print('  ❌ Path not matched - nodes not found in current map');
            }
          }
          
          print('Total matched paths for this map: $matchedPaths');
          print('Total connections to display: ${_connections.length}');
          
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

  void _onMapTapped(TapUpDetails details, double mapWidth, double mapHeight, double scaleX, double scaleY) {
    final tapPosition = details.localPosition;
    
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
            if (connection['distance_meters'] != null)
              Text('Distance: ${connection['distance_meters'].toStringAsFixed(1)}m'),
            if (connection['steps'] != null)
              Text('Steps: ${connection['steps']}'),
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

  void _showConnectionDialog() {
    final startNode = _currentMapData!['map_nodes'].firstWhere((node) => node['id'] == _selectedStartNodeId);
    final endNode = _currentMapData!['map_nodes'].firstWhere((node) => node['id'] == _selectedEndNodeId);
    
    showDialog(
      context: context,
      builder: (context) => ConnectionDialog(
        startNodeName: startNode['name'],
        endNodeName: endNode['name'],
        onRecordPath: () async {
          Navigator.of(context).pop(); // Close dialog first
          await _startPathRecording();
        },
      ),
    );
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

  Future<void> _startPathRecording() async {
    if (_selectedStartNodeId == null || _selectedEndNodeId == null) return;
    
    try {
      // Get available cameras
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No camera available for path recording'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Get node details for the recording
      final startNode = _currentMapData!['map_nodes'].firstWhere((node) => node['id'] == _selectedStartNodeId);
      final endNode = _currentMapData!['map_nodes'].firstWhere((node) => node['id'] == _selectedEndNodeId);
      
      // Navigate to path recording screen
      final result = await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PathRecordingScreen(
            camera: cameras.first,
            startLocationId: _selectedStartNodeId!,
            endLocationId: _selectedEndNodeId!,
            startLocationName: startNode['name'],
            endLocationName: endNode['name'],
          ),
        ),
      );

      // Reset selection and reload connections
      if (mounted) {
        setState(() {
          _selectedStartNodeId = null;
          _selectedEndNodeId = null;
        });
        
        _loadConnections();
        
        if (result != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Path recorded successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting path recording: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
        backgroundColor: _isConnectionMode ? Colors.orange[100] : null,
        actions: [
          IconButton(
            icon: Icon(
              _isConnectionMode ? Icons.link_off : Icons.link,
              color: _isConnectionMode ? Colors.orange[800] : null,
            ),
            tooltip: _isConnectionMode ? 'Exit Connection Mode' : 'Connection Mode',
            onPressed: _toggleConnectionMode,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Connections (Debug)',
            onPressed: () {
              print('🔄 Manual refresh triggered by user');
              _loadConnections();
            },
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
          color: connection['id'] == _selectedConnectionId 
              ? Colors.red.withOpacity(0.1) 
              : null,
          child: ListTile(
            leading: Icon(
              Icons.route, 
              color: connection['id'] == _selectedConnectionId 
                  ? Colors.red 
                  : Colors.green,
            ),
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
                const SizedBox(height: 4),
                Text(
                  connection['connection_type'] == 'recorded' 
                      ? 'Green line: Recorded walking path with AI data'
                      : 'Blue line: Basic structural connection',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
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
            ..color = Colors.red.withOpacity(0.8)
            ..strokeWidth = 4.0
            ..style = PaintingStyle.stroke;
        } else {
          // All connections are recorded paths - use green
          connectionPaint = Paint()
            ..color = Colors.green.withOpacity(0.7)
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
        
        // Draw connection type label
        String typeLabel = 'PATH';
        if (connection['distance_meters'] != null) {
          typeLabel = '$typeLabel (${connection['distance_meters'].toStringAsFixed(1)}m)';
        }
        
        _drawDistanceLabel(
          canvas, 
          Offset(midX, midY - 20), 
          typeLabel,
          isSelected,
        );
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

  void _drawDistanceLabel(Canvas canvas, Offset position, String text, bool isSelected) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: isSelected ? Colors.red : Colors.blue,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(
              offset: Offset(1, 1),
              blurRadius: 2,
              color: Colors.white,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    
    textPainter.layout();
    
    // Draw background
    final backgroundPaint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.fill;
    
    final backgroundRect = Rect.fromCenter(
      center: position,
      width: textPainter.width + 8,
      height: textPainter.height + 4,
    );
    
    canvas.drawRRect(
      RRect.fromRectAndRadius(backgroundRect, Radius.circular(4)),
      backgroundPaint,
    );
    
    textPainter.paint(
      canvas,
      Offset(
        position.dx - textPainter.width / 2,
        position.dy - textPainter.height / 2,
      ),
    );
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
    final screenSize = MediaQuery.of(context).size;
    final isTablet = screenSize.width > 600;
    
    return AlertDialog(
      title: const Text('Record Navigation Path'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('From: $startNodeName'),
          Text('To: $endNodeName'),
          const SizedBox(height: 20),
          const Text(
            'Ready to record your navigation path?',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onRecordPath,
              icon: const Icon(Icons.directions_walk),
              label: const Text('Start Recording Path'),
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
            'Walk the path to automatically record distance, steps, and visual landmarks. A connection line will appear after recording.',
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