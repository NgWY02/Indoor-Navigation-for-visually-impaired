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
    if (!isVisible) {
      return Positioned(
        top: 50,
        right: 10,
        child: FloatingActionButton(
          mini: true,
          onPressed: onToggle,
          backgroundColor: Colors.red.withOpacity(0.7),
          child: const Icon(Icons.bug_report, color: Colors.white),
        ),
      );
    }

    return Positioned(
      top: 40,
      left: 10,
      right: 10,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 300),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.8),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red, width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with close button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: const BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(6),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bug_report, color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  const Text(
                    'DEBUG MODE',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: onToggle,
                    child: const Icon(Icons.close, color: Colors.white, size: 16),
                  ),
                ],
              ),
            ),
            // Debug content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      debugInfo.isEmpty ? 'No debug info available' : debugInfo,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontFamily: 'monospace',
                        height: 1.2,
                      ),
                    ),
                    if (onTestSteps != null) ...[
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: onTestSteps,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        ),
                        child: const Text(
                          '🧪 Test Step Counter',
                          style: TextStyle(fontSize: 10, color: Colors.white),
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
