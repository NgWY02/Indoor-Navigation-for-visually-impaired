import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:camera/camera.dart';
import '../services/supabase_service.dart';
import '../screens/admin/admin_home_screen.dart';
import '../screens/user/user_navigation_screen.dart';
import 'login_screen.dart';

class AuthWrapper extends StatefulWidget {
  final List<CameraDescription> cameras;
  
  const AuthWrapper({Key? key, required this.cameras}) : super(key: key);

  @override
  _AuthWrapperState createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final SupabaseService _supabaseService = SupabaseService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _supabaseService.authStateChanges,
      builder: (context, snapshot) {
        // If we have a user, route based on their role
        if (_supabaseService.isAuthenticated) {
          return FutureBuilder<bool>(
            future: _supabaseService.isAdmin(),
            builder: (context, adminSnapshot) {
              if (adminSnapshot.connectionState == ConnectionState.waiting) {
                // Show loading screen while checking user role
                return const Scaffold(
                  body: Center(
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              
              if (adminSnapshot.hasError) {
                // On error, default to user navigation
                return UserNavigationScreen(cameras: widget.cameras);
              }
              
              final isAdmin = adminSnapshot.data ?? false;
              
              if (isAdmin) {
                // Admin sees home screen with options
                return AdminHomeScreen(cameras: widget.cameras);
              } else {
                // Regular users go directly to navigation (for visually impaired)
                return UserNavigationScreen(cameras: widget.cameras);
              }
            },
          );
        }
        
        // Otherwise, show the login screen
        return const LoginScreen();
      },
    );
  }
}