import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class UIHelper {
  /// Restores normal system UI mode (shows navigation bar and status bar)
  static void restoreSystemUI() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
    );
  }
  
  /// Returns the bottom padding to ensure content doesn't overlap with system navigation
  static double getBottomPadding(BuildContext context) {
    return MediaQuery.of(context).padding.bottom;
  }
  
  /// Creates a safe area at the bottom of the screen to avoid overlapping with system navigation
  static Widget bottomSafeArea({required Widget child}) {
    return SafeArea(
      top: false,
      bottom: true,
      child: child,
    );
  }
  
  /// Applies padding to avoid overlapping with system navigation
  static Widget withBottomPadding(BuildContext context, {required Widget child}) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    // Add extra padding if system navigation is visible but not enough padding is applied
    final double extraPadding = bottomPadding < 16 ? 16.0 : bottomPadding.toDouble();
    
    return Padding(
      padding: EdgeInsets.only(bottom: extraPadding),
      child: child,
    );
  }
}