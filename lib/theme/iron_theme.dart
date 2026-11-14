import 'package:flutter/material.dart';

const ironGreen = Color(0xFF00FF66);
const ironGreenSoft = Color(0xFF67FFA4);
const ironGreenDeep = Color(0xFF00C853);
const ironDark = Color(0xFF070A0B);
const ironSurface = Color(0xFF121618);
const ironSurfaceHigh = Color(0xFF1A1F22);
const ironGraphite = Color(0xFF161A1C);
const ironUserFill = Color(0xFF0F2A1A);
const ironOutline = Color(0xFF2A3236);
const ironHairline = Color(0xFF2A3236);
const ironMuted = Color(0xFF8B949A);
const ironLine = Color(0xFF2A3236);
// Kept names; values are now neutral so the UI is not a wall of green borders.
const ironOutlineStrong = Color(0xB300FF66);
const ironOutlineMuted = Color(0x22FFFFFF);

/// 8-point spacing grid.
class IronSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double page = 16;
}

class IronSpacing {
  static const double xs = IronSpace.sm;
  static const double sm = IronSpace.sm;
  static const double md = IronSpace.md;
  static const double lg = IronSpace.lg;
  static const double xl = IronSpace.xl;
  static const double page = IronSpace.md;
}

class IronRadii {
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double pill = 999;
}

Border ironBorder({bool accent = false, bool strong = false}) {
  return Border.fromBorderSide(ironBorderSide(accent: accent, strong: strong));
}

List<BoxShadow> ironFocusGlow(bool focused) {
  if (!focused) return const <BoxShadow>[];
  return const [
    BoxShadow(
      color: Color(0x2900FF66),
      blurRadius: 10,
      spreadRadius: 0,
    ),
  ];
}

BoxDecoration ironPanelDecoration({
  BorderRadius? radius,
  bool raised = false,
  bool accent = false,
  bool focused = false,
}) {
  return BoxDecoration(
    color: raised ? ironSurfaceHigh : ironSurface,
    borderRadius: radius ?? BorderRadius.circular(IronRadii.md),
    border: ironBorder(accent: accent || focused, strong: focused),
    boxShadow: ironFocusGlow(focused),
  );
}

double _weightValue(FontWeight weight) {
  return weight.value.toDouble();
}

TextStyle ironText({
  double size = 16,
  FontWeight weight = FontWeight.w400,
  Color? color,
  double height = 1.35,
  double letterSpacing = 0,
}) {
  return TextStyle(
    fontFamily: 'Inter',
    fontSize: size,
    fontWeight: weight,
    fontVariations: <FontVariation>[
      FontVariation('wght', _weightValue(weight)),
    ],
    color: color,
    height: height,
    letterSpacing: letterSpacing,
  );
}

TextTheme ironTextTheme() {
  TextStyle base({
    required double size,
    required FontWeight weight,
    double height = 1.3,
    double letterSpacing = 0,
  }) {
    return ironText(
      size: size,
      weight: weight,
      color: Colors.white,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  return TextTheme(
    displaySmall: base(size: 32, weight: FontWeight.w800, height: 1.1),
    headlineLarge: base(size: 28, weight: FontWeight.w700, height: 1.15),
    headlineMedium: base(size: 24, weight: FontWeight.w700, height: 1.2),
    headlineSmall: base(size: 20, weight: FontWeight.w600, height: 1.25),
    titleLarge: base(size: 18, weight: FontWeight.w600),
    titleMedium: base(size: 16, weight: FontWeight.w600),
    titleSmall: base(size: 14, weight: FontWeight.w600, letterSpacing: 0.1),
    bodyLarge: base(size: 16, weight: FontWeight.w400, height: 1.45),
    bodyMedium: base(size: 14, weight: FontWeight.w400, height: 1.45),
    bodySmall: base(size: 12, weight: FontWeight.w400, height: 1.4),
    labelLarge: base(size: 14, weight: FontWeight.w600),
    labelMedium: base(size: 12, weight: FontWeight.w600),
    labelSmall: base(size: 11, weight: FontWeight.w600, letterSpacing: 0.2),
  );
}

BorderSide ironBorderSide({bool accent = false, bool strong = false}) {
  if (accent) {
    return BorderSide(
      color: ironGreen.withValues(alpha: strong ? 0.72 : 0.45),
      width: strong ? 1.4 : 1,
    );
  }
  return BorderSide(
    color: ironHairline.withValues(alpha: strong ? 0.95 : 0.8),
    width: 1,
  );
}

ThemeData ironTheme() {
  const scheme = ColorScheme.dark(
    primary: ironGreen,
    onPrimary: Color(0xFF052010),
    secondary: ironGreenSoft,
    onSecondary: Color(0xFF052010),
    surface: ironSurface,
    onSurface: Colors.white,
    error: Color(0xFFFF6B6B),
    onError: Colors.white,
  );

  final textTheme = ironTextTheme();
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: ironDark,
    canvasColor: ironDark,
    textTheme: textTheme,
  );

  return base.copyWith(
    textTheme: textTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: Colors.white,
    ),
    dividerColor: ironHairline,
    splashFactory: InkRipple.splashFactory,
    // Quiet hairline when idle; accent only while focused.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: ironSurface,
      hintStyle: const TextStyle(color: Colors.white38),
      labelStyle: const TextStyle(color: ironMuted, fontWeight: FontWeight.w600),
      floatingLabelStyle: const TextStyle(
        color: ironGreenSoft,
        fontWeight: FontWeight.w700,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: ironHairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: ironHairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: ironGreen, width: 1.4),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      backgroundColor: const Color(0xF00B0E0F),
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      indicatorColor: ironGreen.withValues(alpha: 0.14),
      indicatorShape: const StadiumBorder(),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 11,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          letterSpacing: 0.1,
          color: selected ? ironGreen : ironMuted,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 22,
          color: selected ? ironGreen : ironMuted,
        );
      }),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: ironSurfaceHigh,
      contentTextStyle: const TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected) ? ironGreen : Colors.white70;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? ironGreen.withValues(alpha: 0.35)
            : ironHairline;
      }),
    ),
  );
}
