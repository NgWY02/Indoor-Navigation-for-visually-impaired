import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/admin/admin_home_screen.dart';
import 'screens/common/profile_screen.dart';
import 'services/supabase_service.dart';
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
        cameras: cameras,
      ),
      routes: {
        '/admin': (context) => const AdminPanel(),
        '/profile': (context) => const ProfileScreen(),
        '/admin_home': (context) => AdminHomeScreen(cameras: cameras),
      },
    );
  }
}

