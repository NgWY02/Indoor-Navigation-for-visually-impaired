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
        // final profile = await _supabaseService.getCurrentUserProfile(); // Removed for simplified single-user experience
        
        setState(() {
          _userEmail = user.email ?? 'No email available';
          _isAdmin = isAdmin;
          _isLoading = false;
        });
        
        // User invite code functionality removed for simplified single-user experience
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

  /*
  void _showQuickInviteDialog(BuildContext context) {
    final TextEditingController userCodeController = TextEditingController();
    String? selectedGroupId;
    List<Map<String, dynamic>> myGroups = [];
    bool isLoading = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          if (isLoading) {
            // Load groups when dialog opens
            _supabaseService.getGroupsICreated().then((groups) {
              setDialogState(() {
                myGroups = groups;
                isLoading = false;
                if (groups.isNotEmpty) {
                  selectedGroupId = groups.first['id'];
                }
              });
            }).catchError((error) {
              setDialogState(() {
                isLoading = false;
              });
              print('Error loading groups: $error');
            });
          }

          return AlertDialog(
            title: const Text('Quick Invite User'),
            content: SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Enter user code to invite:'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: userCodeController,
                    decoration: const InputDecoration(
                      hintText: 'e.g. ABC123',
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.characters,
                  ),
                  const SizedBox(height: 16),
                  const Text('Select group:'),
                  const SizedBox(height: 8),
                  if (isLoading)
                    const Center(child: CircularProgressIndicator())
                  else if (myGroups.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: const Text(
                        'No groups found. Create a group first in Group Management.',
                        style: TextStyle(color: Colors.orange),
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      value: selectedGroupId,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      items: myGroups.map((group) {
                        return DropdownMenuItem<String>(
                          value: group['id'],
                          child: Text(group['name'] ?? 'Unnamed Group'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          selectedGroupId = value;
                        });
                      },
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: (myGroups.isEmpty || userCodeController.text.isEmpty)
                    ? null
                    : () => _inviteUser(context, userCodeController.text.trim(), selectedGroupId!),
                child: const Text('Invite'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _inviteUser(BuildContext context, String userCode, String groupId) async {
    Navigator.of(context).pop(); // Close dialog first

    try {
      await _supabaseService.addUserToGroupByCode(
        groupId: groupId,
        userCode: userCode.toUpperCase(),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('User $userCode successfully invited to group!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      String message = 'Failed to invite user';
      if (e.toString().contains('User code not found')) {
        message = 'User code "$userCode" not found. Please check and try again.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  */

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final bottomPadding = mediaQuery.padding.bottom;
    
    // Responsive values based on screen size
    final isSmallPhone = screenWidth < 360;
    final isLargePhone = screenWidth > 414;
    
    final horizontalPadding = isSmallPhone ? 16.0 : (isLargePhone ? 24.0 : 20.0);
    final cardPadding = isSmallPhone ? 16.0 : (isLargePhone ? 24.0 : 20.0);
    final avatarSize = isSmallPhone ? 70.0 : (isLargePhone ? 90.0 : 80.0);
    final titleFontSize = isSmallPhone ? 16.0 : (isLargePhone ? 20.0 : 18.0);
    final subtitleFontSize = isSmallPhone ? 13.0 : (isLargePhone ? 15.0 : 14.0);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          title: const Text('Profile'),
          backgroundColor: Colors.blue.shade700,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.blue.shade700,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                horizontalPadding,
                horizontalPadding,
                horizontalPadding + bottomPadding + 16, // Extra padding for bottom nav
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - (horizontalPadding * 2) - bottomPadding - 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildProfileCard(context, avatarSize, cardPadding, titleFontSize),
                    SizedBox(height: isSmallPhone ? 20 : 24),
                    if (_isAdmin) ...[
                      _buildSectionTitle('Admin Actions', isSmallPhone),
                      SizedBox(height: isSmallPhone ? 8 : 12),
                      _buildAdminActions(context, cardPadding, titleFontSize, subtitleFontSize),
                      SizedBox(height: isSmallPhone ? 20 : 24),
                    ],
                    _buildSectionTitle('Account', isSmallPhone),
                    SizedBox(height: isSmallPhone ? 8 : 12),
                    _buildAccountActions(context, cardPadding, titleFontSize, subtitleFontSize),
                    SizedBox(height: isSmallPhone ? 32 : 40),
                    _buildAppInfo(isSmallPhone),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildProfileCard(BuildContext context, double avatarSize, double cardPadding, double titleFontSize) {
    final String avatarText = _userEmail.isNotEmpty ? _userEmail[0].toUpperCase() : '?';
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: EdgeInsets.all(cardPadding),
      child: Column(
        children: [
          Container(
            width: avatarSize,
            height: avatarSize,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.blue.shade400,
                  Colors.purple.shade400,
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                avatarText,
                style: TextStyle(
                  fontSize: avatarSize * 0.4,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _userEmail,
            style: TextStyle(
              fontSize: titleFontSize,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _isAdmin ? Colors.amber.shade100 : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _isAdmin ? Colors.amber.shade200 : Colors.blue.shade200,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isAdmin ? Icons.admin_panel_settings : Icons.person,
                  size: 16,
                  color: _isAdmin ? Colors.amber.shade700 : Colors.blue.shade700,
                ),
                const SizedBox(width: 6),
                Text(
                  _isAdmin ? 'Administrator' : 'User',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _isAdmin ? Colors.amber.shade700 : Colors.blue.shade700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // User Code Section - Removed for simplified single-user experience
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, bool isSmallPhone) {
    return Text(
      title,
      style: TextStyle(
        fontSize: isSmallPhone ? 18 : 20,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildAdminActions(BuildContext context, double cardPadding, double titleFontSize, double subtitleFontSize) {
    return Column(
      children: [
        // Quick Invite removed for simplified single-user experience
        /*
        _buildActionTile(
          icon: Icons.person_add,
          title: 'Quick Invite',
          subtitle: 'Add user to group by user code',
          color: Colors.green.shade600,
          onTap: () => _showQuickInviteDialog(context),
          cardPadding: cardPadding,
          titleFontSize: titleFontSize,
          subtitleFontSize: subtitleFontSize,
        ),
        SizedBox(height: cardPadding * 0.6),
        */
        _buildActionTile(
          icon: Icons.people,
          title: 'User Management',
          subtitle: 'Manage user organization assignments',
          color: Colors.blue.shade600,
          onTap: _navigateToUserManagement,
          cardPadding: cardPadding,
          titleFontSize: titleFontSize,
          subtitleFontSize: subtitleFontSize,
        ),
        SizedBox(height: cardPadding * 0.6),
        _buildActionTile(
          icon: Icons.image_search,
          title: 'Image Test',
          subtitle: 'Test image recognition system',
          color: Colors.orange.shade600,
          onTap: () => Navigator.of(context).pushNamed('/image_test'),
          isTemporary: true,
          cardPadding: cardPadding,
          titleFontSize: titleFontSize,
          subtitleFontSize: subtitleFontSize,
        ),
      ],
    );
  }

  Widget _buildAccountActions(BuildContext context, double cardPadding, double titleFontSize, double subtitleFontSize) {
    return _buildActionTile(
      icon: Icons.logout,
      title: 'Sign Out',
      subtitle: 'Sign out of your account',
      color: Colors.red.shade600,
      onTap: _signOut,
      cardPadding: cardPadding,
      titleFontSize: titleFontSize,
      subtitleFontSize: subtitleFontSize,
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    required double cardPadding,
    required double titleFontSize,
    required double subtitleFontSize,
    bool isTemporary = false,
  }) {
    final iconSize = cardPadding > 20 ? 50.0 : 45.0;
    final iconPadding = cardPadding > 20 ? 20.0 : 16.0;
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: EdgeInsets.all(iconPadding),
            child: Row(
              children: [
                Container(
                  width: iconSize,
                  height: iconSize,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: iconSize * 0.48,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontSize: titleFontSize,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          if (isTemporary) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'TEMP',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: subtitleFontSize,
                          color: Colors.grey.shade600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.grey.shade400,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppInfo(bool isSmallPhone) {
    return Center(
      child: Column(
        children: [
          Text(
            'Indoor Navigation for Visually Impaired',
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: isSmallPhone ? 11 : 12,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Version 1.0.0',
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: isSmallPhone ? 9 : 10,
            ),
          ),
        ],
      ),
    );
  }
}