import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _supabaseService = SupabaseService();
  bool _isAdmin = false;
  String _userEmail = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Get current user data
      final user = _supabaseService.currentUser;
      if (user != null) {
        final isAdmin = await _supabaseService.isAdmin();
        
        setState(() {
          _userEmail = user.email ?? 'No email available';
          _isAdmin = isAdmin;
          _isLoading = false;
        });
      } else {
        // User is not logged in, navigate back to login
        Navigator.of(context).pushReplacementNamed('/login');
      }
    } catch (e) {
      print('Error loading user data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _signOut() async {
    try {
      await _supabaseService.signOut();
      // Navigate to login screen after sign out
      Navigator.of(context).pushReplacementNamed('/login');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error signing out: $e'))
      );
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

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            'Profile',
            style: TextStyle(
              fontSize: isTablet ? 22 : 20,
            ),
          ),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Profile',
          style: TextStyle(
            fontSize: isTablet ? 22 : 20,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.only(
              left: horizontalPadding,
              right: horizontalPadding,
              top: verticalPadding,
              bottom: hasBottomNavigation ? verticalPadding + 16 : verticalPadding,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isLargeTablet ? 800 : double.infinity,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              Card(
                elevation: isTablet ? 4 : 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                ),
                child: Padding(
                  padding: EdgeInsets.all(isTablet ? 24.0 : 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'User Information',
                        style: TextStyle(
                          fontSize: isTablet ? 22 : 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Icon(Icons.email, size: isTablet ? 24 : 20),
                          SizedBox(width: isTablet ? 12 : 8),
                          Expanded(
                            child: Text(
                              _userEmail,
                              style: TextStyle(fontSize: isTablet ? 18 : 16),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: isTablet ? 12 : 8),
                      Row(
                        children: [
                          Icon(Icons.verified_user, size: isTablet ? 24 : 20),
                          SizedBox(width: isTablet ? 12 : 8),
                          Text(
                            _isAdmin ? 'Administrator' : 'User',
                            style: TextStyle(
                              fontSize: isTablet ? 18 : 16,
                              color: _isAdmin ? Colors.orange : Colors.blue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: isTablet ? 24 : 16),
              
              // Admin-specific section
              if (_isAdmin) ...[
                Card(
                  elevation: isTablet ? 4 : 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(isTablet ? 24.0 : 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Admin Features',
                          style: TextStyle(
                            fontSize: isTablet ? 22 : 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: isTablet ? 20 : 16),
                        ListTile(
                          leading: Icon(Icons.admin_panel_settings, size: isTablet ? 28 : 24),
                          title: Text(
                            'Admin Panel',
                            style: TextStyle(fontSize: isTablet ? 18 : 16),
                          ),
                          subtitle: Text(
                            'Manage users and system settings',
                            style: TextStyle(fontSize: isTablet ? 16 : 14),
                          ),
                          trailing: Icon(Icons.arrow_forward_ios, size: isTablet ? 20 : 16),
                          onTap: () {
                            Navigator.of(context).pushNamed('/admin');
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: isTablet ? 24 : 16),
              ],
              
              // Sign out section
              Card(
                elevation: isTablet ? 4 : 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                ),
                child: Padding(
                  padding: EdgeInsets.all(isTablet ? 24.0 : 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Account Actions',
                        style: TextStyle(
                          fontSize: isTablet ? 22 : 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: isTablet ? 20 : 16),
                      ListTile(
                        leading: Icon(Icons.logout, color: Colors.red, size: isTablet ? 28 : 24),
                        title: Text(
                          'Sign Out',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: isTablet ? 18 : 16,
                          ),
                        ),
                        subtitle: Text(
                          'Sign out of your account',
                          style: TextStyle(fontSize: isTablet ? 16 : 14),
                        ),
                        onTap: _signOut,
                      ),
                    ],
                  ),
                ),
              ),
              
              SizedBox(height: isTablet ? 40 : 24),
              
              // App info
              Center(
                child: Text(
                  'Indoor Navigation for Visually Impaired',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: isTablet ? 14 : 12,
                  ),
                ),
              ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
} 