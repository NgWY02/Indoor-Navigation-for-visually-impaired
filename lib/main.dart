import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:app_links/app_links.dart';
import 'screens/admin/admin_home_screen.dart';
import 'screens/common/profile_screen.dart';
import 'services/supabase_service.dart';
import 'screens/admin/admin_panel.dart';
import 'screens/admin/image_test_screen.dart';
import 'auth/auth_wrapper.dart';
import 'auth/new_password_screen.dart';

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

class MyApp extends StatefulWidget {
  final List<CameraDescription> cameras;

  const MyApp({Key? key, required this.cameras}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late AppLinks _appLinks;
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  
  @override
  void initState() {
    super.initState();
    _initDeepLinkHandling();
  }

  Future<void> _initDeepLinkHandling() async {
    if (!kIsWeb) {
      _appLinks = AppLinks();
      
      // Handle deep links when app is already running
      _appLinks.uriLinkStream.listen((uri) {
        _handleDeepLink(uri);
      });
      
      // Handle deep link when app is launched
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleDeepLink(initialUri);
      }
    }
  }

  void _handleDeepLink(Uri uri) {
    // This function handles deep links for both password recovery and email confirmation.
    if ((uri.path == '/callback' || uri.path == '/auth/callback' || uri.host == 'auth') 
        && (uri.fragment.isNotEmpty || uri.query.isNotEmpty)) {
      
      final params = Uri.splitQueryString(uri.fragment.isNotEmpty ? uri.fragment : uri.query);
      final accessToken = params['access_token'];
      final refreshToken = params['refresh_token'];
      final type = params['type'];
      
      print('Handling deep link with type: $type, has access_token: ${accessToken != null}');

      // The presence of an access_token indicates a session has been established by the link.
      // We now differentiate based on the 'type' parameter.
      if (accessToken != null && refreshToken != null) {
        if (type == 'recovery') {
          // This is explicitly a password recovery link.
          print('Deep link identified as PASSWORD RECOVERY.');
          _navigateToNewPasswordScreen(accessToken, refreshToken);
        } else {
          // This is an email confirmation link (or another type we treat as such).
          print('Deep link identified as EMAIL CONFIRMATION.');
          _handleEmailConfirmation(accessToken, refreshToken);
        }
      }
      // Handle the OAuth code flow which doesn't pass tokens directly in the URL.
      else if (params.containsKey('code')) {
         print('Deep link identified as OAuth code exchange flow.');
        _handleAuthCodeExchange(params['code']!);
      }
    }
  }

  void _navigateToNewPasswordScreen(String accessToken, String refreshToken) {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (navigatorKey.currentState != null) {
        navigatorKey.currentState!.pushReplacement(
          MaterialPageRoute(
            builder: (context) => NewPasswordScreen(
              accessToken: accessToken,
              refreshToken: refreshToken,
            ),
            settings: const RouteSettings(name: '/reset-password/new'),
          ),
        );
      } else {
        final context = navigatorKey.currentContext;
        if (context != null) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => NewPasswordScreen(
                accessToken: accessToken,
                refreshToken: refreshToken,
              ),
            ),
          );
        }
      }
    });
  }

  void _handleEmailConfirmation(String? accessToken, String? refreshToken) {
    if (accessToken != null && refreshToken != null) {
      // Email is already confirmed by Supabase when the link is clicked
      // Show success message and redirect to login
      Future.delayed(const Duration(milliseconds: 500), () {
        final context = navigatorKey.currentContext;
        if (context != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Email confirmed successfully! You can now login.'),
              backgroundColor: Colors.green,
            ),
          );
          
          // Navigate to login screen (root route with AuthWrapper will show login when not authenticated)
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        }
      });
    } else {
      _showError('Email confirmation failed. Please try clicking the link again.');
    }
  }

  Future<void> _handleAuthCodeExchange(String authCode) async {
    try {
      // Construct the full callback URL that Supabase expects
      final fullCallbackUrl = 'com.example.indoornavigation://auth/callback?code=$authCode';
      
      // Let Supabase handle the full URL processing
      final supabaseService = SupabaseService();
      final response = await supabaseService.client.auth.getSessionFromUrl(Uri.parse(fullCallbackUrl));
      
      final session = response.session;
      if (session.accessToken.isNotEmpty) {
        _navigateToNewPasswordScreen(session.accessToken, session.refreshToken ?? '');
      } else {
        _showError('Failed to process password reset link. Please try again.');
      }
    } catch (e) {
      _showError('Error processing reset link: ${e.toString()}');
    }
  }

  void _showError(String message) {
    Future.delayed(const Duration(milliseconds: 500), () {
      final context = navigatorKey.currentContext;
      if (context != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Indoor Navigation',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      // Use AuthWrapper for proper authentication flow
      home: AuthWrapper(cameras: widget.cameras),
      routes: {
        '/admin': (context) => const AdminPanel(),
        '/profile': (context) => const ProfileScreen(),
        '/admin_home': (context) => AdminHomeScreen(cameras: widget.cameras),
        '/image_test': (context) => const ImageTestScreen(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/reset-password/new') {
          final args = settings.arguments as Map<String, String>?;
          return MaterialPageRoute(
            builder: (context) => NewPasswordScreen(
              accessToken: args?['accessToken'],
              refreshToken: args?['refreshToken'],
            ),
          );
        }
        return null;
      },
    );
  }
}