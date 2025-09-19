import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'user_navigation_main_screen.dart';
import '../common/profile_screen.dart';

class UserHomeScreen extends StatelessWidget {
  final List<CameraDescription> cameras;

  const UserHomeScreen({Key? key, required this.cameras}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;

    // Phone-optimized sizing with small phone adjustments
    final bool isSmallPhone = screenHeight < 600;
    final double buttonHeight = isSmallPhone ? 94.0 : 98.0;
    final double mainIconSize = 100.0;  
    final double buttonIconSize = 45.0; 
    final double titleFontSize = isSmallPhone ? 18.0 : 20.0;
    final double subtitleFontSize = isSmallPhone ? 12.0 : 14.0;
    final double padding = 24.0;

    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          label: 'NAVI App',
          child: Text(
            'User Dashboard',
            style: TextStyle(
              fontSize: isSmallPhone ? 20 : 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        color: Colors.white, 
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(padding),
            child: Column(
              children: [
                // Welcome Header
                Container(
                  padding: EdgeInsets.symmetric(vertical: isSmallPhone ? 12 : 16),
                  child: Column(
                    children: [
                      Semantics(
                        label: 'NAVI app icon',
                        child: Image.asset(
                          'assets/icon.png',
                          width: mainIconSize,
                          height: mainIconSize,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Semantics(
                        label: 'Welcome message',
                        child: Text(
                          'Welcome, User',
                          style: TextStyle(
                            fontSize: titleFontSize,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Semantics(
                        label: 'App description',
                        child: Text(
                          'Choose an option below',
                          style: TextStyle(
                            fontSize: subtitleFontSize,
                            color: Colors.black87,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: isSmallPhone ? 20 : 24),

                // Main Action Buttons
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Start Navigation Button
                      Semantics(
                        label: 'Start Navigation button',
                        hint: 'Opens the indoor navigation system to help you find your way',
                        button: true,
                        child: _buildAccessibleButton(
                          context: context,
                          icon: Icons.navigation,
                          title: 'Start Navigation',
                          subtitle: 'Find your way indoors',
                          backgroundColor: Colors.green.shade600,
                          onTap: () {
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
                                builder: (context) => UserNavigationMainScreen(
                                  camera: cameras.first,
                                ),
                              ),
                            );
                          },
                          buttonHeight: buttonHeight,
                          iconSize: buttonIconSize,
                          titleFontSize: titleFontSize,
                          subtitleFontSize: subtitleFontSize,
                        ),
                      ),

                      SizedBox(height: isSmallPhone ? 20 : 24),

                      // Profile Button
                      Semantics(
                        label: 'Profile button',
                        hint: 'Opens your account settings and profile information',
                        button: true,
                        child: _buildAccessibleButton(
                          context: context,
                          icon: Icons.person,
                          title: 'Profile',
                          subtitle: 'Account settings',
                          backgroundColor: Colors.blue.shade600,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => const ProfileScreen(),
                              ),
                            );
                          },
                          buttonHeight: buttonHeight,
                          iconSize: buttonIconSize,
                          titleFontSize: titleFontSize,
                          subtitleFontSize: subtitleFontSize,
                        ),
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
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
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
