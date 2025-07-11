import 'package:flutter/material.dart';

class ResponsiveHelper {
  static const double _mobileBreakpoint = 450;
  static const double _tabletBreakpoint = 800;
  static const double _desktopBreakpoint = 1200;

  /// Get screen width
  static double screenWidth(BuildContext context) {
    return MediaQuery.of(context).size.width;
  }

  /// Get screen height
  static double screenHeight(BuildContext context) {
    return MediaQuery.of(context).size.height;
  }

  /// Check if device is mobile
  static bool isMobile(BuildContext context) {
    return screenWidth(context) < _mobileBreakpoint;
  }

  /// Check if device is tablet
  static bool isTablet(BuildContext context) {
    return screenWidth(context) >= _mobileBreakpoint && 
           screenWidth(context) < _tabletBreakpoint;
  }

  /// Check if device is desktop
  static bool isDesktop(BuildContext context) {
    return screenWidth(context) >= _desktopBreakpoint;
  }

  /// Get responsive padding based on screen size
  static EdgeInsets getResponsivePadding(BuildContext context) {
    if (isMobile(context)) {
      return const EdgeInsets.all(16.0);
    } else if (isTablet(context)) {
      return const EdgeInsets.all(24.0);
    } else {
      return const EdgeInsets.all(32.0);
    }
  }

  /// Get responsive horizontal padding
  static EdgeInsets getResponsiveHorizontalPadding(BuildContext context) {
    if (isMobile(context)) {
      return const EdgeInsets.symmetric(horizontal: 16.0);
    } else if (isTablet(context)) {
      return const EdgeInsets.symmetric(horizontal: 32.0);
    } else {
      return const EdgeInsets.symmetric(horizontal: 64.0);
    }
  }

  /// Get responsive font size for titles
  static double getTitleFontSize(BuildContext context) {
    if (isMobile(context)) {
      return 20.0;
    } else if (isTablet(context)) {
      return 24.0;
    } else {
      return 28.0;
    }
  }

  /// Get responsive font size for body text
  static double getBodyFontSize(BuildContext context) {
    if (isMobile(context)) {
      return 14.0;
    } else if (isTablet(context)) {
      return 16.0;
    } else {
      return 18.0;
    }
  }

  /// Get responsive font size for headers
  static double getHeaderFontSize(BuildContext context) {
    if (isMobile(context)) {
      return 24.0;
    } else if (isTablet(context)) {
      return 28.0;
    } else {
      return 32.0;
    }
  }

  /// Get responsive button height
  static double getButtonHeight(BuildContext context) {
    if (isMobile(context)) {
      return 48.0;
    } else if (isTablet(context)) {
      return 52.0;
    } else {
      return 56.0;
    }
  }

  /// Get responsive icon size
  static double getIconSize(BuildContext context) {
    if (isMobile(context)) {
      return 24.0;
    } else if (isTablet(context)) {
      return 28.0;
    } else {
      return 32.0;
    }
  }

  /// Get responsive large icon size (for main icons)
  static double getLargeIconSize(BuildContext context) {
    if (isMobile(context)) {
      return 80.0;
    } else if (isTablet(context)) {
      return 100.0;
    } else {
      return 120.0;
    }
  }

  /// Get responsive spacing
  static double getSpacing(BuildContext context, {double multiplier = 1.0}) {
    if (isMobile(context)) {
      return 16.0 * multiplier;
    } else if (isTablet(context)) {
      return 20.0 * multiplier;
    } else {
      return 24.0 * multiplier;
    }
  }

  /// Get responsive card elevation
  static double getCardElevation(BuildContext context) {
    if (isMobile(context)) {
      return 2.0;
    } else {
      return 4.0;
    }
  }

  /// Get responsive border radius
  static double getBorderRadius(BuildContext context) {
    if (isMobile(context)) {
      return 8.0;
    } else if (isTablet(context)) {
      return 12.0;
    } else {
      return 16.0;
    }
  }

  /// Get safe area padding
  static EdgeInsets getSafeAreaPadding(BuildContext context) {
    return MediaQuery.of(context).padding;
  }

  /// Get bottom safe area padding
  static double getBottomSafeArea(BuildContext context) {
    return MediaQuery.of(context).padding.bottom;
  }

  /// Get top safe area padding
  static double getTopSafeArea(BuildContext context) {
    return MediaQuery.of(context).padding.top;
  }

  /// Get device pixel ratio
  static double getDevicePixelRatio(BuildContext context) {
    return MediaQuery.of(context).devicePixelRatio;
  }

  /// Get text scale factor
  static double getTextScaleFactor(BuildContext context) {
    return MediaQuery.of(context).textScaleFactor;
  }

  /// Get responsive width percentage
  static double getWidthPercentage(BuildContext context, double percentage) {
    return screenWidth(context) * (percentage / 100);
  }

  /// Get responsive height percentage
  static double getHeightPercentage(BuildContext context, double percentage) {
    return screenHeight(context) * (percentage / 100);
  }

  /// Get responsive max width for content (useful for wide screens)
  static double getMaxContentWidth(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth > _desktopBreakpoint) {
      return _desktopBreakpoint * 0.8; // 80% of desktop breakpoint
    }
    return screenWidth;
  }

  /// Get adaptive column count for grid layouts
  static int getGridColumnCount(BuildContext context) {
    if (isMobile(context)) {
      return 1;
    } else if (isTablet(context)) {
      return 2;
    } else {
      return 3;
    }
  }

  /// Create responsive sized box for spacing
  static Widget verticalSpace(BuildContext context, {double multiplier = 1.0}) {
    return SizedBox(height: getSpacing(context, multiplier: multiplier));
  }

  /// Create responsive horizontal space
  static Widget horizontalSpace(BuildContext context, {double multiplier = 1.0}) {
    return SizedBox(width: getSpacing(context, multiplier: multiplier));
  }

  /// Responsive container with max width
  static Widget responsiveContainer({
    required BuildContext context,
    required Widget child,
    EdgeInsets? padding,
    Color? color,
  }) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(
        maxWidth: getMaxContentWidth(context),
      ),
      padding: padding ?? getResponsivePadding(context),
      color: color,
      child: child,
    );
  }

  /// Get orientation
  static Orientation getOrientation(BuildContext context) {
    return MediaQuery.of(context).orientation;
  }

  /// Check if device is in landscape mode
  static bool isLandscape(BuildContext context) {
    return getOrientation(context) == Orientation.landscape;
  }

  /// Check if device is in portrait mode
  static bool isPortrait(BuildContext context) {
    return getOrientation(context) == Orientation.portrait;
  }
} 