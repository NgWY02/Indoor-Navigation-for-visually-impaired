import 'package:flutter/material.dart';
import 'services/supabase_service.dart';

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
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Profile'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          // Add admin button in app bar for quick access
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings),
              onPressed: () {
                Navigator.of(context).pushNamed('/admin');
              },
              tooltip: 'Admin Dashboard',
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile header
            Center(
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.blue,
                    child: Icon(
                      Icons.person,
                      size: 50,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _userEmail,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isAdmin ? 'Administrator' : 'Regular User',
                    style: TextStyle(
                      fontSize: 16,
                      color: _isAdmin ? Colors.purple : Colors.blue,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
            
            // Admin panel button (more prominent)
            if (_isAdmin) ...[
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 24),
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushNamed('/admin');
                  },
                  icon: const Icon(Icons.admin_panel_settings),
                  label: const Text('Open Admin Dashboard'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
            
            // Profile options
            const Text(
              'Account Settings',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const Divider(),
            
            // Profile options list
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About'),
              onTap: () {
                showAboutDialog(
                  context: context,
                  applicationName: 'Indoor Navigation App',
                  applicationVersion: '1.0.0',
                  applicationLegalese: '© 2024 Indoor Navigation Team',
                  children: [
                    const Text(
                      'An indoor navigation app designed to help visually impaired users navigate indoor spaces with audio guidance.',
                    ),
                  ],
                );
              },
            ),
            
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () {
                // Navigate to settings screen (if implemented)
                // Navigator.of(context).pushNamed('/settings');
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Settings feature coming soon'))
                );
              },
            ),
            
            const Spacer(),
            
            // Sign out button
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _signOut,
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Sign Out'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
} 