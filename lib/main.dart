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
  // Normalize and check for known callback paths.
  final path = uri.path.toLowerCase();
  final isCallbackPath = path == '/callback' || path == '/auth/callback' || path == '/auth';
  final isResetPath = path == '/reset' || path == '/auth/reset';

  if ((isCallbackPath || isResetPath || uri.host == 'auth') && (uri.fragment.isNotEmpty || uri.query.isNotEmpty)) {
      
      final params = Uri.splitQueryString(uri.fragment.isNotEmpty ? uri.fragment : uri.query);
      final accessToken = params['access_token'];
      final refreshToken = params['refresh_token'];
      final type = params['type'];
      final code = params['code'];

  // Diagnostic log: print the full incoming URI and parsed pieces so we can
  // verify that Supabase's 'state' and 'code' parameters are present.
  print('Incoming deep link: $uri');
  print('  - path: ${uri.path}');
  print('  - fragment: ${uri.fragment}');
  print('  - query: ${uri.query}');
  print('  - parsed params: ${params}');
  print('Handling deep link with type: $type, has access_token: ${accessToken != null}, has_code: ${code != null}');

      // 1) If the link carries tokens (access/refresh) in the fragment/query, handle
      //    according to the explicit path OR the 'type' param. Path wins: if URL was
      //    generated with the reset redirectTo (contains /reset), prefer recovery.
      if (accessToken != null && refreshToken != null) {
        if (isResetPath || type == 'recovery') {
          print('Deep link identified as PASSWORD RECOVERY (token path or reset path).');
          _navigateToNewPasswordScreen(accessToken, refreshToken);
        } else {
          print('Deep link identified as EMAIL CONFIRMATION (token path).');
          _handleEmailConfirmation(accessToken, refreshToken);
        }
        return;
      }

      // 2) If no tokens are present but a code is provided, this is typically an OAuth
      //    or code-exchange flow. Only treat it as password recovery if the `type` param
      //    explicitly indicates 'recovery'. Otherwise handle it as confirmation/code-exchange.
      if (code != null) {
        if (isResetPath || type == 'recovery') {
          print('Deep link identified as PASSWORD RECOVERY (code flow).');
          _handleAuthCodeExchange(uri, expectedType: 'recovery');
        } else {
          print('Deep link identified as CODE/OAUTH flow (treated as confirmation).');
          _handleAuthCodeExchange(uri, expectedType: 'confirm');
        }
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

  // Accept the original incoming Uri so Supabase can validate state parameters
  Future<void> _handleAuthCodeExchange(Uri callbackUri, {String? expectedType}) async {
    try {
      final supabaseService = SupabaseService();

      // Pass the full incoming URI through so Supabase can validate 'state' and other params
      final response = await supabaseService.client.auth.getSessionFromUrl(callbackUri);
      final session = response.session;

  if (session.accessToken.isNotEmpty) {
        if (expectedType == 'recovery') {
          _navigateToNewPasswordScreen(session.accessToken, session.refreshToken ?? '');
        } else {
          Future.delayed(const Duration(milliseconds: 500), () {
            final context = navigatorKey.currentContext;
            if (context != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Welcome!'),
                  backgroundColor: Colors.green,
                ),
              );
              Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
            }
          });
        }
      } else {
        _showError('Failed to process link. Please try again.');
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
      title: 'NAVI',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      // Use AuthWrapper for proper authentication flow
      home: AuthWrapper(cameras: widget.cameras),
      routes: {
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