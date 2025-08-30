import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'user_home_screen.dart';

class UserNavigationScreen extends StatelessWidget {
  final List<CameraDescription> cameras;
  
  const UserNavigationScreen({Key? key, required this.cameras}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Show user home screen with navigation and profile options
    return UserHomeScreen(cameras: cameras);
  }
} 