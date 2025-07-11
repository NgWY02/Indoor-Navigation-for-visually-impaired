import 'package:flutter/material.dart';
import 'dart:async';
import '../services/supabase_service.dart';
import '../services/enhanced_navigation_service.dart';
import '../services/pathfinding_service.dart';
import '../services/responsive_helper.dart';

class NavigationManagement extends StatefulWidget {
  const NavigationManagement({Key? key}) : super(key: key);

  @override
  _NavigationManagementState createState() => _NavigationManagementState();
}

class _NavigationManagementState extends State<NavigationManagement> with TickerProviderStateMixin {
  final SupabaseService _supabaseService = SupabaseService();
  final EnhancedNavigationService _navigationService = EnhancedNavigationService();
  
  late TabController _tabController;
  
  List<Map<String, dynamic>> _maps = [];
  String? _selectedMapId;
  List<Map<String, dynamic>> _nodes = [];
  List<Map<String, dynamic>> _connections = [];
  List<Map<String, dynamic>> _walkingSessions = [];
  
  bool _isLoading = true;
  String? _errorMessage;
  bool _isTeachingMode = false;
  NavigationNode? _teachingStartNode;
  NavigationNode? _teachingEndNode;
  String _customInstruction = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _initializeNavigation();
    _loadMaps();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _initializeNavigation() async {
    try {
      await _navigationService.initialize();
    } catch (e) {
      print('Navigation service initialization error: $e');
    }
  }

  Future<void> _loadMaps() async {
    setState(() => _isLoading = true);
    
    try {
      final maps = await _supabaseService.getMaps();
      setState(() {
        _maps = maps;
        _isLoading = false;
        if (_selectedMapId == null && maps.isNotEmpty) {
          _selectedMapId = maps.first['id'];
          _loadMapData();
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading maps: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMapData() async {
    if (_selectedMapId == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      // Load navigation data
      final navigationData = await _supabaseService.getNavigationData(_selectedMapId!);
      final walkingSessions = await _supabaseService.getWalkingSessions(_selectedMapId!);
      
      setState(() {
        _nodes = List<Map<String, dynamic>>.from(navigationData['nodes']);
        _connections = List<Map<String, dynamic>>.from(navigationData['connections']);
        _walkingSessions = walkingSessions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading map data: $e';
        _isLoading = false;
      });
    }
  }

  void _onMapChanged(String? mapId) {
    setState(() {
      _selectedMapId = mapId;
      _nodes.clear();
      _connections.clear();
      _walkingSessions.clear();
    });
    if (mapId != null) {
      _loadMapData();
    }
  }

  Future<void> _startTeachByWalking() async {
    if (_teachingStartNode == null || _teachingEndNode == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select start and end nodes first')),
      );
      return;
    }

    setState(() => _isTeachingMode = true);
    
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Teaching mode activated. Start walking to your destination.'),
          duration: Duration(seconds: 3),
        ),
      );

      await _navigationService.startTrainingMode(
        _selectedMapId!,
        _teachingStartNode!,
        _teachingEndNode!,
      );
    } catch (e) {
      setState(() => _isTeachingMode = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error starting teaching mode: $e')),
      );
    }
  }

  Future<void> _stopTeachByWalking() async {
    if (!_isTeachingMode || _teachingEndNode == null) return;

    try {
      await _navigationService.completeTrainingSession(
        _teachingEndNode!,
        _customInstruction.isNotEmpty ? _customInstruction : 'Walk to ${_teachingEndNode!.name}',
      );

      setState(() {
        _isTeachingMode = false;
        _teachingStartNode = null;
        _teachingEndNode = null;
        _customInstruction = '';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Training session completed successfully!')),
      );

      // Reload connections to show the new one
      _loadMapData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error completing training: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Navigation Management',
          style: TextStyle(fontSize: ResponsiveHelper.getTitleFontSize(context)),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.route), text: 'Connections'),
            Tab(icon: Icon(Icons.school), text: 'Teach Walking'),
            Tab(icon: Icon(Icons.analytics), text: 'Sessions'),
            Tab(icon: Icon(Icons.map_outlined), text: 'Overview'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Map selector
          Container(
            padding: ResponsiveHelper.getResponsivePadding(context),
            child: Row(
              children: [
                Text(
                  'Map:',
                  style: TextStyle(fontSize: ResponsiveHelper.getBodyFontSize(context)),
                ),
                ResponsiveHelper.horizontalSpace(context),
                Expanded(
                  child: DropdownButton<String>(
                    value: _selectedMapId,
                    hint: const Text('Select a map'),
                    isExpanded: true,
                    items: _maps.map((map) {
                      return DropdownMenuItem<String>(
                        value: map['id'],
                        child: Text(map['name'] ?? 'Unnamed Map'),
                      );
                    }).toList(),
                    onChanged: _onMapChanged,
                  ),
                ),
              ],
            ),
          ),
          
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)))
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildConnectionsTab(),
                          _buildTeachWalkingTab(),
                          _buildSessionsTab(),
                          _buildOverviewTab(),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionsTab() {
    return RefreshIndicator(
      onRefresh: _loadMapData,
      child: ListView(
        children: [
          Card(
            margin: ResponsiveHelper.getResponsivePadding(context),
            child: Padding(
              padding: ResponsiveHelper.getResponsivePadding(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Path Connections',
                    style: TextStyle(
                      fontSize: ResponsiveHelper.getHeaderFontSize(context) * 0.8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  ResponsiveHelper.verticalSpace(context),
                  Text(
                    '${_connections.length} connections found',
                    style: TextStyle(fontSize: ResponsiveHelper.getBodyFontSize(context)),
                  ),
                ],
              ),
            ),
          ),
          
          ..._connections.map((connection) => _buildConnectionCard(connection)),
        ],
      ),
    );
  }

