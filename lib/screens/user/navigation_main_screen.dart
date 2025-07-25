import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/clip_service.dart';
import '../../services/supabase_service.dart';
import '../../services/position_localization_service.dart';
import '../../services/real_time_navigation_service.dart' as nav_service;
import '../../models/path_models.dart';

class NavigationMainScreen extends StatefulWidget {
  final CameraDescription camera;

  const NavigationMainScreen({Key? key, required this.camera}) : super(key: key);

  @override
  State<NavigationMainScreen> createState() => _NavigationMainScreenState();
}

class _NavigationMainScreenState extends State<NavigationMainScreen> with WidgetsBindingObserver {
  // Services
  late ClipService _clipService;
  late SupabaseService _supabaseService;
  late PositionLocalizationService _localizationService;
  late nav_service.RealTimeNavigationService _navigationService;
  
  // Camera
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  
  // State
  NavigationScreenState _screenState = NavigationScreenState.initializing;
  LocationMatch? _currentLocation;
  List<NavigationRoute> _availableRoutes = [];
  NavigationRoute? _selectedRoute;
  String _statusMessage = 'Initializing...';
  nav_service.NavigationInstruction? _currentInstruction;
  
  // UI State
  bool _isProcessingFrame = false;
  Timer? _frameProcessingTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeServices();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _frameProcessingTimer?.cancel();
    _cameraController?.dispose();
    _navigationService.dispose();
    _localizationService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isCameraInitialized || _cameraController == null) return;

    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeServices() async {
    try {
      // Initialize services
      _supabaseService = SupabaseService();
      _clipService = ClipService();
      _localizationService = PositionLocalizationService(
        clipService: _clipService,
        supabaseService: _supabaseService,
      );
      _navigationService = nav_service.RealTimeNavigationService(
        clipService: _clipService,
        onStateChanged: _onNavigationStateChanged,
        onStatusUpdate: _onStatusUpdate,
        onInstructionUpdate: _onInstructionUpdate,
        onError: _onError,
      );

      // Initialize camera
      await _initializeCamera();
      
      setState(() {
        _screenState = NavigationScreenState.localizingPosition;
        _statusMessage = 'Ready to localize position';
      });

    } catch (e) {
      _onError('Failed to initialize: $e');
    }
  }

  Future<void> _initializeCamera() async {
    try {
      // Request camera permission
      final status = await Permission.camera.request();
      if (status != PermissionStatus.granted) {
        throw Exception('Camera permission denied');
      }

      _cameraController = CameraController(
        widget.camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      
      setState(() {
        _isCameraInitialized = true;
      });

    } catch (e) {
      _onError('Failed to initialize camera: $e');
    }
  }

  Future<void> _startLocalization() async {
    setState(() {
      _screenState = NavigationScreenState.localizingPosition;
      _statusMessage = 'Starting position localization...';
    });

    try {
      // Capture current image for localization
      if (_cameraController != null && _cameraController!.value.isInitialized) {
        final image = await _cameraController!.takePicture();
        final imageFile = File(image.path);
        
        setState(() {
          _statusMessage = 'Analyzing current location...';
        });
        
        final location = await _localizationService.localizePosition(imageFile);
        
        // Clean up temp file
        await imageFile.delete();
        
        if (location != null) {
          _currentLocation = location;
          await _loadAvailableRoutes();
        } else {
          setState(() {
            _statusMessage = 'Unable to determine location. Please try again from a different angle.';
          });
        }
      }
    } catch (e) {
      _onError('Localization failed: $e');
    }
  }

  Future<void> _loadAvailableRoutes() async {
    if (_currentLocation == null) return;

    setState(() {
      _statusMessage = 'Loading available routes...';
    });

    try {
      final routes = await _localizationService.getAvailableRoutes(_currentLocation!.nodeId);
      
      setState(() {
        _availableRoutes = routes;
        _screenState = NavigationScreenState.selectingRoute;
        _statusMessage = routes.isNotEmpty 
            ? 'Found ${routes.length} available routes'
            : 'No routes available from this location';
      });

    } catch (e) {
      _onError('Failed to load routes: $e');
    }
  }

  void _selectRoute(NavigationRoute route) {
    setState(() {
      _selectedRoute = route;
      _screenState = NavigationScreenState.confirmingRoute;
      _statusMessage = 'Route selected: ${route.pathName}';
    });
  }

  Future<void> _startNavigation() async {
    if (_selectedRoute == null) return;

    setState(() {
      _screenState = NavigationScreenState.navigating;
      _statusMessage = 'Starting navigation...';
    });

    await _navigationService.startNavigation(_selectedRoute!);
    
    // Start periodic frame processing for navigation
    _frameProcessingTimer = Timer.periodic(Duration(seconds: 2), (_) {
      _processNavigationFrame();
    });
  }

  Future<void> _processNavigationFrame() async {
    if (_isProcessingFrame || 
        _cameraController == null || 
        !_cameraController!.value.isInitialized ||
        _screenState != NavigationScreenState.navigating) {
      return;
    }

    _isProcessingFrame = true;

    try {
      final image = await _cameraController!.takePicture();
      final imageFile = File(image.path);
      
      await _navigationService.processNavigationFrame(imageFile);
      
      // Clean up temp file
      await imageFile.delete();
      
    } catch (e) {
      print('Error processing navigation frame: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  // Callback methods
  void _onNavigationStateChanged(nav_service.NavigationState state) {
    // Handle navigation state changes if needed
  }

  void _onStatusUpdate(String message) {
    setState(() {
      _statusMessage = message;
    });
  }

  void _onInstructionUpdate(nav_service.NavigationInstruction instruction) {
    setState(() {
      _currentInstruction = instruction;
    });
  }

  void _onError(String error) {
    setState(() {
      _statusMessage = 'Error: $error';
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Camera preview
            Expanded(
              flex: 3,
              child: _buildCameraPreview(),
            ),
            
            // Control panel
            Expanded(
              flex: 2,
              child: _buildControlPanel(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (!_isCameraInitialized || _cameraController == null) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text(
                'Initializing Camera...',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        CameraPreview(_cameraController!),
        
        // Overlay information
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_currentLocation != null) ...[
                  Text(
                    'Current Location: ${_currentLocation!.nodeName}',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Confidence: ${(_currentLocation!.confidence * 100).round()}%',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  SizedBox(height: 8),
                ],
                
                if (_currentInstruction != null) ...[
                  Text(
                    _currentInstruction!.displayText,
                    style: TextStyle(color: Colors.orange, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Progress: ${_navigationService.progressPercentage.round()}%',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ] else ...[
                  Text(
                    _statusMessage,
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControlPanel() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          Expanded(
            child: _buildScreenContent(),
          ),
          
          SizedBox(height: 16),
          
          // Action buttons
          _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildScreenContent() {
    switch (_screenState) {
      case NavigationScreenState.initializing:
        return _buildInitializingContent();
      case NavigationScreenState.localizingPosition:
        return _buildLocalizationContent();
      case NavigationScreenState.selectingRoute:
        return _buildRouteSelectionContent();
      case NavigationScreenState.confirmingRoute:
        return _buildRouteConfirmationContent();
      case NavigationScreenState.navigating:
        return _buildNavigationContent();
    }
  }

  Widget _buildInitializingContent() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            _statusMessage,
            style: TextStyle(color: Colors.white, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildLocalizationContent() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.location_searching, color: Colors.blue, size: 64),
          SizedBox(height: 16),
          Text(
            'Position Localization',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            'Point your camera at your surroundings to determine your current location.',
            style: TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildRouteSelectionContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Available Routes',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 12),
        
        Expanded(
          child: _availableRoutes.isEmpty
              ? Center(
                  child: Text(
                    'No routes available from this location',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                )
              : ListView.builder(
                  itemCount: _availableRoutes.length,
                  itemBuilder: (context, index) {
                    final route = _availableRoutes[index];
                    return Card(
                      color: Colors.grey[800],
                      child: ListTile(
                        title: Text(
                          route.endNodeName,
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              route.pathName,
                              style: TextStyle(color: Colors.white70),
                            ),
                            SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.straighten, color: Colors.blue, size: 16),
                                SizedBox(width: 4),
                                Text(
                                  route.formattedDistance,
                                  style: TextStyle(color: Colors.blue),
                                ),
                                SizedBox(width: 16),
                                Icon(Icons.access_time, color: Colors.green, size: 16),
                                SizedBox(width: 4),
                                Text(
                                  route.formattedDuration,
                                  style: TextStyle(color: Colors.green),
                                ),
                              ],
                            ),
                          ],
                        ),
                        trailing: Icon(Icons.arrow_forward_ios, color: Colors.white),
                        onTap: () => _selectRoute(route),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildRouteConfirmationContent() {
    if (_selectedRoute == null) return Container();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Confirm Route',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 16),
        
        Card(
          color: Colors.grey[800],
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Destination: ${_selectedRoute!.endNodeName}',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'Route: ${_selectedRoute!.pathName}',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.straighten, color: Colors.blue, size: 16),
                            SizedBox(width: 4),
                            Text(
                              _selectedRoute!.formattedDistance,
                              style: TextStyle(color: Colors.blue),
                            ),
                          ],
                        ),
                        SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.access_time, color: Colors.green, size: 16),
                            SizedBox(width: 4),
                            Text(
                              _selectedRoute!.formattedDuration,
                              style: TextStyle(color: Colors.green),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${_selectedRoute!.estimatedSteps} steps',
                          style: TextStyle(color: Colors.white70),
                        ),
                        Text(
                          '${_selectedRoute!.waypoints.length} waypoints',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNavigationContent() {
    return Column(
      children: [
        if (_currentInstruction != null) ...[
          Card(
            color: Colors.orange[900],
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _currentInstruction!.displayText,
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        'Waypoint ${_currentInstruction!.waypointNumber} of ${_currentInstruction!.totalWaypoints}',
                        style: TextStyle(color: Colors.white70),
                      ),
                      Spacer(),
                      Text(
                        '${_navigationService.progressPercentage.round()}%',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _navigationService.progressPercentage / 100,
                    backgroundColor: Colors.grey[600],
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.orange),
                  ),
                ],
              ),
            ),
          ),
        ],
        
        Spacer(),
        
        // Emergency controls
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _navigationService.requestRepositioning(),
                icon: Icon(Icons.refresh),
                label: Text('Reorient'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _navigationService.stopNavigation(),
                icon: Icon(Icons.stop),
                label: Text('Stop'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    switch (_screenState) {
      case NavigationScreenState.initializing:
        return SizedBox.shrink();
        
      case NavigationScreenState.localizingPosition:
        return ElevatedButton.icon(
          onPressed: _isCameraInitialized ? _startLocalization : null,
          icon: Icon(Icons.location_on),
          label: Text('Find My Location'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            minimumSize: Size(double.infinity, 48),
          ),
        );
        
      case NavigationScreenState.selectingRoute:
        return ElevatedButton.icon(
          onPressed: _startLocalization,
          icon: Icon(Icons.refresh),
          label: Text('Relocalize'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.grey[700],
            foregroundColor: Colors.white,
            minimumSize: Size(double.infinity, 48),
          ),
        );
        
      case NavigationScreenState.confirmingRoute:
        return Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _screenState = NavigationScreenState.selectingRoute;
                    _selectedRoute = null;
                  });
                },
                icon: Icon(Icons.arrow_back),
                label: Text('Back'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[700],
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _startNavigation,
                icon: Icon(Icons.navigation),
                label: Text('Start Navigation'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        );
        
      case NavigationScreenState.navigating:
        return SizedBox.shrink(); // Controls are in the navigation content
    }
  }
}

enum NavigationScreenState {
  initializing,
  localizingPosition,
  selectingRoute,
  confirmingRoute,
  navigating,
}
