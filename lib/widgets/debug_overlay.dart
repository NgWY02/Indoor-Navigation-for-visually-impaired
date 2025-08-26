import 'package:flutter/material.dart';

/// Debug overlay widget to display navigation debug information on screen
class DebugOverlay extends StatelessWidget {
  final String debugInfo;
  final bool isVisible;
  final VoidCallback? onToggle;
  final VoidCallback? onTestSteps; // 🧪 Test step counter

  const DebugOverlay({
    Key? key,
    required this.debugInfo,
    this.isVisible = true,
    this.onToggle,
    this.onTestSteps,
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
                    if (onTestSteps != null) ...[
                      SizedBox(height: isSmallScreen ? 6 : 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: onTestSteps,
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
                            '🧪 Test Step Counter',
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

  // 🧪 Override this in your screen to add test functionality
  void testStepCounter() {
    // Default implementation - can be overridden
    updateDebugInfo(_debugInfo + '\n🧪 Test button pressed!');
  }

  Widget buildDebugOverlay() {
    return DebugOverlay(
      debugInfo: _debugInfo,
      isVisible: _isDebugVisible,
      onToggle: toggleDebugOverlay,
      onTestSteps: testStepCounter,
    );
  }
}
