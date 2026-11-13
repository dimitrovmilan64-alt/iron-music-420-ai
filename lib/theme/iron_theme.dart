import 'package:flutter/material.dart';

const ironGreen = Color(0xFF00FF66);
const ironGreenSoft = Color(0xFF4DFF8A);
const ironGreenDeep = Color(0xFF00A852);
const ironDark = Color(0xFF070A08);
const ironSurface = Color(0xFF0E1511);
const ironSurfaceHigh = Color(0xFF161E19);
const ironLine = Color(0xFF2A4A36);
const ironMuted = Color(0xFF9AA59D);
const ironGraphite = Color(0xFF161A1C);
const ironUserFill = Color(0xFF0F2A1A);
const ironOutline = Color(0x5900FF66);
const ironOutlineStrong = Color(0x9900FF66);
const ironOutlineMuted = Color(0x33FFFFFF);

BorderSide ironBorderSide({bool accent = false, bool strong = false}) {
  final color = strong
      ? ironOutlineStrong
      : accent
          ? ironOutline
          : ironOutlineMuted;
  return BorderSide(color: color, width: 1);
}

Border ironBorder({bool accent = false, bool strong = false}) {
  return Border.fromBorderSide(ironBorderSide(accent: accent, strong: strong));
}

List<BoxShadow> ironFocusGlow(bool focused) {
  if (!focused) return const <BoxShadow>[];
  return const [
    BoxShadow(
      color: Color(0x3300FF66),
      blurRadius: 12,
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

class IronSpacing {
  static const double xs = 6;
  static const double sm = 10;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double page = 20;
}

class IronRadii {
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 22;
  static const double pill = 999;
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
    displaySmall: base(size: 32, weight: FontWeight.w700, height: 1.1),
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

ThemeData ironTheme() {
  final textTheme = ironTextTheme();
  final scheme = const ColorScheme.dark(
    primary: ironGreen,
    onPrimary: Color(0xFF002410),
    secondary: ironGreenSoft,
    onSecondary: Color(0xFF002410),
    surface: ironSurface,
    onSurface: Colors.white,
    error: Color(0xFFFF745C),
    onError: Colors.black,
    outline: ironLine,
    surfaceContainerHighest: ironSurfaceHigh,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: ironDark,
    fontFamily: 'Inter',
    textTheme: textTheme,
    iconTheme: const IconThemeData(color: Color(0xFFD7E0D9), size: 22),
    appBarTheme: AppBarTheme(
      backgroundColor: ironDark,
      foregroundColor: Colors.white,
      elevation: 0,
      titleTextStyle: textTheme.titleLarge,
    ),
    dividerColor: ironLine,
    dividerTheme: const DividerThemeData(
      color: ironLine,
      thickness: 1,
      space: 24,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: ironSurfaceHigh,
      textStyle: textTheme.bodyMedium,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(IronRadii.md),
        side: const BorderSide(color: ironOutline, width: 1),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: ironSurfaceHigh,
      titleTextStyle: textTheme.titleLarge,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: ironMuted),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(IronRadii.lg),
        side: const BorderSide(color: ironOutline, width: 1),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: ironSurfaceHigh,
      modalBackgroundColor: ironSurfaceHigh,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ironSurfaceHigh,
      contentTextStyle: textTheme.bodyMedium,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: ironGreen,
      inactiveTrackColor: ironGreen.withValues(alpha: 0.18),
      thumbColor: ironGreenSoft,
      overlayColor: ironGreen.withValues(alpha: 0.12),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ironGreen,
        foregroundColor: const Color(0xFF002410),
        textStyle: textTheme.labelLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(IronRadii.md),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ironGreen,
        side: BorderSide(color: ironGreen.withValues(alpha: 0.4)),
        textStyle: textTheme.labelLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: ironGreenSoft,
        textStyle: textTheme.labelLarge,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF0B100D),
      labelStyle: textTheme.bodySmall?.copyWith(color: ironGreen),
      hintStyle: textTheme.bodyMedium?.copyWith(color: Colors.white38),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: const BorderSide(color: ironOutline, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: const BorderSide(color: ironOutlineStrong, width: 1),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: ironSurface,
      selectedColor: ironGreen.withValues(alpha: 0.16),
      side: const BorderSide(color: ironOutline, width: 1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(IronRadii.pill),
      ),
      labelStyle: textTheme.labelMedium?.copyWith(color: Colors.white),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xFF0B0F0C),
      elevation: 0,
      height: 72,
      indicatorColor: ironGreen.withValues(alpha: 0.12),
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: ironOutlineStrong, width: 1),
      ),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(color: selected ? ironGreen : ironMuted, size: 24);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return ironText(
          size: 12,
          weight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected ? ironGreen : ironMuted,
        );
      }),
    ),
  );
}
