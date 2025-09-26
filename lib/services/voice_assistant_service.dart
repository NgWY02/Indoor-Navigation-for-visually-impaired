import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:porcupine_flutter/porcupine_manager.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dinov2_service.dart';
import 'gpt_service.dart';
import 'supabase_service.dart';
import 'real_time_navigation_service.dart';
import '../models/path_models.dart';
import 'position_localization_service.dart';

/// Voice assistant session states
enum VoiceSessionState {
  idle,           // Background wake word detection
  wakeWordDetected, // "Hey Navi" detected, ready to listen
  listening,      // Recording user speech
  processing,     // Converting speech to text + NLU
  executing,      // Performing requested action
  speaking,       // Providing TTS response
  error          // Error state
}

/// Voice command intents
enum VoiceIntent {
  localize,
  navigate,
  recordLocation,
  speakLocation,
  stop,
  repeat,
  explain,
  listNodes,
  unknown
}

/// Voice command data structure
class VoiceCommand {
  final VoiceIntent intent;
  final Map<String, dynamic> parameters;
  final String originalText;
  final double confidence;

  VoiceCommand({
    required this.intent,
    required this.parameters,
    required this.originalText,
    required this.confidence,
  });
}

/// Voice assistant service for hands-free navigation
class VoiceAssistantService {
  static final VoiceAssistantService _instance = VoiceAssistantService._internal();
  factory VoiceAssistantService() => _instance;
  VoiceAssistantService._internal();

  // Core services
  PorcupineManager? _porcupineManager;
  final SpeechToText _speechToText = SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  final GPTService _gptService = GPTService();
  ClipService? _clipService;
  SupabaseService? _supabaseService;
  RealTimeNavigationService? _navigationService;
  PositionLocalizationService? _localizationService;

  // State management
  VoiceSessionState _sessionState = VoiceSessionState.idle;
  String? _currentListenText = '';
  String? _gptApiKey;
  String? _picovoiceAccessKey;
  int _retryCount = 0;

  // Last localization result for explanation
  Map<String, dynamic>? _lastLocalizationResult;
  
  // Callback functions
  Function(VoiceSessionState)? onStateChanged;
  Function(String)? onStatusUpdate;
  Function(String)? onTranscriptUpdate;
  Function(VoiceCommand)? onCommandDetected;
  Function(String)? onError;
  Function(String)? onResponse;

  // Configuration
  static const String WAKE_WORD = "Hey Navi";
  static const int LISTENING_TIMEOUT = 8; // seconds - increased for better speech detection
  static const double MIN_CONFIDENCE = 0.6;
  static const int MAX_RETRY_ATTEMPTS = 2; // Maximum retry attempts for network errors
  
  bool get isInitialized => _porcupineManager != null;
  bool get isListening => _sessionState == VoiceSessionState.listening;
  VoiceSessionState get sessionState => _sessionState;

  /// Initialize the voice assistant
  Future<bool> initialize({
    ClipService? clipService,
    SupabaseService? supabaseService,
    RealTimeNavigationService? navigationService,
    PositionLocalizationService? localizationService,
  }) async {
    try {
      debugPrint('🎤 Initializing Voice Assistant...');
      
      // Store service references
      _clipService = clipService;
      _supabaseService = supabaseService;
      _navigationService = navigationService;
      _localizationService = localizationService;
      
      // Load API keys
      await _loadApiKeys();
      
      // Initialize components
      await _initializeTTS();
      await _initializeSpeechToText();
      await _initializePorcupine();
      
      debugPrint('Voice Assistant initialized successfully');
      return true;
      
    } catch (e) {
      debugPrint('Voice Assistant initialization failed: $e');
      onError?.call('Failed to initialize voice assistant: $e');
      return false;
    }
  }

  /// Load API keys from environment
  Future<void> _loadApiKeys() async {
    try {
      _gptApiKey = dotenv.env['OPENAI_API_KEY'];
      _picovoiceAccessKey = 'AVSvkwsR0pxY0l+huQ8+2DSiDpDW/0vhy4TolkK8XIUq3BpQEGLUbA==';
      
      if (_gptApiKey == null || _gptApiKey!.isEmpty) {
        debugPrint('OpenAI API key not found in .env file');
      } else {
        debugPrint('OpenAI API key loaded');
      }
      
      debugPrint('Picovoice access key configured');
      
    } catch (e) {
      debugPrint('Error loading API keys: $e');
    }
  }

