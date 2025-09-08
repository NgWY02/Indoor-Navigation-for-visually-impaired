import 'package:flutter/material.dart';
import '../services/supabase_service.dart';

class NewPasswordScreen extends StatefulWidget {
  final String? accessToken;
  final String? refreshToken;
  
  const NewPasswordScreen({
    Key? key, 
    this.accessToken,
    this.refreshToken,
  }) : super(key: key);

  @override
  _NewPasswordScreenState createState() => _NewPasswordScreenState();
}

class _NewPasswordScreenState extends State<NewPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _supabaseService = SupabaseService();
  
  bool _isLoading = false;
  String? _errorMessage;
  bool _isSuccess = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    
    // Validate tokens
    if (widget.accessToken == null || widget.refreshToken == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacementNamed('/');
      });
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _updatePassword() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _supabaseService.updatePassword(
        newPassword: _passwordController.text,
        accessToken: widget.accessToken,
        refreshToken: widget.refreshToken,
      );
      
      if (!mounted) return;
      
      setState(() {
        _isSuccess = true;
      });

      // Log out the user and navigate to login screen
      await _supabaseService.signOut();
      
      if (!mounted) return;
      
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password updated successfully! Please login with your new password.'),
          backgroundColor: Colors.green,
        ),
      );

      // Navigate to login screen after 2 seconds
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        }
      });

    } catch (e) {
      setState(() {
        // Show user-friendly error messages
        if (e.toString().toLowerCase().contains('session')) {
          _errorMessage = 'Session expired. Please request a new password reset link.';
        } else if (e.toString().toLowerCase().contains('token')) {
          _errorMessage = 'Invalid reset link. Please request a new password reset.';
        } else {
          _errorMessage = 'Failed to update password. Please try again.';
        }
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
    final titleFontSize = screenWidth < 360 ? 20.0 : 22.0;
    final horizontalPadding = screenWidth * 0.05;
    final verticalSpacing = isKeyboardVisible ? 12.0 : 16.0;

    if (_isSuccess) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 24),
                  Text(
                    'Password Updated Successfully!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'You can now login with your new password.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 32),
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  const Text(
                    'Redirecting to login...',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return WillPopScope(
      onWillPop: () async {
        // When user presses back, sign out first to clear session, then go to login
        await _supabaseService.signOut();
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        return false; 
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Set New Password'),
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
                        Text(
                          'Set New Password',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: titleFontSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: verticalSpacing * 0.5),
                        Text(
                          'Please enter your new password below',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
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
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(
                                color: Colors.red.shade800,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          SizedBox(height: verticalSpacing),
                        ],
                        
                        TextFormField(
                          controller: _passwordController,
                          style: const TextStyle(fontSize: 16),
                          decoration: InputDecoration(
                            labelText: 'New Password',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility : Icons.visibility_off,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                          ),
                          obscureText: _obscurePassword,
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
                          decoration: InputDecoration(
                            labelText: 'Confirm New Password',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirmPassword ? Icons.visibility : Icons.visibility_off,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscureConfirmPassword = !_obscureConfirmPassword;
                                });
                              },
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                          ),
                          obscureText: _obscureConfirmPassword,
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
                        SizedBox(height: verticalSpacing * 1.5),
                        
                        ElevatedButton(
                          onPressed: _isLoading ? null : _updatePassword,
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
                                  'Update Password',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                        SizedBox(height: verticalSpacing),
                        
                        TextButton(
                          onPressed: () async {
                            // Sign out first to clear any session; otherwise AuthWrapper
                            // may detect an active session and navigate to dashboard.
                            try {
                              await _supabaseService.signOut();
                            } catch (_) {}
                            if (!mounted) return;
                            Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
                          },
                          child: const Text(
                            'Back to Login',
                            style: TextStyle(fontSize: 14),
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
    ), 
    ); 
  }
}