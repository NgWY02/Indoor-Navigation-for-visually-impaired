import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({Key? key}) : super(key: key);

  @override
  _UserManagementScreenState createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final SupabaseService _supabaseService = SupabaseService();

  List<Map<String, dynamic>> _organizations = [];
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  String? _errorMessage;

  String? _selectedOrganizationId;
  String _userEmailInput = '';

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

      // Load organizations
      final organizations = await _supabaseService.getAllOrganizations();

      // Load users with their organizations
      final users = await _supabaseService.getAllUsersWithOrganizations();

      if (mounted) {
        setState(() {
          _organizations = organizations;
          _users = users;
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
    if (_userEmailInput.isEmpty || _selectedOrganizationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter user email and select organization')),
      );
      return;
    }

    try {
      await _supabaseService.assignUserToOrganization(
        _userEmailInput,
        _selectedOrganizationId!,
      );

      // Clear the input
      if (mounted) {
        setState(() {
          _userEmailInput = '';
          _selectedOrganizationId = null;
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User assigned successfully!')),
      );
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
    final screenHeight = mediaQuery.size.height;
    final viewPadding = mediaQuery.viewPadding;

    // Phone-optimized sizing with small phone adjustments
    final bool isSmallPhone = screenHeight < 600;
    final bool isSmallScreen = screenHeight < 600; 
    final double buttonHeight = isSmallPhone ? 92.0 : 96.0;
    final double iconSize = 40.0;
    final double titleFontSize = isSmallPhone ? 16.0 : 18.0;
    final double subtitleFontSize = isSmallPhone ? 12.0 : 14.0;
    final double padding = 24.0;
    final double verticalPadding = padding;
    final double horizontalPadding = padding;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Semantics(
            label: 'Organization management loading',
            child: const Text('Organization Management'),
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

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Semantics(
            label: 'Organization management error',
            child: const Text('Organization Management'),
          ),
          backgroundColor: Colors.black,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(padding),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Semantics(
                    label: 'Error icon',
                    child: Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Semantics(
                    label: 'Error message',
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        fontSize: titleFontSize,
                        color: Colors.black,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Semantics(
                    label: 'Retry button',
                    hint: 'Tap to retry loading data',
                    button: true,
                    child: _buildAccessibleButton(
                      context: context,
                      icon: Icons.refresh,
                      title: 'Retry',
                      subtitle: 'Try loading data again',
                      backgroundColor: Colors.blue.shade600,
                      onTap: _loadData,
                      buttonHeight: buttonHeight,
                      iconSize: iconSize,
                      titleFontSize: titleFontSize,
                      subtitleFontSize: subtitleFontSize,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Semantics(
          label: 'Organization management screen',
          child: const Text('Organization Management'),
        ),
        backgroundColor: Colors.black,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          color: Colors.blue.shade600,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Quick Actions
                Semantics(
                  label: 'Quick actions section',
                  child: Text(
                    'Quick Actions',
                    style: TextStyle(
                      fontSize: titleFontSize + 2,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Semantics(
                  label: 'Create organization button',
                  hint: 'Opens dialog to create new organization',
                  button: true,
                  child: _buildAccessibleButton(
                    context: context,
                    icon: Icons.add_business,
                    title: 'Create Organization',
                    subtitle: 'Add new organization',
                    backgroundColor: Colors.green.shade600,
                    onTap: _showCreateOrganizationDialog,
                    buttonHeight: buttonHeight,
                    iconSize: iconSize,
                    titleFontSize: titleFontSize,
                    subtitleFontSize: subtitleFontSize,
                  ),
                ),
                const SizedBox(height: 16),
                Semantics(
                  label: 'Assign users button',
                  hint: 'Opens dialog to assign users to organizations',
                  button: true,
                  child: _buildAccessibleButton(
                    context: context,
                    icon: Icons.assignment_ind,
                    title: 'Assign Users',
                    subtitle: 'Manage user assignments',
                    backgroundColor: Colors.blue.shade600,
                    onTap: () => _showAssignmentDialog(padding, padding, viewPadding),
                    buttonHeight: buttonHeight,
                    iconSize: iconSize,
                    titleFontSize: titleFontSize,
                    subtitleFontSize: subtitleFontSize,
                  ),
                ),

                SizedBox(height: padding),

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
                                        '$userCount ${userCount == 1 ? 'user' : 'users'}',
                                        style: TextStyle(
                                          fontSize: isSmallScreen ? 11 : 12,
                                          color: Colors.grey[500],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              onTap: () => _showOrganizationUsersDialog(org['id'], org['name'] ?? 'Organization'),
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

                // Bottom padding for navigation bar
                SizedBox(height: viewPadding.bottom + verticalPadding),
              ],
            ),
          ),
        ),
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

  void _showAssignmentDialog(double horizontalPadding, double verticalPadding, EdgeInsets viewPadding) {
    // Clear the email input when opening the dialog
    _userEmailInput = '';

    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final isSmallScreen = screenSize.width < 360;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Assign User to Organization',
          style: TextStyle(
            fontSize: isSmallScreen ? 18 : 20,
            fontWeight: FontWeight.bold,
            color: Colors.grey[800],
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User Email Input
              Text(
                'User Email',
                style: TextStyle(
                  fontSize: isSmallScreen ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              SizedBox(height: verticalPadding / 2),
              TextField(
                controller: TextEditingController(text: _userEmailInput),
                decoration: InputDecoration(
                  hintText: 'Enter user email address',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Theme.of(context).primaryColor),
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding / 2,
                    vertical: verticalPadding / 2,
                  ),
                ),
                style: TextStyle(
                  fontSize: isSmallScreen ? 14 : 16,
                  color: Colors.grey[800],
                ),
                keyboardType: TextInputType.emailAddress,
                onChanged: (value) {
                  _userEmailInput = value.trim();
                },
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
            ],
          ),
        ),
      ),
    );
  }

  void _showOrganizationUsersDialog(String organizationId, String organizationName) async {
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final isSmallScreen = screenSize.width < 360;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Users in Organization',
              style: TextStyle(
                fontSize: isSmallScreen ? 16 : 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            SizedBox(height: 4),
            Text(
              organizationName,
              style: TextStyle(
                fontSize: isSmallScreen ? 14 : 16,
                color: Theme.of(context).primaryColor,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _supabaseService.getUsersByOrganization(organizationId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return SizedBox(
                  height: 200,
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              if (snapshot.hasError) {
                return SizedBox(
                  height: 200,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: isSmallScreen ? 32 : 40,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Error loading users',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: isSmallScreen ? 14 : 16,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 4),
                        Text(
                          '${snapshot.error}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: isSmallScreen ? 12 : 14,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              }

              final users = snapshot.data ?? [];

              if (users.isEmpty) {
                return SizedBox(
                  height: 200,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.people_outline,
                          color: Colors.grey[400],
                          size: isSmallScreen ? 48 : 64,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No users assigned',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: isSmallScreen ? 16 : 18,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'This organization has no assigned users yet',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: isSmallScreen ? 12 : 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              }

              // Calculate dynamic height based on number of users
              final itemHeight = isSmallScreen ? 85.0 : 95.0; // Increased for subtitle layout
              final maxHeight = screenSize.height * 0.7;
              final calculatedHeight = (users.length * itemHeight) + 32; // 32 for padding
              final dialogHeight = calculatedHeight > maxHeight ? maxHeight : calculatedHeight;

              return SizedBox(
                height: dialogHeight,
                child: ListView.builder(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final user = users[index];
                    final email = user['email'] ?? 'No Email';
                    final role = user['role'] ?? 'user';
                    final roleText = role == 'admin' ? 'Administrator' : 'User';

                    return Container(
                      margin: EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: ListTile(
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: isSmallScreen ? 12 : 16,
                          vertical: isSmallScreen ? 12 : 16,
                        ),
                        title: Text(
                          email,
                          style: TextStyle(
                            fontSize: isSmallScreen ? 12 : 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[800],
                          ),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Container(
                          margin: EdgeInsets.only(top: 4),
                          padding: EdgeInsets.symmetric(
                            horizontal: roleText.length > 4 ? 10 : 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: role == 'admin' ? Colors.blue[100] : Colors.green[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            roleText,
                            style: TextStyle(
                              fontSize: isSmallScreen ? 10 : 12,
                              fontWeight: FontWeight.w500,
                              color: role == 'admin' ? Colors.blue[800] : Colors.green[800],
                            ),
                          ),
                        ),
                        trailing: IconButton(
                          icon: Icon(
                            Icons.remove_circle_outline,
                            color: Colors.red[400],
                            size: isSmallScreen ? 20 : 24,
                          ),
                          onPressed: () => _showRemoveUserDialog(email, organizationName, organizationId),
                          tooltip: 'Remove user from organization',
                          padding: EdgeInsets.zero,
                          constraints: BoxConstraints(),
                        ),
                        isThreeLine: false,
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(
                horizontal: isSmallScreen ? 16 : 20,
                vertical: isSmallScreen ? 8 : 12,
              ),
            ),
            child: Text(
              'Close',
              style: TextStyle(
                fontSize: isSmallScreen ? 14 : 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showRemoveUserDialog(String userEmail, String organizationName, String organizationId) {
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final isSmallScreen = screenSize.width < 360;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Remove User',
          style: TextStyle(
            fontSize: isSmallScreen ? 16 : 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to remove "$userEmail" from "$organizationName"? '
          'This will:\n\n'
          '• Remove the user from this organization\n'
          '• Clear organization_id from all their content\n'
          '• The user can still access the app but won\'t be part of this organization\n\n'
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
              Navigator.of(context).pop(); // Close confirmation dialog
              Navigator.of(context).pop(); // Close users dialog
              _removeUserFromOrganization(userEmail, organizationName);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(
              'REMOVE',
              style: TextStyle(
                fontSize: isSmallScreen ? 14 : 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _removeUserFromOrganization(String userEmail, String organizationName) async {
    try {
      await _supabaseService.removeUserFromOrganization(userEmail);

      // Refresh the data to show updated state
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('User "$userEmail" removed from "$organizationName" successfully!')),
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
