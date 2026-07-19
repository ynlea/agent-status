import 'package:flutter/material.dart';

/// 轻芽原型使用的视觉令牌。
class QingyaColors {
  static const scaffold = Color(0xFFFFF9F5);
  static const card = Color(0xFFFFFEFD);
  static const primary = Color(0xFFFF7F73);
  static const primaryDark = Color(0xFFE9685F);
  static const primarySoft = Color(0xFFFFEEE9);
  static const device = Color(0xFF6078FF);
  static const deviceSoft = Color(0xFFEEF1FF);
  static const textPrimary = Color(0xFF342E2A);
  static const textSecondary = Color(0xFF9D948E);
  static const confirm = Color(0xFFFF6B63);
  static const confirmSoft = Color(0xFFFFE9E6);
  static const working = Color(0xFFFFB23E);
  static const workingSoft = Color(0xFFFFF2D8);
  static const done = Color(0xFF67C77D);
  static const doneSoft = Color(0xFFE9F7EC);
  static const idle = Color(0xFFC6BFB9);
  static const idleSoft = Color(0xFFF4F1EE);
  static const online = Color(0xFF5BC56D);
  static const offline = Color(0xFFFFA21A);
  static const divider = Color(0xFFF2EAE5);
  static const navInactive = Color(0xFFAFA9A4);
  static const shadow = Color(0x120F0703);
  static const border = Color(0xFFF0E4DE);
}

class QingyaTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: QingyaColors.primary,
        onPrimary: Colors.white,
        secondary: QingyaColors.device,
        surface: QingyaColors.card,
        onSurface: QingyaColors.textPrimary,
        error: QingyaColors.confirm,
      ),
      scaffoldBackgroundColor: QingyaColors.scaffold,
      fontFamilyFallback: const ['Noto Sans CJK SC', 'Noto Sans SC'],
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: QingyaColors.scaffold,
        foregroundColor: QingyaColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: QingyaColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      dividerColor: QingyaColors.divider,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: QingyaColors.card,
        hintStyle: const TextStyle(
          color: QingyaColors.textSecondary,
          fontSize: 14,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: QingyaColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: QingyaColors.device, width: 1.5),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? Colors.white
              : Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? QingyaColors.device
              : const Color(0xFFE7E3E0);
        }),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: QingyaColors.device,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: QingyaColors.primary,
        secondary: QingyaColors.device,
        surface: Color(0xFF2A2624),
        onSurface: Color(0xFFF5EDE6),
      ),
      scaffoldBackgroundColor: const Color(0xFF1C1917),
    );
  }
}
