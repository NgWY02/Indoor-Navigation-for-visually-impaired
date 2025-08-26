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
  final _nameController = TextEditingController();
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
    _nameController.dispose();
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
          'name': _nameController.text.trim(),
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
    final keyboardHeight = mediaQuery.viewInsets.bottom;
    final isKeyboardVisible = keyboardHeight > 0;
    
    // Phone-focused responsive sizing
    final iconSize = isKeyboardVisible ? 50.0 : 70.0;
    final titleFontSize = screenWidth < 360 ? 20.0 : 22.0;
    final horizontalPadding = screenWidth * 0.05; 
    final verticalSpacing = isKeyboardVisible ? 10.0 : 16.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Register'),
        elevation: 0,
        backgroundColor: Colors.blue.shade700,
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
                      Icon(
                        Icons.person_add,
                        size: iconSize,
                        color: Colors.blue,
                      ),
                      SizedBox(height: verticalSpacing),
                    ],
                    Text(
                      'Create an Account',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: titleFontSize,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: verticalSpacing * 1.5),
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, 
                                 color: Colors.red.shade700, size: 20),
                            const SizedBox(width: 8),
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
                      SizedBox(height: verticalSpacing),
                    ],
                    TextFormField(
                      controller: _nameController,
                      style: const TextStyle(fontSize: 16),
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your name';
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: verticalSpacing),
                    TextFormField(
                      controller: _emailController,
                      style: const TextStyle(fontSize: 16),
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.email),
                        contentPadding: EdgeInsets.symmetric(
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
                    SizedBox(height: verticalSpacing),
                    TextFormField(
                      controller: _passwordController,
                      style: const TextStyle(fontSize: 16),
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock),
                        contentPadding: EdgeInsets.symmetric(
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
                    SizedBox(height: verticalSpacing),
                    TextFormField(
                      controller: _confirmPasswordController,
                      style: const TextStyle(fontSize: 16),
                      decoration: const InputDecoration(
                        labelText: 'Confirm Password',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock_outline),
                        contentPadding: EdgeInsets.symmetric(
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
                    SizedBox(height: verticalSpacing),
                    
                    // Only show this if admin creation is allowed
                    if (widget.allowAdminCreation)
                      Card(
                        child: SwitchListTile(
                          title: const Text(
                            'Register as Admin',
                            style: TextStyle(fontSize: 16),
                          ),
                          subtitle: const Text(
                            'Special privileges for system management',
                            style: TextStyle(fontSize: 12),
                          ),
                          value: _isAdmin,
                          onChanged: (value) {
                            setState(() {
                              _isAdmin = value;
                              _showAdminCodeField = value;
                            });
                          },
                        ),
                      ),
                    
                    // Admin code field - only shown when admin option selected
                    if (_showAdminCodeField) ...[
                      SizedBox(height: verticalSpacing),
                      TextFormField(
                        controller: _adminCodeController,
                        style: const TextStyle(fontSize: 16),
                        decoration: const InputDecoration(
                          labelText: 'Admin Registration Code',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.admin_panel_settings),
                          contentPadding: EdgeInsets.symmetric(
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
                    ],
                    
                    SizedBox(height: verticalSpacing * 2),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _signUp,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
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
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                    SizedBox(height: verticalSpacing),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: const Text(
                        'Already have an account? Login',
                        style: TextStyle(fontSize: 14),
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