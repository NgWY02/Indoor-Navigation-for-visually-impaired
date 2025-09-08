import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/clip_service.dart';
import '../../services/supabase_service.dart';
import '../../services/position_localization_service.dart';
import '../../services/real_time_navigation_service.dart' as nav_service;
import '../../widgets/debug_overlay.dart'; 

class NavigationMainScreen extends StatefulWidget {
  final CameraDescription camera;

  const NavigationMainScreen({Key? key, required this.camera}) : super(key: key);

  @override
  State<NavigationMainScreen> createState() => _NavigationMainScreenState();
}

class _NavigationMainScreenState extends State<NavigationMainScreen> 
    with WidgetsBindingObserver { 
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
  bool _isTakingPicture = false;  // New: Only for camera access
  Timer? _frameProcessingTimer;
  
  // Debug overlay
  bool _isDebugVisible = false;
  String _debugInfo = '🐛 Debug overlay ready';
  
  // Localization state
  List<String> _capturedDirections = [];
  List<String> _directionNames = ['North', 'East', 'South', 'West'];
  List<File> _capturedFrames = [];
  int _currentDirectionIndex = 0;
  
  // Localization result display
  String? _localizationResult;
  bool _showLocalizationResult = false;
  
  // Recovery system state
  bool _isInRecoveryMode = false;
  int _recoveryFrameCount = 0;
  bool _isCapturingRecoveryFrame = false;

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
    _disposeCamera(); // Use the safe disposal method
    _navigationService.dispose();
    _localizationService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      // Dispose camera when app goes to background
      _disposeCamera();
    } else if (state == AppLifecycleState.resumed) {
      // Reinitialize camera when app resumes
      if (!_isCameraInitialized) {
        _initializeCamera();
      }
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
        onDebugUpdate: _onDebugUpdate,
        onRequestManualCapture: _onRequestManualCapture,
        onManualFrameCaptured: _onManualFrameCaptured,
      );

      // Initialize camera
      await _initializeCamera();
      
      setState(() {
        _screenState = NavigationScreenState.readyToLocalize;
        _statusMessage = 'Ready to start localization';
      });

    } catch (e) {
      _onError('Failed to initialize: $e');
    }
  }

  Future<void> _initializeCamera() async {
    try {
      // Dispose existing controller if it exists and is disposed
      await _disposeCamera();

      // Request permissions including step counter
      final permissions = await [
        Permission.camera,
        Permission.activityRecognition, // For step counter
        Permission.sensors, // For step counter and compass
      ].request();

      if (permissions[Permission.camera] != PermissionStatus.granted) {
        throw Exception('Camera permission denied');
      }
      
      // Check step counter permissions
      if (permissions[Permission.activityRecognition] != PermissionStatus.granted) {
        print('⚠️ Activity recognition permission denied - step counter may not work');
      }

      _cameraController = CameraController(
        widget.camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }

    } catch (e) {
      print('Error initializing camera: $e');
      if (mounted) {
        setState(() {
          _isCameraInitialized = false;
          _statusMessage = 'Camera initialization failed: ${e.toString()}';
        });
      }
      _onError('Failed to initialize camera: $e');
    }
  }

  Future<void> _disposeCamera() async {
    if (_cameraController != null) {
      try {
        if (_cameraController!.value.isInitialized) {
          await _cameraController!.dispose();
        }
      } catch (e) {
        print('Error disposing camera: $e');
      } finally {
        _cameraController = null;
        if (mounted) {
          setState(() {
            _isCameraInitialized = false;
          });
        }
      }
    }
  }


  Future<void> _startLocalizationProcess() async {
    setState(() {
      _screenState = NavigationScreenState.capturingDirections;
      _capturedDirections = [];
      _capturedFrames = [];
      _directionNames = ['North', 'East', 'South', 'West'];
      _currentDirectionIndex = 0;
      _statusMessage = 'Point camera towards North and tap "Capture North"';
      // Clear previous localization result
      _localizationResult = null;
      _showLocalizationResult = false;
    });
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
      // Clear localization result when navigation starts
      _localizationResult = null;
      _showLocalizationResult = false;
    });

    await _navigationService.startNavigation(_selectedRoute!);
    
    // Start periodic frame processing for navigation
    _frameProcessingTimer = Timer.periodic(Duration(seconds: 1), (_) {
      _processNavigationFrame();
    });
  }

  Future<void> _processNavigationFrame() async {
    if (_isProcessingFrame || 
        _cameraController == null || 
        !_cameraController!.value.isInitialized ||
        _screenState != NavigationScreenState.navigating ||
        _isTakingPicture) {  // ✅ Only check camera access, not recovery processing
      return;
    }

    _isProcessingFrame = true;

    try {
      // Phase 1: Camera access (needs mutual exclusion)
      _isTakingPicture = true;
      final image = await _cameraController!.takePicture();
      _isTakingPicture = false;  // Camera is now free
      
      // Phase 2: Processing (can happen in parallel)
      final imageFile = File(image.path);
      await _navigationService.processNavigationFrame(imageFile);
      
      // Clean up temp file
      await imageFile.delete();
      
    } catch (e) {
      print('Error processing navigation frame: $e');
      _isTakingPicture = false;  // Ensure camera is freed on error
    } finally {
      _isProcessingFrame = false;
    }
  }

  // Callback methods
  void _onNavigationStateChanged(nav_service.NavigationState state) {
    // Handle recovery state changes
    setState(() {
      switch (state) {
        case nav_service.NavigationState.awaitingManualCapture:
          _isInRecoveryMode = true;
          _isCapturingRecoveryFrame = false;  // ✅ Reset when entering recovery mode
          _isTakingPicture = false;
          break;
        case nav_service.NavigationState.manualCaptureInProgress:
          _isInRecoveryMode = true;
          _isCapturingRecoveryFrame = false;  // ✅ Reset when ready to capture
          _isTakingPicture = false;
          break;
        case nav_service.NavigationState.analyzingCapturedFrames:
          _isInRecoveryMode = true;
          break;
        case nav_service.NavigationState.navigating:
        case nav_service.NavigationState.idle:
        case nav_service.NavigationState.destinationReached:
          _isInRecoveryMode = false;
          _recoveryFrameCount = 0;
          _isCapturingRecoveryFrame = false;
          _isTakingPicture = false;  // Reset camera state
          break;
        default:
          break;
      }
    });
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

  void _onDebugUpdate(String debugInfo) {
    setState(() {
      _debugInfo = debugInfo;
    });
  }

  void _onRequestManualCapture() {
    setState(() {
      _isInRecoveryMode = true;
      _recoveryFrameCount = 0;
      _isCapturingRecoveryFrame = false;  // ✅ Reset capture state when recovery starts/restarts
      _isTakingPicture = false;  // ✅ Reset camera state
    });
  }

  void _onManualFrameCaptured(File imageFile) {
    setState(() {
      _recoveryFrameCount++;
    });
  }

  Future<void> _captureRecoveryFrame() async {
    if (!_isInRecoveryMode || 
        _cameraController == null || 
        !_cameraController!.value.isInitialized ||
        _isCapturingRecoveryFrame ||
        _isTakingPicture) {  // ✅ Only check camera access, not frame processing
      return;
    }

    setState(() {
      _isCapturingRecoveryFrame = true;
    });
    
    try {
      // Phase 1: Camera access (needs mutual exclusion)
      _isTakingPicture = true;
      final image = await _cameraController!.takePicture();
      _isTakingPicture = false;  // Camera is now free
      
      // Phase 2: Processing (can happen in parallel)
      final imageFile = File(image.path);
      await _navigationService.processManualCapturedFrame(imageFile);
      
    } catch (e) {
      _onError('Failed to capture recovery frame: $e');
      _isTakingPicture = false;  // Ensure camera is freed on error
    } finally {
      if (mounted) {
        setState(() {
          _isCapturingRecoveryFrame = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Full screen camera preview
            _buildCameraPreview(),

            // Localization result display at top - hide during navigation
            if (_showLocalizationResult && _screenState != NavigationScreenState.navigating)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildLocalizationResultDisplay(),
              ),

            // Overlay control panel at bottom
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildOverlayControlPanel(),
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

    return SizedBox.expand(
      child: Stack(
        children: [
          CameraPreview(_cameraController!),

          // Debug overlay - only show during navigation
          if (_screenState == NavigationScreenState.navigating)
            DebugOverlay(
              debugInfo: _debugInfo,
              isVisible: true,  // Always show during navigation
              onToggle: () {
                setState(() {
                  _isDebugVisible = !_isDebugVisible;
                });
              },
            ),
        ],
      ),
    );
  }

  Widget _buildLocalizationResultDisplay() {
    return Container(
      padding: EdgeInsets.all(16),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha:0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha:0.1),
                    width: 1,
                  ),
                ),
                child: Text(
                  _localizationResult ?? 'Processing...',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlayControlPanel() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withOpacity(0.3),
            Colors.black.withOpacity(0.1),
            Colors.transparent,
          ],
          stops: [0.0, 0.8, 1.0],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Recovery mode overlay (if active)
          if (_isInRecoveryMode)
            Container(
              margin: EdgeInsets.only(bottom: 16),
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    'Recovery Mode Active',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Frame ${_recoveryFrameCount} of 3',
                    style: TextStyle(color: Colors.white),
                  ),
                  if (_navigationService.state == nav_service.NavigationState.manualCaptureInProgress) ...[
                    SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: (_isCapturingRecoveryFrame || _isTakingPicture) 
                          ? null 
                          : _captureRecoveryFrame,
                      icon: (_isCapturingRecoveryFrame || _isTakingPicture)
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Icon(Icons.camera_alt),
                      label: Text((_isCapturingRecoveryFrame || _isTakingPicture) ? 'Capturing...' : 'Capture Frame'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepOrange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
            ),

          // Screen content
          Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.3,
            ),
            child: _buildScreenContent(),
          ),

          SizedBox(height: 12),

          // Navigation instruction (only show during navigation)
          if (_screenState == NavigationScreenState.navigating && _currentInstruction != null)
            Container(
              margin: EdgeInsets.only(bottom: 12),
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[900]!.withOpacity(0.9),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
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
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      Spacer(),
                      Text(
                        '${_navigationService.progressPercentage.round()}%',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
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
      case NavigationScreenState.readyToLocalize:
        return _buildReadyToLocalizeContent();
      case NavigationScreenState.capturingDirections:
        return _buildCapturingDirectionsContent();
      case NavigationScreenState.processingLocation:
        return _buildProcessingLocationContent();
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
          SizedBox(height: 12),
          Text(
            _statusMessage,
            style: TextStyle(color: Colors.white, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildReadyToLocalizeContent() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.location_searching, color: Colors.blue, size: 48),
          SizedBox(height: 16),
          Text(
            'Ready to Localize',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 12),
          Text(
            'Tap the localize button to find your current location',
            style: TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildCapturingDirectionsContent() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.camera_alt, color: Colors.green, size: 48),
          SizedBox(height: 16),
          Text(
            'Capture Direction ${_capturedDirections.length + 1} of ${_directionNames.length}',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 12),
          Text(
            'Point camera towards ${_directionNames[_currentDirectionIndex]} and tap capture',
            style: TextStyle(color: Colors.white70, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 12),
          LinearProgressIndicator(
            value: _capturedDirections.length / _directionNames.length,
            backgroundColor: Colors.grey[700],
            valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
          ),
          SizedBox(height: 8),
          Text(
            '${_capturedDirections.length}/${_directionNames.length} directions captured',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingLocationContent() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            'Processing Location',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 12),
          Text(
            'Analyzing captured images to identify your location...',
            style: TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }



  Widget _buildRouteSelectionContent() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.route, color: Colors.blue, size: 24),
              SizedBox(width: 8),
              Text(
                'Available Routes',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
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
                        margin: EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(Icons.directions, color: Colors.green, size: 24),
                          title: Text(
                            route.endNodeName,
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            route.pathName,
                            style: TextStyle(color: Colors.white70),
                          ),
                          trailing: Icon(Icons.arrow_forward_ios, color: Colors.white),
                          onTap: () => _selectRoute(route),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteConfirmationContent() {
    if (_selectedRoute == null) return Container();

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 24),
              SizedBox(width: 8),
              Text(
                'Confirm Route',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          SizedBox(height: 16),

          Card(
            color: Colors.grey[800],
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.location_on, color: Colors.red, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Destination: ${_selectedRoute!.endNodeName}',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.route, color: Colors.blue, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Route: ${_selectedRoute!.pathName}',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.flag, color: Colors.orange, size: 20),
                      SizedBox(width: 8),
                      Text(
                        '${_selectedRoute!.waypoints.length} waypoints',
                        style: TextStyle(color: Colors.orange, fontSize: 14),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationContent() {
    return Container(); // Navigation controls moved to action buttons
  }

  Widget _buildActionButtons() {
    switch (_screenState) {
      case NavigationScreenState.initializing:
        return SizedBox.shrink();
        
      case NavigationScreenState.readyToLocalize:
        return ElevatedButton.icon(
          onPressed: _isCameraInitialized ? _startLocalizationProcess : null,
          icon: Icon(Icons.location_searching, size: 24),
          label: Text('Start Localization'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            minimumSize: Size(double.infinity, 50),
            textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );

      case NavigationScreenState.capturingDirections:
        return ElevatedButton.icon(
          onPressed: _isCameraInitialized ? _captureDirection : null,
          icon: Icon(Icons.camera_alt, size: 24),
          label: Text('Capture ${_directionNames[_currentDirectionIndex]}'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            minimumSize: Size(double.infinity, 50),
            textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );

      case NavigationScreenState.processingLocation:
        return SizedBox.shrink();

      case NavigationScreenState.selectingRoute:
        return ElevatedButton.icon(
          onPressed: _startLocalizationProcess,
          icon: Icon(Icons.refresh, size: 20),
          label: Text('Relocalize'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.grey[700],
            foregroundColor: Colors.white,
            minimumSize: Size(double.infinity, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
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
                icon: Icon(Icons.arrow_back, size: 20),
                label: Text('Back'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[700],
                  foregroundColor: Colors.white,
                  minimumSize: Size(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _startNavigation,
                icon: Icon(Icons.navigation, size: 20),
                label: Text('Start Navigation'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  minimumSize: Size(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        );

      case NavigationScreenState.navigating:
        return Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _restartNavigationFromBeginning,
                icon: Icon(Icons.refresh, size: 20),
                label: Text('Reorient'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  minimumSize: Size(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _stopAndReturnToMain,
                icon: Icon(Icons.stop, size: 20),
                label: Text('Stop'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  minimumSize: Size(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        );
    }
  }

  Future<void> _captureDirection() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      _onError('Camera not ready');
      return;
    }

    try {
      setState(() {
        _statusMessage = 'Capturing ${_directionNames[_currentDirectionIndex]}...';
      });

      final image = await _cameraController!.takePicture();
      final imageFile = File(image.path);

      _capturedFrames.add(imageFile);
      _capturedDirections.add(_directionNames[_currentDirectionIndex]);

      _currentDirectionIndex++;

      if (_currentDirectionIndex >= _directionNames.length) {
        // All directions captured, process location
        await _processCapturedDirections();
      } else {
        // Move to next direction
        setState(() {
          _statusMessage = 'Point camera towards ${_directionNames[_currentDirectionIndex]} and tap "Capture ${_directionNames[_currentDirectionIndex]}"';
        });
      }
    } catch (e) {
      _onError('Failed to capture direction: $e');
    }
  }

  Future<void> _processCapturedDirections() async {
    setState(() {
      _screenState = NavigationScreenState.processingLocation;
      _statusMessage = 'Processing captured directions...';
    });

    try {
      // Use the localization service to process all captured frames
      final location = await _localizationService.localizePositionFromDirections(_capturedFrames);
      
      // Clean up temp files
      for (final frame in _capturedFrames) {
        await frame.delete();
      }

      if (location != null) {
        _currentLocation = location;
        setState(() {
          _localizationResult = '📍 ${location.nodeName} (${(location.similarity * 100).round()}% similarity)';
          _showLocalizationResult = true;
        });
        await _loadAvailableRoutes();
      } else {
        setState(() {
          _screenState = NavigationScreenState.readyToLocalize;
          _statusMessage = 'Unable to determine location. Please try again from a different position.';
          _localizationResult = '❌ No location found';
          _showLocalizationResult = true;
        });
      }
    } catch (e) {
      _onError('Failed to process directions: $e');
      setState(() {
        _screenState = NavigationScreenState.readyToLocalize;
        _localizationResult = '❌ No location found';
        _showLocalizationResult = true;
      });
    }
  }

  Future<void> _stopAndReturnToMain() async {
    await _navigationService.stopNavigation();
    setState(() {
      _screenState = NavigationScreenState.readyToLocalize;
      _selectedRoute = null;
      _currentLocation = null;
      _availableRoutes = [];
      _currentInstruction = null;
      _statusMessage = 'Ready to start localization';
    });
  }

  Future<void> _restartNavigationFromBeginning() async {
    if (_selectedRoute != null) {
      await _navigationService.stopNavigation();
      await _navigationService.startNavigation(_selectedRoute!);
      // Optionally reset any progress if the service supports it
    }
  }
}

enum NavigationScreenState {
  initializing,
  readyToLocalize,
  capturingDirections,
  processingLocation,
  selectingRoute,
  confirmingRoute,
  navigating,
}
