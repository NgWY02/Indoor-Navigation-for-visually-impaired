import 'package:flutter/material.dart';
import '../services/supabase_service.dart';

class RegisterScreen extends StatefulWidget {
  final bool allowAdminCreation;
  
  const RegisterScreen({
    Key? key, 
    this.allowAdminCreation = false,
  }) : super(key: key);

  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _adminCodeController = TextEditingController();
  final _supabaseService = SupabaseService();
  bool _isLoading = false;
  String? _errorMessage;
  bool _isAdmin = false;
  bool _showAdminCodeField = false;
  
  // This would be securely stored on your backend in a real app
  static const String _adminRegistrationCode = "ADMIN123";

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _adminCodeController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;
    
    // Admin validation
    if (_isAdmin && _adminCodeController.text != _adminRegistrationCode) {
      setState(() {
        _errorMessage = 'Invalid admin code. Please try again or register as a regular user.';
      });
      return;
    }
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Step 1: Check if the email already exists using our new RPC function
      final emailExists = await _supabaseService.checkEmailExists(_emailController.text.trim());
      
      if (emailExists) {
        setState(() {
          _errorMessage = 'This email is already registered. Please try logging in.';
          _isLoading = false;
        });
        return; // Stop the registration process
      }
      
      // Step 2: If email does not exist, proceed with signup
      final result = await _supabaseService.signUpWithCheck(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        role: _isAdmin ? UserRole.admin : UserRole.user,
        data: {
        },
      );
      
      if (!mounted) return;
      
      // This part now handles only successful new signups
      if (result.authResponse.user != null && result.isNewUser) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Registration successful! Please check your email to confirm your account.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(); // Go back to login screen
      } else {
        // This case should now be rare, but we'll handle it
        setState(() {
          _errorMessage = 'An unexpected error occurred. The email might already be registered.';
        });
      }
    } catch (e) {
      // Handle explicit errors thrown by our service or Supabase
      String errorMessage = 'Registration failed. Please try again.';
      
      // Check for specific error messages
      String errorString = e.toString().toLowerCase();
      if (errorString.contains('already registered') || 
          errorString.contains('already exists') || 
          errorString.contains('user already registered')) {
        errorMessage = 'This email is already registered. Please use a different email or try logging in.';
      } else if (errorString.contains('invalid email')) {
        errorMessage = 'Please enter a valid email address.';
      } else if (errorString.contains('weak password') || errorString.contains('password')) {
        errorMessage = 'Password is too weak. Please use a stronger password.';
      } else if (errorString.contains('network') || errorString.contains('connection')) {
        errorMessage = 'Network error. Please check your internet connection and try again.';
      }
      
      setState(() {
        _errorMessage = errorMessage;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    final keyboardHeight = mediaQuery.viewInsets.bottom;
    final isKeyboardVisible = keyboardHeight > 0;

    // Phone-focused responsive sizing with small phone adjustments
    final bool isSmallPhone = screenHeight < 600;
    final double iconSize = isKeyboardVisible ? 50.0 : 70.0;
    final double titleFontSize = screenWidth < 360 ? 20.0 : 22.0;
    final double subtitleFontSize = isSmallPhone ? 12.0 : 14.0;
    final double horizontalPadding = screenWidth * 0.05;
    final double verticalSpacing = isKeyboardVisible ? 10.0 : 16.0;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Semantics(
          label: 'Register screen',
          child: const Text('Register'),
        ),
        elevation: 0,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding.clamp(16.0, 24.0),
                vertical: 16.0,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!isKeyboardVisible) ...[
                      Semantics(
                        label: 'Registration icon',
                        child: Icon(
                          Icons.person_add,
                          size: iconSize,
                          color: Colors.black,
                        ),
                      ),
                      SizedBox(height: verticalSpacing),
                    ],
                    Semantics(
                      label: 'Registration title',
                      child: Text(
                        'Create an Account',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
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
                          return 'Please enter a password';
                        }
                        if (value.length < 6) {
                          return 'Password should be at least 6 characters';
                        }
                        return null;
                      },
                      ),
                    ),
                    SizedBox(height: verticalSpacing),
                    Semantics(
                      label: 'Confirm password input field',
                      hint: 'Re-enter your password to confirm',
                      textField: true,
                      child: TextFormField(
                        controller: _confirmPasswordController,
                        style: const TextStyle(fontSize: 16, color: Colors.black),
                        decoration: InputDecoration(
                          labelText: 'Confirm Password',
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
                          prefixIcon: const Icon(Icons.lock_outline, color: Colors.black87),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                        ),
                      obscureText: true,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please confirm your password';
                        }
                        if (value != _passwordController.text) {
                          return 'Passwords do not match';
                        }
                        return null;
                      },
                      ),
                    ),
                    SizedBox(height: verticalSpacing),
                    
                    // Only show this if admin creation is allowed
                    widget.allowAdminCreation ? Card(
                      child: SwitchListTile(
                        title: const Text('Register as Admin'),
                        subtitle: const Text('Special privileges for system management'),
                        value: _isAdmin,
                        onChanged: (value) {
                          setState(() {
                            _isAdmin = value;
                            _showAdminCodeField = value;
                          });
                        },
                      ),
                    ) : const SizedBox.shrink(),

                    // Admin code field - only shown when admin option selected
                    _showAdminCodeField ? Column(
                      children: [
                        SizedBox(height: verticalSpacing),
                        Semantics(
                        label: 'Admin code input field',
                        hint: 'Enter the admin registration code',
                        textField: true,
                        child: TextFormField(
                          controller: _adminCodeController,
                          style: const TextStyle(fontSize: 16, color: Colors.black),
                          decoration: InputDecoration(
                            labelText: 'Admin Registration Code',
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
                            prefixIcon: const Icon(Icons.admin_panel_settings, color: Colors.black87),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                          ),
                        obscureText: true,
                        validator: (value) {
                          if (_isAdmin) {
                            if (value == null || value.isEmpty) {
                              return 'Admin code is required';
                            }
                          }
                          return null;
                        },
                        ),
                        ),
                      ],
                    ) : const SizedBox.shrink(),

                    SizedBox(height: verticalSpacing * 2),
                    Semantics(
                      label: 'Register button',
                      hint: 'Tap to create your account',
                      button: true,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _signUp,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
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
                                'Register',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    SizedBox(height: verticalSpacing),
                    Semantics(
                      label: 'Login link',
                      hint: 'Tap to go back to login screen',
                      button: true,
                      child: TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        child: const Text(
                          'Already have an account? Login',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                    // Extra bottom padding for safe area
                    SizedBox(height: mediaQuery.padding.bottom + 16),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}