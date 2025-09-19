import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import 'register_screen.dart';
import 'reset_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _supabaseService = SupabaseService();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _supabaseService.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      
      if (response.user == null) {
        setState(() {
          _errorMessage = 'Login failed. Please check your credentials.';
        });
      }
    } catch (e) {
      setState(() {
        // Check if it's an invalid credentials error
        if (e.toString().toLowerCase().contains('invalid login credentials') ||
            e.toString().toLowerCase().contains('invalid email or password')) {
          _errorMessage = 'Wrong password or email address.';
        } else {
          _errorMessage = 'Login failed. Please try again.';
        }
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _navigateToRegister({bool allowAdminCreation = false}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RegisterScreen(allowAdminCreation: allowAdminCreation),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final keyboardHeight = mediaQuery.viewInsets.bottom;
    final isKeyboardVisible = keyboardHeight > 0;
    
    // Responsive sizing for phones
    final iconSize = isKeyboardVisible ? 80.0 : 120.0;
    final titleFontSize = screenWidth < 360 ? 20.0 : 22.0;
    final horizontalPadding = screenWidth * 0.05; // 5% of screen width
    final verticalSpacing = isKeyboardVisible ? 12.0 : 20.0;
    
    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          label: 'Login screen',
          child: const Text('Login'),
        ),
        elevation: 0,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding.clamp(16.0, 24.0),
                vertical: 16.0,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 32,
                ),
                child: IntrinsicHeight(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!isKeyboardVisible) ...[
                          Semantics(
                            label: 'App logo',
                            child: Image.asset(
                              'assets/icon.png',
                              height: iconSize,
                              width: iconSize,
                              fit: BoxFit.contain,
                            ),
                          ),
                          SizedBox(height: verticalSpacing),
                        ],
                        Semantics(
                          label: 'App title',
                          child: Text(
                            'NAVI',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: titleFontSize,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(height: verticalSpacing * 1.5),
                        if (_errorMessage != null) ...[
                          Semantics(
                            label: 'Error message',
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.red.shade600, width: 2),
                              ),
                              child: Row(
                                children: [
                                  Semantics(
                                    label: 'Error icon',
                                    child: Icon(
                                      Icons.error_outline,
                                      color: Colors.red.shade600,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: TextStyle(
                                        color: Colors.red.shade800,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(height: verticalSpacing),
                        ],
                        Semantics(
                          label: 'Email input field',
                          hint: 'Enter your email address',
                          textField: true,
                          child: TextFormField(
                            controller: _emailController,
                            style: const TextStyle(fontSize: 16, color: Colors.black),
                            decoration: InputDecoration(
                              labelText: 'Email',
                              labelStyle: const TextStyle(color: Colors.black87),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Colors.black, width: 2),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Colors.black54, width: 1),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Colors.black, width: 2),
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              prefixIcon: const Icon(Icons.email, color: Colors.black87),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                            ),
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your email';
                            }
                            if (!value.contains('@') || !value.contains('.')) {
                              return 'Please enter a valid email';
                            }
                            return null;
                          },
                          ),
                        ),
                        SizedBox(height: verticalSpacing),
                        Semantics(
                          label: 'Password input field',
                          hint: 'Enter your password',
                          textField: true,
                          child: TextFormField(
                            controller: _passwordController,
                            style: const TextStyle(fontSize: 16, color: Colors.black),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              labelStyle: const TextStyle(color: Colors.black87),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Colors.black, width: 2),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Colors.black54, width: 1),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Colors.black, width: 2),
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              prefixIcon: const Icon(Icons.lock, color: Colors.black87),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                            ),
                          obscureText: true,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your password';
                            }
                            if (value.length < 6) {
                              return 'Password should be at least 6 characters';
                            }
                            return null;
                          },
                          ),
                        ),
                        const SizedBox(height: 8),
                        Semantics(
                          label: 'Forgot password link',
                          hint: 'Tap to reset your password',
                          button: true,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const ResetPasswordScreen(),
                                  ),
                                );
                              },
                              child: const Text(
                                'Forgot Password?',
                                style: TextStyle(
                                  color: Colors.black87,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: verticalSpacing),
                        Semantics(
                          label: 'Login button',
                          hint: 'Tap to sign in to your account',
                          button: true,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _signIn,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade600,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text(
                                    'Login',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                        SizedBox(height: verticalSpacing),
                        Semantics(
                          label: 'Register new account link',
                          hint: 'Tap to create a new user account',
                          button: true,
                          child: TextButton(
                            onPressed: () => _navigateToRegister(),
                            child: const Text(
                              "Don't have an account? Register",
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Semantics(
                          label: 'Register as admin link',
                          hint: 'Tap to create a new admin account',
                          button: true,
                          child: TextButton(
                            onPressed: () => _navigateToRegister(allowAdminCreation: true),
                            child: const Text(
                              "Register as Admin",
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        // Extra bottom padding for safe area
                        SizedBox(height: mediaQuery.padding.bottom + 16),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}