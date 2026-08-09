import 'package:flutter/material.dart';

/// OpenMinis 暗色主题。与原版 iOS 的蓝紫色调一致：#2E5BFF 主色、
/// 深色面板、统一圆角与间距。
class MinisTheme {
  // Brand palette (aligned with the original accent).
  static const Color accent = Color(0xFF3B6CF6);
  static const Color accentBright = Color(0xFF2E5BFF);
  static const Color accentGreen = Color(0xFF21C063);
  static const Color bg = Color(0xFF0C1018);
  static const Color panel = Color(0xFF121826);
  static const Color panel2 = Color(0xFF0F1520);
  static const Color border = Color(0xFF232D42);
  static const Color textPrimary = Color(0xFFE8ECF3);
  static const Color textMuted = Color(0xFF8B96AB);
  static const Color userBubble = Color(0xFF2A4BD7);
  static const Color assistantBubble = Color(0xFF1A2233);
  static const Color danger = Color(0xFFE5484D);

  static ThemeData get dark {
    final scheme = ColorScheme.dark(
      primary: accent,
      onPrimary: Colors.white,
      secondary: accentGreen,
      onSecondary: Colors.black,
      surface: panel,
      onSurface: textPrimary,
      surfaceContainerHighest: panel2,
      error: danger,
      onError: Colors.white,
      outline: border,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      fontFamilyFallback: const ['Noto Sans SC', 'PingFang SC', 'sans-serif'],
      appBarTheme: const AppBarTheme(
        backgroundColor: panel,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        surfaceTintColor: panel,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: panel,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panel2,
        hintStyle: const TextStyle(color: textMuted),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: textMuted,
        textColor: textPrimary,
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: panel,
        indicatorColor: panel2,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? accentBright : textMuted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            color: states.contains(WidgetState.selected) ? accentBright : textMuted,
          ),
        ),
      ),
    );
  }
}
