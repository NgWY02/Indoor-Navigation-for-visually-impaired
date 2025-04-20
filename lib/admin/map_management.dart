import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/supabase_service.dart';
import 'node_capture.dart';
import 'map_details_screen.dart'; // Add this import

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
      // First save image to storage
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
        
        // Reset form
        setState(() {
          _mapImage = null;
          _mapNameController.clear();
        });
        
        // Reload maps
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
    );
  }

  // Add a new method to navigate to map details screen
  void _viewMapDetails() {
    if (_selectedMap == null) return;
    
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => MapDetailsScreen(mapId: _selectedMap!['id']),
      ),
    ).then((_) {
      // Refresh the maps after returning from details
      _loadMaps();
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Map Management'),
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Error message
                    if (_errorMessage != null) 
                      Container(
                        padding: const EdgeInsets.all(8),
                        margin: const EdgeInsets.only(bottom: 16),
                        color: Colors.red.shade100,
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red.shade900),
                        ),
                      ),
                    
                    // Add new map section
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Add New Map',
                              style: TextStyle(
                                fontSize: 18.0,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16.0),
                            TextField(
                              controller: _mapNameController,
                              decoration: const InputDecoration(
                                labelText: 'Map Name',
                                border: OutlineInputBorder(),
                                hintText: 'e.g., 1st Floor, Building A',
                              ),
                            ),
                            const SizedBox(height: 16.0),
                            Center(
                              child: _mapImage != null
                                ? Stack(
                                    alignment: Alignment.topRight,
                                    children: [
                                      Container(
                                        constraints: BoxConstraints(
                                          maxHeight: 300,
                                        ),
                                        child: Image.file(
                                          _mapImage!,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close, color: Colors.white),
                                        onPressed: () => setState(() => _mapImage = null),
                                        style: IconButton.styleFrom(
                                          backgroundColor: Colors.black54,
                                        ),
                                      ),
                                    ],
                                  )
                                : Container(
                                    height: 200,
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.grey),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: InkWell(
                                      onTap: _pickImage,
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: const [
                                          Icon(Icons.upload_file, size: 50),
                                          SizedBox(height: 8),
                                          Text('Select Map Image'),
                                        ],
                                      ),
                                    ),
                                  ),
                            ),
                            const SizedBox(height: 16.0),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _mapImage != null ? _saveMap : _pickImage,
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                                ),
                                child: Text(_mapImage != null ? 'Save Map' : 'Select Map Image'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 24.0),
                    
                    // Available maps section
                    const Text(
                      'Available Maps',
                      style: TextStyle(
                        fontSize: 18.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8.0),
                    
                    if (_maps.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text('No maps available. Add your first map!'),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _maps.length,
                        itemBuilder: (context, index) {
                          final map = _maps[index];
                          final bool isSelected = _selectedMap != null && _selectedMap!['id'] == map['id'];
                          
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 8.0),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8.0),
                              side: isSelected
                                ? BorderSide(color: Theme.of(context).primaryColor, width: 2)
                                : BorderSide.none,
                            ),
                            child: InkWell(
                              onTap: () => _selectMap(map),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Map image
                                  Container(
                                    height: 120,
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      image: DecorationImage(
                                        image: NetworkImage(map['image_url']),
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          map['name'],
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text('${map['node_count'] ?? 0} nodes'),
                                        const SizedBox(height: 8),
                                        if (isSelected)
                                          Row(
                                            children: [
                                              Expanded(
                                                child: ElevatedButton.icon(
                                                  onPressed: _addNodeToMap,
                                                  icon: const Icon(Icons.add_location),
                                                  label: const Text('Add Node'),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: Theme.of(context).primaryColor,
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
                                                    backgroundColor: const Color.fromARGB(255, 245, 249, 248),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}