import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'recognition_screen.dart';
import 'profile_screen.dart';
import 'services/supabase_service.dart';
import 'services/ui_helper.dart';
import 'auth/auth_wrapper.dart';
import 'admin/admin_panel.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Lock orientation to portrait for better compass functionality
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  // Ensure the system UI is visible in normal mode (not immersive)
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  
  // Request permissions needed for Android
  if (Platform.isAndroid) {
    await [
      Permission.camera,
      Permission.location,
    ].request();
  }
  
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
      routes: {
        '/login': (context) => AuthWrapper(child: HomeScreen(cameras: cameras)),
        '/admin': (context) => const AdminPanel(),
        '/profile': (context) => const ProfileScreen(),
      },
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
      const ProfileScreen(),
    ];
  }

  Future<void> _loadUserRole() async {
    try {
      final isAdmin = await _supabaseService.isAdmin();
      if (mounted) {
        setState(() {
          _isAdmin = isAdmin;
          // Admin panel is now accessible via profile page, not as a separate tab
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
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.location_on),
                label: 'Recognize',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person),
                label: 'Profile',
              ),
              // Admin tab removed from bottom navigation
            ],
          ),
        ),
      ),
    );
  }
}