import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/supabase_service.dart';
import 'node_capture.dart';
import 'map_details_screen.dart'; 

class MapManagement extends StatefulWidget {
  const MapManagement({Key? key}) : super(key: key);

  @override
  _MapManagementState createState() => _MapManagementState();
}

class _MapManagementState extends State<MapManagement> {
  final ImagePicker _picker = ImagePicker();
  final SupabaseService _supabaseService = SupabaseService();
  final TextEditingController _mapNameController = TextEditingController();
  
  File? _mapImage;
  String? _errorMessage;
  bool _isLoading = false;
  List<Map<String, dynamic>> _maps = [];
  Map<String, dynamic>? _selectedMap;
  bool _isAddingMap = false; 
  
  @override
  void initState() {
    super.initState();
    _loadMaps();
  }
  
  @override
  void dispose() {
    _mapNameController.dispose();
    super.dispose();
  }
  
  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
    );
    if (image != null) {
      setState(() {
        _mapImage = File(image.path);
      });
    }
  }
  
  Future<void> _saveMap() async {
    if (_mapImage == null) {
      setState(() {
        _errorMessage = 'Please select a map image first';
      });
      return;
    }
    
    if (_mapNameController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a map name';
      });
      return;
    }
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      final String mapId = await _supabaseService.uploadMap(
        _mapNameController.text.trim(),
        _mapImage!,
      );
      
      if (mapId.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Map saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        
        setState(() {
          _mapImage = null;
          _mapNameController.clear();
          _isAddingMap = false;
        });
        
        _loadMaps();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error saving map: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _loadMaps() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      final maps = await _supabaseService.getMaps();
      setState(() {
        _maps = maps;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading maps: ${e.toString()}';
        _isLoading = false;
      });
    }
  }
  
  void _selectMap(Map<String, dynamic> map) {
    setState(() {
      _selectedMap = map;
    });
  }
  
  void _addNodeToMap() {
    if (_selectedMap == null) return;
    
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => NodeCapture(mapId: _selectedMap!['id']),
      ),
    ).then((result) {
      if (result == true) {
        _loadMaps();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Node added successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    });
  }

  void _viewMapDetails() {
    if (_selectedMap == null) return;
    
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => MapDetailsScreen(mapId: _selectedMap!['id']),
      ),
    ).then((_) {
      _loadMaps();
    });
  }

  void _cancelAddMap() {
    setState(() {
      _mapImage = null;
      _mapNameController.clear();
      _errorMessage = null;
      _isAddingMap = false;
    });
  }

  Future<void> _confirmDeleteMap(Map<String, dynamic> mapToDelete) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: Text('Are you sure you want to delete the map "${mapToDelete['name'] ?? 'Unnamed Map'}" and all its associated nodes and data? This action cannot be undone.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            TextButton(
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      _deleteMap(mapToDelete['id']);
    }
  }

  Future<void> _deleteMap(String mapId) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _supabaseService.deleteMap(mapId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Map deleted successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {
        _selectedMap = null;
      });
      _loadMaps();
    } catch (e) {
      setState(() {
        _errorMessage = 'Error deleting map: ${e.toString()}';
        _isLoading = false;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final isWideScreen = screenWidth > 600;
    final isTablet = screenWidth > 800;
    
    // Calculate responsive padding based on screen size and system UI
    final horizontalPadding = isTablet ? 32.0 : (isWideScreen ? 24.0 : 16.0);
    final verticalPadding = isTablet ? 24.0 : 16.0;
    final bottomSafeArea = mediaQuery.padding.bottom;
    final hasBottomNavigation = bottomSafeArea > 0;
    
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).primaryColor, 
        foregroundColor: Colors.white,
        title: Text(
          'Map Management',
          style: TextStyle(
            fontSize: isTablet ? 22 : 20,
          ),
        ),
      ),
      body: SafeArea(
        child: _isLoading 
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
                builder: (context, constraints) {
                  if (isWideScreen && !_isAddingMap) {
                    // Wide screen layout: side-by-side for tablets/desktop
                    return _buildWideScreenLayout(constraints, horizontalPadding, verticalPadding);
                  } else {
                    // Mobile layout: single column with bottom navigation awareness
                    return _buildMobileLayout(horizontalPadding, verticalPadding, hasBottomNavigation);
                  }
                },
              ),
      ),
    );
  }

  Widget _buildMobileLayout(double horizontalPadding, double verticalPadding, bool hasBottomNavigation) {
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.only(
          left: horizontalPadding,
          right: horizontalPadding,
          top: verticalPadding,
          bottom: hasBottomNavigation ? verticalPadding + 16 : verticalPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _buildMainContent(),
        ),
      ),
    );
  }

  Widget _buildWideScreenLayout(BoxConstraints constraints, double horizontalPadding, double verticalPadding) {
    return Row(
      children: [
        // Left panel: Map list (1/3 width)
        Expanded(
          flex: 1,
          child: Container(
            margin: EdgeInsets.only(
              left: horizontalPadding,
              top: verticalPadding,
              bottom: verticalPadding,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Available Maps',
                      style: TextStyle(
                        fontSize: constraints.maxWidth > 1000 ? 22 : 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                      label: const Text('Add Map'),
                      onPressed: () {
                        setState(() {
                          _isAddingMap = true;
                          _errorMessage = null;
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                        textStyle: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Error message
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: Colors.red.shade900),
                    ),
                  ),
                
                // Maps list
                Expanded(
                  child: _maps.isEmpty
                      ? const Center(
                          child: Text(
                            'No maps available.\nAdd your first map!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _maps.length,
                          itemBuilder: (context, index) {
                            final map = _maps[index];
                            final bool isSelected = _selectedMap != null && _selectedMap!['id'] == map['id'];
                            
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4.0),
                              elevation: isSelected ? 4 : 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12.0),
                                side: isSelected
                                    ? BorderSide(color: Theme.of(context).primaryColor, width: 2)
                                    : BorderSide.none,
                              ),
                              child: ListTile(
                                title: Text(
                                  map['name'] ?? 'Unnamed Map',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: constraints.maxWidth > 1000 ? 16 : 15,
                                  ),
                                ),
                                subtitle: Text('${map['node_count'] ?? 0} nodes'),
                                selected: isSelected,
                                selectedTileColor: Theme.of(context).primaryColor.withOpacity(0.1),
                                onTap: () => _selectMap(map),
                                trailing: isSelected 
                                    ? Icon(Icons.check_circle, color: Theme.of(context).primaryColor) 
                                    : null,
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
        
        // Divider
        Container(
          width: 1,
          color: Colors.grey[300],
          margin: const EdgeInsets.symmetric(vertical: 16),
        ),
        
        // Right panel: Map details/actions (2/3 width)
        Expanded(
          flex: 2,
          child: Container(
            padding: EdgeInsets.only(
              left: horizontalPadding,
              right: horizontalPadding,
              top: verticalPadding,
              bottom: verticalPadding,
            ),
            child: _selectedMap != null
                ? _buildMapDetailsPanel(constraints)
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.map_outlined,
                          size: constraints.maxWidth > 1000 ? 80 : 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Select a map to view details and actions',
                          style: TextStyle(
                            fontSize: constraints.maxWidth > 1000 ? 18 : 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildMapDetailsPanel(BoxConstraints constraints) {
    if (_selectedMap == null) return const SizedBox.shrink();
    
    final isLargeScreen = constraints.maxWidth > 1000;
    
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _selectedMap!['name'] ?? 'Unnamed Map',
            style: TextStyle(
              fontSize: isLargeScreen ? 28 : 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_selectedMap!['node_count'] ?? 0} nodes',
            style: TextStyle(
              fontSize: isLargeScreen ? 18 : 16,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 32),
          
          // Action buttons with responsive sizing
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildActionButton(
                onPressed: _addNodeToMap,
                icon: Icons.add_location,
                label: 'Add Node',
                color: Theme.of(context).primaryColor,
                isLargeScreen: isLargeScreen,
              ),
              const SizedBox(height: 16),
              _buildActionButton(
                onPressed: _viewMapDetails,
                icon: Icons.manage_search,
                label: 'View Details',
                color: Colors.teal,
                isLargeScreen: isLargeScreen,
              ),
              const SizedBox(height: 16),
              _buildActionButton(
                onPressed: () => _confirmDeleteMap(_selectedMap!),
                icon: Icons.delete_forever,
                label: 'Delete Map',
                color: Colors.red[700]!,
                isLargeScreen: isLargeScreen,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    required Color color,
    required bool isLargeScreen,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: isLargeScreen ? 24 : 20),
      label: Text(
        label,
        style: TextStyle(fontSize: isLargeScreen ? 16 : 14),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(
          vertical: isLargeScreen ? 20 : 16,
          horizontal: isLargeScreen ? 24 : 16,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 2,
      ),
    );
  }

  List<Widget> _buildMainContent() {
    return [
      // Error message (show only when not adding)
      if (_errorMessage != null && !_isAddingMap)
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.red.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.red.shade300),
          ),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Colors.red.shade900),
                ),
              ),
            ],
          ),
        ),

      // Available maps section Title + Button Row
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Available Maps',
            style: TextStyle(
              fontSize: 20.0,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (!_isAddingMap)
            ElevatedButton.icon(
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: const Text('Upload New Map'),
              onPressed: () {
                setState(() {
                  _isAddingMap = true;
                  _errorMessage = null;
                });
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 16.0),

      // Conditionally Display Map List OR Add Form
      if (!_isAddingMap)
        ..._buildMapsList()
      else
        _buildAddMapForm(),
    ];
  }

  List<Widget> _buildMapsList() {
    if (_maps.isEmpty) {
      return [
        Center(
          child: Container(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              children: [
                Icon(
                  Icons.map_outlined,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                const Text(
                  'No maps available',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Add your first map to get started!',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    return [
      ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _maps.length,
        itemBuilder: (context, index) {
          final map = _maps[index];
          final bool isSelected = _selectedMap != null && _selectedMap!['id'] == map['id'];

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8.0),
            elevation: isSelected ? 4 : 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.0),
              side: isSelected
                  ? BorderSide(color: Theme.of(context).primaryColor, width: 2)
                  : BorderSide.none,
            ),
            child: InkWell(
              onTap: () => _selectMap(map),
              borderRadius: BorderRadius.circular(12.0),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            map['name'] ?? 'Unnamed Map',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        if (isSelected)
                          Icon(
                            Icons.check_circle,
                            color: Theme.of(context).primaryColor,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          '${map['node_count'] ?? 0} nodes',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                    if (isSelected) ...[
                      const SizedBox(height: 16),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isNarrow = constraints.maxWidth < 400;
                          
                          if (isNarrow) {
                            // Stacked layout for narrow screens
                            return Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: _addNodeToMap,
                                        icon: const Icon(Icons.add_location, size: 18),
                                        label: const Text('Add Node'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Theme.of(context).primaryColor,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: _viewMapDetails,
                                        icon: const Icon(Icons.manage_search, size: 18),
                                        label: const Text('Details'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.teal,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: () => _confirmDeleteMap(map),
                                    icon: const Icon(Icons.delete_forever, size: 18),
                                    label: const Text('Delete Map'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red[700],
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          } else {
                            // Row layout for wider screens
                            return Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: _addNodeToMap,
                                        icon: const Icon(Icons.add_location),
                                        label: const Text('Add Node'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Theme.of(context).primaryColor,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: _viewMapDetails,
                                        icon: const Icon(Icons.manage_search),
                                        label: const Text('View Details'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.teal,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: () => _confirmDeleteMap(map),
                                    icon: const Icon(Icons.delete_forever),
                                    label: const Text('Delete Map'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red[700],
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
      const SizedBox(height: 24.0),
    ];
  }

  Widget _buildAddMapForm() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Add New Map',
                  style: TextStyle(
                    fontSize: 20.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _cancelAddMap,
                  tooltip: 'Cancel',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey[200],
                    shape: const CircleBorder(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20.0),
            
            // Form error message
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red.shade900),
                      ),
                    ),
                  ],
                ),
              ),
              
            TextField(
              controller: _mapNameController,
              decoration: InputDecoration(
                labelText: 'Map Name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                hintText: 'e.g., 1st Floor, Building A',
                prefixIcon: const Icon(Icons.map),
              ),
            ),
            const SizedBox(height: 20.0),
            
            // Responsive image picker
            LayoutBuilder(
              builder: (context, constraints) {
                final maxImageHeight = constraints.maxWidth > 600 ? 400.0 : 300.0;
                
                return Center(
                  child: _mapImage != null
                      ? Stack(
                          alignment: Alignment.topRight,
                          children: [
                            Container(
                              constraints: BoxConstraints(
                                maxHeight: maxImageHeight,
                                maxWidth: constraints.maxWidth - 32,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.file(
                                  _mapImage!,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: IconButton(
                                icon: const Icon(Icons.close, color: Colors.white),
                                onPressed: () => setState(() => _mapImage = null),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black54,
                                  shape: const CircleBorder(),
                                ),
                              ),
                            ),
                          ],
                        )
                      : Container(
                          height: 200,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.grey[400]!,
                              width: 2,
                              style: BorderStyle.solid,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.grey[50],
                          ),
                          child: InkWell(
                            onTap: _pickImage,
                            borderRadius: BorderRadius.circular(12),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.upload_file,
                                  size: 64,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Select Map Image',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Tap to browse files',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                );
              },
            ),
            const SizedBox(height: 24.0),
            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : (_mapImage != null ? _saveMap : _pickImage),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 2,
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _mapImage != null ? 'Save Map' : 'Select Map Image',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
