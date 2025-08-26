import 'package:flutter/material.dart';
import '../user/navigation_main_screen.dart';
import 'map_management.dart';
import '../common/profile_screen.dart';
import 'package:camera/camera.dart';

class AdminHomeScreen extends StatelessWidget {
  final List<CameraDescription> cameras;
  
  const AdminHomeScreen({Key? key, required this.cameras}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final isTablet = screenWidth > 600;
    final isLargeTablet = screenWidth > 900;
    
    // Calculate responsive values
    final horizontalPadding = isLargeTablet ? 48.0 : (isTablet ? 32.0 : 20.0);
    final verticalPadding = isTablet ? 24.0 : 16.0;
    final bottomSafeArea = mediaQuery.padding.bottom;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Admin Dashboard',
          style: TextStyle(
            fontSize: isTablet ? 22 : 20,
          ),
        ),
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
            padding: EdgeInsets.only(
              left: horizontalPadding,
              right: horizontalPadding,
              top: verticalPadding,
              bottom: bottomSafeArea > 0 ? verticalPadding + 8 : verticalPadding,
            ),
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
                          size: isLargeTablet ? 120 : (isTablet ? 100 : 80),
                          color: Colors.white,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Welcome, Admin',
                          style: TextStyle(
                            fontSize: isLargeTablet ? 32 : (isTablet ? 28 : 24),
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Choose an option below',
                          style: TextStyle(
                            fontSize: isLargeTablet ? 18 : (isTablet ? 16 : 14),
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
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // For very wide screens, use a grid layout
                      if (constraints.maxWidth > 800) {
                        return GridView.count(
                          crossAxisCount: isLargeTablet ? 3 : 2,
                          crossAxisSpacing: 20,
                          mainAxisSpacing: 20,
                          childAspectRatio: 1.5,
                          children: [
                            _buildMenuCard(
                              context,
                              icon: Icons.navigation,
                              title: 'Navigation',
                              subtitle: 'Test navigation system',
                              color: Colors.green,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => NavigationMainScreen(
                                      camera: cameras.first,
                                    ),
                                  ),
                                );
                              },
                              isLargeScreen: isLargeTablet,
                            ),
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
                              isLargeScreen: isLargeTablet,
                            ),
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
                              isLargeScreen: isLargeTablet,
                            ),
                          ],
                        );
                      } else {
                        // For mobile and small tablets, use column layout
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildMenuCard(
                              context,
                              icon: Icons.navigation,
                              title: 'Navigation',
                              subtitle: 'Test navigation system',
                              color: Colors.green,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => NavigationMainScreen(
                                      camera: cameras.first,
                                    ),
                                  ),
                                );
                              },
                              isLargeScreen: isTablet,
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
                              isLargeScreen: isTablet,
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
                              isLargeScreen: isTablet,
                            ),
                          ],
                        );
                      }
                    },
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
    bool isLargeScreen = false,
  }) {
    final cardPadding = isLargeScreen ? 24.0 : 16.0;
    final borderRadius = isLargeScreen ? 16.0 : 12.0;
    final iconSize = isLargeScreen ? 32.0 : 24.0;
    final titleFontSize = isLargeScreen ? 20.0 : 18.0;
    final subtitleFontSize = isLargeScreen ? 16.0 : 14.0;
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(cardPadding),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(borderRadius),
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
              padding: EdgeInsets.all(isLargeScreen ? 20 : 16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(borderRadius * 0.75),
              ),
              child: Icon(
                icon,
                size: iconSize,
                color: color,
              ),
            ),
            SizedBox(width: isLargeScreen ? 24 : 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: subtitleFontSize,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: iconSize * 0.7,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }
} 