  Widget _buildConnectionCard(Map<String, dynamic> connection) {
    final nodeA = _nodes.firstWhere((n) => n['id'] == connection['node_a_id'], orElse: () => {});
    final nodeB = _nodes.firstWhere((n) => n['id'] == connection['node_b_id'], orElse: () => {});
    
    return Card(
      margin: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.getSpacing(context),
        vertical: ResponsiveHelper.getSpacing(context, multiplier: 0.5),
      ),
      child: ListTile(
        leading: const Icon(Icons.route, color: Colors.blue),
        title: Text('${nodeA['name'] ?? 'Unknown'} → ${nodeB['name'] ?? 'Unknown'}'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (connection['distance_meters'] != null)
              Text('Distance: ${connection['distance_meters'].toStringAsFixed(1)}m'),
            if (connection['steps'] != null)
              Text('Steps: ${connection['steps']}'),
            if (connection['custom_instruction'] != null)
              Text('Instruction: ${connection['custom_instruction']}'),
            if (connection['confirmation_objects'] != null)
              Text('Objects: ${(connection['confirmation_objects'] as List).length} detected'),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _editConnection(connection),
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _deleteConnection(connection['id']),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeachWalkingTab() {
    return SingleChildScrollView(
      child: Padding(
        padding: ResponsiveHelper.getResponsivePadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: ResponsiveHelper.getResponsivePadding(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Teach by Walking',
                      style: TextStyle(
                        fontSize: ResponsiveHelper.getHeaderFontSize(context) * 0.8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            ResponsiveHelper.verticalSpace(context),
            
            // Node selection
            Card(
              child: Padding(
                padding: ResponsiveHelper.getResponsivePadding(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select Path',
                      style: TextStyle(
                        fontSize: ResponsiveHelper.getBodyFontSize(context),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    ResponsiveHelper.verticalSpace(context),
                    
                    // Start node selector
                    Row(
                      children: [
                        const Text('From: '),
                        Expanded(
                          child: DropdownButton<NavigationNode>(
                            value: _teachingStartNode,
                            hint: const Text('Select start location'),
                            isExpanded: true,
                            items: _nodes.map((node) {
                              final navNode = NavigationNode.fromJson(node);
                              return DropdownMenuItem<NavigationNode>(
                                value: navNode,
                                child: Text(navNode.name),
                              );
                            }).toList(),
                            onChanged: (node) {
                              setState(() => _teachingStartNode = node);
                            },
                          ),
                        ),
                      ],
                    ),
                    
                    ResponsiveHelper.verticalSpace(context, multiplier: 0.5),
                    
                    // End node selector
                    Row(
                      children: [
                        const Text('To: '),
                        Expanded(
                          child: DropdownButton<NavigationNode>(
                            value: _teachingEndNode,
                            hint: const Text('Select destination'),
                            isExpanded: true,
                            items: _nodes.map((node) {
                              final navNode = NavigationNode.fromJson(node);
                              return DropdownMenuItem<NavigationNode>(
                                value: navNode,
                                child: Text(navNode.name),
                              );
                            }).toList(),
                            onChanged: (node) {
                              setState(() => _teachingEndNode = node);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            ResponsiveHelper.verticalSpace(context),
            
            // Teaching controls
            if (!_isTeachingMode)
              ElevatedButton.icon(
                onPressed: _teachingStartNode != null && _teachingEndNode != null
                    ? _startTeachByWalking
                    : null,
                icon: const Icon(Icons.school),
                label: const Text('Start Teaching Mode'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  minimumSize: Size(double.infinity, ResponsiveHelper.getButtonHeight(context)),
                ),
              )
            else
              Column(
                children: [
                  Container(
                    padding: ResponsiveHelper.getResponsivePadding(context),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.directions_walk, size: 48, color: Colors.orange),
                        ResponsiveHelper.verticalSpace(context, multiplier: 0.5),
                        const Text(
                          'Teaching Mode Active',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Text(
                          'Walk normally from start to destination. The system is recording your path.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  
                  ResponsiveHelper.verticalSpace(context),
                  
                  ElevatedButton.icon(
                    onPressed: _stopTeachByWalking,
                    icon: const Icon(Icons.stop),
                    label: const Text('Complete Teaching'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      minimumSize: Size(double.infinity, ResponsiveHelper.getButtonHeight(context)),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionsTab() {
    return RefreshIndicator(
      onRefresh: _loadMapData,
      child: ListView(
        children: [
          Card(
            margin: ResponsiveHelper.getResponsivePadding(context),
            child: Padding(
              padding: ResponsiveHelper.getResponsivePadding(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Walking Sessions',
                    style: TextStyle(
                      fontSize: ResponsiveHelper.getHeaderFontSize(context) * 0.8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  ResponsiveHelper.verticalSpace(context),
                  Text(
                    '${_walkingSessions.length} training sessions recorded',
                    style: TextStyle(fontSize: ResponsiveHelper.getBodyFontSize(context)),
                  ),
                ],
              ),
            ),
          ),
          
          ..._walkingSessions.map((session) => _buildSessionCard(session)),
        ],
      ),
    );
  }

  Widget _buildSessionCard(Map<String, dynamic> session) {
    final startNode = _nodes.firstWhere((n) => n['id'] == session['start_node_id'], orElse: () => {});
    final endNode = _nodes.firstWhere((n) => n['id'] == session['end_node_id'], orElse: () => {});
    
    return Card(
      margin: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.getSpacing(context),
        vertical: ResponsiveHelper.getSpacing(context, multiplier: 0.5),
      ),
      child: ExpansionTile(
        leading: const Icon(Icons.timeline, color: Colors.green),
        title: Text('${startNode['name'] ?? 'Unknown'} → ${endNode['name'] ?? 'Unknown'}'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Distance: ${session['distance_meters']?.toStringAsFixed(1) ?? 'N/A'}m'),
            Text('Steps: ${session['step_count'] ?? 'N/A'}'),
            Text('Created: ${DateTime.parse(session['created_at']).toLocal().toString().split(' ')[0]}'),
          ],
        ),
        children: [
          Padding(
            padding: ResponsiveHelper.getResponsivePadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (session['instruction'] != null)
                  Text('Instruction: ${session['instruction']}'),
                if (session['average_heading'] != null)
                  Text('Average Heading: ${session['average_heading'].toStringAsFixed(1)}°'),
                if (session['detected_objects'] != null)
                  Text('Objects Detected: ${(session['detected_objects'] as List).length}'),
                ResponsiveHelper.verticalSpace(context, multiplier: 0.5),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: () => _createConnectionFromSession(session),
                      child: const Text('Create Connection'),
                    ),
                    ResponsiveHelper.horizontalSpace(context),
                    TextButton(
                      onPressed: () => _deleteSession(session['id']),
                      child: const Text('Delete', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    final nodeCount = _nodes.length;
    final connectionCount = _connections.length;
    final sessionCount = _walkingSessions.length;
    final coverage = nodeCount > 1 ? (connectionCount / (nodeCount * (nodeCount - 1) / 2) * 100) : 0.0;
    
    return SingleChildScrollView(
      child: Padding(
        padding: ResponsiveHelper.getResponsivePadding(context),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: ResponsiveHelper.getResponsivePadding(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Navigation Overview',
                      style: TextStyle(
                        fontSize: ResponsiveHelper.getHeaderFontSize(context) * 0.8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    ResponsiveHelper.verticalSpace(context),
                    
                    _buildStatRow('Nodes', nodeCount.toString()),
                    _buildStatRow('Connections', connectionCount.toString()),
                    _buildStatRow('Training Sessions', sessionCount.toString()),
                    _buildStatRow('Coverage', '${coverage.toStringAsFixed(1)}%'),
                  ],
                ),
              ),
            ),
            
            ResponsiveHelper.verticalSpace(context),
            
            Card(
              child: Padding(
                padding: ResponsiveHelper.getResponsivePadding(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recommendations',
                      style: TextStyle(
                        fontSize: ResponsiveHelper.getBodyFontSize(context),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    ResponsiveHelper.verticalSpace(context),
                    
                    if (coverage < 50)
                      const ListTile(
                        leading: Icon(Icons.warning, color: Colors.orange),
                        title: Text('Low Navigation Coverage'),
                        subtitle: Text('Consider adding more path connections between nodes'),
                      ),
                    
                    if (sessionCount < connectionCount)
                      const ListTile(
                        leading: Icon(Icons.info, color: Colors.blue),
                        title: Text('Training Opportunities'),
                        subtitle: Text('Some connections lack detailed training data'),
                      ),
                    
                    if (nodeCount > 0 && connectionCount == 0)
                      const ListTile(
                        leading: Icon(Icons.error, color: Colors.red),
                        title: Text('No Connections'),
                        subtitle: Text('Create path connections to enable navigation'),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.getSpacing(context, multiplier: 0.25)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Future<void> _editConnection(Map<String, dynamic> connection) async {
    // TODO: Implement connection editing dialog
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Connection editing coming soon')),
    );
  }

  Future<void> _deleteConnection(String connectionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Connection'),
        content: const Text('Are you sure you want to delete this path connection?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _supabaseService.deleteNodeConnection(connectionId);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connection deleted successfully')),
        );
        _loadMapData();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting connection: $e')),
        );
      }
    }
  }

  Future<void> _createConnectionFromSession(Map<String, dynamic> session) async {
    try {
      await _supabaseService.createNodeConnection(
        mapId: _selectedMapId!,
        nodeAId: session['start_node_id'],
        nodeBId: session['end_node_id'],
        distanceMeters: session['distance_meters']?.toDouble(),
        steps: session['step_count'],
        averageHeading: session['average_heading']?.toDouble(),
        customInstruction: session['instruction'],
        confirmationObjects: session['detected_objects'] != null 
            ? List<Map<String, dynamic>>.from(session['detected_objects'])
            : null,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connection created from session')),
      );
      
      _loadMapData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error creating connection: $e')),
      );
    }
  }

  Future<void> _deleteSession(String sessionId) async {
    // TODO: Implement session deletion
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Session deletion coming soon')),
    );
  }
} 