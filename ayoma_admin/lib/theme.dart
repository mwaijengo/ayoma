import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';

/// Same palette as the AyomaMax user app.
class AppColors {
  AppColors._();

  static const bg = Color(0xFF090D0C);
  static const surface = Color(0xFF101514);
  static const surface2 = Color(0xFF171D1B);
  static const sheet = Color(0xFF111615);
  static const line = Color(0x14FFFFFF);
  static const muted = Color(0xFF8D9794);
  static const dim = Color(0xFF68716E);
  static const faint = Color(0xFF515956);
  static const green = Color(0xFFA8EF3A);
  static const ink = Color(0xFF0B1009);
  static const text = Color(0xFFF6F7F8);
  static const red = Color(0xFFFF493F);
  static const error = Color(0xFFFF837B);
  static const amber = Color(0xFFFFC145);
  static const blue = Color(0xFF6CB8FF);

  static Color greenA(double alpha) => green.withValues(alpha: alpha);
}

class AppTheme {
  AppTheme._();

  static const overlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Color(0xFF0D1211),
    systemNavigationBarIconBrightness: Brightness.light,
  );

  static ThemeData dark() {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: AppColors.line),
    );
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
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      dividerColor: AppColors.line,
      dividerTheme: const DividerThemeData(color: AppColors.line, space: 1, thickness: 1),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.green,
        selectionColor: AppColors.greenA(0.3),
        selectionHandleColor: AppColors.green,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface2,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        labelStyle: const TextStyle(color: AppColors.muted),
        hintStyle: const TextStyle(color: AppColors.faint),
        helperStyle: const TextStyle(color: AppColors.dim),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(borderSide: const BorderSide(color: AppColors.green)),
        errorBorder: border.copyWith(borderSide: const BorderSide(color: AppColors.error)),
        focusedErrorBorder: border.copyWith(borderSide: const BorderSide(color: AppColors.error)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.green,
          foregroundColor: AppColors.ink,
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text,
          minimumSize: const Size(0, 48),
          side: const BorderSide(color: AppColors.line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.ink : AppColors.muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.green : const Color(0xFF303734),
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface2,
        selectedColor: AppColors.greenA(0.16),
        side: const BorderSide(color: AppColors.line),
        labelStyle: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600),
        secondaryLabelStyle: const TextStyle(color: AppColors.green, fontWeight: FontWeight.w700),
        checkmarkColor: AppColors.green,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          side: const WidgetStatePropertyAll(BorderSide(color: AppColors.line)),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.greenA(0.16) : AppColors.surface2,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.green : AppColors.muted,
          ),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surface2,
        contentTextStyle: TextStyle(color: AppColors.text),
      ),
      dialogTheme: const DialogThemeData(backgroundColor: AppColors.sheet),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.sheet,
        showDragHandle: true,
        dragHandleColor: AppColors.faint,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF0D1211),
        indicatorColor: AppColors.greenA(0.16),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: s.contains(WidgetState.selected) ? AppColors.green : AppColors.muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            size: 21,
            color: s.contains(WidgetState.selected) ? AppColors.green : AppColors.muted,
          ),
        ),
      ),
    );
    return base.copyWith(
      textTheme: GoogleFonts.manropeTextTheme(base.textTheme)
          .apply(bodyColor: AppColors.text, displayColor: AppColors.text),
    );
  }
}

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
