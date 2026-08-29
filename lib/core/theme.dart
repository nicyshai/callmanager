import 'package:flutter/material.dart';

class AppColors {
  static const Color background = Color(0xFFF4F7FA);
  static const Color surface = Colors.white;
  static const Color surfaceLight = Color(0xFFE8EEF3);
  
  static const Color primary = Color(0xFF0087FF); // Truecaller Blue
  static const Color primaryGlow = Color(0x330087FF);

  static const Color success = Color(0xFF00C853);
  static const Color successGlow = Color(0x3300C853);

  static const Color error = Color(0xFFFF5252);
  static const Color errorGlow = Color(0x33FF5252);

  static const Color warning = Color(0xFFFFAB00);
  static const Color warningGlow = Color(0x33FFAB00);

  static const Color info = Color(0xFF00B0FF);
  static const Color infoGlow = Color(0x3300B0FF);

  static const Color textPrimary = Color(0xFF202124);
  static const Color textSecondary = Color(0xFF5F6368);
  static const Color textMuted = Color(0xFF80868B);

  static const Color border = Color(0xFFDADCE0);
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.background,
      primaryColor: AppColors.primary,
      cardColor: AppColors.surface,
      dividerColor: AppColors.border,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 24),
        titleLarge: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 18),
        bodyLarge: TextStyle(color: AppColors.textPrimary, fontSize: 16),
        bodyMedium: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        labelSmall: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
      ),
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        secondary: AppColors.info,
        surface: AppColors.surface,
        error: AppColors.error,
      ),
      useMaterial3: true,
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0F1219),
      primaryColor: AppColors.primary,
      cardColor: const Color(0xFF181D26),
      dividerColor: const Color(0xFF2E3748),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(color: Color(0xFFF3F4F6), fontWeight: FontWeight.bold, fontSize: 24),
        titleLarge: TextStyle(color: Color(0xFFF3F4F6), fontWeight: FontWeight.w600, fontSize: 18),
        bodyLarge: TextStyle(color: Color(0xFFF3F4F6), fontSize: 16),
        bodyMedium: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
        labelSmall: TextStyle(color: Color(0xFF6B7280), fontSize: 11, fontWeight: FontWeight.w600),
      ),
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        secondary: AppColors.info,
        surface: Color(0xFF181D26),
        error: AppColors.error,
      ),
      useMaterial3: true,
    );
  }

  static BoxDecoration glassBox({
    Color color = AppColors.surface,
    double radius = 16,
    double borderWidth = 1,
    Color borderColor = AppColors.border,
  }) {
    return BoxDecoration(
      color: color.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor, width: borderWidth),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.2),
          blurRadius: 10,
          offset: const Offset(0, 4),
        )
      ],
    );
  }
}
