import 'dart:async';
import 'dart:io';
import 'dart:math';
// For CompassPainter potentially

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/supabase_service.dart';
import 'services/clip_service.dart';
import 'package:flutter/foundation.dart'; 

// Utility function for reshaping lists (from navigation_screen)
List reshapeList(List inputList, List<int> shape) {
  if (shape.length == 1) {
    return inputList;
  }

  int total = shape.reduce((a, b) => a * b);
  if (total != inputList.length) {
    throw ArgumentError(
        'Cannot reshape a list of length ${inputList.length} to shape $shape');
  }

  List result = [];
  int chunkSize = inputList.length ~/ shape[0];
  for (int i = 0; i < shape[0]; i++) {
    List chunk = inputList.sublist(i * chunkSize, (i + 1) * chunkSize);
    if (shape.length > 2) {
      chunk = reshapeList(chunk, shape.sublist(1));
    }
    result.add(chunk);
  }
  return result;
}

class CompassPainter extends CustomPainter {
  final double currentHeading;
  final Map<int, bool> scannedDirections;
  final List<double> targetAngles;
  final double
      targetAngle; // This is the specific angle the painter should highlight/focus on
  final double threshold;

  CompassPainter({
    required this.currentHeading,
    required this.scannedDirections,
    required this.targetAngles,
    required this.targetAngle,
    required this.threshold,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;

    final backgroundPaint = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, backgroundPaint);

    final circlePaint = Paint()
      ..color = Colors.white30
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, radius, circlePaint);

    for (var angle in targetAngles) {
      final radian = (angle - 90) * pi / 180;
      final x = center.dx + radius * cos(radian);
      final y = center.dy + radius * sin(radian);

      Color dotColor;
      double dotRadius;

      if (scannedDirections[angle.toInt()] == true) {
        dotColor = Colors.green;
        dotRadius = 5.0;
      } else if ((angle - targetAngle).abs() < 0.1) {
        // Highlight current target
        dotColor =
            Colors.blueAccent; // Use a distinct color for the painter's target
        dotRadius = 7.0;
      } else {
        dotColor = Colors.white60;
        dotRadius = 3.0;
      }

      final dotPaint = Paint()
        ..color = dotColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), dotRadius, dotPaint);
    }

    final headingRadian = (currentHeading - 90) * pi / 180;
    final headingX = center.dx + radius * 0.8 * cos(headingRadian);
    final headingY = center.dy + radius * 0.8 * sin(headingRadian);

    final headingPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawLine(center, Offset(headingX, headingY), headingPaint);

    final arrowPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final arrowPath = Path();
    const arrowSize = 8.0;
    final tipX = center.dx + radius * 0.8 * cos(headingRadian);
    final tipY = center.dy + radius * 0.8 * sin(headingRadian);
    final baseAngle = headingRadian + pi / 2;
    final base1X = tipX + arrowSize * cos(baseAngle);
    final base1Y = tipY + arrowSize * sin(baseAngle);
    final base2X = tipX - arrowSize * cos(baseAngle);
    final base2Y = tipY - arrowSize * sin(baseAngle);
    arrowPath.moveTo(tipX, tipY);
    arrowPath.lineTo(base1X, base1Y);
    arrowPath.lineTo(base2X, base2Y);
    arrowPath.close();
    canvas.drawPath(arrowPath, arrowPaint);

    // Draw target sector for the painter's specific targetAngle
    final bool isPainterTargetAlreadyScanned =
        scannedDirections[targetAngle.toInt()] ?? false;
    if (!isPainterTargetAlreadyScanned) {
      final sectorPaint = Paint()
        ..color = Colors.blueAccent.withOpacity(0.3)
        ..style = PaintingStyle.fill;
      final targetRadianForSector = (targetAngle - 90) * pi / 180;
      final startAngleForSector =
          targetRadianForSector - (threshold * pi / 180);
      final sweepAngleForSector = (threshold * 2 * pi / 180);
      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawArc(
          rect, startAngleForSector, sweepAngleForSector, true, sectorPaint);
    }
  }

  @override
  bool shouldRepaint(CompassPainter oldDelegate) {
    return oldDelegate.currentHeading != currentHeading ||
        oldDelegate.targetAngle != targetAngle ||
        !mapEquals(oldDelegate.scannedDirections,
            scannedDirections); // Use mapEquals for Map comparison
  }
}

class NavigationLocalizationScreen extends StatefulWidget {
  final CameraDescription camera;

  const NavigationLocalizationScreen({Key? key, required this.camera})
      : super(key: key);

  @override
  _NavigationLocalizationScreenState createState() =>
      _NavigationLocalizationScreenState();
}

