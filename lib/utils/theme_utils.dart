import 'package:flutter/material.dart';

/// Semi Design (bytedance) Design Tokens - https://semi.design
///
/// Light/Dark values from semi-design DESIGN.md:
/// - primary #0064FA / #54A9FF
/// - radius: small 3 / medium 6 / large 12
/// - control height 32px, body 14px, label 12px
/// - cards flat (bg-1 + 1px border), floating elements use elevated shadow
abstract final class SemiColors {
  // Brand
  static const primaryLight = Color(0xFF0064FA);
  static const primaryDark = Color(0xFF54A9FF);
  static const secondaryLight = Color(0xFF0095EE);
  static const secondaryDark = Color(0xFF40B4F3);
  static const successLight = Color(0xFF3BB346);
  static const successDark = Color(0xFF5DC264);
  static const warningLight = Color(0xFFFC8800);
  static const warningDark = Color(0xFFFFAE43);
  static const dangerLight = Color(0xFFF93920);
  static const dangerDark = Color(0xFFFC725A);

  // Background levels
  static const bg0Light = Color(0xFFFFFFFF);
  static const bg0Dark = Color(0xFF16161A);
  static const bg1Light = Color(0xFFFFFFFF);
  static const bg1Dark = Color(0xFF232429);
  static const bg2Light = Color(0xFFFFFFFF);
  static const bg2Dark = Color(0xFF35363C);

  // Fills (light: rgba(46,50,56,a), dark: rgba(255,255,255,a))
  static const fill0Light = Color(0x0D2E3238); // 5%
  static const fill1Light = Color(0x172E3238); // 9%
  static const fill2Light = Color(0x212E3238); // 13%
  static const fill0Dark = Color(0x1FFFFFFF); // 12%
  static const fill1Dark = Color(0x29FFFFFF); // 16%
  static const fill2Dark = Color(0x33FFFFFF); // 20%

  // Text
  static const text0Light = Color(0xFF1C1F23);
  static const text1Light = Color(0xCC1C1F23); // 80%
  static const text2Light = Color(0x9E1C1F23); // 62%
  static const text3Light = Color(0x591C1F23); // 35% disabled
  static const text0Dark = Color(0xFFF9F9F9);
  static const text1Dark = Color(0xCCF9F9F9); // 80%
  static const text2Dark = Color(0x99F9F9F9); // 60%
  static const text3Dark = Color(0x59F9F9F9); // 35% disabled

  // Border & disabled
  static const borderLight = Color(0x141C1F23); // 8%
  static const borderDark = Color(0x14FFFFFF); // 8%
  static const disabledBgLight = Color(0xFFE6E8EA);
  static const disabledBgDark = Color(0xFF2E3238);

  // Radius hierarchy
  static const radiusSmall = 3.0;
  static const radiusMedium = 6.0;
  static const radiusLarge = 12.0;
}

class ThemeUtils {
  static ThemeData get lightTheme => _semiTheme(Brightness.light);
  static ThemeData get darkTheme => _semiTheme(Brightness.dark);

  static Color warning(BuildContext context) => _color(context, SemiColors.warningLight, SemiColors.warningDark);
  static Color success(BuildContext context) => _color(context, SemiColors.successLight, SemiColors.successDark);
  static Color danger(BuildContext context) => _color(context, SemiColors.dangerLight, SemiColors.dangerDark);

