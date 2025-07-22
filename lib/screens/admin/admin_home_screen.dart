import 'package:flutter/material.dart';
import '../../services/responsive_helper.dart';
import '../../navigation_localization.dart';
import '../../admin/map_management.dart';
import '../common/profile_screen.dart';
import 'package:camera/camera.dart';

class AdminHomeScreen extends StatelessWidget {
  final List<CameraDescription> cameras;
  
  const AdminHomeScreen({Key? key, required this.cameras}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        centerTitle: true,
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blue.shade700,
              Colors.blue.shade50,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: ResponsiveHelper.getResponsivePadding(context),
            child: Column(
              children: [
                Expanded(
                  flex: 1,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.admin_panel_settings,
                          size: ResponsiveHelper.getLargeIconSize(context),
                          color: Colors.white,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Welcome, Admin',
                          style: TextStyle(
                            fontSize: ResponsiveHelper.getHeaderFontSize(context),
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Choose an option below',
                          style: TextStyle(
                            fontSize: ResponsiveHelper.getBodyFontSize(context),
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                      ],
                    ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildMenuCard(
                        context,
                        icon: Icons.navigation,
                        title: 'Navigation',
                        subtitle: 'Access navigation system',
                        color: Colors.green,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => NavigationLocalizationScreen(
                                camera: cameras.first,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      _buildMenuCard(
                        context,
                        icon: Icons.map,
                        title: 'Map Management',
                        subtitle: 'Manage maps and nodes',
                        color: Colors.orange,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const MapManagement(),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      _buildMenuCard(
                        context,
                        icon: Icons.person,
                        title: 'Profile',
                        subtitle: 'Account settings',
                        color: Colors.purple,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const ProfileScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: ResponsiveHelper.getResponsivePadding(context),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(ResponsiveHelper.getBorderRadius(context)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: ResponsiveHelper.getIconSize(context),
                color: color,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: ResponsiveHelper.getTitleFontSize(context),
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: ResponsiveHelper.getBodyFontSize(context),
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: ResponsiveHelper.getIconSize(context) * 0.7,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }
} 