class _NavigationLocalizationScreenState
    extends State<NavigationLocalizationScreen> {
  late CameraController _cameraController;
  late ClipService _clipService;
  bool _isClipServerReady = false;
  Map<String, List<double>> _storedEmbeddings = {};
  String _recognizedPlace = "Ready to scan"; // Initial state
  double _confidence = 0.0;
  bool _isLoading = true;

  // TTS related variables
  late FlutterTts _flutterTts;
  String _lastSpokenText = "";
  bool _isSpeaking = false;
  double _speechVolume = 1.0;

  // 360° Scan variables
  bool _isScanning360 = false;
  List<Map<String, dynamic>> _scan360Results =
      []; // To store {'embedding': List<double>, 'heading': double}
  double? _currentHeading;
  StreamSubscription<CompassEvent>? _compassSubscription360;
  Timer? _scan360Timer;
  final int _totalScansNeeded = 18; // 360 / 20 = 18 intervals
  final List<double> _targetAngles =
      List.generate(18, (i) => i * 20.0); // 0, 20, 40, ..., 340
  final double _captureAngleThreshold = 10.0; // +/- 10 degrees (half of 20)
  late Map<int, bool> _scannedDirections;
  String _scanGuidance = "";
  int _scanCount360 = 0;
  double _currentPainterTargetAngle = 0.0;

  // Dwell time variables
  int?
      _angleBeingDwelledOn; // The specific target angle (e.g., 0, 20, 40) currently being aimed at
  DateTime? _dwellStartTime;
  final Duration _requiredDwellDuration =
      const Duration(milliseconds: 750); // e.g., 0.75 seconds

  // Debug helper
  void _debugLog(String message) {
    print('[NavigationLocalizationScreen] $message');
  }

  @override
  void initState() {
    super.initState();
    _debugLog('initState called');
    _reset360ScanState(); // Initialize scan state

    _requestPermissions();
    _initializeCamera();
    _loadModel();
    _loadEmbeddingsFromSupabase();
    _initializeCompassFor360Scan(); // Initialize compass for scanning
    _initializeTts();
  }

  Future<void> _requestPermissions() async {
    _debugLog('Requesting permissions');
    if (Platform.isAndroid) {
      final status = await [
        Permission.camera,
        Permission.location, // For compass
        Permission.microphone, // For TTS (optional, but good practice)
      ].request();
      _debugLog('Permission status: $status');
    }
  }

  Future<void> _initializeCamera() async {
    _debugLog('Initializing camera');
    _cameraController = CameraController(
      widget.camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420, // Match navigation_screen
    );

    try {
      await _cameraController.initialize();
      await _cameraController.setFlashMode(FlashMode.off);
      _debugLog('Camera initialized successfully');
      if (mounted) {
        setState(() {
          // _isLoading might still be true due to model/embeddings
        });
      }
    } catch (e) {
      _debugLog('Error initializing camera: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _recognizedPlace = "Camera error: $e";
        });
      }
    }
  }

  Future<void> _loadModel() async {
    _debugLog('Initializing CLIP service');
    try {
      _clipService = ClipService();
      _isClipServerReady = await _clipService.isServerAvailable();
      if (_isClipServerReady) {
        _debugLog('CLIP service initialized successfully');
      } else {
        _debugLog('CLIP server not ready - will use fallback');
      }
    } catch (e) {
      _debugLog('Error initializing CLIP service: $e');
      _isClipServerReady = false;
      if (mounted) {
        setState(() {
          _isLoading = false;
          _recognizedPlace = "CLIP service error: $e";
        });
      }
    }
  }

  Future<void> _loadEmbeddingsFromSupabase() async {
    _debugLog('Loading embeddings from Supabase');
    setState(() {
      _isLoading = true; // Set loading true at the start
      _recognizedPlace = "Loading locations...";
    });
    try {
      final supabaseService = SupabaseService();
      final embeddings = await supabaseService.getAllEmbeddings();
      _debugLog('Embeddings loaded, found ${embeddings.length} locations');

      if (embeddings.isNotEmpty) {
        _debugLog('Available locations: ${embeddings.keys.join(", ")}');
      }

      if (mounted) {
        setState(() {
          _storedEmbeddings = embeddings;
          _isLoading = false;
          if (_storedEmbeddings.isEmpty) {
            _recognizedPlace = "No locations found.";
            _speak(
                "No locations found in the database. Please add some first.");
          } else {
            _recognizedPlace = "Ready to scan.";
            _speak("Ready for 360 degree scan. Tap start scan when ready.");
          }
        });
      }
    } catch (e) {
      _debugLog('Error loading embeddings: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _recognizedPlace = "Error loading locations.";
        });
      }
    }
  }

  Future<void> _initializeTts() async {
    _debugLog('Initializing TTS');
    _flutterTts = FlutterTts();
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(_speechVolume);
    await _flutterTts.setPitch(1.0);
    _flutterTts.setCompletionHandler(() {
      if (mounted) setState(() => _isSpeaking = false);
    });
    _debugLog('TTS initialized');
  }

  Future<void> _speak(String text) async {
    if (_isSpeaking ||
        text.isEmpty ||
        text == _lastSpokenText &&
            text != "Scan complete. Processing results.") {
      // Allow "Scan complete" to be spoken even if it was the last message (e.g. after stop)
      return;
    }
    if (mounted) {
      setState(() {
        _isSpeaking = true;
        _lastSpokenText = text;
      });
    }
    await _flutterTts.speak(text);
  }

  void _initializeCompassFor360Scan() {
    _debugLog('Initializing compass for 360 scan');
    if (FlutterCompass.events == null) {
      _debugLog('Compass not available on this device');
      setState(() => _scanGuidance = "Compass not available.");
      return;
    }
    _compassSubscription360 = FlutterCompass.events!.listen((event) {
      if (mounted && event.heading != null) {
        setState(() {
          _currentHeading = event.heading;
          if (_isScanning360) {
            // Potentially update text guidance based on current heading vs next target
            _updateScanGuidanceText();
          }
        });
      }
    });
  }

  void _reset360ScanState() {
    _scannedDirections = Map.fromIterable(_targetAngles,
        key: (angle) => angle.toInt(), value: (_) => false);
    _scanCount360 = 0;
    _scan360Results = [];
    _scanGuidance = "Tap 'Start 360 Scan'";
    _recognizedPlace =
        _storedEmbeddings.isEmpty ? "No locations found." : "Ready to scan.";
    _confidence = 0.0;
  }

  void _start360Scan() {
    if (_isScanning360) return;
    if (_storedEmbeddings.isEmpty) {
      _speak("Cannot start scan. No locations loaded from database.");
      setState(() => _recognizedPlace = "No locations loaded.");
      return;
    }

    _debugLog('Starting 360 scan');
    _reset360ScanState(); // Ensure a clean state
    setState(() {
      _isScanning360 = true;
      _recognizedPlace = "Scanning..."; // Update main status
      _scanGuidance = "Initializing scan...";
    });
    _speak("Starting 360 degree scan. Please turn slowly.");

    _updateScanGuidanceText(); // Initial guidance

    _scan360Timer?.cancel();
    _scan360Timer = Timer.periodic(const Duration(milliseconds: 750), (timer) {
      // Check more frequently
      if (!_isScanning360) {
        timer.cancel();
        return;
      }
      if (_allDirectionsScanned360()) {
        timer.cancel();
        _speak("Scan complete. Processing results.");
        _process360ScanResults();
      } else {
        _checkAndCaptureFor360Scan();
      }
    });
  }

  void _stop360Scan() {
    _debugLog('Stopping 360 scan');
    _scan360Timer?.cancel();
    if (mounted) {
      setState(() {
        _isScanning360 = false;
        // Decide what to do with partial results, for now, we discard and reset
        _recognizedPlace = "Scan stopped.";
        _speak("Scan stopped.");
        _reset360ScanState(); // Reset to initial state
      });
    }
  }

  bool _allDirectionsScanned360() {
    return !_scannedDirections.containsValue(false);
  }

  double _getAngleDifference(double angle1, double angle2) {
    double diff = (angle1 - angle2).abs() % 360;
    return diff > 180 ? 360 - diff : diff;
  }

  String _getDirectionName(int angle) {
    int normalizedAngle = angle % 360;
    if (normalizedAngle >= 348.75 || normalizedAngle < 11.25) return "North";
    if (normalizedAngle >= 11.25 && normalizedAngle < 33.75)
      return "North-Northeast";
    if (normalizedAngle >= 33.75 && normalizedAngle < 56.25) return "Northeast";
    // ... (add all 16 compass points from navigation_screen)
    if (normalizedAngle >= 56.25 && normalizedAngle < 78.75)
      return "East-Northeast";
    if (normalizedAngle >= 78.75 && normalizedAngle < 101.25) return "East";
    if (normalizedAngle >= 101.25 && normalizedAngle < 123.75)
      return "East-Southeast";
    if (normalizedAngle >= 123.75 && normalizedAngle < 146.25)
      return "Southeast";
    if (normalizedAngle >= 146.25 && normalizedAngle < 168.75)
      return "South-Southeast";
    if (normalizedAngle >= 168.75 && normalizedAngle < 191.25) return "South";
    if (normalizedAngle >= 191.25 && normalizedAngle < 213.75)
      return "South-Southwest";
    if (normalizedAngle >= 213.75 && normalizedAngle < 236.25)
      return "Southwest";
    if (normalizedAngle >= 236.25 && normalizedAngle < 258.75)
      return "West-Southwest";
    if (normalizedAngle >= 258.75 && normalizedAngle < 281.25) return "West";
    if (normalizedAngle >= 281.25 && normalizedAngle < 303.75)
      return "West-Northwest";
    if (normalizedAngle >= 303.75 && normalizedAngle < 326.25)
      return "Northwest";
    if (normalizedAngle >= 326.25 && normalizedAngle < 348.75)
      return "North-Northwest";
    return "$normalizedAngle°";
  }

  String _getTurnDirection(double currentAngle, double targetAngle) {
    currentAngle %= 360;
    targetAngle %= 360;
    double clockwise = (targetAngle - currentAngle + 360) % 360;
    double counterClockwise = (currentAngle - targetAngle + 360) % 360;
    return clockwise <= counterClockwise ? "right" : "left";
  }

  void _updateScanGuidanceText() {
    String newGuidance =
        ""; // Initialize to prevent uninitialized access if conditions not met
    IconData newIcon = Icons.explore;
    bool shouldSpeakGuidance = false;

    if (!_isScanning360 || _currentHeading == null) {
      newGuidance = _isScanning360 ? "Waiting for compass..." : "Ready";
      newIcon =
          _isScanning360 ? Icons.hourglass_empty : Icons.play_circle_outline;
      // Don't speak "Waiting for compass" too often, only if state changes to this.
      if (newGuidance != _scanGuidance) {
        shouldSpeakGuidance =
            _isScanning360; // Speak if actively scanning and waiting
      }
      setState(() {
        _scanGuidance = newGuidance;
        // _guidanceIcon = newIcon; // If we add an icon state variable
        if (_isScanning360) {
          _currentPainterTargetAngle =
              _targetAngles.isNotEmpty ? _targetAngles.first : 0.0;
        }
      });
      if (shouldSpeakGuidance) _speak(newGuidance);
      return;
    }

    if (_allDirectionsScanned360()) {
      newGuidance = "All directions scanned. Processing...";
      newIcon = Icons.celebration;
      if (newGuidance != _scanGuidance) shouldSpeakGuidance = true;
      setState(() {
        _scanGuidance = newGuidance;
        // _guidanceIcon = newIcon;
        _currentPainterTargetAngle = _currentHeading ?? _targetAngles.first;
      });
      if (shouldSpeakGuidance) _speak(newGuidance);
      return;
    }

    // _currentPainterTargetAngle should already be set to the next unscanned angle by successful scan logic
    double actualNextTargetForTextGuidance = _currentPainterTargetAngle;
    String actualTargetNameForText =
        _getDirectionName(actualNextTargetForTextGuidance.toInt());
    double diffToActualNextTarget =
        _getAngleDifference(_currentHeading!, actualNextTargetForTextGuidance);

    if (diffToActualNextTarget <= _captureAngleThreshold) {
      newGuidance = "Perfect! Hold steady at $actualTargetNameForText";
      newIcon = Icons.check_circle;
      // Only speak "Perfect" or "Hold Steady" if it's a new state or different target
      if (newGuidance != _scanGuidance) shouldSpeakGuidance = true;
    } else {
      String turnDir =
          _getTurnDirection(_currentHeading!, actualNextTargetForTextGuidance);
      newGuidance =
          "Turn $turnDir to $actualTargetNameForText (${diffToActualNextTarget.round()}°)";
      newIcon = turnDir == "right" ? Icons.arrow_forward : Icons.arrow_back;
      // Always speak turn instructions if they are different from previous guidance
      if (newGuidance != _scanGuidance) shouldSpeakGuidance = true;
    }

    bool painterTargetChanged =
        _currentPainterTargetAngle != actualNextTargetForTextGuidance;

    if (newGuidance != _scanGuidance || painterTargetChanged) {
      setState(() {
        _scanGuidance = newGuidance;
        _currentPainterTargetAngle =
            actualNextTargetForTextGuidance; // Ensure painter target is consistent
        // _guidanceIcon = newIcon;
      });
      if (shouldSpeakGuidance) {
        _speak(newGuidance);
      }
    }
  }

  Future<void> _checkAndCaptureFor360Scan() async {
    if (!_isScanning360 ||
        _currentHeading == null ||
        !_cameraController.value.isInitialized) {
      // If not scanning or no heading, reset any active dwelling state
      if (_angleBeingDwelledOn != null) {
        _debugLog(
            "Scan conditions not met, resetting dwell on $_angleBeingDwelledOn");
        _angleBeingDwelledOn = null;
        _dwellStartTime = null;
      }
      _updateScanGuidanceText();
      return;
    }

    bool captureMadeThisTick = false;
    int? currentlyAlignedUnscannedAngle = null;

    // First, check if we are aligned with ANY unscanned target
    for (var targetAngleIter in _targetAngles) {
      int angleInt = targetAngleIter.toInt();
      if (_scannedDirections[angleInt] == false) {
        double diff = _getAngleDifference(_currentHeading!, targetAngleIter);
        if (diff <= _captureAngleThreshold) {
          currentlyAlignedUnscannedAngle = angleInt;
          break; // Found an angle we are aligned with
        }
      }
    }

    if (currentlyAlignedUnscannedAngle != null) {
      // User is aligned with an unscanned target: `currentlyAlignedUnscannedAngle`
      if (_angleBeingDwelledOn != currentlyAlignedUnscannedAngle) {
        // Just entered this new target zone, or switched from another
        _debugLog(
            "Now dwelling on target: $currentlyAlignedUnscannedAngle. Current heading: $_currentHeading");
        _angleBeingDwelledOn = currentlyAlignedUnscannedAngle;
        _dwellStartTime = DateTime.now();
        // Guidance will be updated by _updateScanGuidanceText to "Hold steady..."
      } else {
        // Still dwelling on the same target `currentlyAlignedUnscannedAngle`
        if (_dwellStartTime != null &&
            DateTime.now().difference(_dwellStartTime!) >=
                _requiredDwellDuration) {
          _debugLog(
              "Dwell time met for $currentlyAlignedUnscannedAngle. Attempting capture.");
          bool success = await _captureAndStoreEmbedding();
          captureMadeThisTick = true;

          if (success) {
            if (mounted) {
              _scannedDirections[currentlyAlignedUnscannedAngle] = true;
              _scanCount360++;
              // Updated debug log for clarity and to show the map state
              _debugLog(
                  'Successfully scanned angle: $currentlyAlignedUnscannedAngle. Scan count: $_scanCount360/$_totalScansNeeded. Scanned directions map: $_scannedDirections');

              String successMessage =
                  "${_getDirectionName(currentlyAlignedUnscannedAngle)} scanned (${_scanCount360}/${_totalScansNeeded})";
              // _debugLog(successMessage); // Original log, now covered by the one above mostly

              int newNextTargetAngle = _targetAngles
                  .firstWhere((a) => _scannedDirections[a.toInt()] == false,
                      orElse: () => -1)
                  .toInt();

              setState(() {
                if (newNextTargetAngle != -1) {
                  _currentPainterTargetAngle = newNextTargetAngle.toDouble();
                } else if (_allDirectionsScanned360()) {
                  // Handled by _updateScanGuidanceText
                }
              });
              _speak(
                  "${_getDirectionName(currentlyAlignedUnscannedAngle)} scanned.");
              HapticFeedback.mediumImpact();
            }
          } else {
            _debugLog(
                "Capture failed for $currentlyAlignedUnscannedAngle despite dwell.");
          }
          // Reset dwell state AFTER capture attempt (success or fail) for this angle
          _angleBeingDwelledOn = null;
          _dwellStartTime = null;
        } else {
          _debugLog(
              "Still dwelling on $currentlyAlignedUnscannedAngle, time not met. Started: $_dwellStartTime, Now: ${DateTime.now()}");
          // Not enough dwell time yet, do nothing, guidance should remain "Hold steady"
        }
      }
    } else {
      // User is NOT aligned with ANY unscanned target right now
      if (_angleBeingDwelledOn != null) {
        _debugLog(
            "Moved out of dwell zone for $_angleBeingDwelledOn. Resetting dwell state.");
        _angleBeingDwelledOn =
            null; // Reset if user moved away from a dwelling target
        _dwellStartTime = null;
      }
    }

    _updateScanGuidanceText();
  }

  Future<bool> _captureAndStoreEmbedding() async {
    if (!_cameraController.value.isInitialized) {
      _debugLog('360Scan: Camera not initialized, skipping capture');
      return false;
    }
    
    if (!_isClipServerReady) {
      _debugLog('360Scan: CLIP server not ready, skipping capture');
      return false;
    }
    
    try {
      final image = await _cameraController.takePicture();
      final File imageFile = File(image.path);

      // Use CLIP service to generate embedding with people removal preprocessing
      final List<double> embedding = await _clipService.generatePreprocessedEmbedding(imageFile);

      _scan360Results.add({
        'embedding': embedding,
        'heading': _currentHeading ?? 0.0, // Store heading at time of capture
      });
      _debugLog('360Scan: Stored CLIP embedding with ${embedding.length} dimensions. Total: ${_scan360Results.length}');
      await imageFile.delete(); // Delete temp image
      return true;
    } catch (e) {
      _debugLog('360Scan: Error capturing or processing image: $e');
      return false;
    }
  }

  void _process360ScanResults() {
    _debugLog(
        "Processing ${_scan360Results.length} scan results for majority vote.");
    if (mounted) {
      setState(() {
        _isScanning360 = false; // Ensure scanning stops
        _recognizedPlace = "Processing results...";
        _confidence = 0.0;
      });
    }

    if (_scan360Results.isEmpty) {
      _debugLog("No scan results to process.");
      if (mounted) setState(() => _recognizedPlace = "No scan data.");
      _speak("No scan data was collected.");
      _reset360ScanState();
      return;
    }
    if (_storedEmbeddings.isEmpty) {
      _debugLog("No stored embeddings to compare against.");
      if (mounted) setState(() => _recognizedPlace = "No stored locations.");
      _speak("No stored locations to compare against.");
      _reset360ScanState();
      return;
    }

    Map<String, int> voteCounts = {};
    Map<String, List<double>> similaritiesPerLocation =
        {}; // To average confidence for majority

    for (var scanData in _scan360Results) {
      List<double> scannedEmbedding = scanData['embedding'];
      String bestMatchForThisScan = "Unknown";
      double highestSimilarityForThisScan = 0.0;

      _storedEmbeddings.forEach((locationName, storedEmbedding) {
        if (scannedEmbedding.length != storedEmbedding.length) {
          _debugLog("Dimension mismatch for $locationName. Skipping.");
          return; // continue to next storedEmbedding
        }
        double similarity =
            _calculateCosineSimilarity(scannedEmbedding, storedEmbedding);
        if (similarity > highestSimilarityForThisScan) {
          highestSimilarityForThisScan = similarity;
          bestMatchForThisScan = locationName;
        }
      });

      // Define a threshold for a vote to count
      const double voteThreshold = 0.6; // Can be adjusted
      if (bestMatchForThisScan != "Unknown" &&
          highestSimilarityForThisScan > voteThreshold) {
        voteCounts[bestMatchForThisScan] =
            (voteCounts[bestMatchForThisScan] ?? 0) + 1;

        // Store similarity for averaging later
        similaritiesPerLocation
            .putIfAbsent(bestMatchForThisScan, () => [])
            .add(highestSimilarityForThisScan);
        _debugLog(
            "Vote for $bestMatchForThisScan with similarity ${(highestSimilarityForThisScan * 100).round()}%");
      } else {
        _debugLog(
            "Scan point did not meet threshold or no match. Similarity: ${(highestSimilarityForThisScan * 100).round()}% for $bestMatchForThisScan");
      }
    }

    if (voteCounts.isEmpty) {
      _debugLog("No location received enough votes above threshold.");
      if (mounted)
        setState(() => _recognizedPlace = "Unknown Location (No consensus)");
      _speak("Could not determine location from scans.");
      _reset360ScanState();
      return;
    }

    // Find the location with the most votes
    String majorityLocation =
        voteCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key;
    int majorityVotes = voteCounts[majorityLocation]!;

    double averageConfidenceForMajority = 0.0;
    if (similaritiesPerLocation.containsKey(majorityLocation) &&
        similaritiesPerLocation[majorityLocation]!.isNotEmpty) {
      List<double> scores = similaritiesPerLocation[majorityLocation]!;
      averageConfidenceForMajority =
          scores.reduce((a, b) => a + b) / scores.length;
    }

    _debugLog(
        "Majority location: $majorityLocation with $majorityVotes votes. Avg Confidence: ${(averageConfidenceForMajority * 100).round()}%");

    // *** Combined Threshold Checks ***
    const double finalConfidenceThreshold = 0.7;
    const int minimumRequiredVotes = 5; // New threshold
    String finalRecognizedPlace;
    double finalConfidence;
    String finalSpeechOutput;
    String reasonForUnknown = ""; // For logging/debugging

    if (majorityVotes >= minimumRequiredVotes &&
        averageConfidenceForMajority >= finalConfidenceThreshold) {
      // Sufficient votes AND sufficient confidence
      _debugLog(
          "Votes ($majorityVotes >= $minimumRequiredVotes) and Confidence (${(averageConfidenceForMajority * 100).round()}% >= ${(finalConfidenceThreshold * 100).round()}%) meet thresholds. Setting location to $majorityLocation.");
      finalRecognizedPlace = majorityLocation;
      finalConfidence = averageConfidenceForMajority;
      // Use the calculated average confidence for the speech output
      finalSpeechOutput =
          "Based on the 360 scan, you are likely at $majorityLocation with ${(averageConfidenceForMajority * 100).round()}% confidence.";
    } else {
      // Either votes or confidence (or both) are too low
      if (majorityVotes < minimumRequiredVotes) {
        reasonForUnknown =
            "Insufficient Votes ($majorityVotes < $minimumRequiredVotes)";
      } else {
        // Must be low confidence if votes were okay
        reasonForUnknown =
            "Low Confidence (${(averageConfidenceForMajority * 100).round()}% < ${(finalConfidenceThreshold * 100).round()}%)";
      }
      _debugLog("$reasonForUnknown. Setting location to Unknown.");
      // Provide a more informative status message
      finalRecognizedPlace = "Unknown Location ($reasonForUnknown)";
      finalConfidence = 0.0; // Set confidence to 0 for Unknown results
      finalSpeechOutput =
          "Could not determine location reliably. $reasonForUnknown.";
      // Optionally reset more state if needed when confidence is low or votes insufficient
      // _reset360ScanState(); // Example: uncomment if you want full reset on failure
    }

    if (mounted) {
      setState(() {
        _recognizedPlace = finalRecognizedPlace;
        _confidence = finalConfidence;
      });
    }
    _speak(finalSpeechOutput);

    // Reset scan state for next scan, but keep result displayed (unless reset above)
    if (mounted) {
      setState(() {
        // Only reset scan-specific tracking, not the result itself
        _scannedDirections = Map.fromIterable(_targetAngles,
            key: (angle) => angle.toInt(), value: (_) => false);
        _scanCount360 = 0;
        _scan360Results = [];
        _scanGuidance = "Ready for new scan";
      });
    }
  }

  double _calculateCosineSimilarity(List<double> vec1, List<double> vec2) {
    if (vec1.length != vec2.length) {
      _debugLog('Cosine Similarity: Vector dimension mismatch!');
      return 0.0;
    }
    double dotProduct = 0.0;
    double normVec1 = 0.0;
    double normVec2 = 0.0;
    for (int i = 0; i < vec1.length; i++) {
      dotProduct += vec1[i] * vec2[i];
      normVec1 += vec1[i] * vec1[i];
      normVec2 += vec2[i] * vec2[i];
    }
    normVec1 = sqrt(normVec1);
    normVec2 = sqrt(normVec2);
    if (normVec1 == 0 || normVec2 == 0) return 0.0;
    return dotProduct / (normVec1 * normVec2);
  }

  @override
  void dispose() {
    _cameraController.dispose();
    // CLIP service uses HTTP client which is automatically disposed
    _debugLog('Disposing CLIP service resources');
    _compassSubscription360?.cancel();
    _scan360Timer?.cancel();
    _flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Indoor Navigation'),
          backgroundColor: Colors.teal,
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(
                _recognizedPlace, // Shows "Loading locations..." or other status
                style: const TextStyle(fontSize: 18),
                textAlign: TextAlign.center,
              ),
              // Omitting Reset/Skip Camera buttons from nav screen as their logic is different here
            ],
          ),
        ),
      );
    }

    // Camera not initialized screen similar to navigation_screen.dart
    if (!_cameraController.value.isInitialized) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Indoor Navigation'),
          backgroundColor: Colors.teal,
        ),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text(
                "Initializing camera...",
                style: TextStyle(fontSize: 18),
              ),
            ],
          ),
        ),
      );
    }

    // Main UI structure
    return Scaffold(
      appBar: AppBar(
        title: const Text('Indoor Navigation'),
        backgroundColor: Colors.teal,
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                CameraPreview(_cameraController),

                // Scan overlay using a new helper method
                if (_isScanning360)
                  Container(
                    color: Colors.black.withOpacity(0.6), // Full overlay color
                    width: double.infinity,
                    height: double.infinity,
                    child: Center(
                        child: _buildScanningOverlayWidget()), // Use new helper
                  ),

                // Status panel (top-left), similar to navigation_screen.dart
                // Remains visible during scan, can be adjusted if needed when not scanning
                Positioned(
                  top: 20,
                  left: 20,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Text(
                        //   "Status: ${_isScanning360 ? 'Scanning' : 'Ready'}",
                        //   style: const TextStyle(color: Colors.white),
                        // ),
                        // const SizedBox(height: 4),
                        // if (_isScanning360) // Show scan count only during scan for this panel
                        //   Text(
                        //     "Scanned: $_scanCount360/$_totalScansNeeded",
                        //     style: const TextStyle(color: Colors.white),
                        //   ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Location information panel
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.teal.shade100, // Match AppBar color scheme
            width: double.infinity,
            child: Column(
              children: [
                Text(
                  // During scan, show guidance from the overlay. After scan, show result.
                  // _scanGuidance will be updated by _updateScanGuidanceText (which is called by compass)
                  // and will be the primary text source for the overlay. This panel can show a summary.
                  _isScanning360
                      ? (_scanGuidance.isNotEmpty
                          ? _scanGuidance
                          : "Scanning...")
                      : _recognizedPlace,
                  style: const TextStyle(
                    fontSize: 22, // Adjusted size
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (!_isScanning360 && _confidence > 0.01)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      "Confidence: ${(_confidence * 100).round()}%",
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
              ],
            ),
          ),

          // Controls
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text("Reload Data"), // Kept specific label
                  onPressed: _isScanning360
                      ? null
                      : () {
                          _loadEmbeddingsFromSupabase();
                          _reset360ScanState();
                        },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orangeAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      textStyle: const TextStyle(fontSize: 16)),
                ),
                ElevatedButton.icon(
                  icon: Icon(_isScanning360
                      ? Icons.stop_circle_outlined
                      : Icons.threesixty),
                  label: Text(_isScanning360 ? "Stop Scan" : "Start 360° Scan"),
                  onPressed: _isLoading
                      ? null
                      : (_isScanning360 ? _stop360Scan : _start360Scan),
                  style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _isScanning360 ? Colors.redAccent : Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      textStyle: const TextStyle(fontSize: 16)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // New helper widget for the scanning overlay
  Widget _buildScanningOverlayWidget() {
    if (_currentHeading == null && _isScanning360) {
      return const Text("Waiting for compass...",
          style: TextStyle(color: Colors.white, fontSize: 18));
    }

    // Angle for the Painter's visual highlight (blue sector and prominent blue dot)
    // This will be the discrete 15-degree angle closest to the current compass heading.
    double angleForPainterHighlight = 0.0;
    if (_currentHeading != null) {
      angleForPainterHighlight = (_currentHeading! / 20.0).round() *
          20.0; // Snap to 20-degree increments
      angleForPainterHighlight = angleForPainterHighlight % 360;
      // Ensure 360 maps to 0 if 0 is a target angle (it is)
      if (angleForPainterHighlight == 360 && _targetAngles.contains(0.0)) {
        angleForPainterHighlight = 0.0;
      }
    } else {
      angleForPainterHighlight =
          _targetAngles.isNotEmpty ? _targetAngles.first : 0.0; // Default
    }

    // The actual next target angle the user needs to reach for an unscanned point.
    // This is used for textual guidance.
    double actualNextTargetForTextGuidance = _currentPainterTargetAngle;
    String actualTargetNameForText =
        _getDirectionName(actualNextTargetForTextGuidance.toInt());

    double diffToActualNextTarget = _currentHeading != null
        ? _getAngleDifference(_currentHeading!, actualNextTargetForTextGuidance)
        : 360.0; // Large diff if no heading, or if scan just started

    IconData guidanceIcon =
        Icons.explore; // Default icon before specific guidance
    String guidanceText = "Align with target"; // Default text

    if (_currentHeading != null) {
      if (diffToActualNextTarget <= _captureAngleThreshold) {
        guidanceIcon = Icons.check_circle;
        guidanceText =
            "Perfect! Hold steady at $actualTargetNameForText"; // Text for visual display
      } else {
        String turnDir = _getTurnDirection(
            _currentHeading!, actualNextTargetForTextGuidance);
        guidanceIcon =
            turnDir == "right" ? Icons.arrow_forward : Icons.arrow_back;
        guidanceText =
            "Turn $turnDir to $actualTargetNameForText (${diffToActualNextTarget.round()}°)"; // Text for visual display
      }
    } else if (_isScanning360) {
      guidanceIcon = Icons.hourglass_empty;
      guidanceText =
          "Waiting for compass to guide you to $actualTargetNameForText";
    }

    int completedDirections = _scannedDirections.values.where((v) => v).length;
    int remainingDirections = _totalScansNeeded - completedDirections;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Compass Painter visual
        SizedBox(
          width: 220, // Consistent size
          height: 220,
          child: CustomPaint(
            painter: CompassPainter(
              currentHeading: _currentHeading ?? 0,
              scannedDirections: _scannedDirections,
              targetAngles: _targetAngles,
              targetAngle:
                  angleForPainterHighlight, // Painter's highlight follows current heading segment
              threshold: _captureAngleThreshold,
            ),
          ),
        ),
        const SizedBox(height: 15),
        // Inner guidance text on the compass (progress, icon, turn advice)
        Text("$completedDirections/$_totalScansNeeded",
            style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Icon(guidanceIcon, color: Colors.white, size: 40),
        Text(guidanceText,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            textAlign: TextAlign.center),
        const SizedBox(height: 20),
        // Detailed text guidance below compass
        Text("$remainingDirections directions remaining",
            style: const TextStyle(color: Colors.white, fontSize: 14)),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40.0),
          child: LinearProgressIndicator(
            value: _totalScansNeeded > 0
                ? completedDirections / _totalScansNeeded
                : 0,
            backgroundColor: Colors.white30,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.tealAccent),
          ),
        ),
      ],
    );
  }
}
