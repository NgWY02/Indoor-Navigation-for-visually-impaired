import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';
import '../admin/user_management_screen.dart';


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
        // final profile = await _supabaseService.getCurrentUserProfile(); 
        
        setState(() {
          _userEmail = user.email ?? 'No email available';
          _isAdmin = isAdmin;
          _isLoading = false;
        });
      
      } else {
        // User is not logged in, navigate back to home (AuthWrapper will handle login)
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
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
      // Navigate to home (AuthWrapper will handle showing login screen)
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error signing out: $e'))
      );
    }
  }

  void _navigateToUserManagement() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const UserManagementScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;

    // Phone-optimized sizing with small phone adjustments
    final bool isSmallPhone = screenHeight < 600;
    final double buttonHeight = isSmallPhone ? 94.0 : 98.0;
    final double iconSize = 25.0;
    final double titleFontSize = isSmallPhone ? 16.0 : 18.0;
    final double subtitleFontSize = isSmallPhone ? 10.0 : 12.0;
    final double padding = 24.0;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Semantics(
            label: 'Profile loading',
            child: const Text('Profile'),
          ),
          backgroundColor: Colors.black,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Semantics(
          label: 'Profile screen',
          child: const Text('Profile'),
        ),
        backgroundColor: Colors.black,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(padding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
              // Profile Header
              Semantics(
                label: 'User profile information',
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: isSmallPhone ? 16 : 20),
                  child: Column(
                    children: [
                      Semantics(
                        label: 'User avatar',
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.blue.shade600,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black, width: 2),
                          ),
                          child: Center(
                            child: Text(
                              _userEmail.isNotEmpty ? _userEmail[0].toUpperCase() : '?',
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Semantics(
                        label: 'User email',
                        child: Text(
                          _userEmail,
                          style: TextStyle(
                            fontSize: titleFontSize,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

                    SizedBox(height: isSmallPhone ? 32 : 40),

              if (_isAdmin) ...[
                Semantics(
                  label: 'Admin actions section',
                  child: Text(
                    'Admin Actions',
                    style: TextStyle(
                      fontSize: titleFontSize + 2,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Semantics(
                  label: 'Organization management button',
                  hint: 'Opens organization settings',
                  button: true,
                  child: _buildAccessibleButton(
                    context: context,
                    icon: Icons.people,
                    title: 'Manage Organization',
                    subtitle: 'Assign users to organization',
                    backgroundColor: Colors.blue.shade600,
                    onTap: _navigateToUserManagement,
                    buttonHeight: buttonHeight,
                    iconSize: iconSize,
                    titleFontSize: titleFontSize,
                    subtitleFontSize: subtitleFontSize,
                  ),
                ),
                const SizedBox(height: 24),
              ],

              Semantics(
                label: 'Account actions section',
                child: Text(
                  'Account',
                  style: TextStyle(
                    fontSize: titleFontSize + 2,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Semantics(
                label: 'Sign out button',
                hint: 'Signs out of your account',
                button: true,
                child: _buildAccessibleButton(
                  context: context,
                  icon: Icons.logout,
                  title: 'Sign Out',
                  subtitle: 'Sign out of your account',
                  backgroundColor: Colors.red.shade600,
                  onTap: _signOut,
                  buttonHeight: buttonHeight,
                  iconSize: iconSize,
                  titleFontSize: titleFontSize,
                  subtitleFontSize: subtitleFontSize,
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccessibleButton({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color backgroundColor,
    required VoidCallback onTap,
    required double buttonHeight,
    required double iconSize,
    required double titleFontSize,
    required double subtitleFontSize,
  }) {
    return Container(
      height: buttonHeight,
      width: double.infinity,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: Colors.white,
                  size: iconSize,
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: subtitleFontSize,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward,
                  color: Colors.white,
                  size: 28,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}