  /// Initialize Text-to-Speech
  Future<void> _initializeTTS() async {
    try {
      await _flutterTts.setLanguage('en-US');
      await _flutterTts.setSpeechRate(0.5); // Slower speech rate
      await _flutterTts.setVolume(0.9);
      await _flutterTts.setPitch(1.0);
      
      // Set completion handler
      _flutterTts.setCompletionHandler(() {
        if (_sessionState == VoiceSessionState.speaking) {
          _updateState(VoiceSessionState.idle);
        }
      });
      
      debugPrint('TTS initialized');
    } catch (e) {
      debugPrint('TTS initialization failed: $e');
      throw e;
    }
  }

  /// Initialize Speech-to-Text
  Future<void> _initializeSpeechToText() async {
    try {
      // Configure speech recognition options
      bool available = await _speechToText.initialize(
        onError: (errorNotification) {
          debugPrint('STT Error: ${errorNotification.errorMsg}');
          // Handle specific error types
          if (errorNotification.errorMsg == 'error_language_unavailable') {
            debugPrint('Language not available, will use device default');
            onError?.call('Speech recognition language not available. Using device default language.');
            _updateState(VoiceSessionState.idle);
          } else if (errorNotification.errorMsg == 'error_network' ||
              errorNotification.errorMsg == 'error_network_timeout') {
            debugPrint('Network error detected, retry count: $_retryCount');
            if (_retryCount < MAX_RETRY_ATTEMPTS) {
              _retryCount++;
              debugPrint('Retrying speech recognition (attempt $_retryCount)');
              onError?.call('Network issue detected. Retrying speech recognition...');
              // Retry after a short delay
              Future.delayed(Duration(seconds: 2), () {
                if (_sessionState == VoiceSessionState.error) {
                  _startListening();
                }
              });
            } else {
              onError?.call('Network connectivity issue. Please check your internet connection and try again.');
              _retryCount = 0; // Reset retry count
              _updateState(VoiceSessionState.idle);
            }
          } else if (errorNotification.errorMsg == 'error_speech_timeout') {
            debugPrint('Speech timeout - possible causes:');
            debugPrint('  - No speech detected (speak louder/clearer)');
            debugPrint('  - Microphone muted or not working');
            debugPrint('  - Another app using microphone');
            debugPrint('  - Device in silent mode');
            onError?.call('No speech detected. Please speak clearly into the microphone and ensure no other apps are using it.');
            _retryCount = 0; // Reset retry count for non-network errors
            _updateState(VoiceSessionState.idle);
            // Restart Porcupine after timeout
            _restartPorcupine();
          } else if (errorNotification.errorMsg == 'error_busy') {
            debugPrint('Speech recognition busy - another app may be using it');
            onError?.call('Speech recognition is busy. Please close other apps that might be using the microphone.');
            _updateState(VoiceSessionState.idle);
            // Restart Porcupine after busy error
            _restartPorcupine();
          } else if (errorNotification.errorMsg == 'error_no_match') {
            debugPrint('Speech detected but no match found');
            onError?.call('Speech was detected but couldn\'t be understood. Please try again.');
            _updateState(VoiceSessionState.idle);
            // Restart Porcupine after no match
            _restartPorcupine();
          } else {
            onError?.call('Speech recognition error: ${errorNotification.errorMsg}');
            _retryCount = 0; // Reset retry count
            _updateState(VoiceSessionState.idle);
            // Restart Porcupine after other errors
            _restartPorcupine();
          }
        },
        onStatus: (status) {
          debugPrint('STT Status: $status');
        },
      );

      if (!available) {
        throw Exception('Speech recognition not available on this device');
      }

      debugPrint('Speech-to-Text initialized');
    } catch (e) {
      debugPrint('STT initialization failed: $e');
      throw Exception('Failed to initialize speech recognition: $e');
    }
  }

  /// Initialize Picovoice Porcupine wake word detection
  Future<void> _initializePorcupine() async {
    try {
      if (_picovoiceAccessKey == null) {
        throw Exception('Picovoice access key not found');
      }

      _porcupineManager = await PorcupineManager.fromKeywordPaths(
        _picovoiceAccessKey!,
        ['assets/wakeword.ppn'], // Custom "Hey Navi" wake word
        _onWakeWordDetected,
        errorCallback: (error) {
          debugPrint('Porcupine Error: ${error.message}');
          onError?.call('Wake word detection error: ${error.message}');
        },
      );
      
      await _porcupineManager!.start();
      debugPrint('Porcupine wake word detection started');
      
    } catch (e) {
      debugPrint('Porcupine initialization failed: $e');
      throw e;
    }
  }

  /// Wake word detected callback
  void _onWakeWordDetected(int keywordIndex) {
    debugPrint('Wake word "Hey Navi" detected!');

    // Provide haptic feedback
    HapticFeedback.lightImpact();

    _updateState(VoiceSessionState.wakeWordDetected);

    // Stop Porcupine to free up microphone for speech recognition
    _stopPorcupineTemporarily().then((_) {
      speak('Listening...');
      _startListeningWithDelay();
    });
  }

