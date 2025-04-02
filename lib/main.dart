import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'recognition_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
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
      title: 'Place Recognition',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: RecognitionScreen(camera: cameras.first),
    );
  }
}