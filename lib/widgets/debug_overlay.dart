import 'package:flutter/material.dart';

/// Debug overlay widget to display navigation debug information on screen
class DebugOverlay extends StatelessWidget {
  final String debugInfo;
  final bool isVisible;
  final VoidCallback? onToggle;

  const DebugOverlay({
    Key? key,
    required this.debugInfo,
    this.isVisible = true,
    this.onToggle,
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
      top: mediaQuery.padding.top + (isSmallScreen ? 8 : 12),
      left: isSmallScreen ? 6 : 8,
      right: isSmallScreen ? 6 : 8,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: screenHeight * (isSmallScreen ? 0.35 : 0.4), // Adaptive height
          maxWidth: screenWidth - (isSmallScreen ? 12 : 16),
        ),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.9),
          borderRadius: BorderRadius.circular(isSmallScreen ? 8 : 12),
          border: Border.all(color: Colors.red.withOpacity(0.8), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 10,
              offset: const Offset(0, 3),
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
                    // Format debug info with better structure
                    if (debugInfo.isNotEmpty) ...[
                      _buildFormattedDebugText(debugInfo, isSmallScreen),
                    ] else ...[
                      Text(
                        'No debug info available',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: isSmallScreen ? 10 : 11,
                          fontStyle: FontStyle.italic,
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

  Widget _buildFormattedDebugText(String debugInfo, bool isSmallScreen) {
    // Split debug info into lines and format each one
    final lines = debugInfo.split('\n').where((line) => line.trim().isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        // Check if line starts with emoji or special characters
        final hasEmoji = line.trim().startsWith(RegExp(r'[^\w\s]'));
        final isError = line.contains('Error') || line.contains('Failed') || line.contains('Exception');
        final isSuccess = line.contains('Success') || line.contains('✅') || line.contains('Complete');
        final isWarning = line.contains('Warning') || line.contains('⚠️');

        Color textColor = Colors.white;
        if (isError) textColor = Colors.red[300]!;
        else if (isSuccess) textColor = Colors.green[300]!;
        else if (isWarning) textColor = Colors.orange[300]!;
        else if (hasEmoji) textColor = Colors.blue[200]!;

        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(
            line.trim(),
            style: TextStyle(
              color: textColor,
              fontSize: isSmallScreen ? 9 : 10,
              fontFamily: hasEmoji ? null : 'monospace',
              height: 1.3,
              fontWeight: hasEmoji ? FontWeight.w500 : FontWeight.normal,
            ),
            softWrap: true,
            overflow: TextOverflow.visible,
          ),
        );
      }).toList(),
    );
  }
}
