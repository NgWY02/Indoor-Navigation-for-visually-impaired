import 'package:flutter/material.dart';

/// Debug overlay widget to display navigation debug information on screen
class DebugOverlay extends StatelessWidget {
  final String debugInfo;
  final bool isVisible;
  final VoidCallback? onToggle;
  final VoidCallback? onTestAuth; // 🔐 Test authentication status
  final VoidCallback? onTestPaths; // 🧪 Test path creation and loading
  final VoidCallback? onDebugDatabase; // 🔍 Debug database contents
  final VoidCallback? onRunMigration; // 🔧 Run database migration

  const DebugOverlay({
    Key? key,
    required this.debugInfo,
    this.isVisible = true,
    this.onToggle,
    this.onTestAuth,
    this.onTestPaths,
    this.onDebugDatabase,
    this.onRunMigration,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;
    final isSmallScreen = screenWidth < 400;
    
    if (!isVisible) {
      return Positioned(
        top: mediaQuery.padding.top + 10,
        right: 10,
        child: FloatingActionButton(
          mini: true,
          onPressed: onToggle,
          backgroundColor: Colors.red.withOpacity(0.7),
          child: const Icon(Icons.bug_report, color: Colors.white, size: 18),
        ),
      );
    }

    return Positioned(
      top: mediaQuery.padding.top + 10,
      left: 8,
      right: 8,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: screenHeight * 0.4, // Max 40% of screen height
          maxWidth: screenWidth - 16,
        ),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with close button
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isSmallScreen ? 8 : 12, 
                vertical: isSmallScreen ? 6 : 8,
              ),
              decoration: const BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(10),
                  topRight: Radius.circular(10),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.bug_report, 
                    color: Colors.white, 
                    size: isSmallScreen ? 14 : 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'DEBUG MODE',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: isSmallScreen ? 10 : 12,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: onToggle,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.close, 
                        color: Colors.white, 
                        size: isSmallScreen ? 14 : 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Debug content
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isSmallScreen ? 8 : 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      debugInfo.isEmpty ? 'No debug info available' : debugInfo,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isSmallScreen ? 10 : 11,
                        fontFamily: 'monospace',
                        height: 1.2,
                      ),
                    ),
                    if (onTestAuth != null) ...[
                      SizedBox(height: isSmallScreen ? 6 : 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: onTestAuth,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            padding: EdgeInsets.symmetric(
                              horizontal: isSmallScreen ? 6 : 8,
                              vertical: isSmallScreen ? 3 : 4,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          child: Text(
                            '🔐 Check Auth Status',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 9 : 10,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (onTestPaths != null) ...[
                      SizedBox(height: isSmallScreen ? 6 : 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: onTestPaths,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding: EdgeInsets.symmetric(
                              horizontal: isSmallScreen ? 6 : 8,
                              vertical: isSmallScreen ? 3 : 4,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          child: Text(
                            '🧪 Test Path Creation',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 9 : 10,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (onDebugDatabase != null) ...[
                      SizedBox(height: isSmallScreen ? 6 : 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: onDebugDatabase,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple,
                            padding: EdgeInsets.symmetric(
                              horizontal: isSmallScreen ? 6 : 8,
                              vertical: isSmallScreen ? 3 : 4,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          child: Text(
                            '🔍 Debug Database',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 9 : 10,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (onRunMigration != null) ...[
                      SizedBox(height: isSmallScreen ? 6 : 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: onRunMigration,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            padding: EdgeInsets.symmetric(
                              horizontal: isSmallScreen ? 6 : 8,
                              vertical: isSmallScreen ? 3 : 4,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          child: Text(
                            '🔧 Fix Organization IDs',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 9 : 10,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mixin to add debug overlay functionality to navigation screens
mixin DebugOverlayMixin<T extends StatefulWidget> on State<T> {
  String _debugInfo = '';
  bool _isDebugVisible = true;

  void updateDebugInfo(String info) {
    if (mounted) {
      setState(() {
        _debugInfo = info;
      });
    }
  }

  void toggleDebugOverlay() {
    if (mounted) {
      setState(() {
        _isDebugVisible = !_isDebugVisible;
      });
    }
  }

  // 🔐 Override this in your screen to add authentication testing
  void testStepCounter() {
    // Default implementation - can be overridden
    updateDebugInfo(_debugInfo + '\n🔐 Auth check button pressed!');
  }

  Widget buildDebugOverlay() {
    return DebugOverlay(
      debugInfo: _debugInfo,
      isVisible: _isDebugVisible,
      onToggle: toggleDebugOverlay,
      onTestAuth: testStepCounter,
      onTestPaths: testPathCreation,
      onDebugDatabase: debugDatabaseContents,
      onRunMigration: runDatabaseMigration,
    );
  }

  void testPathCreation() {
    // This method should be overridden by classes using this mixin
    updateDebugInfo('Path creation test not implemented for this screen');
  }

  void debugDatabaseContents() {
    // This method should be overridden by classes using this mixin
    updateDebugInfo('Database debug not implemented for this screen');
  }

  void runDatabaseMigration() {
    // This method should be overridden by classes using this mixin
    updateDebugInfo('Database migration not implemented for this screen');
  }
}
