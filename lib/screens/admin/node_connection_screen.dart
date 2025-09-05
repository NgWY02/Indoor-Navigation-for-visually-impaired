import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../services/supabase_service.dart';
import '../../services/map_service.dart';
import 'path_recording_screen.dart';
import 'dart:ui' as ui;
import 'dart:math';

class NodeConnectionScreen extends StatefulWidget {
  final String mapId;

  const NodeConnectionScreen({Key? key, required this.mapId}) : super(key: key);

  @override
  _NodeConnectionScreenState createState() => _NodeConnectionScreenState();
}

class _NodeConnectionScreenState extends State<NodeConnectionScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  late MapService _mapService;
  late Future<Map<String, dynamic>> _mapDetailsFuture;
  Map<String, dynamic>? _currentMapData;

  // Connection mode state
  bool _isConnectionMode = true; // Always start in connection mode
  String? _selectedStartNodeId;
  String? _selectedEndNodeId;
  List<Map<String, dynamic>> _connections = [];

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
  }  void _onNodeTapped(String nodeId, String nodeName) {
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
    if (_selectedStartNodeId == null || _selectedEndNodeId == null || _currentMapData == null) return;

    final startNode = _currentMapData!['map_nodes'].firstWhere((node) => node['id'] == _selectedStartNodeId);
    final endNode = _currentMapData!['map_nodes'].firstWhere((node) => node['id'] == _selectedEndNodeId);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return ConnectionDialog(
          startNodeName: startNode['name'],
          endNodeName: endNode['name'],
          onRecordPath: () async {
            Navigator.of(context).pop(); // Close dialog first
            await _startPathRecording();
          },
          onCancel: () {
            // Clear selected nodes when cancel is pressed
            setState(() {
              _selectedStartNodeId = null;
              _selectedEndNodeId = null;
            });
          },
        );
      },
    );
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
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      appBar: AppBar(
        title: FutureBuilder<Map<String, dynamic>>(
          future: _mapDetailsFuture,
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              return Text(
                snapshot.data!['name'] ?? 'Node Connection',
                style: TextStyle(
                  fontSize: 18,
                ),
              );
            }
            return Text(
              'Node Connection',
              style: TextStyle(
                fontSize: 18,
              ),
            );
          },
        ),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          TextButton.icon(
            icon: Icon(
              Icons.link,
              color: Colors.white,
              size: 20,
            ),
            label: Text(
              'Connect',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            onPressed: () {
              setState(() {
                _isConnectionMode = !_isConnectionMode;
                _selectedStartNodeId = null;
                _selectedEndNodeId = null;
              });
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
          ),
        ],
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

            return Column(
              children: [
                if (_isConnectionMode) _buildConnectionModeHeader(),
                Expanded(
                  child: _buildMapView(nodes, context),
                ),
                SizedBox(height: bottomPadding),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildConnectionModeHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      color: Colors.orange.withValues(alpha: 0.1),
      child: Text(
        _selectedStartNodeId == null
          ? 'Connection Mode: Tap a node to select start point'
          : 'Connection Mode: Tap another node to create connection',
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.orange,
          fontSize: 16,
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
                maxScale: 3.0,
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
                      ),
                    ),
                    // Node markers
                    ...nodes.map((node) => _buildNodeMarker(node, nodes.indexOf(node) + 1, scaleX, scaleY)),
                  ],
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

        // All connections are recorded paths - use green
        final connectionPaint = Paint()
          ..color = Colors.green.withOpacity(0.7)
          ..strokeWidth = 3.5
          ..style = PaintingStyle.stroke;

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
  final VoidCallback? onCancel;

  const ConnectionDialog({
    Key? key,
    required this.startNodeName,
    required this.endNodeName,
    required this.onRecordPath,
    this.onCancel,
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
              onPressed: () {
                Navigator.of(context).pop();
                onCancel?.call();
              },
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
