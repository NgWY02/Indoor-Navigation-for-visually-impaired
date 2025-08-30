import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'navigation_main_screen.dart';
import '../common/profile_screen.dart';

class UserHomeScreen extends StatelessWidget {
  final List<CameraDescription> cameras;
  
  const UserHomeScreen({Key? key, required this.cameras}) : super(key: key);

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
          'Indoor Navigation',
          style: TextStyle(
            fontSize: isTablet ? 22 : 20,
            fontWeight: FontWeight.bold,
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
                            Icons.accessibility_new,
                            size: isLargeTablet ? 120 : (isTablet ? 100 : 80),
                            color: Colors.white,
                          ),
                          SizedBox(height: isTablet ? 24 : 16),
                          Text(
                            'Welcome',
                            style: TextStyle(
                              fontSize: isLargeTablet ? 36 : (isTablet ? 32 : 28),
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: isTablet ? 12 : 8),
                          Text(
                            'Indoor Navigation System',
                            style: TextStyle(
                              fontSize: isLargeTablet ? 20 : (isTablet ? 18 : 16),
                              color: Colors.white70,
                            ),
                            textAlign: TextAlign.center,
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
                        title: 'Start Navigation',
                        subtitle: 'Find your way indoors',
                        color: Colors.green,
                        onTap: () {
                          // Check if cameras are available
                          if (cameras.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('No camera available on this device'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                          
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
                        icon: Icons.person,
                        title: 'Profile',
                        subtitle: 'Account settings and sign out',
                        color: Colors.blue,
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
    required VoidCallback onTap,
    required bool isLargeScreen,
  }) {
    final cardHeight = isLargeScreen ? 120.0 : 100.0;
    final iconSize = isLargeScreen ? 40.0 : 36.0;
    final titleFontSize = isLargeScreen ? 20.0 : 18.0;
    final subtitleFontSize = isLargeScreen ? 16.0 : 14.0;

    return Container(
      height: cardHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: iconSize + 20,
                  height: iconSize + 20,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: iconSize,
                  ),
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
                          color: Colors.black87,
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
                  color: Colors.grey.shade400,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
