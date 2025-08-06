import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/admin/admin_home_screen.dart';
import 'screens/common/profile_screen.dart';
import 'services/supabase_service.dart';
import 'auth/auth_wrapper.dart';
import 'admin/admin_panel.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  if (Platform.isAndroid) {
    await [
      Permission.camera,
      Permission.location,
    ].request();
  }

  final supabaseService = SupabaseService();
  await supabaseService.initialize();

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