  static Color _color(BuildContext context, Color light, Color dark) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  static ThemeData _semiTheme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final primary = dark ? SemiColors.primaryDark : SemiColors.primaryLight;
    final secondary = dark ? SemiColors.secondaryDark : SemiColors.secondaryLight;
    final danger = dark ? SemiColors.dangerDark : SemiColors.dangerLight;
    final bg0 = dark ? SemiColors.bg0Dark : SemiColors.bg0Light;
    final bg1 = dark ? SemiColors.bg1Dark : SemiColors.bg1Light;
    final bg2 = dark ? SemiColors.bg2Dark : SemiColors.bg2Light;
    final fill0 = dark ? SemiColors.fill0Dark : SemiColors.fill0Light;
    final fill1 = dark ? SemiColors.fill1Dark : SemiColors.fill1Light;
    final fill2 = dark ? SemiColors.fill2Dark : SemiColors.fill2Light;
    final text0 = dark ? SemiColors.text0Dark : SemiColors.text0Light;
    final text1 = dark ? SemiColors.text1Dark : SemiColors.text1Light;
    final text2 = dark ? SemiColors.text2Dark : SemiColors.text2Light;
    final text3 = dark ? SemiColors.text3Dark : SemiColors.text3Light;
    final border = dark ? SemiColors.borderDark : SemiColors.borderLight;
    final disabledBg = dark ? SemiColors.disabledBgDark : SemiColors.disabledBgLight;

    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: primary.withValues(alpha: dark ? 0.18 : 0.10),
      onPrimaryContainer: text0,
      secondary: secondary,
      onSecondary: Colors.white,
      error: danger,
      onError: Colors.white,
      surface: bg1,
      onSurface: text0,
      onSurfaceVariant: text2,
      surfaceTint: Colors.transparent,
      outline: border,
      outlineVariant: border,
      surfaceContainerLowest: bg0,
      surfaceContainerLow: bg1,
      surfaceContainer: fill0,
      surfaceContainerHigh: fill1,
      surfaceContainerHighest: fill1,
      inverseSurface: text0,
      onInverseSurface: bg0,
      inversePrimary: dark ? SemiColors.primaryLight : SemiColors.primaryDark,
    );

    final textTheme = TextTheme(
      headlineLarge: TextStyle(fontSize: 28, height: 40 / 28, fontWeight: FontWeight.w600, color: text0),
      headlineMedium: TextStyle(fontSize: 24, height: 32 / 24, fontWeight: FontWeight.w600, color: text0),
      headlineSmall: TextStyle(fontSize: 20, height: 28 / 20, fontWeight: FontWeight.w600, color: text0),
      titleLarge: TextStyle(fontSize: 18, height: 24 / 18, fontWeight: FontWeight.w600, color: text0),
      titleMedium: TextStyle(fontSize: 16, height: 22 / 16, fontWeight: FontWeight.w600, color: text0),
      titleSmall: TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, color: text0),
      bodyLarge: TextStyle(fontSize: 14, height: 20 / 14, color: text0),
      bodyMedium: TextStyle(fontSize: 14, height: 20 / 14, color: text0),
      bodySmall: TextStyle(fontSize: 12, height: 16 / 12, color: text1),
      labelLarge: TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500, color: text0),
      labelMedium: TextStyle(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500, color: text0),
      labelSmall: TextStyle(fontSize: 12, height: 16 / 12, color: text1),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg0,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        backgroundColor: bg0,
        foregroundColor: text0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(color: text0, fontSize: 18, fontWeight: FontWeight.w600),
        iconTheme: IconThemeData(color: text1, size: 20),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: bg1,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SemiColors.radiusLarge),
          side: BorderSide(color: border),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: disabledBg,
          disabledForegroundColor: text3,
          minimumSize: const Size(64, 32),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SemiColors.radiusSmall)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 32),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          foregroundColor: text0,
          side: BorderSide(color: border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SemiColors.radiusSmall)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 32),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          foregroundColor: primary,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        backgroundColor: primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SemiColors.radiusMedium)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fill0,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: _inputBorder(borderRadius: SemiColors.radiusSmall, side: BorderSide.none),
        enabledBorder: _inputBorder(borderRadius: SemiColors.radiusSmall, side: BorderSide.none),
        focusedBorder: _inputBorder(
          borderRadius: SemiColors.radiusSmall,
          side: BorderSide(color: primary, width: 1),
        ),
        errorBorder: _inputBorder(
          borderRadius: SemiColors.radiusSmall,
          side: BorderSide(color: danger, width: 1),
        ),
        focusedErrorBorder: _inputBorder(
          borderRadius: SemiColors.radiusSmall,
          side: BorderSide(color: danger, width: 1),
        ),
        labelStyle: TextStyle(color: text1, fontSize: 14),
        hintStyle: TextStyle(color: text2, fontSize: 14),
        prefixIconColor: text2,
        suffixIconColor: text2,
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 4,
        backgroundColor: dark ? bg2 : const Color(0xFF1C1F23),
        contentTextStyle: TextStyle(color: dark ? text0 : Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SemiColors.radiusMedium)),
      ),
      dialogTheme: DialogThemeData(
        elevation: 4,
        backgroundColor: bg2,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SemiColors.radiusLarge)),
        titleTextStyle: TextStyle(color: text0, fontSize: 18, fontWeight: FontWeight.w600),
        contentTextStyle: TextStyle(color: text1, fontSize: 14, height: 1.5),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: bg2,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(SemiColors.radiusLarge)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: text1,
        textColor: text0,
        selectedColor: primary,
        selectedTileColor: fill1,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: fill1,
        circularTrackColor: fill1,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? Colors.white : text2,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? primary : fill2,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? primary : Colors.transparent,
        ),
        side: BorderSide(color: text2, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SemiColors.radiusSmall)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? primary : text2,
        ),
      ),
    );
  }

  static OutlineInputBorder _inputBorder({required double borderRadius, required BorderSide side}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(borderRadius),
      borderSide: side,
    );
  }
}
