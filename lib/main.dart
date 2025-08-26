import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/admin/admin_home_screen.dart';
import 'screens/common/profile_screen.dart';
import 'services/supabase_service.dart';
import 'screens/admin/admin_panel.dart';
import 'screens/admin/image_test_screen.dart';
import 'auth/auth_wrapper.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  
  // Only set orientation on mobile platforms
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  // Only request permissions on Android (not web)
  if (!kIsWeb && Platform.isAndroid) {
    await [
      Permission.camera,
      Permission.location,
    ].request();
  }

  final supabaseService = SupabaseService();
  await supabaseService.initialize();

  // Get cameras (empty list on web since camera access is different)
  final cameras = kIsWeb ? <CameraDescription>[] : await availableCameras();

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
      // Use AuthWrapper for proper authentication flow
      home: AuthWrapper(cameras: cameras),
      routes: {
        '/admin': (context) => const AdminPanel(),
        '/profile': (context) => const ProfileScreen(),
        '/admin_home': (context) => AdminHomeScreen(cameras: cameras),
        '/image_test': (context) => const ImageTestScreen(),
      },
    );
  }
}