  /// Start listening with a small delay to ensure TTS completes
  void _startListeningWithDelay() {
    Future.delayed(Duration(milliseconds: 800), () {
      _startListening();
    });
  }

  /// Check network connectivity before speech recognition
  Future<bool> _checkConnectivity() async {
    try {
      final connectivity = Connectivity();
      final result = await connectivity.checkConnectivity();
      return result != ConnectivityResult.none;
    } catch (e) {
      debugPrint('Connectivity check failed: $e');
      // Assume connected if check fails
      return true;
    }
  }

  /// Check microphone permission
  Future<bool> _checkMicrophonePermission() async {
    try {
      final status = await Permission.microphone.status;
      if (status.isGranted) {
        debugPrint('Microphone permission granted');
        return true;
      } else if (status.isDenied) {
        debugPrint('Microphone permission denied');
        // Try to request permission
        final result = await Permission.microphone.request();
        return result.isGranted;
      } else if (status.isPermanentlyDenied) {
        debugPrint('Microphone permission permanently denied');
        onError?.call('Microphone permission is required for voice assistant. Please enable it in app settings.');
        return false;
      }
      return false;
    } catch (e) {
      debugPrint('Microphone permission check failed: $e');
      return false;
    }
  }

  /// Stop Porcupine temporarily during speech recognition
  Future<void> _stopPorcupineTemporarily() async {
    if (_porcupineManager != null) {
      try {
        debugPrint('Temporarily stopping Porcupine for speech recognition');
        await _porcupineManager!.stop();
        debugPrint('Porcupine stopped');
      } catch (e) {
        debugPrint('Failed to stop Porcupine: $e');
      }
    }
  }

  /// Restart Porcupine after speech recognition
  Future<void> _restartPorcupine() async {
    if (_porcupineManager != null) {
      try {
        // Small delay to ensure speech recognition has fully stopped
        await Future.delayed(Duration(milliseconds: 500));
        debugPrint('Restarting Porcupine wake word detection');
        await _porcupineManager!.start();
        debugPrint('Porcupine restarted');
      } catch (e) {
        debugPrint('Failed to restart Porcupine: $e');
      }
    }
  }

  /// Start listening for user speech
  Future<void> _startListening() async {
    if (!_speechToText.isAvailable) {
      debugPrint('Speech recognition not available');
      onError?.call('Speech recognition not available on this device');
      return;
    }

    // Check microphone permission
    final hasMicPermission = await _checkMicrophonePermission();
    if (!hasMicPermission) {
      debugPrint('Microphone permission not granted');
      onError?.call('Microphone permission required for voice assistant');
      _updateState(VoiceSessionState.idle);
      return;
    }

    // Check connectivity before starting speech recognition
    final hasConnectivity = await _checkConnectivity();
    if (!hasConnectivity) {
      debugPrint('No network connectivity detected');
      onError?.call('No internet connection. Speech recognition may not work properly.');
    }

    // Check if microphone is available
    try {
      // You can add microphone availability check here if needed
      debugPrint('Checking microphone availability...');
    } catch (e) {
      debugPrint('Microphone check failed: $e');
    }

    try {
      _updateState(VoiceSessionState.listening);
      _currentListenText = '';
      _retryCount = 0; // Reset retry count on successful start

      debugPrint('Initializing speech recognition with timeout: ${LISTENING_TIMEOUT}s');

      await _speechToText.listen(
        onResult: _onSpeechResult,
        listenFor: Duration(seconds: LISTENING_TIMEOUT),
        pauseFor: Duration(seconds: 3), // Increased pause time for better detection
        partialResults: true,
        cancelOnError: false, // Let error handler manage instead of canceling
      );

      debugPrint('Started listening...');

    } catch (e) {
      debugPrint('Failed to start listening: $e');
      onError?.call('Failed to start listening. Please check microphone permissions.');
      _updateState(VoiceSessionState.error);
    }
  }

  /// Speech recognition result callback
  void _onSpeechResult(SpeechRecognitionResult result) {
    _currentListenText = result.recognizedWords;
    onTranscriptUpdate?.call(_currentListenText ?? '');

    if (result.finalResult) {
      debugPrint('Final transcript: $_currentListenText');
      _processVoiceCommand(_currentListenText ?? '').then((_) {
        // Restart Porcupine after processing command
        _restartPorcupine();
      });
    }
  }

