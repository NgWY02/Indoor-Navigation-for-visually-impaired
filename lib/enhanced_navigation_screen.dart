import 'package:flutter/material.dart';
import 'dart:async';
import 'package:camera/camera.dart';
import 'services/enhanced_navigation_service.dart';
import 'services/pathfinding_service.dart';
import 'services/responsive_helper.dart';
import 'recognition_screen.dart';

class EnhancedNavigationScreen extends StatefulWidget {
  final String mapId;
  final String mapName;

  const EnhancedNavigationScreen({
    Key? key,
    required this.mapId,
    required this.mapName,
  }) : super(key: key);

  @override
  _EnhancedNavigationScreenState createState() => _EnhancedNavigationScreenState();
}

class _EnhancedNavigationScreenState extends State<EnhancedNavigationScreen> {
  final EnhancedNavigationService _navigationService = EnhancedNavigationService();
  
  NavigationState _currentState = NavigationState.idle;
  NavigationProgress? _currentProgress;
  String _currentInstruction = '';
  String? _errorMessage;
  
  NavigationNode? _currentLocation;
  List<NavigationNode> _availableDestinations = [];
  NavigationNode? _selectedDestination;
  
  late StreamSubscription _stateSubscription;
  late StreamSubscription _progressSubscription;
  late StreamSubscription _instructionSubscription;
  late StreamSubscription _errorSubscription;
  
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeNavigation();
  }

  @override
  void dispose() {
    _stateSubscription.cancel();
    _progressSubscription.cancel();
    _instructionSubscription.cancel();
    _errorSubscription.cancel();
    _navigationService.dispose();
    super.dispose();
  }

  Future<void> _initializeNavigation() async {
    try {
      bool success = await _navigationService.initialize();
      
      if (success) {
        // Set up stream listeners
        _stateSubscription = _navigationService.stateStream.listen((state) {
          setState(() => _currentState = state);
          
          if (state == NavigationState.selectingDestination) {
            _loadDestinations();
          }
        });
        
        _progressSubscription = _navigationService.progressStream.listen((progress) {
          setState(() => _currentProgress = progress);
        });
        
        _instructionSubscription = _navigationService.instructionStream.listen((instruction) {
          setState(() => _currentInstruction = instruction);
        });
        
        _errorSubscription = _navigationService.errorStream.listen((error) {
          setState(() => _errorMessage = error);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error), backgroundColor: Colors.red),
          );
        });
        
        setState(() => _isInitialized = true);
      } else {
        setState(() {
          _errorMessage = 'Failed to initialize navigation system';
          _isInitialized = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Navigation initialization error: $e';
        _isInitialized = false;
      });
    }
  }

  Future<void> _startLocalization() async {
    setState(() => _errorMessage = null);
    
    NavigationNode? location = await _navigationService.localizePosition(widget.mapId);
    
    if (location != null) {
      setState(() => _currentLocation = location);
    }
  }

  Future<void> _loadDestinations() async {
    try {
      List<NavigationNode> destinations = await _navigationService.getAvailableDestinations();
      setState(() => _availableDestinations = destinations);
    } catch (e) {
      setState(() => _errorMessage = 'Error loading destinations: $e');
    }
  }

  Future<void> _startNavigation() async {
    if (_selectedDestination == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a destination first')),
      );
      return;
    }
    
    setState(() => _errorMessage = null);
    await _navigationService.startNavigation(_selectedDestination!);
  }

  void _pauseNavigation() {
    _navigationService.pauseNavigation();
  }

  void _resumeNavigation() {
    _navigationService.resumeNavigation();
  }

  void _cancelNavigation() {
    _navigationService.cancelNavigation();
    setState(() {
      _selectedDestination = null;
      _currentProgress = null;
      _currentInstruction = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Navigation - ${widget.mapName}',
          style: TextStyle(fontSize: ResponsiveHelper.getTitleFontSize(context)),
        ),
        actions: [
          if (_currentState == NavigationState.navigating)
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'pause':
                    _pauseNavigation();
                    break;
                  case 'resume':
                    _resumeNavigation();
                    break;
                  case 'cancel':
                    _showCancelConfirmation();
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'pause',
                  child: Row(
                    children: [Icon(Icons.pause), SizedBox(width: 8), Text('Pause')],
                  ),
                ),
                const PopupMenuItem(
                  value: 'resume',
                  child: Row(
                    children: [Icon(Icons.play_arrow), SizedBox(width: 8), Text('Resume')],
                  ),
                ),
                const PopupMenuItem(
                  value: 'cancel',
                  child: Row(
                    children: [Icon(Icons.stop, color: Colors.red), SizedBox(width: 8), Text('Cancel')],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: !_isInitialized
          ? _buildInitializationScreen()
          : _buildMainContent(),
    );
  }

  Widget _buildInitializationScreen() {
    return Center(
      child: Padding(
        padding: ResponsiveHelper.getResponsivePadding(context),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            ResponsiveHelper.verticalSpace(context),
            Text(
              'Initializing Navigation System...',
              style: TextStyle(fontSize: ResponsiveHelper.getBodyFontSize(context)),
            ),
            if (_errorMessage != null) ...[
              ResponsiveHelper.verticalSpace(context),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              ResponsiveHelper.verticalSpace(context),
              ElevatedButton(
                onPressed: _initializeNavigation,
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    switch (_currentState) {
      case NavigationState.idle:
        return _buildIdleScreen();
      case NavigationState.locating:
        return _buildLocalizationScreen();
      case NavigationState.selectingDestination:
        return _buildDestinationSelectionScreen();
      case NavigationState.planning:
        return _buildPlanningScreen();
      case NavigationState.navigating:
        return _buildNavigationScreen();
      case NavigationState.reconfirming:
        return _buildReconfirmationScreen();
      case NavigationState.lost:
        return _buildLostScreen();
      case NavigationState.completed:
        return _buildCompletedScreen();
      default:
        return _buildIdleScreen();
    }
  }

  Widget _buildIdleScreen() {
    return Center(
      child: Padding(
        padding: ResponsiveHelper.getResponsivePadding(context),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.navigation,
              size: ResponsiveHelper.getIconSize(context) * 2,
              color: Theme.of(context).primaryColor,
            ),
            ResponsiveHelper.verticalSpace(context),
            Text(
              'Enhanced Navigation',
              style: TextStyle(
                fontSize: ResponsiveHelper.getHeaderFontSize(context),
                fontWeight: FontWeight.bold,
              ),
            ),
            ResponsiveHelper.verticalSpace(context),
            const Text(
              'Start by localizing your position with a 360° scan',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            ResponsiveHelper.verticalSpace(context, multiplier: 2),
            ElevatedButton.icon(
              onPressed: _startLocalization,
              icon: const Icon(Icons.my_location),
              label: const Text('Start Localization'),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, ResponsiveHelper.getButtonHeight(context)),
              ),
            ),
            ResponsiveHelper.verticalSpace(context),
            TextButton(
              onPressed: () async {
                // Get available cameras
                final cameras = await availableCameras();
                if (cameras.isNotEmpty) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => RecognitionScreen(camera: cameras.first),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No camera available')),
                  );
                }
              },
              child: const Text('Or use Recognition Screen'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalizationScreen() {
    return Center(
      child: Padding(
        padding: ResponsiveHelper.getResponsivePadding(context),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(strokeWidth: 6),
            ResponsiveHelper.verticalSpace(context, multiplier: 2),
            Text(
              'Determining Your Location...',
              style: TextStyle(
                fontSize: ResponsiveHelper.getHeaderFontSize(context) * 0.8,
                fontWeight: FontWeight.bold,
              ),
            ),
            ResponsiveHelper.verticalSpace(context),
            const Text(
              'Please rotate slowly in a complete circle while holding your phone steady',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            ResponsiveHelper.verticalSpace(context, multiplier: 2),
            Container(
              padding: ResponsiveHelper.getResponsivePadding(context),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                children: [
                  Icon(Icons.threesixty, size: 48, color: Colors.blue),
                  SizedBox(height: 8),
                  Text('360° Scanning Active'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDestinationSelectionScreen() {
    return Column(
      children: [
        Container(
          padding: ResponsiveHelper.getResponsivePadding(context),
          color: Colors.green.withOpacity(0.1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.green),
                  ResponsiveHelper.horizontalSpace(context, multiplier: 0.5),
                  Text(
                    'Current Location',
                    style: TextStyle(
                      fontSize: ResponsiveHelper.getBodyFontSize(context),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              ResponsiveHelper.verticalSpace(context, multiplier: 0.5),
              Text(
                _currentLocation?.name ?? 'Unknown',
                style: TextStyle(fontSize: ResponsiveHelper.getHeaderFontSize(context) * 0.7),
              ),
            ],
          ),
        ),
        
        Expanded(
          child: Padding(
            padding: ResponsiveHelper.getResponsivePadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select Destination',
                  style: TextStyle(
                    fontSize: ResponsiveHelper.getHeaderFontSize(context) * 0.8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ResponsiveHelper.verticalSpace(context),
                
                Expanded(
                  child: _availableDestinations.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.info_outline, size: 48, color: Colors.grey),
                              SizedBox(height: 16),
                              Text('No destinations available'),
                              Text('Contact administrator to set up navigation paths'),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _availableDestinations.length,
                          itemBuilder: (context, index) {
                            final destination = _availableDestinations[index];
                            final isSelected = _selectedDestination?.id == destination.id;
                            
                            return Card(
                              margin: EdgeInsets.symmetric(
                                vertical: ResponsiveHelper.getSpacing(context, multiplier: 0.25),
                              ),
                              color: isSelected ? Theme.of(context).primaryColor.withOpacity(0.1) : null,
                              child: ListTile(
                                leading: Icon(
                                  Icons.place,
                                  color: isSelected ? Theme.of(context).primaryColor : Colors.grey,
                                ),
                                title: Text(
                                  destination.name,
                                  style: TextStyle(
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                subtitle: destination.description.isNotEmpty 
                                    ? Text(destination.description)
                                    : null,
                                onTap: () {
                                  setState(() {
                                    _selectedDestination = isSelected ? null : destination;
                                  });
                                },
                                trailing: isSelected 
                                    ? Icon(Icons.check, color: Theme.of(context).primaryColor)
                                    : null,
                              ),
                            );
                          },
                        ),
                ),
                
                ResponsiveHelper.verticalSpace(context),
                
                ElevatedButton.icon(
                  onPressed: _selectedDestination != null ? _startNavigation : null,
                  icon: const Icon(Icons.navigation),
                  label: const Text('Start Navigation'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: Size(double.infinity, ResponsiveHelper.getButtonHeight(context)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlanningScreen() {
    return Center(
      child: Padding(
        padding: ResponsiveHelper.getResponsivePadding(context),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            ResponsiveHelper.verticalSpace(context, multiplier: 2),
            Text(
              'Planning Route...',
              style: TextStyle(
                fontSize: ResponsiveHelper.getHeaderFontSize(context) * 0.8,
                fontWeight: FontWeight.bold,
              ),
            ),
            ResponsiveHelper.verticalSpace(context),
            Text(
              'To: ${_selectedDestination?.name ?? 'Unknown'}',
              style: TextStyle(fontSize: ResponsiveHelper.getBodyFontSize(context)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationScreen() {
    if (_currentProgress == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Current instruction banner
        Container(
          width: double.infinity,
          padding: ResponsiveHelper.getResponsivePadding(context),
          color: Theme.of(context).primaryColor,
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current Instruction',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: ResponsiveHelper.getBodyFontSize(context),
                  ),
                ),
                ResponsiveHelper.verticalSpace(context, multiplier: 0.5),
                Text(
                  _currentInstruction.isNotEmpty ? _currentInstruction : 'Follow the path ahead',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: ResponsiveHelper.getHeaderFontSize(context) * 0.7,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        
        Expanded(
          child: Padding(
            padding: ResponsiveHelper.getResponsivePadding(context),
            child: Column(
              children: [
                ResponsiveHelper.verticalSpace(context),
                
                // Progress card
                Card(
                  child: Padding(
                    padding: ResponsiveHelper.getResponsivePadding(context),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Progress',
                              style: TextStyle(
                                fontSize: ResponsiveHelper.getBodyFontSize(context),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${_currentProgress!.progressPercent.toStringAsFixed(0)}%',
                              style: TextStyle(
                                fontSize: ResponsiveHelper.getBodyFontSize(context),
                                color: Theme.of(context).primaryColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        ResponsiveHelper.verticalSpace(context, multiplier: 0.5),
                        LinearProgressIndicator(
                          value: _currentProgress!.progressPercent / 100,
                          backgroundColor: Colors.grey[300],
                        ),
                        ResponsiveHelper.verticalSpace(context),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildStatColumn('Distance', '${_currentProgress!.distanceRemaining.toStringAsFixed(0)}m'),
                            _buildStatColumn('Time', _formatDuration(_currentProgress!.estimatedTimeRemaining)),
                            _buildStatColumn('Confidence', '${(_currentProgress!.confidence * 100).toStringAsFixed(0)}%'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                
                ResponsiveHelper.verticalSpace(context),
                
                // Next step preview
                if (_currentProgress!.nextStep != null) ...[
                  Card(
                    child: Padding(
                      padding: ResponsiveHelper.getResponsivePadding(context),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Next',
                            style: TextStyle(
                              fontSize: ResponsiveHelper.getBodyFontSize(context),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          ResponsiveHelper.verticalSpace(context, multiplier: 0.5),
                          Text(
                            _currentProgress!.nextStep!.instruction,
                            style: TextStyle(fontSize: ResponsiveHelper.getBodyFontSize(context)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  ResponsiveHelper.verticalSpace(context),
                ],
                
                // Position confidence indicator
                Card(
                  color: _getConfidenceColor(_currentProgress!.confidence).withOpacity(0.1),
                  child: Padding(
                    padding: ResponsiveHelper.getResponsivePadding(context),
                    child: Row(
                      children: [
                        Icon(
                          _getConfidenceIcon(_currentProgress!.confidence),
                          color: _getConfidenceColor(_currentProgress!.confidence),
                        ),
                        ResponsiveHelper.horizontalSpace(context, multiplier: 0.5),
                        Expanded(
                          child: Text(
                            _getConfidenceText(_currentProgress!.confidence),
                            style: TextStyle(fontSize: ResponsiveHelper.getBodyFontSize(context)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const Spacer(),
                
                // Control buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pauseNavigation,
                        icon: const Icon(Icons.pause),
                        label: const Text('Pause'),
                      ),
                    ),
                    ResponsiveHelper.horizontalSpace(context),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _showCancelConfirmation,
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      ),
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

  Widget _buildReconfirmationScreen() {
    return Center(
      child: Padding(
        padding: ResponsiveHelper.getResponsivePadding(context),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_searching, size: 64, color: Colors.orange),
            ResponsiveHelper.verticalSpace(context, multiplier: 2),
            Text(
              'Verifying Your Location...',
              style: TextStyle(
                fontSize: ResponsiveHelper.getHeaderFontSize(context) * 0.8,
                fontWeight: FontWeight.bold,
              ),
            ),
            ResponsiveHelper.verticalSpace(context),
            const Text(
              'Please hold your phone steady while we confirm your position',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLostScreen() {
    return Center(
      child: Padding(
        padding: ResponsiveHelper.getResponsivePadding(context),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_off, size: 64, color: Colors.red),
            ResponsiveHelper.verticalSpace(context, multiplier: 2),
            Text(
              'Navigation Lost',
              style: TextStyle(
                fontSize: ResponsiveHelper.getHeaderFontSize(context) * 0.8,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            ResponsiveHelper.verticalSpace(context),
            const Text(
              'Unable to determine your exact location. Please move to a recognizable landmark and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            ResponsiveHelper.verticalSpace(context, multiplier: 2),
            ElevatedButton.icon(
              onPressed: _startLocalization,
              icon: const Icon(Icons.refresh),
              label: const Text('Restart Localization'),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, ResponsiveHelper.getButtonHeight(context)),
              ),
            ),
            ResponsiveHelper.verticalSpace(context),
            TextButton(
              onPressed: _cancelNavigation,
              child: const Text('Cancel Navigation'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompletedScreen() {
    return Center(
      child: Padding(
        padding: ResponsiveHelper.getResponsivePadding(context),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, size: 64, color: Colors.green),
            ResponsiveHelper.verticalSpace(context, multiplier: 2),
            Text(
              'Navigation Complete!',
              style: TextStyle(
                fontSize: ResponsiveHelper.getHeaderFontSize(context) * 0.8,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            ResponsiveHelper.verticalSpace(context),
            Text(
              'You have arrived at ${_selectedDestination?.name ?? 'your destination'}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: ResponsiveHelper.getBodyFontSize(context)),
            ),
            ResponsiveHelper.verticalSpace(context, multiplier: 2),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _currentState = NavigationState.idle;
                  _selectedDestination = null;
                  _currentProgress = null;
                  _currentInstruction = '';
                });
              },
              icon: const Icon(Icons.home),
              label: const Text('Back to Start'),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, ResponsiveHelper.getButtonHeight(context)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatColumn(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: ResponsiveHelper.getBodyFontSize(context),
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: ResponsiveHelper.getBodyFontSize(context) * 0.8,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    int minutes = duration.inMinutes;
    int seconds = duration.inSeconds % 60;
    return minutes > 0 ? '${minutes}m ${seconds}s' : '${seconds}s';
  }

  Color _getConfidenceColor(double confidence) {
    if (confidence >= 0.8) return Colors.green;
    if (confidence >= 0.5) return Colors.orange;
    return Colors.red;
  }

  IconData _getConfidenceIcon(double confidence) {
    if (confidence >= 0.8) return Icons.wifi;
    if (confidence >= 0.5) return Icons.wifi_2_bar;
    return Icons.wifi_off;
  }

  String _getConfidenceText(double confidence) {
    if (confidence >= 0.8) return 'High accuracy - You\'re on track';
    if (confidence >= 0.5) return 'Moderate accuracy - Stay on course';
    return 'Low accuracy - Verifying location...';
  }

  void _showCancelConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Navigation'),
        content: const Text('Are you sure you want to stop navigation?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Continue'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _cancelNavigation();
            },
            child: const Text('Stop', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
} 