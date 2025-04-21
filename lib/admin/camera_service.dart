import 'dart:io';
import 'package:camera/camera.dart';
import 'package:video_player/video_player.dart';

class CameraService {
  // Camera and video recording
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool isRecording = false;
  bool isCameraInitialized = false;
  XFile? videoFile;
  VideoPlayerController? videoPlayerController;
  bool isVideoLoaded = false;

  Future<void> initializeCamera() async {
    _cameras = await availableCameras();
    if (_cameras!.isNotEmpty) {
      _cameraController = CameraController(
        _cameras!.first,
        ResolutionPreset.high,
        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      
      await _cameraController!.initialize();
      isCameraInitialized = true;
    }
  }
  
  CameraController? get cameraController => _cameraController;

  Future<void> startRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    
    // Start video recording
    await _cameraController!.startVideoRecording();
    isRecording = true;
  }
  
  Future<void> stopRecording() async {
    if (_cameraController == null || !isRecording) {
      return;
    }
    
    final video = await _cameraController!.stopVideoRecording();
    isRecording = false;
    videoFile = video;
    
    // Initialize video player
    await initializeVideoPlayer();
  }
  
  Future<void> initializeVideoPlayer() async {
    if (videoFile == null) return;
    
    if (videoPlayerController != null) {
      await videoPlayerController!.dispose();
    }
    
    videoPlayerController = VideoPlayerController.file(File(videoFile!.path));
    await videoPlayerController!.initialize();
    
    isVideoLoaded = true;
  }
  
  void resetVideo() {
    videoFile = null;
  }
  
  void dispose() {
    _cameraController?.dispose();
    videoPlayerController?.dispose();
  }
}