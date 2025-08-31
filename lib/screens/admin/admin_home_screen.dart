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
    final cameras = this.cameras; // Store reference to cameras
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    
    // Responsive values for phones
    final padding = screenWidth * 0.05; // 5% of screen width
    final iconSize = screenWidth * 0.1; // 10% of screen width
    final titleFontSize = screenWidth * 0.06; // 6% of screen width
    final subtitleFontSize = screenWidth * 0.04; // 4% of screen width
    final cardHeight = screenHeight * 0.12; // 12% of screen height
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        centerTitle: true,
        backgroundColor: Colors.blueAccent,
        elevation: 2,
      ),
      body: Container(
        color: Colors.grey.shade100,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(padding),
            child: Column(
              children: [
                // Welcome Section
                Container(
                  padding: EdgeInsets.symmetric(vertical: screenHeight * 0.03),
                  child: Column(
                    children: [
                      Icon(
                        Icons.admin_panel_settings,
                        size: iconSize,
                        color: Colors.blueAccent,
                      ),
                      SizedBox(height: screenHeight * 0.02),
                      Text(
                        'Welcome, Admin',
                        style: TextStyle(
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(height: screenHeight * 0.01),
                      Text(
                        'Choose an option below',
                        style: TextStyle(
                          fontSize: subtitleFontSize,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                // Menu Cards
                Expanded(
                  child: ListView(
                    children: [
                      _buildMenuCard(
                        context,
                        icon: Icons.navigation,
                        title: 'Navigation',
                        subtitle: 'Test navigation system',
                        color: Colors.green,
                        cameras: cameras,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => NavigationMainScreen(
                                camera: cameras.first,
                              ),
                            ),
                          );
                        },
                        cardHeight: cardHeight,
                        screenWidth: screenWidth,
                        screenHeight: screenHeight,
                      ),
                      SizedBox(height: screenHeight * 0.02),
                      _buildMenuCard(
                        context,
                        icon: Icons.map,
                        title: 'Map Management',
                        subtitle: 'Manage maps and nodes',
                        color: Colors.orange,
                        cameras: cameras,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => MapManagement(cameras: cameras),
                            ),
                          );
                        },
                        cardHeight: cardHeight,
                        screenWidth: screenWidth,
                        screenHeight: screenHeight,
                      ),
                      SizedBox(height: screenHeight * 0.02),
                      _buildMenuCard(
                        context,
                        icon: Icons.person,
                        title: 'Profile',
                        subtitle: 'Account settings',
                        color: Colors.purple,
                        cameras: cameras,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const ProfileScreen(),
                            ),
                          );
                        },
                        cardHeight: cardHeight,
                        screenWidth: screenWidth,
                        screenHeight: screenHeight,
                      ),
                    ],
                  ),
                ),
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
    required List<CameraDescription> cameras,
    required VoidCallback onTap,
    required double cardHeight,
    required double screenWidth,
    required double screenHeight,
  }) {
    final iconSize = screenWidth * 0.08;
    final titleFontSize = screenWidth * 0.045;
    final subtitleFontSize = screenWidth * 0.035;
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: cardHeight,
          padding: EdgeInsets.all(screenWidth * 0.04),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(screenWidth * 0.03),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: iconSize,
                  color: color,
                ),
              ),
              SizedBox(width: screenWidth * 0.04),
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
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.005),
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
                size: iconSize * 0.6,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }
} 