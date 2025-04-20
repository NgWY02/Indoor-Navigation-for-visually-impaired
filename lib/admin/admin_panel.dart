import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import 'map_management.dart';

class AdminPanel extends StatefulWidget {
  const AdminPanel({Key? key}) : super(key: key);

  @override
  _AdminPanelState createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel> {
  final SupabaseService _supabaseService = SupabaseService();
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final isAdmin = await _supabaseService.isAdmin();
      if (!isAdmin) {
        setState(() {
          _errorMessage = 'Access denied. Admin privileges required.';
          _isLoading = false;
        });
        return;
      }

      final users = await _supabaseService.getAllUsers();
      
      if (mounted) {
        setState(() {
          _users = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error loading users: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleUserRole(String userId, UserRole currentRole) async {
    // Toggle the role
    final newRole = currentRole == UserRole.admin ? UserRole.user : UserRole.admin;
    
    try {
      await _supabaseService.updateUserRole(userId, newRole);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('User role updated successfully to ${newRole == UserRole.admin ? 'Admin' : 'User'}'),
          backgroundColor: Colors.green,
        ),
      );
      // Refresh the user list
      _loadUsers();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating user role: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  void _navigateToMapManagement() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const MapManagement(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Panel'),
      ),
      body: Column(
        children: [
          // Admin actions section
          Container(
            padding: const EdgeInsets.all(16.0),
            color: Theme.of(context).primaryColor.withOpacity(0.1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Admin Actions',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _navigateToMapManagement,
                        icon: const Icon(Icons.map),
                        label: const Text('Map Management'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // User management section
          Expanded(
            child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: _loadUsers,
                          child: const Text('Try Again'),
                        ),
                      ],
                    ),
                  )
                : _users.isEmpty
                  ? const Center(
                      child: Text('No users found'),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadUsers,
                      child: ListView.builder(
                        itemCount: _users.length,
                        itemBuilder: (context, index) {
                          final user = _users[index];
                          final userRole = user['role'] == 'admin' ? UserRole.admin : UserRole.user;
                          final profiles = user['profiles'] as Map<String, dynamic>?;
                          final email = profiles != null ? profiles['email'] as String? : 'No email';
                          final name = profiles != null ? profiles['name'] as String? : 'Unknown';
                          
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: userRole == UserRole.admin ? Colors.amber : Colors.blue,
                                child: Icon(
                                  userRole == UserRole.admin 
                                      ? Icons.admin_panel_settings 
                                      : Icons.person,
                                  color: Colors.white,
                                ),
                              ),
                              title: Text(name ?? 'Unknown'),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(email ?? 'No email'),
                                  Text(
                                    'Role: ${userRole == UserRole.admin ? 'Admin' : 'User'}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: userRole == UserRole.admin ? Colors.amber[800] : Colors.blue,
                                    ),
                                  ),
                                ],
                              ),
                              isThreeLine: true,
                              trailing: ElevatedButton(
                                onPressed: () => _toggleUserRole(user['user_id'], userRole),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: userRole == UserRole.admin ? Colors.orange : Colors.green,
                                ),
                                child: Text(
                                  userRole == UserRole.admin ? 'Make User' : 'Make Admin',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
          ),
        ],
      ),
    );
  }
}