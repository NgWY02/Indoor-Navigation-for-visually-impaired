import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'navigation_main_screen.dart';

class UserNavigationScreen extends StatelessWidget {
  final List<CameraDescription> cameras;
  
  const UserNavigationScreen({Key? key, required this.cameras}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // For visually impaired users, go directly to the comprehensive navigation screen
    return NavigationMainScreen(
      camera: cameras.first,
    );
  }
} 