  /// Process voice command with NLU
  Future<void> _processVoiceCommand(String transcript) async {
    if (transcript.trim().isEmpty) {
      speak('I didn\'t catch that. Please try again.');
      _updateState(VoiceSessionState.idle);
      return;
    }

    try {
      _updateState(VoiceSessionState.processing);
      onStatusUpdate?.call('Understanding command...');
      
      // Use GPT for natural language understanding
      final command = await _parseCommandWithGPT(transcript);
      onCommandDetected?.call(command);
      
      // Execute the command
      await _executeCommand(command);
      
    } catch (e) {
      debugPrint('Command processing failed: $e');
      speak('Sorry, I couldn\'t process that command.');
      _updateState(VoiceSessionState.idle);
    }
  }

  /// Parse command using GPT-5\4-mini for NLU
  Future<VoiceCommand> _parseCommandWithGPT(String transcript) async {
    if (_gptApiKey == null) {
      // Fallback to simple keyword matching
      return _parseCommandSimple(transcript);
    }

    try {
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_gptApiKey',
        },
        body: json.encode({
          'model': 'gpt-4.1-nano',
          'messages': [
            {
              'role': 'system',
              'content': '''You are an intelligent voice assistant for indoor navigation designed for visually impaired users. You understand natural human language and can perform these actions:

CAPABILITIES:
- Find/scan the user's current location using the camera
- Tell the user their current location (if already known)
- Navigate the user to a destination
- Explain why you identified a location a certain way
- List all available navigation routes
- Stop any current action

When the user speaks, understand their natural language request and map it to the most appropriate action. Be flexible with phrasing - people don't always use exact words.

Examples:
- "Where am I?" → hear current location
- "Find my location" → scan and find current location
- "Help me to relocalize" → scan and find current location
- "Relocalize" → scan and find current location
- "What's my location?" → tell current location
- "Take me to the library" → navigate to library
- "Why do you think I'm here?" → explain location reasoning
- "What routes are available?" → list available routes
- "Stop" → stop current action

IMPORTANT: Return the intent EXACTLY as shown in the examples above (natural language phrases with spaces, not underscores or camelCase).

Return ONLY valid JSON: {"intent": "exact phrase from examples", "parameters": {"destination": "extracted_place_name_if_navigating"}, "confidence": 0.95}'''
            },
            {
              'role': 'user',
              'content': transcript
            }
          ],
          'max_completion_tokens': 800,
        }),
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final content = responseData['choices'][0]['message']['content'];
        debugPrint('GPT Raw Response: $content');

        // Parse GPT response
        final commandData = json.decode(content);
        final intentString = commandData['intent'];
        final mappedIntent = _stringToIntent(intentString);

        debugPrint('GPT Intent: "$intentString" → Mapped to: ${mappedIntent.toString()}');

        // If GPT returned unknown intent, fall back to simple parsing
        if (mappedIntent == VoiceIntent.unknown) {
          debugPrint('GPT returned unknown intent, falling back to simple parsing');
          return _parseCommandSimple(transcript);
        }

        return VoiceCommand(
          intent: mappedIntent,
          parameters: Map<String, dynamic>.from(commandData['parameters'] ?? {}),
          originalText: transcript,
          confidence: (commandData['confidence'] ?? 0.8).toDouble(),
        );
      } else {
        throw Exception('GPT API error: ${response.statusCode}');
      }
      
    } catch (e) {
      debugPrint('GPT NLU failed, using simple parsing: $e');
      return _parseCommandSimple(transcript);
    }
  }

  /// Simple keyword-based command parsing (fallback)
  VoiceCommand _parseCommandSimple(String transcript) {
    final text = transcript.toLowerCase();
    debugPrint('🎤 Using simple parsing for: "$transcript"');

    // Check for localize commands first
    if (text.contains('find my location') ||
        text.contains('localize') || text.contains('localise') ||
        text.contains('relocalize') || text.contains('re-localize') ||
        text.contains('scan') || text.contains('surroundings') ||
        (text.contains('help me') && text.contains('relocalize'))) {
      return VoiceCommand(
        intent: VoiceIntent.localize,
        parameters: {},
        originalText: transcript,
        confidence: 0.8,
      );
    } else if (text.contains('what places') || text.contains('available locations') ||
        text.contains('show locations') || text.contains('where can i go') ||
        text.contains('list destinations') || text.contains('what locations') ||
        text.contains('what nodes') || text.contains('available nodes') ||
        (text.contains('is there any') && (text.contains('locations') || text.contains('places') || text.contains('nodes'))) ||
        text.contains('what destinations') || text.contains('recorded places') ||
        text.contains('available routes')) {
      return VoiceCommand(
        intent: VoiceIntent.listNodes,
        parameters: {},
        originalText: transcript,
        confidence: 0.8,
      );
    } else if (text.contains('what\'s my location') || text.contains('where\'s my location') ||
        text.contains('tell me where i am') || text.contains('where am i') || text.contains('where am i right now') ||
        text.contains('current location')) {
      return VoiceCommand(
        intent: VoiceIntent.speakLocation,
        parameters: {},
        originalText: transcript,
        confidence: 0.8,
      );
    } else if (text.contains('take me to') || text.contains('navigate to') || text.contains('go to')) {
      // Extract destination
      String destination = '';
      final patterns = ['take me to ', 'navigate to ', 'go to '];
      for (String pattern in patterns) {
        if (text.contains(pattern)) {
          destination = text.split(pattern)[1].trim();
          break;
        }
      }
      
      return VoiceCommand(
        intent: VoiceIntent.navigate,
        parameters: {'destination': destination},
        originalText: transcript,
        confidence: 0.8,
      );
    } else if (text.contains('record') || text.contains('save location')) {
      return VoiceCommand(
        intent: VoiceIntent.recordLocation,
        parameters: {},
        originalText: transcript,
        confidence: 0.8,
      );
    } else if (text.contains('why do you think') || text.contains('how do you know') ||
        text.contains('explain') || text.contains('what did you see')) {
      return VoiceCommand(
        intent: VoiceIntent.explain,
        parameters: {},
        originalText: transcript,
        confidence: 0.8,
      );
    } else if (text.contains('what places') || text.contains('available locations') ||
        text.contains('show locations') || text.contains('where can i go') ||
        text.contains('list destinations') || text.contains('what locations') ||
        text.contains('what nodes') || text.contains('available nodes') ||
        (text.contains('is there any') && (text.contains('locations') || text.contains('places') || text.contains('nodes'))) ||
        text.contains('what destinations') || text.contains('recorded places')) {
      return VoiceCommand(
        intent: VoiceIntent.listNodes,
        parameters: {},
        originalText: transcript,
        confidence: 0.8,
      );
    } else if (text.contains('stop') || text.contains('cancel')) {
      return VoiceCommand(
        intent: VoiceIntent.stop,
        parameters: {},
        originalText: transcript,
        confidence: 0.9,
      );
    }
    
    return VoiceCommand(
      intent: VoiceIntent.unknown,
      parameters: {},
      originalText: transcript,
      confidence: 0.3,
    );
  }

  /// Convert string to VoiceIntent enum
  VoiceIntent _stringToIntent(String intentString) {
    final intent = intentString.toLowerCase();

    // Handle natural language descriptions from GPT
    if (intent.contains('find_current_location') || intent.contains('find current location') ||
        intent.contains('scan') || intent.contains('localize') || intent.contains('localise') ||
        intent.contains('relocalize') || intent.contains('re-localize') ||
        intent == 'find_current_location') {
      return VoiceIntent.localize;
    } else if (intent.contains('tell current location') || intent.contains('what\'s my location') ||
        intent.contains('speaklocation') || intent.contains('where am i') || intent.contains('where am i right now')) {
      return VoiceIntent.speakLocation;
    } else if (intent.contains('navigate') || intent.contains('take me to') ||
        intent.contains('go to')) {
      return VoiceIntent.navigate;
    } else if (intent.contains('explain') || intent.contains('why do you think')) {
      return VoiceIntent.explain;
    } else if (intent.contains('list available routes') || intent.contains('what routes') ||
        intent.contains('list_nodes')) {
      return VoiceIntent.listNodes;
    } else if (intent.contains('stop') || intent.contains('cancel')) {
      return VoiceIntent.stop;
    }

    // Handle exact enum matches as fallback
    switch (intent) {
      case 'localize': return VoiceIntent.localize;
      case 'navigate': return VoiceIntent.navigate;
      case 'recordlocation': return VoiceIntent.recordLocation;
      case 'speaklocation': return VoiceIntent.speakLocation;
      case 'explain': return VoiceIntent.explain;
      case 'list_nodes': return VoiceIntent.listNodes;
      case 'stop': return VoiceIntent.stop;
      case 'repeat': return VoiceIntent.repeat;
      default: return VoiceIntent.unknown;
    }
  }

  /// Execute parsed voice command
  Future<void> _executeCommand(VoiceCommand command) async {
    _updateState(VoiceSessionState.executing);
    debugPrint('🎤 Executing command: ${command.intent.toString()} (confidence: ${command.confidence})');
    onStatusUpdate?.call('Executing command...');

    try {
      switch (command.intent) {
        case VoiceIntent.localize:
          await _executeLocalize();
          break;
        case VoiceIntent.navigate:
          await _executeNavigate(command.parameters['destination'] ?? '');
          break;
        case VoiceIntent.recordLocation:
          await _executeRecordLocation();
          break;
        case VoiceIntent.speakLocation:
          await _executeSpeakLocation();
          break;
        case VoiceIntent.stop:
          await _executeStop();
          break;
        case VoiceIntent.repeat:
          await _executeRepeat();
          break;
        case VoiceIntent.explain:
          await _executeExplain();
          break;
        case VoiceIntent.listNodes:
          await _executeListNodes();
          break;
        case VoiceIntent.unknown:
          await _executeUnknown(command.originalText);
          break;
      }
        } catch (e) {
          debugPrint('Command execution failed: $e');
          speak('Sorry, I couldn\'t complete that action.');
      _updateState(VoiceSessionState.idle);
    }
  }

  /// Execute localization command
  Future<void> _executeLocalize() async {
    if (_clipService == null) {
      speak('Localization service not available.');
      _updateState(VoiceSessionState.idle);
      return;
    }

    try {
      speak('Starting localization. Please hold still and scan your surroundings.');
      debugPrint('Sending "Enhanced localization requested" to navigation screen');

      // Notify the calling screen to start enhanced localization
      onStatusUpdate?.call('Enhanced localization requested');

      _updateState(VoiceSessionState.idle);
    } catch (e) {
      debugPrint('Localization execution failed: $e');
      speak('Failed to start location detection.');
      _updateState(VoiceSessionState.idle);
    }
  }

  /// Execute navigation command
  Future<void> _executeNavigate(String destination) async {
    if (destination.isEmpty) {
      speak('Where would you like to go?');
      _updateState(VoiceSessionState.idle);
      return;
    }

    // Check if we know current location
    debugPrint('Current localization result: $_lastLocalizationResult');
    if (_lastLocalizationResult == null || _lastLocalizationResult!['nodeId'] == null) {
      speak('I don\'t know your current location. Please say "find my location" to scan and find your location first.');
      _updateState(VoiceSessionState.idle);
      return;
    }

    speak('Searching for route to $destination...');

    try {
      final currentNodeId = _lastLocalizationResult!['nodeId'];
      final currentLocation = _lastLocalizationResult!['detectedLocation'];
      debugPrint('Current location: $currentLocation (nodeId: $currentNodeId)');

      // Load all available routes from current location
      final allRoutes = await _supabaseService?.loadAllPaths();
      if (allRoutes == null || allRoutes.isEmpty) {
        speak('I couldn\'t find any navigation routes. Please make sure routes have been set up by an administrator.');
        _updateState(VoiceSessionState.idle);
        return;
      }

      // Find route that starts from current location and goes to destination
      NavigationRoute? matchingRoute;
      debugPrint('Looking for route from $currentNodeId to destination "$destination"');
      for (final path in allRoutes) {
        debugPrint('Checking path: ${path.name} (start: ${path.startLocationId}, end: ${path.endLocationId})');
        // Check if path starts from current location
        if (path.startLocationId == currentNodeId) {
          debugPrint('Path starts from current location ✅');
          // Get the end location name
          final endLocationName = await _getNodeName(path.endLocationId);
          debugPrint('End location name: "$endLocationName"');

          // Check if destination matches end location name (case insensitive)
          final destLower = destination.toLowerCase();
          final endLower = endLocationName.toLowerCase();
          debugPrint('Checking if "$endLower" contains "$destLower" or vice versa');

          if (endLower.contains(destLower) || destLower.contains(endLower)) {
            debugPrint('Route match found! ✅');
            // Get full route details
            final routeDetails = await _getRouteDetails(path);
            if (routeDetails != null) {
              matchingRoute = routeDetails;
              debugPrint('Route details created successfully');
              break;
            } else {
              debugPrint('Failed to create route details');
            }
          } else {
            debugPrint('No match for this route');
          }
        } else {
          debugPrint('Path does not start from current location');
        }
      }

      if (matchingRoute == null) {
        speak('I couldn\'t find a route from $currentLocation to $destination. Please check available routes by saying "what routes are available".');
        _updateState(VoiceSessionState.idle);
        return;
      }

      // Start navigation
      debugPrint('Starting navigation to ${matchingRoute.endNodeName}');
      onStatusUpdate?.call('Starting navigation to $destination');
      speak('Starting navigation to ${matchingRoute.endNodeName}. Follow the audio instructions.');

      // Start navigation using the navigation service
      debugPrint('Calling _navigationService.startNavigation()');
      await _navigationService?.startNavigation(matchingRoute);
      debugPrint('Navigation service startNavigation() completed');

      onStatusUpdate?.call('Navigation started');
      _updateState(VoiceSessionState.idle);

    } catch (e) {
      debugPrint('Navigation execution failed: $e');
      speak('I couldn\'t start navigation to $destination. Please try again.');
      _updateState(VoiceSessionState.idle);
    }
  }

  /// Get detailed route information from a navigation path
  Future<NavigationRoute?> _getRouteDetails(NavigationPath path) async {
    try {
      // Get node names from embeddings (similar to position_localization_service)
      final startNodeName = await _getNodeName(path.startLocationId);
      final endNodeName = await _getNodeName(path.endLocationId);

      return NavigationRoute(
        pathId: path.id,
        pathName: path.name,
        startNodeId: path.startLocationId,
        endNodeId: path.endLocationId,
        startNodeName: startNodeName,
        endNodeName: endNodeName,
        estimatedDistance: path.estimatedDistance,
        estimatedSteps: path.estimatedSteps,
        estimatedDuration: _estimateDuration(path.estimatedDistance),
        waypoints: path.waypoints,
      );

    } catch (e) {
      debugPrint('Failed to get route details: $e');
      return null;
    }
  }

  /// Get node name from database
  Future<String> _getNodeName(String nodeId) async {
    try {
      debugPrint('🎤 Getting node name for ID: $nodeId');
      final nodeDetails = await _supabaseService?.getMapNodeDetails(nodeId);

      if (nodeDetails != null && nodeDetails['name'] != null) {
        final nodeName = nodeDetails['name'] as String;
        debugPrint('🎤 Found node name: $nodeName');
        return nodeName;
      }

      debugPrint('Node name not found in database, returning Unknown Location');
      return 'Unknown Location';
    } catch (e) {
      debugPrint('Failed to get node name: $e');
      return 'Unknown Location';
    }
  }

  /// Estimate navigation duration based on distance
  Duration _estimateDuration(double distance) {
    // Rough estimate: 1.4 m/s walking speed
    final seconds = (distance / 1.4).round();
    return Duration(seconds: seconds);
  }

  /// Execute record location command
  Future<void> _executeRecordLocation() async {
    speak('Recording location is an admin function. Please use the admin interface.');
    _updateState(VoiceSessionState.idle);
  }

  /// Execute speak location command
  Future<void> _executeSpeakLocation() async {
    // Check if we have a location from last localization
    if (_lastLocalizationResult != null) {
      final location = _lastLocalizationResult!['detectedLocation'];
      if (location != null && location.isNotEmpty) {
        speak('Based on my last scan, your current location is $location.');
        _updateState(VoiceSessionState.idle);
        return;
      }
    }

    // No location available - guide them to localize first
    speak('I don\'t know your current location yet. Say "find my location" to scan and find your location.');
    _updateState(VoiceSessionState.idle);
  }

  /// Execute stop command
  Future<void> _executeStop() async {
    debugPrint('Stopping all voice assistant actions');
    await _stopAllActions();
    _updateState(VoiceSessionState.idle);
  }

  /// Execute repeat command
  Future<void> _executeRepeat() async {
    speak('Please say "Hey Navi" followed by your command.');
    _updateState(VoiceSessionState.idle);
  }

  /// Execute explain command - explain the last localization reasoning
  Future<void> _executeExplain() async {
    if (_lastLocalizationResult == null) {
      speak('I don\'t have any recent location identification to explain. Please find your location first by saying "find my location".');
      _updateState(VoiceSessionState.idle);
      return;
    }

    try {
      final location = _lastLocalizationResult!['detectedLocation'] ?? 'Unknown location';
      final vlmReasoning = _lastLocalizationResult!['vlmReasoning'];

      String explanation = 'I recognized you\'re at $location because: ';

      // Focus on the key visual features from VLM reasoning
      if (vlmReasoning != null && vlmReasoning.isNotEmpty) {
        explanation += vlmReasoning;
      } else {
        explanation += 'the visual features match the stored images of this location.';
      }

      speak(explanation);
      _updateState(VoiceSessionState.idle);

    } catch (e) {
      debugPrint('Explain execution failed: $e');
      speak('I\'m having trouble explaining the location identification. Please try again.');
      _updateState(VoiceSessionState.idle);
    }
  }

  /// Execute list routes command - show available navigation routes
  Future<void> _executeListNodes() async {
    try {
      // Check if user has been localized first
      if (_lastLocalizationResult == null || _lastLocalizationResult!['nodeId'] == null) {
        speak('I need to know your current location first before I can tell you about available routes. Please say "where am I" or "find my location" to localize yourself.');
        _updateState(VoiceSessionState.idle);
        return;
      }

      speak('Let me check what navigation routes are available from your current location...');

      // Get current location
      final currentNodeId = _lastLocalizationResult!['nodeId'];
      final currentLocation = _lastLocalizationResult!['detectedLocation'] ?? 'your current location';

      // Get available navigation routes from current location
      if (_localizationService == null) {
        speak('Location service not available. Please try again later.');
        _updateState(VoiceSessionState.idle);
        return;
      }

      final routes = await _localizationService!.getAvailableRoutes(currentNodeId);
      if (routes.isEmpty) {
        speak('I\'m sorry, there are no navigation routes available from $currentLocation. You may need to move to a different location first.');
        _updateState(VoiceSessionState.idle);
        return;
      }

      // Build response with route names
      String response = 'Available navigation routes from $currentLocation: ';
      final routeNames = routes.map((route) => route.pathName).toList();

      if (routeNames.length == 1) {
        response += routeNames.first;
      } else if (routeNames.length == 2) {
        response += '${routeNames[0]} and ${routeNames[1]}';
      } else {
        // Join all but last with commas, then add "and" before last
        final allButLast = routeNames.sublist(0, routeNames.length - 1).join(', ');
        response += '$allButLast, and ${routeNames.last}';
      }

      response += '. Say "take me to" followed by a destination name to start navigation.';

      speak(response);
      _updateState(VoiceSessionState.idle);

    } catch (e) {
      debugPrint('List routes execution failed: $e');
      speak('I\'m having trouble retrieving the list of navigation routes. Please try again.');
      _updateState(VoiceSessionState.idle);
    }
  }

  /// Execute unknown command
  Future<void> _executeUnknown(String originalText) async {
    speak('I didn\'t understand "$originalText". Please try saying "Where am I" or "Find my location".');
    _updateState(VoiceSessionState.idle);
  }

  /// Stop all current actions
  Future<void> _stopAllActions() async {
    try {
      await _flutterTts.stop();
      await _speechToText.stop();
    } catch (e) {
      debugPrint('Error stopping actions: $e');
    }
  }

  /// Speak text using TTS
  Future<void> speak(String text) async {
    try {
      _updateState(VoiceSessionState.speaking);
      onResponse?.call(text);
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint('TTS failed: $e');
      _updateState(VoiceSessionState.idle);
    }
  }

  /// Update session state
  void _updateState(VoiceSessionState newState) {
    if (_sessionState != newState) {
      _sessionState = newState;
      onStateChanged?.call(_sessionState);
      debugPrint('Voice Assistant State: ${_sessionState.toString()}');
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    try {
      await _porcupineManager?.delete();
      await _speechToText.stop();
      await _flutterTts.stop();
      debugPrint('Voice Assistant disposed');
    } catch (e) {
      debugPrint('Voice Assistant disposal error: $e');
    }
  }

  /// Public methods for manual control
  Future<void> startListeningManually() async {
    if (_sessionState == VoiceSessionState.idle) {
      await _startListening();
    }
  }

  /// Manually test voice recognition (for debugging)
  Future<void> testVoiceRecognition() async {
    try {
      debugPrint('Starting voice recognition test...');

      // Test microphone first
      final micTest = await testMicrophone();
      if (!micTest) {
        speak('Microphone test failed. Please check permissions.');
        return;
      }

      // Start listening manually
      await _startListening();

      // Set a timeout for the test
      Timer(Duration(seconds: 10), () async {
        if (_sessionState == VoiceSessionState.listening) {
          await stopListening();
          speak('Voice test timed out. Please try speaking into the microphone.');
        }
      });

    } catch (e) {
      debugPrint('❌ Voice recognition test failed: $e');
      speak('Voice recognition test failed.');
    }
  }

  Future<void> stopListening() async {
    if (_sessionState == VoiceSessionState.listening) {
      await _speechToText.stop();
      _updateState(VoiceSessionState.idle);
      // Restart Porcupine after stopping speech recognition
      _restartPorcupine();
    }
  }

  /// Test microphone functionality
  Future<bool> testMicrophone() async {
    try {
      debugPrint('Testing microphone functionality...');

      // Check permission first
      final hasPermission = await _checkMicrophonePermission();
      if (!hasPermission) {
        debugPrint('Microphone test failed: No permission');
        return false;
      }

      // Check if speech recognition is available
      if (!_speechToText.isAvailable) {
        debugPrint('Microphone test failed: Speech recognition not available');
        return false;
      }

      debugPrint('✅ Microphone test passed');
      return true;
    } catch (e) {
      debugPrint('Microphone test failed: $e');
      return false;
    }
  }

  /// Store the last successful localization result for explanation
  void updateLastLocalizationResult(Map<String, dynamic> result) {
    _lastLocalizationResult = result;
    debugPrint('Updated last localization result: ${result['detectedLocation']}');
  }

  /// Get available voice commands
  List<String> getAvailableCommands() {
    return [
      'Where am I?',
      'Find my location',
      'Help me to relocalize',
      'Relocalize',
      'Take me to the library',
      'Navigate to room 101',
      'What routes are available?',
      'What\'s my location?',
      'Why do you think so?',
      'Stop',
    ];
  }
}
