import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'recognition_screen.dart';
import 'services/supabase_service.dart';
import 'services/ui_helper.dart';
import 'auth/auth_wrapper.dart';
import 'admin/admin_panel.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Ensure the system UI is visible in normal mode (not immersive)
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  
  // Initialize Supabase
  final supabaseService = SupabaseService();
  await supabaseService.initialize();
  
  // Get available cameras
  final cameras = await availableCameras();
  
  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  
  const MyApp({Key? key, required this.cameras}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Indoor Navigation',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: AuthWrapper(
        child: HomeScreen(cameras: cameras),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const HomeScreen({Key? key, required this.cameras}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  late List<Widget> _screens;
  bool _isAdmin = false;
  final SupabaseService _supabaseService = SupabaseService();

  @override
  void initState() {
    super.initState();
    _loadUserRole();
    _screens = [
      RecognitionScreen(camera: widget.cameras.first),
      // CaptureScreen removed
    ];
  }

  Future<void> _loadUserRole() async {
    try {
      final isAdmin = await _supabaseService.isAdmin();
      if (mounted) {
        setState(() {
          _isAdmin = isAdmin;
          // If user is admin, add the admin panel to screens
          if (_isAdmin) {
            _screens.add(const AdminPanel());
          }
        });
      }
    } catch (e) {
      print('Error loading user role: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Indoor Navigation'),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await _supabaseService.signOut();
              },
              tooltip: 'Sign Out',
            ),
          ],
        ),
        body: _selectedIndex < _screens.length 
            ? _screens[_selectedIndex]
            : _screens[0], // Fallback to first screen if index is out of bounds
        bottomNavigationBar: UIHelper.bottomSafeArea(
          child: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            items: [
              const BottomNavigationBarItem(
                icon: Icon(Icons.location_on),
                label: 'Recognize',
              ),
              // "Add Location" tab removed
              if (_isAdmin)
                const BottomNavigationBarItem(
                  icon: Icon(Icons.admin_panel_settings),
                  label: 'Admin',
                ),
            ],
          ),
        ),
      ),
    );
  }
}