import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({Key? key}) : super(key: key);

  @override
  _UserManagementScreenState createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final SupabaseService _supabaseService = SupabaseService();

  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _organizations = [];
  bool _isLoading = true;
  String? _errorMessage;

  String? _selectedUserEmail;
  String? _selectedOrganizationId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Check if user is admin
      final isAdmin = await _supabaseService.isAdmin();
      if (!isAdmin) {
        setState(() {
          _errorMessage = 'Access denied. Admin privileges required.';
          _isLoading = false;
        });
        return;
      }

      // Load users and organizations in parallel for better performance
      final results = await Future.wait([
        _supabaseService.getAllUsersWithOrganizations(),
        _supabaseService.getAllOrganizations(),
      ]);

      final users = results[0];
      final organizations = results[1];

      if (mounted) {
        setState(() {
          _users = users;
          _organizations = organizations;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error loading data: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _assignUserToOrganization() async {
    if (_selectedUserEmail == null || _selectedOrganizationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select both user and organization')),
      );
      return;
    }

    try {
      await _supabaseService.assignUserToOrganization(
        _selectedUserEmail!,
        _selectedOrganizationId!,
      );

      // Update the local data instead of reloading everything for better performance
      if (mounted) {
        setState(() {
          // Find and update the user in the local list
          final userIndex = _users.indexWhere((user) => user['email'] == _selectedUserEmail);
          if (userIndex != -1) {
            final selectedOrg = _organizations.firstWhere(
              (org) => org['id'] == _selectedOrganizationId,
              orElse: () => <String, dynamic>{},
            );
            _users[userIndex] = {
              ..._users[userIndex],
              'organization_id': _selectedOrganizationId,
              'organizations': selectedOrg.isNotEmpty ? selectedOrg : null,
            };
          }

          // Clear selections
          _selectedUserEmail = null;
          _selectedOrganizationId = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User assigned successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error assigning user: ${e.toString()}')),
        );
      }
    }
  }

  void _showCreateOrganizationDialog() {
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final isSmallScreen = screenSize.width < 360;

    final TextEditingController nameController = TextEditingController();
    final TextEditingController descriptionController = TextEditingController();
    bool isCreating = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            'Create New Organization',
            style: TextStyle(
              fontSize: isSmallScreen ? 16 : 18,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Organization Name',
                  hintText: 'Enter organization name',
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: isSmallScreen ? 12 : 16,
                    vertical: isSmallScreen ? 12 : 16,
                  ),
                ),
                style: TextStyle(
                  fontSize: isSmallScreen ? 14 : 16,
                ),
                enabled: !isCreating,
              ),
              SizedBox(height: isSmallScreen ? 12 : 16),
              TextField(
                controller: descriptionController,
                decoration: InputDecoration(
                  labelText: 'Description',
                  hintText: 'Enter organization description',
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: isSmallScreen ? 12 : 16,
                    vertical: isSmallScreen ? 12 : 16,
                  ),
                ),
                style: TextStyle(
                  fontSize: isSmallScreen ? 14 : 16,
                ),
                maxLines: isSmallScreen ? 2 : 3,
                enabled: !isCreating,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isCreating ? null : () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(
                  fontSize: isSmallScreen ? 14 : 16,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: isCreating
                  ? null
                  : () async {
                      if (nameController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter organization name')),
                        );
                        return;
                      }

                      setDialogState(() => isCreating = true);

                      try {
                        await _supabaseService.createOrganization(
                          nameController.text.trim(),
                          descriptionController.text.trim(),
                        );

                        if (mounted) {
                          Navigator.of(context).pop();
                          await _loadData(); // Refresh organizations list

                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Organization created successfully!')),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => isCreating = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error creating organization: ${e.toString()}')),
                          );
                        }
                      }
                    },
              child: isCreating
                  ? SizedBox(
                      width: isSmallScreen ? 16 : 20,
                      height: isSmallScreen ? 16 : 20,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      'Create',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 14 : 16,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removeUserFromOrganization(String userEmail) async {
    try {
      await _supabaseService.removeUserFromOrganization(userEmail);

      // Update the local data instead of reloading everything for better performance
      if (mounted) {
        setState(() {
          // Find and update the user in the local list
          final userIndex = _users.indexWhere((user) => user['email'] == userEmail);
          if (userIndex != -1) {
            _users[userIndex] = {
              ..._users[userIndex],
              'organization_id': null,
              'organizations': null,
            };
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User removed from organization successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error removing user: ${e.toString()}')),
        );
      }
    }
  }

  Future<bool> _canDeleteOrganization(String organizationId) async {
    try {
      final currentUser = _supabaseService.currentUser;
      if (currentUser == null) return false;

      final orgResponse = await _supabaseService.client
          .from('organizations')
          .select('created_by_admin_id')
          .eq('id', organizationId)
          .maybeSingle();

      if (orgResponse == null) return false;

      return orgResponse['created_by_admin_id'] == currentUser.id;
    } catch (e) {
      print('Error checking organization ownership: $e');
      return false;
    }
  }

  Future<void> _deleteOrganization(String organizationId, String organizationName) async {
    try {
      await _supabaseService.deleteOrganization(organizationId);

      // Remove the organization from local list
      if (mounted) {
        setState(() {
          _organizations.removeWhere((org) => org['id'] == organizationId);
          // Also update users that were in this organization
          for (var i = 0; i < _users.length; i++) {
            if (_users[i]['organization_id'] == organizationId) {
              _users[i] = {
                ..._users[i],
                'organization_id': null,
                'organizations': null,
              };
            }
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Organization "$organizationName" deleted successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting organization: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final viewPadding = mediaQuery.viewPadding;
    final isSmallScreen = screenSize.width < 360;
    final isMediumScreen = screenSize.width >= 360 && screenSize.width < 600;

    // Calculate responsive padding
    final horizontalPadding = isSmallScreen ? 8.0 : isMediumScreen ? 12.0 : 16.0;
    final verticalPadding = isSmallScreen ? 8.0 : 12.0;

    if (_isLoading) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('User Management'),
          toolbarHeight: isSmallScreen ? 48 : 56,
        ),
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline,
                      size: isSmallScreen ? 48 : 64,
                      color: Colors.red),
                  SizedBox(height: verticalPadding),
                  Text(
                    _errorMessage!,
                    style: TextStyle(
                      fontSize: isSmallScreen ? 14 : 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: verticalPadding),
                  ElevatedButton(
                    onPressed: _loadData,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('User Management'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          color: Theme.of(context).primaryColor,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(horizontalPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Section
                Container(
                  padding: EdgeInsets.all(verticalPadding),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.admin_panel_settings,
                        color: Theme.of(context).primaryColor,
                        size: isSmallScreen ? 24 : 28,
                      ),
                      SizedBox(width: horizontalPadding / 2),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Admin Dashboard',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 16 : 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[800],
                              ),
                            ),
                            Text(
                              'Manage users and organizations',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 12 : 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: verticalPadding),

                // Quick Actions Row
                Row(
                  children: [
                    Expanded(
                      child: _buildQuickActionCard(
                        icon: Icons.add_business,
                        title: 'Create Organization',
                        subtitle: 'Add new org',
                        color: Colors.green,
                        onTap: _showCreateOrganizationDialog,
                        isSmallScreen: isSmallScreen,
                        horizontalPadding: horizontalPadding,
                        verticalPadding: verticalPadding,
                      ),
                    ),
                    SizedBox(width: horizontalPadding / 2),
                    Expanded(
                      child: _buildQuickActionCard(
                        icon: Icons.assignment_ind,
                        title: 'Assign Users',
                        subtitle: 'Manage assignments',
                        color: Colors.blue,
                        onTap: () => _showAssignmentDialog(horizontalPadding, verticalPadding, viewPadding),
                        isSmallScreen: isSmallScreen,
                        horizontalPadding: horizontalPadding,
                        verticalPadding: verticalPadding,
                      ),
                    ),
                  ],
                ),

                SizedBox(height: verticalPadding),

                // Organizations Section
                _buildSectionHeader(
                  'Organizations',
                  '(${_organizations.length})',
                  isSmallScreen,
                ),
                SizedBox(height: verticalPadding / 2),

                _organizations.isEmpty
                    ? _buildEmptyState(
                        'No organizations found',
                        'Create your first organization to get started',
                        Icons.business,
                        isSmallScreen,
                        verticalPadding,
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _organizations.length,
                        itemBuilder: (context, index) {
                          final org = _organizations[index];
                          final userCount = _users.where((user) => user['organization_id'] == org['id']).length;

                          return Container(
                            margin: EdgeInsets.only(bottom: verticalPadding / 2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: ListTile(
                              contentPadding: EdgeInsets.all(horizontalPadding / 2),
                              leading: CircleAvatar(
                                backgroundColor: Colors.grey[100],
                                child: Icon(
                                  Icons.business,
                                  color: Theme.of(context).primaryColor,
                                  size: isSmallScreen ? 20 : 24,
                                ),
                              ),
                              title: Text(
                                org['name'] ?? 'Unnamed Organization',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: isSmallScreen ? 14 : 16,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(height: 4),
                                  Text(
                                    org['description'] ?? 'No description',
                                    style: TextStyle(
                                      fontSize: isSmallScreen ? 12 : 14,
                                      color: Colors.grey[600],
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.people,
                                        size: 14,
                                        color: Colors.grey[500],
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        '$userCount users',
                                        style: TextStyle(
                                          fontSize: isSmallScreen ? 11 : 12,
                                          color: Colors.grey[500],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              trailing: FutureBuilder<bool>(
                                future: _canDeleteOrganization(org['id']),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState == ConnectionState.waiting) {
                                    return SizedBox(
                                      width: isSmallScreen ? 20 : 24,
                                      height: isSmallScreen ? 20 : 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.grey[400]!),
                                      ),
                                    );
                                  }

                                  final canDelete = snapshot.data ?? false;

                                  if (!canDelete) {
                                    return Tooltip(
                                      message: 'You can only delete organizations you created',
                                      child: Icon(
                                        Icons.lock,
                                        color: Colors.grey[400],
                                        size: isSmallScreen ? 20 : 24,
                                      ),
                                    );
                                  }

                                  return IconButton(
                                    icon: Icon(
                                      Icons.delete_outline,
                                      color: Colors.red[400],
                                      size: isSmallScreen ? 20 : 24,
                                    ),
                                    onPressed: () => _showDeleteOrganizationDialog(org['id'], org['name']),
                                    tooltip: 'Delete organization (you created this)',
                                  );
                                },
                              ),
                            ),
                          );
                        },
                      ),

                SizedBox(height: verticalPadding),

                // Users Section
                _buildSectionHeader(
                  'Users',
                  '(${_users.length})',
                  isSmallScreen,
                ),
                SizedBox(height: verticalPadding / 2),

                _users.isEmpty
                    ? _buildEmptyState(
                        'No users found',
                        'Users will appear here once they register',
                        Icons.people,
                        isSmallScreen,
                        verticalPadding,
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _users.length,
                        itemBuilder: (context, index) {
                          final user = _users[index];
                          final organization = user['organizations'];
                          final organizationName = organization?['name'] ?? 'No Organization';

                          return Container(
                            margin: EdgeInsets.only(bottom: verticalPadding / 2),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: ListTile(
                              contentPadding: EdgeInsets.all(horizontalPadding / 2),
                              leading: CircleAvatar(
                                backgroundColor: Colors.grey[100],
                                child: Icon(
                                  Icons.person,
                                  color: Theme.of(context).primaryColor,
                                  size: isSmallScreen ? 20 : 24,
                                ),
                              ),
                              title: Text(
                                user['email'] ?? 'No Email',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: isSmallScreen ? 14 : 16,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(height: 4),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _getRoleColor(user['role']).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      user['role'] ?? 'user',
                                      style: TextStyle(
                                        fontSize: isSmallScreen ? 11 : 12,
                                        color: _getRoleColor(user['role']),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    organizationName,
                                    style: TextStyle(
                                      fontSize: isSmallScreen ? 12 : 14,
                                      color: Colors.grey[600],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                              trailing: organization != null
                                  ? IconButton(
                                      icon: Icon(
                                        Icons.remove_circle_outline,
                                        color: Colors.orange[400],
                                        size: isSmallScreen ? 20 : 24,
                                      ),
                                      onPressed: () => _showRemoveDialog(user['email']),
                                      tooltip: 'Remove from organization',
                                    )
                                  : null,
                            ),
                          );
                        },
                      ),

                // Bottom padding for navigation bar
                SizedBox(height: viewPadding.bottom + verticalPadding),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showRemoveDialog(String userEmail) {
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final isSmallScreen = screenSize.width < 360;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Remove User from Organization',
          style: TextStyle(
            fontSize: isSmallScreen ? 16 : 18,
          ),
        ),
        content: Text(
          'Are you sure you want to remove $userEmail from their organization?',
          style: TextStyle(
            fontSize: isSmallScreen ? 14 : 16,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontSize: isSmallScreen ? 14 : 16,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _removeUserFromOrganization(userEmail);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(
              'Remove',
              style: TextStyle(
                fontSize: isSmallScreen ? 14 : 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteOrganizationDialog(String organizationId, String organizationName) {
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final isSmallScreen = screenSize.width < 360;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Delete Organization',
          style: TextStyle(
            fontSize: isSmallScreen ? 16 : 18,
          ),
        ),
        content: Text(
          'Are you sure you want to delete "$organizationName"? '
          'This will:\n\n'
          '• Remove all users from this organization\n'
          '• Clear organization_id from all user content\n'
          '• Delete the organization permanently\n\n'
          '⚠️ You can only delete organizations you created.\n'
          'This action cannot be undone!',
          style: TextStyle(
            fontSize: isSmallScreen ? 12 : 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontSize: isSmallScreen ? 14 : 16,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteOrganization(organizationId, organizationName);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(
              'DELETE',
              style: TextStyle(
                fontSize: isSmallScreen ? 14 : 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    required bool isSmallScreen,
    required double horizontalPadding,
    required double verticalPadding,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(horizontalPadding / 2),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: color,
              size: isSmallScreen ? 24 : 28,
            ),
            SizedBox(height: verticalPadding / 4),
            Text(
              title,
              style: TextStyle(
                fontSize: isSmallScreen ? 12 : 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: isSmallScreen ? 10 : 11,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String count, bool isSmallScreen) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: isSmallScreen ? 16 : 18,
            fontWeight: FontWeight.bold,
            color: Colors.grey[800],
          ),
        ),
        SizedBox(width: 8),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            count,
            style: TextStyle(
              fontSize: isSmallScreen ? 12 : 14,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).primaryColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(String title, String subtitle, IconData icon, bool isSmallScreen, double verticalPadding) {
    return Container(
      padding: EdgeInsets.all(verticalPadding * 2),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: isSmallScreen ? 48 : 64,
            color: Colors.grey[400],
          ),
          SizedBox(height: verticalPadding / 2),
          Text(
            title,
            style: TextStyle(
              fontSize: isSmallScreen ? 16 : 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: verticalPadding / 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: isSmallScreen ? 12 : 14,
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Color _getRoleColor(String? role) {
    switch (role?.toLowerCase()) {
      case 'admin':
        return Colors.red;
      case 'moderator':
        return Colors.orange;
      case 'user':
      default:
        return Colors.blue;
    }
  }

  void _showAssignmentDialog(double horizontalPadding, double verticalPadding, EdgeInsets viewPadding) {
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final isSmallScreen = screenSize.width < 360;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        constraints: BoxConstraints(
          maxHeight: screenSize.height * 0.8,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.all(horizontalPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: EdgeInsets.only(bottom: verticalPadding),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Title
            Text(
              'Assign User to Organization',
              style: TextStyle(
                fontSize: isSmallScreen ? 18 : 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            SizedBox(height: verticalPadding),

            // User Selection
            Text(
              'Select User',
              style: TextStyle(
                fontSize: isSmallScreen ? 14 : 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            SizedBox(height: verticalPadding / 2),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding / 2,
                    vertical: verticalPadding / 2,
                  ),
                ),
                value: _selectedUserEmail,
                style: TextStyle(
                  fontSize: isSmallScreen ? 14 : 16,
                  color: Colors.grey[800],
                ),
                items: _users.map((user) {
                  final organizationName = user['organizations']?['name'] ?? 'No Organization';
                  return DropdownMenuItem<String>(
                    value: user['email'],
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: screenSize.width - (horizontalPadding * 4),
                      ),
                      child: Text(
                        '${user['email']} (${user['role']}) - $organizationName',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 12 : 14,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedUserEmail = value;
                  });
                },
              ),
            ),

            SizedBox(height: verticalPadding),

            // Organization Selection
            Text(
              'Select Organization',
              style: TextStyle(
                fontSize: isSmallScreen ? 14 : 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            SizedBox(height: verticalPadding / 2),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding / 2,
                    vertical: verticalPadding / 2,
                  ),
                ),
                value: _selectedOrganizationId,
                style: TextStyle(
                  fontSize: isSmallScreen ? 14 : 16,
                  color: Colors.grey[800],
                ),
                items: _organizations.map((org) {
                  return DropdownMenuItem<String>(
                    value: org['id'],
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: screenSize.width - (horizontalPadding * 4),
                      ),
                      child: Text(
                        '${org['name']} - ${org['description']}',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 12 : 14,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedOrganizationId = value;
                  });
                },
              ),
            ),

            SizedBox(height: verticalPadding * 1.5),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: verticalPadding / 2),
                      side: BorderSide(color: Colors.grey[300]!),
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 14 : 16,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                ),
                SizedBox(width: horizontalPadding / 2),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _assignUserToOrganization();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: verticalPadding / 2),
                    ),
                    child: Text(
                      'Assign',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 14 : 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            SizedBox(height: viewPadding.bottom),
          ],
        ),
      ),
    );
  }
}
