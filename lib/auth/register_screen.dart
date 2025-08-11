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
      final response = await _supabaseService.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        role: _isAdmin ? UserRole.admin : UserRole.user,
        data: {
          'name': _nameController.text.trim(),
        },
      );
      
      if (!mounted) return;
      
      if (response.user != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Registration successful! Please check your email to confirm your account.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(); // Go back to login screen
      } else {
        setState(() {
          _errorMessage = 'Registration failed. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
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
    final isTablet = screenWidth > 600;
    final isLargeTablet = screenWidth > 900;
    
    // Calculate responsive values
    final horizontalPadding = isLargeTablet ? 48.0 : (isTablet ? 32.0 : 16.0);
    final verticalPadding = isTablet ? 24.0 : 16.0;
    final bottomSafeArea = mediaQuery.padding.bottom;
    final hasBottomNavigation = bottomSafeArea > 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Register',
          style: TextStyle(
            fontSize: isTablet ? 22 : 20,
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: horizontalPadding,
              right: horizontalPadding,
              top: verticalPadding,
              bottom: hasBottomNavigation ? verticalPadding + 16 : verticalPadding,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isLargeTablet ? 600 : double.infinity,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.person_add,
                      size: isTablet ? 100 : 80,
                      color: Colors.blue,
                    ),
                    SizedBox(height: isTablet ? 40 : 32),
                    Text(
                      'Create an Account',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: isTablet ? 28 : 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: isTablet ? 40 : 32),
                    if (_errorMessage != null)
                      Container(
                        padding: EdgeInsets.all(isTablet ? 12 : 8),
                        decoration: BoxDecoration(
                          color: Colors.red[100],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: Colors.red.shade700),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(
                                  color: Colors.red.shade900,
                                  fontSize: isTablet ? 16 : 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    SizedBox(height: isTablet ? 20 : 16),
                    TextFormField(
                      controller: _nameController,
                      style: TextStyle(fontSize: isTablet ? 18 : 16),
                      decoration: InputDecoration(
                        labelText: 'Full Name',
                        labelStyle: TextStyle(fontSize: isTablet ? 16 : 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(isTablet ? 12 : 8),
                        ),
                        prefixIcon: Icon(Icons.person, size: isTablet ? 24 : 20),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: isTablet ? 16 : 12,
                          vertical: isTablet ? 20 : 16,
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your name';
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: isTablet ? 20 : 16),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
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
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
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
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPasswordController,
                  decoration: const InputDecoration(
                    labelText: 'Confirm Password',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outline),
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
                const SizedBox(height: 16),
                
                // Only show this if admin creation is allowed
                if (widget.allowAdminCreation)
                  SwitchListTile(
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
                
                // Admin code field - only shown when admin option selected
                if (_showAdminCodeField)
                  Column(
                    children: [
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _adminCodeController,
                        decoration: const InputDecoration(
                          labelText: 'Admin Registration Code',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.admin_panel_settings),
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
                  ),
                
                    SizedBox(height: isTablet ? 32 : 24),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _signUp,
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                          vertical: isTablet ? 20 : 16,
                          horizontal: isTablet ? 24 : 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(isTablet ? 12 : 8),
                        ),
                      ),
                      child: _isLoading
                          ? SizedBox(
                              height: isTablet ? 24 : 20,
                              width: isTablet ? 24 : 20,
                              child: const CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              'Register',
                              style: TextStyle(
                                fontSize: isTablet ? 18 : 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                    SizedBox(height: isTablet ? 20 : 16),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: Text(
                        'Already have an account? Login',
                        style: TextStyle(fontSize: isTablet ? 16 : 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}