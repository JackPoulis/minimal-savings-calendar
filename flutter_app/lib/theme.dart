import 'package:flutter/material.dart';

/// The app palette.
abstract final class C {
  static const bg = Color(0xFF1E1E1E);
  static const panel = Color(0xFF252526);
  static const input = Color(0xFF3C3C3C);
  static const border = Color(0xFF3C3C3C);
  static const text = Color(0xFFD4D4D4);
  static const muted = Color(0xFF858585);
  static const accent = Color(0xFF007ACC);
  static const green = Color(0xFF89D185);
  static const red = Color(0xFFF14C4C);

  // Further shades used directly.
  static const button = Color(0xFF3A3D41);
  static const buttonHover = Color(0xFF45494E);
  static const accentHover = Color(0xFF1F8AD2);
  static const dangerBg = Color(0xFF5A1D1D);
  static const inBg = Color(0xFF2D4A2B);
  static const rowHover = Color(0xFF2A2D2E);
  static const grid = Color(0xFF2D2D2D);
  static const zero = Color(0xFF5A5A5A);
  static const dialogBorder = Color(0xFF454545);
  static const barGray = Color(0xFF6E6E6E);
  static const expected = Color(0xFFA0A0A0);
  static const neg = Color(0x14F14C4C); // rgba(241,76,76,.08)
  static const todayCol = Color(0x1F007ACC); // rgba(0,122,204,.12)
  static const hoverCol = Color(0x0DFFFFFF); // rgba(255,255,255,.05)
}

/// 'Segoe UI' on Windows; Roboto is the Android stand-in.
const fontFallback = ['Segoe UI', 'Roboto', 'system-ui', 'sans-serif'];
const monoFallback = ['Consolas', 'Cascadia Mono', 'monospace'];

const body = TextStyle(
  fontFamily: 'Segoe UI',
  fontFamilyFallback: fontFallback,
  fontSize: 14,
  height: 1.4,
  color: C.text,
);

const mono = TextStyle(
  fontFamily: 'Consolas',
  fontFamilyFallback: monoFallback,
  fontSize: 14,
  height: 1.4,
  color: C.text,
);

/// `.num.big`
const monoBig = TextStyle(
  fontFamily: 'Consolas',
  fontFamilyFallback: monoFallback,
  fontSize: 20,
  height: 1.4,
  color: C.text,
);

/// `label` — the small caption above a field.
const labelStyle = TextStyle(
  fontFamily: 'Segoe UI',
  fontFamilyFallback: fontFallback,
  fontSize: 12,
  height: 1.4,
  color: C.muted,
);

const h1 = TextStyle(
  fontFamily: 'Segoe UI',
  fontFamilyFallback: fontFallback,
  fontSize: 18,
  fontWeight: FontWeight.w600,
  color: C.text,
);

const h2 = TextStyle(
  fontFamily: 'Segoe UI',
  fontFamilyFallback: fontFallback,
  fontSize: 15,
  fontWeight: FontWeight.w600,
  color: C.text,
);

/// `h3` — uppercase, tracked out, muted.
const h3 = TextStyle(
  fontFamily: 'Segoe UI',
  fontFamilyFallback: fontFallback,
  fontSize: 13,
  fontWeight: FontWeight.w600,
  letterSpacing: 0.52,
  color: C.muted,
);

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: C.bg,
    canvasColor: C.bg,
    dialogTheme: const DialogThemeData(backgroundColor: C.panel),
    colorScheme: base.colorScheme.copyWith(
      primary: C.accent,
      surface: C.panel,
      onSurface: C.text,
      error: C.red,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: C.text,
      selectionColor: C.accent,
    ),
    textTheme: base.textTheme.apply(
      fontFamily: 'Segoe UI',
      fontFamilyFallback: fontFallback,
      bodyColor: C.text,
      displayColor: C.text,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: C.panel,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 64,
      indicatorColor: C.todayCol,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 26,
          color: states.contains(WidgetState.selected) ? C.accent : C.muted,
        ),
      ),
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
  );
}
