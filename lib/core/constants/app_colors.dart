import 'package:flutter/material.dart';

class AppColors {
  // Primary Palette - Clean Medical Emerald & Deep Teal
  static const Color primary = Color(0xFF0D9488);        // Teal 600
  static const Color primaryDark = Color(0xFF0F766E);    // Teal 700
  static const Color primaryLight = Color(0xFF2DD4BF);   // Teal 400
  static const Color primarySurface = Color(0xFFF0FDFA); // Teal 50

  // Secondary Accent - Electric Royal Blue for POS & Action items
  static const Color accent = Color(0xFF2563EB);         // Blue 600
  static const Color accentLight = Color(0xFF60A5FA);    // Blue 400

  // Status & Financial Indicators
  static const Color success = Color(0xFF16A34A);        // Green 600 (Paid, In-Stock)
  static const Color successSurface = Color(0xFFDCFCE7);
  static const Color warning = Color(0xFFD97706);        // Amber 600 (Near Expiry, Low Stock)
  static const Color warningSurface = Color(0xFFFEF3C7);
  static const Color error = Color(0xFFDC2626);          // Red 600 (Due, Expired, Out of Stock)
  static const Color errorSurface = Color(0xFFFEE2E2);

  // Background & Surfaces
  static const Color background = Color(0xFFF8FAFC);     // Slate 50
  static const Color surface = Color(0xFFFFFFFF);        // Pure White
  static const Color surfaceElevated = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE2E8F0);         // Slate 200
  static const Color borderSubtle = Color(0xFFF1F5F9);   // Slate 100

  // Typography Colors
  static const Color textPrimary = Color(0xFF0F172A);    // Slate 900
  static const Color textSecondary = Color(0xFF475569);  // Slate 600
  static const Color textMuted = Color(0xFF94A3B8);      // Slate 400
  static const Color textInverse = Color(0xFFFFFFFF);

  // POS Custom High-Contrast Badges
  static const Color cashBadge = Color(0xFF10B981);
  static const Color bkashBadge = Color(0xFFE2136E);
  static const Color nagadBadge = Color(0xFFF7941D);
  static const Color dueBadge = Color(0xFFEF4444);
}
