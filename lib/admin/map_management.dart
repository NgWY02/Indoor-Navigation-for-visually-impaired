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
  bool _isAddingMap = false; // Add this state variable
  
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
        
        // Reset form and hide it
        setState(() {
          _mapImage = null;
          _mapNameController.clear();
          _isAddingMap = false; // Hide the form
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

  // Add method to cancel adding a map
  void _cancelAddMap() {
    setState(() {
      _mapImage = null;
      _mapNameController.clear();
      _errorMessage = null;
      _isAddingMap = false; // Hide the form
    });
  }

  // NEW: Method to show delete confirmation dialog
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
                Navigator.of(context).pop(false); // Return false
              },
            ),
            TextButton(
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
              onPressed: () {
                Navigator.of(context).pop(true); // Return true
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

  // NEW: Method to handle the actual deletion process
  Future<void> _deleteMap(String mapId) async {
    setState(() {
      _isLoading = true; // Show loading indicator
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
      // Refresh map list and deselect
      setState(() {
        _selectedMap = null;
      });
      _loadMaps(); // Reload maps (will also set _isLoading to false)
    } catch (e) {
      setState(() {
        _errorMessage = 'Error deleting map: ${e.toString()}';
        _isLoading = false; // Hide loading indicator on error
      });
    }
    // No finally block needed here as _loadMaps handles _isLoading on success
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
                    // Error message (show only when not adding)
                    if (_errorMessage != null && !_isAddingMap)
                      Container(
                        padding: const EdgeInsets.all(8),
                        margin: const EdgeInsets.only(bottom: 16),
                        color: Colors.red.shade100,
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red.shade900),
                        ),
                      ),

                    // --- Available maps section Title + Button Row ---
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween, // Align items
                      children: [
                        const Text( // Title on the left
                          'Available Maps',
                          style: TextStyle(
                            fontSize: 18.0,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        // Spacer(), // Use Spacer to push button right
                        if (!_isAddingMap) // Show button only if form is hidden
                          ElevatedButton.icon( // Button on the right
                            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18), // Smaller icon
                            label: const Text('Upload New Map'), // Shorter text
                            onPressed: () {
                              setState(() {
                                _isAddingMap = true;
                                _errorMessage = null; // Clear previous errors
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0), // Adjust padding
                              textStyle: TextStyle(fontSize: 14), // Adjust text size if needed
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8.0), // Space below the title/button row

                    // --- Conditionally Display Map List OR Add Form ---
                    if (!_isAddingMap) // Show list only if NOT adding map
                      Column( // Wrap list-related widgets
                        children: [
                          if (_maps.isEmpty)
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text('No maps available. Add your first map!'),
                              ),
                            )
                          else
                            ListView.builder(
                              // ... (existing ListView.builder code remains the same) ...
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
                                        Padding(
                                          padding: const EdgeInsets.all(12.0), // Adjusted padding
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                map['name'] ?? 'Unnamed Map',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text('${map['node_count'] ?? 0} nodes'),
                                              const SizedBox(height: 10), // Adjusted spacing
                                              if (isSelected)
                                                Column(
                                                  // ... (existing buttons remain the same) ...
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
                          const SizedBox(height: 24.0), // Add spacing after the list
                        ],
                      )
                    else // Show Add Map Form if _isAddingMap is true
                      Card( // The existing Add Map Card
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Add New Map',
                                    style: TextStyle(
                                      fontSize: 18.0,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  IconButton( // Cancel button
                                    icon: Icon(Icons.close),
                                    onPressed: _cancelAddMap,
                                    tooltip: 'Cancel',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16.0),
                              // Specific error message for the form
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
                                // ... (existing image picker/display widget) ...
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
                                // ... (existing Save Map button) ...
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : (_mapImage != null ? _saveMap : _pickImage), // Disable while loading
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                                  ),
                                  child: _isLoading
                                      ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                                      : Text(_mapImage != null ? 'Save Map' : 'Select Map Image'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    // --- END Conditional Display ---

                    // --- REMOVED Visibility wrapper for Add Map Form ---
                    // Visibility(
                    //   visible: _isAddingMap,
                    //   child: Card(...)
                    // ),
                  ],
                ),
              ),
            ),
    );
  }
}