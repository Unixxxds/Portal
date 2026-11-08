import 'package:flutter/material.dart';

class AppTheme {
  // Font Families (loaded from assets/fonts)
  static const String fontDisplay = 'SF Pro Display';
  static const String fontText = 'SF Pro Text';
  static const String fontInter = 'Inter';

  // Dark Theme Palette matching user prompt
  static const Color appBg = Color(0xFF090909);
  static const Color bgCanvas = Color(0xFF090909);
  static const Color bgSurface = Color(0xFF191919);
  static const Color bgSurface1 = Color(0xFF191919);
  static const Color bgSurface2 = Color(0xFF191919);
  static const Color bgSurface3 = Color(0xFF262626);
  static const Color bgSurfaceHover = Color(0xFF222222);
  static const Color bgCard = Color(0xFF191919);
  static const Color bgInput = Color(0xFF191919);

  // Backward compatibility aliases
  static const Color background = appBg;
  static const Color surface = bgSurface;
  static const Color surfaceLight = bgSurface2;
  static const Color primary = textPrimary;
  static const Color primaryDark = bgSurface3;
  static const Color accentGreen = statusOnline;
  static const Color badgeColor = textPrimary;
  static const Color incomingBubble = bubbleIncomingBg;
  static const Color outgoingBubble = bubbleOutgoingBg;

  // Auth Card tokens
  static const Color authCardBg = Color(0xFF121212);
  static const Color authCardBorder = Color(0xFF242424);
  static const Color authInputBg = Color(0xFF191919);
  static const Color authInputBorder = Color(0xFF2B2B2B);

  // Borders
  static const Color borderHairline = Color(0x1AFFFFFF);
  static const Color borderStrong = Color(0x33FFFFFF);
  static const Color borderFocus = Color(0xFFFFFFFF);

  // Typography Colors
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF929292);
  static const Color textTertiary = Color(0xFF929292);
  static const Color textPlaceholder = Color(0xFF929292);
  static const Color textInverse = Color(0xFF090909);

  // Accents & Status
  static const Color accentWhite = Color(0xFFFFFFFF);
  static const Color accentBlue = Color(0xFF3B98FF); // Kept for verified checkmarks
  static const Color accentHover = Color(0xFFE5E5E5);
  static const Color accentActive = Color(0xFFFFFFFF);
  static const Color accentBlueSubtle = Color(0x1AFFFFFF);
  static const Color statusOnline = Color(0xFF22C55E); // Green only for online status!
  static const Color statusOffline = Color(0xFF929292);
  static const Color destructive = Color(0xFFEF4444);
  static const Color sparksGold = Color(0xFFF59E0B);

  // Message Bubbles
  static const Color bubbleIncomingBg = Color(0xFF191919);
  static const Color bubbleIncomingBorder = Color(0x1AFFFFFF);
  static const Color bubbleIncomingText = Color(0xFFFFFFFF);

  static const Color bubbleOutgoingBg = Color(0xFF2A2A2A);
  static const Color bubbleOutgoingBorder = Colors.transparent;
  static const Color bubbleOutgoingText = Color(0xFFFFFFFF);

  // Liquid Glass Navigation
  static const Color glassBarBg = Color(0xFA191919);
  static const Color pillBg = Color(0xFF2C2C2E);
  static const Color tabInactive = Color(0xFF929292);
  static const Color tabActive = Color(0xFFFFFFFF);
  static const Color dialogHeaderBg = Color(0xFF090909);

  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    fontFamily: fontText,
    scaffoldBackgroundColor: appBg,
    primaryColor: Colors.white,
    colorScheme: const ColorScheme.dark(
      primary: Colors.white,
      secondary: Colors.white,
      surface: bgSurface,
      error: destructive,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: dialogHeaderBg,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: fontDisplay,
        color: textPrimary,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      iconTheme: IconThemeData(color: textPrimary),
    ),
    dividerTheme: const DividerThemeData(
      color: borderHairline,
      thickness: 0.5,
      space: 0,
    ),
  );
}
