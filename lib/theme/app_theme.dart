import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  static const bg = Color(0xFF0F1C2E);
  static const backdrop = Color(0xFF0A1422);
  static const surface = Color(0xFF16253A);
  static const surface2 = Color(0xFF1D2E46);
  static const sheet = Color(0xFF152338);
  static const navBar = Color(0xFF122135);
  static const line = Color(0xFF2C3E58);
  static const cardBorder = Color(0xFF80B4FF);
  static const muted = Color(0xFF8D9794);
  static const dim = Color(0xFF68716E);
  static const faint = Color(0xFF515956);
  static const navInactive = Color(0xFF78827F);
  static const green = Color(0xFFA8EF3A);
  static const greenDark = Color(0xFF14220A);
  static const ink = Color(0xFF0B1009);
  static const text = Color(0xFFF6F7F8);
  static const red = Color(0xFFFF493F);
  static const error = Color(0xFFFF837B);
  static const toggleOff = Color(0xFF2E3D52);
  static const toggleKnobOff = Color(0xFF8D9693);

  /// Solid green. Alpha is ignored so green is never mixed with another color.
  static Color greenA(double _) => green;
}

class AppTheme {
  AppTheme._();

  static const overlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: AppColors.navBar,
    systemNavigationBarIconBrightness: Brightness.light,
  );

  static ThemeData dark() {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.bg,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.green,
        onPrimary: AppColors.ink,
        secondary: AppColors.green,
        surface: AppColors.surface,
        onSurface: AppColors.text,
        error: AppColors.error,
      ),
      splashFactory: InkSparkle.splashFactory,
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.green,
        selectionColor: AppColors.greenA(0.3),
        selectionHandleColor: AppColors.green,
      ),
    );
    return base.copyWith(
      textTheme: GoogleFonts.manropeTextTheme(base.textTheme)
          .apply(bodyColor: AppColors.text, displayColor: AppColors.text),
    );
  }
}

/// Manrope text style shorthand used across the app.
TextStyle uStyle(
  double size, {
  FontWeight weight = FontWeight.w500,
  Color color = AppColors.text,
  double? letterSpacing,
  double? height,
}) {
  return GoogleFonts.manrope(
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing,
    height: height,
  );
}
