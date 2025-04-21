import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import 'login_screen.dart';

class AuthWrapper extends StatefulWidget {
  final Widget child;
  
  const AuthWrapper({Key? key, required this.child}) : super(key: key);

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
        // If we have a user, show the app
        if (_supabaseService.isAuthenticated) {
          return widget.child;
        }
        
        // Otherwise, show the login screen
        return const LoginScreen();
      },
    );
  }
}