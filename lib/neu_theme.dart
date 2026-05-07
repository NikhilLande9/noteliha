// lib/neu_theme.dart
// ─────────────────────────────────────────────────────────────────────────────
// Shared Visual Theme Tokens
//
// HOW TO ADD A NEW THEME:
//   1. Add a value to AppVisualTheme in models/enums.dart
//   2. Add a case to EVERY switch in the Neu class below
//   3. Add display name + icon to visualThemeName() / visualThemeIcon()
//   4. Set isPremium() if needed
//   No screen files, no widget files need to change — ever.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'models.dart';

class Neu {
  static AppVisualTheme _theme = AppVisualTheme.neumorphic;

  static void setTheme(AppVisualTheme theme) => _theme = theme;
  static AppVisualTheme get currentTheme => _theme;

  // ── Base scaffold / surface color ──────────────────────────────────────────
  static Color base(bool isDark) => switch (_theme) {
    AppVisualTheme.material   => isDark ? const Color(0xFF1C1B1F) : Colors.white,
    AppVisualTheme.neumorphic => isDark ? const Color(0xFF1E2128) : const Color(0xFFE8EAF0),
  // Clay: clean white / black — color lives on the cards, not the scaffold
    AppVisualTheme.clay       => isDark ? const Color(0xFF0A0A0A) : Colors.white,
    AppVisualTheme.glass      => isDark ? const Color(0xFF0D1117) : const Color(0xFFF0F4FF),
    AppVisualTheme.bento      => isDark ? const Color(0xFF111318) : const Color(0xFFFAFAFA),
  };

  // ── Text hierarchy ─────────────────────────────────────────────────────────
  static Color textPrimary(bool isDark) => switch (_theme) {
    AppVisualTheme.material   => isDark ? Colors.white           : const Color(0xFF1C1B1F),
    AppVisualTheme.neumorphic => isDark ? const Color(0xFFECEEF5): const Color(0xFF1E2128),
    AppVisualTheme.clay       => isDark ? const Color(0xFFF0F0F0): const Color(0xFF1A1A1A),
    AppVisualTheme.glass      => isDark ? const Color(0xFFE8EEFF): const Color(0xFF1A1F3C),
    AppVisualTheme.bento      => isDark ? const Color(0xFFF0F0F0): const Color(0xFF111318),
  };

  static Color textSecondary(bool isDark) => switch (_theme) {
    AppVisualTheme.material   => isDark ? const Color(0xFFCAC4D0): const Color(0xFF49454F),
    AppVisualTheme.neumorphic => isDark ? const Color(0xFFADB3C4): const Color(0xFF5A5E6E),
    AppVisualTheme.clay       => isDark ? const Color(0xFFBBBBBB): const Color(0xFF555555),
    AppVisualTheme.glass      => isDark ? const Color(0xFFA8B4D8): const Color(0xFF4A5580),
    AppVisualTheme.bento      => isDark ? const Color(0xFFAAAAAA): const Color(0xFF555555),
  };

  static Color textTertiary(bool isDark) => switch (_theme) {
    AppVisualTheme.material   => isDark ? const Color(0xFF938F99): const Color(0xFF79747E),
    AppVisualTheme.neumorphic => isDark ? const Color(0xFF7A8090): const Color(0xFF8A8D9A),
    AppVisualTheme.clay       => isDark ? const Color(0xFF888888): const Color(0xFF888888),
    AppVisualTheme.glass      => isDark ? const Color(0xFF6878A8): const Color(0xFF7888B8),
    AppVisualTheme.bento      => isDark ? const Color(0xFF777777): const Color(0xFF888888),
  };

  // ── Raised outer shadows ───────────────────────────────────────────────────
  static Color _lightShadow(bool isDark) =>
      isDark ? const Color(0xFF2A2E38) : const Color(0xFFFFFFFF);
  static Color _darkShadow(bool isDark) =>
      isDark ? const Color(0xFF13151A) : const Color(0xFFC8CAD4);

  static List<BoxShadow> raised(bool isDark) => switch (_theme) {
    AppVisualTheme.material => [],

    AppVisualTheme.neumorphic => [
      BoxShadow(
        color: _lightShadow(isDark).withAlpha(isDark ? 60 : 220),
        offset: const Offset(-5, -5),
        blurRadius: 12,
        spreadRadius: 1,
      ),
      BoxShadow(
        color: _darkShadow(isDark).withAlpha(isDark ? 180 : 160),
        offset: const Offset(5, 5),
        blurRadius: 12,
        spreadRadius: 1,
      ),
    ],

  // Clay outer shadow: x:20 y:20 blur:30 — diagonal per spec
  // Neutral grey shadow works on both white (light) and black (dark) base
    AppVisualTheme.clay => [
      BoxShadow(
        color: (isDark
            ? const Color(0xFF000000)
            : const Color(0xFFAAAAAA))
            .withAlpha(isDark ? 220 : 160),
        offset: const Offset(20, 20),
        blurRadius: 30,
        spreadRadius: 0,
      ),
    ],

    AppVisualTheme.glass => [
      BoxShadow(
        color: (isDark ? Colors.black : const Color(0xFF8899CC))
            .withAlpha(isDark ? 120 : 60),
        offset: const Offset(0, 8),
        blurRadius: 32,
        spreadRadius: -4,
      ),
      BoxShadow(
        color: (isDark ? const Color(0xFF334488) : const Color(0xFFAABBFF))
            .withAlpha(isDark ? 40 : 30),
        offset: const Offset(0, 2),
        blurRadius: 8,
        spreadRadius: 0,
      ),
    ],

    AppVisualTheme.bento => [],
  };

  static List<BoxShadow> raisedSm(bool isDark) => switch (_theme) {
    AppVisualTheme.material => [],

    AppVisualTheme.neumorphic => [
      BoxShadow(
        color: _lightShadow(isDark).withAlpha(isDark ? 50 : 200),
        offset: const Offset(-3, -3),
        blurRadius: 7,
      ),
      BoxShadow(
        color: _darkShadow(isDark).withAlpha(isDark ? 160 : 140),
        offset: const Offset(3, 3),
        blurRadius: 7,
      ),
    ],

    AppVisualTheme.clay => [
      BoxShadow(
        color: (isDark
            ? const Color(0xFF000000)
            : const Color(0xFFAAAAAA))
            .withAlpha(isDark ? 180 : 130),
        offset: const Offset(10, 10),
        blurRadius: 15,
        spreadRadius: 0,
      ),
    ],

    AppVisualTheme.glass => [
      BoxShadow(
        color: (isDark ? Colors.black : const Color(0xFF8899CC))
            .withAlpha(isDark ? 80 : 40),
        offset: const Offset(0, 4),
        blurRadius: 16,
        spreadRadius: -2,
      ),
    ],

    AppVisualTheme.bento => [],
  };

  static List<BoxShadow> inset(bool isDark) => switch (_theme) {
    AppVisualTheme.material => [],

    AppVisualTheme.neumorphic => [
      BoxShadow(
        color: _darkShadow(isDark).withAlpha(isDark ? 200 : 180),
        offset: const Offset(3, 3),
        blurRadius: 8,
      ),
      BoxShadow(
        color: _lightShadow(isDark).withAlpha(isDark ? 80 : 255),
        offset: const Offset(-3, -3),
        blurRadius: 8,
      ),
    ],

  // Clay pressed: smaller outer shadow
    AppVisualTheme.clay => [
      BoxShadow(
        color: (isDark
            ? const Color(0xFF000000)
            : const Color(0xFFAAAAAA))
            .withAlpha(isDark ? 140 : 90),
        offset: const Offset(8, 8),
        blurRadius: 12,
        spreadRadius: 0,
      ),
    ],

    AppVisualTheme.glass => [
      BoxShadow(
        color: Colors.black.withAlpha(isDark ? 60 : 30),
        offset: const Offset(2, 2),
        blurRadius: 8,
      ),
    ],

    AppVisualTheme.bento => [],
  };

  // ── Card border ────────────────────────────────────────────────────────────
  static BorderSide cardBorder(bool isDark) => switch (_theme) {
    AppVisualTheme.material => BorderSide(
        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE0E0E0),
        width: 1),
    AppVisualTheme.neumorphic => BorderSide.none,
    AppVisualTheme.clay       => BorderSide.none,
    AppVisualTheme.glass => BorderSide(
        color: Colors.white.withAlpha(isDark ? 30 : 60),
        width: 1),
    AppVisualTheme.bento => BorderSide(
        color: isDark ? const Color(0xFFEEEEEE) : const Color(0xFF111318),
        width: 2.5),
  };

  // ── Input fill ─────────────────────────────────────────────────────────────
  static Color inputFill(bool isDark) => switch (_theme) {
    AppVisualTheme.material =>
    isDark ? const Color(0xFF2C2B30) : const Color(0xFFF0F0F0),
    AppVisualTheme.neumorphic => base(isDark),
    AppVisualTheme.clay =>
    isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5),
    AppVisualTheme.glass =>
        Colors.white.withAlpha(isDark ? 12 : 20),
    AppVisualTheme.bento =>
    isDark ? const Color(0xFF111318) : Colors.white,
  };

  // ── Glass surface ──────────────────────────────────────────────────────────
  static Color glassSurface(ColorTheme theme, bool isDark) {
    final accent = accentFromTheme(theme);
    return isDark
        ? Color.alphaBlend(accent.withAlpha(18), Colors.white.withAlpha(15))
        : Color.alphaBlend(accent.withAlpha(12), Colors.white.withAlpha(180));
  }

  // ── Card tint / surface color ──────────────────────────────────────────────
  static Color cardTint(ColorTheme theme, bool isDark) {
    final accent = accentFromTheme(theme);
    return switch (_theme) {
      AppVisualTheme.neumorphic => base(isDark),
      AppVisualTheme.glass      => glassSurface(theme, isDark),
    // Clay: use the same pastel colors as the original ThemeHelper color themes.
    // These match getThemeColor() light values — teal.100, orange.200, etc.
    // On a white/black scaffold these pastel cards with clay inner shadows
    // look exactly like inflated colored clay tiles.
      AppVisualTheme.clay => _clayCardColor(theme, isDark),
      AppVisualTheme.bento => isDark
          ? Color.alphaBlend(accent.withAlpha(55), base(isDark))
          : Color.alphaBlend(accent.withAlpha(45), base(isDark)),
      _ => isDark
          ? Color.alphaBlend(accent.withAlpha(28), base(isDark))
          : Color.alphaBlend(accent.withAlpha(22), base(isDark)),
    };
  }

  /// Returns the exact pastel surface color for a clay card.
  /// matches ThemeHelper.getThemeColor() light/dark values precisely.
  static Color _clayCardColor(ColorTheme theme, bool isDark) {
    if (isDark) {
      return switch (theme) {
        ColorTheme.default_ => const Color(0xFF004D40).withAlpha(120), // teal.800 @ 47%
        ColorTheme.sunset   => const Color(0xFFE65100).withAlpha(110), // orange.900 @ 43%
        ColorTheme.orange   => const Color(0xFFE65100).withAlpha(100),
        ColorTheme.forest   => const Color(0xFF1B5E20).withAlpha(110), // green.900 @ 43%
        ColorTheme.lavender => const Color(0xFF4A148C).withAlpha(110), // purple.900 @ 43%
        ColorTheme.rose     => const Color(0xFF880E4F).withAlpha(110), // pink.900 @ 43%
      };
    }
    return switch (theme) {
      ColorTheme.default_ => const Color(0xFFB2DFDB), // teal.100
      ColorTheme.sunset   => const Color(0xFFFFCC80), // orange.200
      ColorTheme.orange   => const Color(0xFFFFB74D), // orange.300
      ColorTheme.forest   => const Color(0xFFA5D6A7), // green.200
      ColorTheme.lavender => const Color(0xFFCE93D8), // purple.200
      ColorTheme.rose     => const Color(0xFFF48FB1), // pink.200
    };
  }

  // ── Clay inner shadow colors ──────────────────────────────────────────────
  // Light (top-left x:10 y:8 blur:12): white highlight — works on any color
  // Dark (bottom-right x:-10 y:-8 blur:12): semi-transparent black —
  //   darkens whatever card color it sits on (teal, orange, green, etc.)
  static Color clayInnerLight(bool isDark) =>
      Colors.white.withAlpha(isDark ? 35 : 200);
  static Color clayInnerDark(bool isDark) =>
      Colors.black.withAlpha(isDark ? 100 : 60);

  // ── Full card BoxDecoration ────────────────────────────────────────────────
  static BoxDecoration cardDecoration(
      ColorTheme theme,
      bool isDark, {
        double radius = 20,
      }) {
    final border = cardBorder(isDark);
    final effectiveRadius = switch (_theme) {
    // Clay: radius beyond 50% of a typical card — very puffy
      AppVisualTheme.clay  => radius * 1.8,
      AppVisualTheme.bento => 0.0,
      _                    => radius,
    };
    return BoxDecoration(
      color: _theme == AppVisualTheme.glass ? null : cardTint(theme, isDark),
      borderRadius: BorderRadius.circular(effectiveRadius),
      boxShadow: raised(isDark),
      border: border == BorderSide.none ? null : Border.fromBorderSide(border),
    );
  }

  // ── Container decoration ───────────────────────────────────────────────────
  static BoxDecoration containerDecoration(
      bool isDark, {
        double radius = 14,
        bool insetStyle = false,
      }) {
    final border = cardBorder(isDark);
    final effectiveRadius = switch (_theme) {
      AppVisualTheme.clay  => radius * 1.6,
      AppVisualTheme.bento => 0.0,
      _                    => radius,
    };
    return BoxDecoration(
      color: base(isDark),
      borderRadius: BorderRadius.circular(effectiveRadius),
      border: border == BorderSide.none ? null : Border.fromBorderSide(border),
      boxShadow: insetStyle ? inset(isDark) : raised(isDark),
    );
  }

  // ── Pressable decoration ───────────────────────────────────────────────────
  static BoxDecoration pressableDecoration(
      bool isDark, {
        required bool pressed,
        required double radius,
      }) {
    final border = cardBorder(isDark);
    final effectiveRadius = switch (_theme) {
      AppVisualTheme.clay  => radius * 1.6,
      AppVisualTheme.bento => 0.0,
      _                    => radius,
    };
    final effectiveBorder = (_theme == AppVisualTheme.bento && pressed)
        ? const BorderSide(color: Color(0xFF888888), width: 2.5)
        : border;
    return BoxDecoration(
      color: pressed &&
          (_theme == AppVisualTheme.material ||
              _theme == AppVisualTheme.bento)
          ? textTertiary(isDark).withAlpha(20)
          : base(isDark),
      borderRadius: BorderRadius.circular(effectiveRadius),
      border: effectiveBorder == BorderSide.none
          ? null
          : Border.fromBorderSide(effectiveBorder),
      boxShadow: pressed ? inset(isDark) : raised(isDark),
    );
  }

  // ── Neumorphic input shadows ───────────────────────────────────────────────
  static List<BoxShadow> _inputInset(bool isDark) => [
    BoxShadow(
      color: (isDark ? const Color(0xFF0E1013) : const Color(0xFFB8BACA))
          .withAlpha(isDark ? 220 : 180),
      offset: const Offset(4, 4),
      blurRadius: 10,
    ),
    BoxShadow(
      color: (isDark ? const Color(0xFF383E4B) : const Color(0xFFFFFFFF))
          .withAlpha(isDark ? 180 : 255),
      offset: const Offset(-4, -4),
      blurRadius: 10,
    ),
  ];

  static List<BoxShadow> _inputFocusGlow(bool isDark) => [
    BoxShadow(
      color: const Color(0xFFFF6600).withAlpha(isDark ? 80 : 50),
      offset: Offset.zero,
      blurRadius: 10,
      spreadRadius: -2,
    ),
    BoxShadow(
      color: const Color(0xFFFFD43B).withAlpha(isDark ? 80 : 50),
      offset: Offset.zero,
      blurRadius: 10,
      spreadRadius: -2,
    ),
    ..._inputInset(isDark),
  ];

  static List<BoxShadow> inputShadow(bool isDark) =>
      _theme == AppVisualTheme.neumorphic ? _inputInset(isDark) : [];
  static List<BoxShadow> inputFocusShadow(bool isDark) =>
      _theme == AppVisualTheme.neumorphic ? _inputFocusGlow(isDark) : [];

  // ── Field border styles ────────────────────────────────────────────────────
  static ({Color idle, Color focused, double idleWidth, double focusedWidth})
  fieldBorderStyle(bool isDark) => switch (_theme) {
    AppVisualTheme.neumorphic => (
    idle: (isDark ? const Color(0xFF383E4B) : const Color(0xFFC8CAD4))
        .withAlpha(100),
    focused: isDark
        ? const Color(0xFFFFD43B).withAlpha(200)
        : const Color(0xFFFF6600).withAlpha(160),
    idleWidth: 1.0,
    focusedWidth: 1.5,
    ),
    AppVisualTheme.clay => (
    idle: (isDark ? const Color(0xFF333333) : const Color(0xFFCCCCCC))
        .withAlpha(200),
    focused: isDark
        ? Colors.white.withAlpha(180)
        : Colors.black.withAlpha(160),
    idleWidth: 1.5,
    focusedWidth: 2.0,
    ),
    AppVisualTheme.glass => (
    idle: Colors.white.withAlpha(isDark ? 25 : 40),
    focused: (isDark
        ? const Color(0xFF88AAFF)
        : const Color(0xFF4466FF))
        .withAlpha(180),
    idleWidth: 1.0,
    focusedWidth: 1.5,
    ),
    AppVisualTheme.bento => (
    idle: isDark ? const Color(0xFF444444) : const Color(0xFF999999),
    focused: isDark ? Colors.white : const Color(0xFF111318),
    idleWidth: 2.0,
    focusedWidth: 2.0,
    ),
    _ => (
    idle: textTertiary(isDark).withAlpha(80),
    focused: textSecondary(isDark).withAlpha(120),
    idleWidth: 1.0,
    focusedWidth: 1.5,
    ),
  };

  // ── Accent colors ──────────────────────────────────────────────────────────
  static Color accentFromTheme(ColorTheme theme) => switch (theme) {
    ColorTheme.default_ => const Color(0xFF00897B),
    ColorTheme.sunset   => const Color(0xFFEF6C00),
    ColorTheme.orange   => const Color(0xFFF57C00),
    ColorTheme.forest   => const Color(0xFF388E3C),
    ColorTheme.lavender => const Color(0xFF7B1FA2),
    ColorTheme.rose     => const Color(0xFFC2185B),
  };

  // ── InputDecoration ────────────────────────────────────────────────────────
  static InputDecoration fieldDecoration(
      bool isDark,
      String label, {
        IconData? icon,
        String? hint,
      }) {
    final ter = textTertiary(isDark);
    final bs  = fieldBorderStyle(isDark);
    return InputDecoration(
      labelText: label.isNotEmpty ? label : null,
      hintText: hint,
      prefixIcon: icon != null ? Icon(icon, size: 18, color: ter) : null,
      filled: true,
      fillColor: inputFill(isDark),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: bs.idle, width: bs.idleWidth)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: bs.focused, width: bs.focusedWidth)),
      labelStyle: TextStyle(fontSize: 13, color: ter),
      hintStyle: TextStyle(fontSize: 13, color: ter),
    );
  }

  // ── Theme metadata ─────────────────────────────────────────────────────────
  static String visualThemeName(AppVisualTheme t) => switch (t) {
    AppVisualTheme.material   => 'Material',
    AppVisualTheme.neumorphic => 'Neo',
    AppVisualTheme.clay       => 'Clay',
    AppVisualTheme.glass      => 'Glass',
    AppVisualTheme.bento      => 'Bento',
  };

  static IconData visualThemeIcon(AppVisualTheme t) => switch (t) {
    AppVisualTheme.material   => Icons.layers_outlined,
    AppVisualTheme.neumorphic => Icons.blur_on_rounded,
    AppVisualTheme.clay       => Icons.bubble_chart_rounded,
    AppVisualTheme.glass      => Icons.water_drop_outlined,
    AppVisualTheme.bento      => Icons.grid_view_rounded,
  };

  static bool isPremium(AppVisualTheme t) => switch (t) {
    AppVisualTheme.material   => false,
    AppVisualTheme.neumorphic => false,
    AppVisualTheme.clay       => false,
    AppVisualTheme.glass      => false,
    AppVisualTheme.bento      => false,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// _ClayInnerShadowPainter
//
// Implements claymorphism's two inset shadows using CustomPainter.
// Spec (from reference image):
//   Inset light:  x:10  y:8   blur:12  (top-left,     lighter)
//   Inset dark:   x:-10 y:-8  blur:12  (bottom-right, darker)
//   Outer shadow: x:20  y:20  blur:30  (handled via BoxShadow in raised())
//
// Technique: clip to the rounded rect, then draw two blurred offset rects
// that bleed inward from each corner — simulating CSS inset box-shadow.
// ─────────────────────────────────────────────────────────────────────────────

class _ClayInnerShadowPainter extends CustomPainter {
  final Color surfaceColor;
  final Color innerLightColor; // top-left highlight
  final Color innerDarkColor;  // bottom-right shadow
  final double radius;

  const _ClayInnerShadowPainter({
    required this.surfaceColor,
    required this.innerLightColor,
    required this.innerDarkColor,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );

    // 1. Draw base surface
    canvas.drawRRect(rrect, Paint()..color = surfaceColor);

    // 2. Clip everything to the shape — inset effects must stay inside
    canvas.save();
    canvas.clipRRect(rrect);

    // 3. Top-left inset highlight: x:10 y:8 blur:12
    //    Draw a same-size rect shifted by (+10, +8) so its blurred edge
    //    bleeds inward from the top-left corner only.
    final lightPaint = Paint()
      ..color = innerLightColor
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(10, 8, size.width, size.height),
        Radius.circular(radius),
      ),
      lightPaint,
    );

    // 4. Bottom-right inset shadow: x:-10 y:-8 blur:12
    //    Draw a same-size rect shifted by (-10, -8) so its blurred edge
    //    bleeds inward from the bottom-right corner only.
    final darkPaint = Paint()
      ..color = innerDarkColor
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-10, -8, size.width, size.height),
        Radius.circular(radius),
      ),
      darkPaint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_ClayInnerShadowPainter old) =>
      old.surfaceColor != surfaceColor ||
          old.innerLightColor != innerLightColor ||
          old.innerDarkColor != innerDarkColor ||
          old.radius != radius;
}

// ─────────────────────────────────────────────────────────────────────────────
// _ClayWrapper
//
// Wraps any widget with the claymorphic inner-shadow effect.
// Only used internally — NeuContainer, NeuPressable, NeuIconButton, NeuField
// all delegate to this when theme == clay.
// ─────────────────────────────────────────────────────────────────────────────

class _ClayWrapper extends StatelessWidget {
  final Widget child;
  final bool isDark;
  final double radius;
  final Color surfaceColor;
  final EdgeInsetsGeometry? padding;

  const _ClayWrapper({
    required this.child,
    required this.isDark,
    required this.radius,
    required this.surfaceColor,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ClayInnerShadowPainter(
        surfaceColor: surfaceColor,
        innerLightColor: Neu.clayInnerLight(isDark),
        innerDarkColor: Neu.clayInnerDark(isDark),
        radius: radius,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: padding != null
            ? Padding(padding: padding!, child: child)
            : child,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NeuPressable
// ─────────────────────────────────────────────────────────────────────────────

class NeuPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double radius;
  final bool isDark;
  final EdgeInsetsGeometry? padding;

  const NeuPressable({
    required this.child,
    required this.onTap,
    required this.isDark,
    this.radius = 16,
    this.padding,
    super.key,
  });

  @override
  State<NeuPressable> createState() => _NeuPressableState();
}

class _NeuPressableState extends State<NeuPressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isClay    = Neu.currentTheme == AppVisualTheme.clay;
    final clayR     = widget.radius * 1.6;
    final decoration = Neu.pressableDecoration(
      widget.isDark,
      pressed: _pressed,
      radius: widget.radius,
    );

    Widget content;

    if (isClay) {
      content = AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        // No decoration color — _ClayWrapper paints the surface
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(clayR),
          boxShadow: decoration.boxShadow,
        ),
        child: _ClayWrapper(
          isDark: widget.isDark,
          radius: clayR,
          surfaceColor: decoration.color ?? Neu.base(widget.isDark),
          padding: widget.padding,
          child: widget.child,
        ),
      );
    } else {
      content = AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: widget.padding,
        decoration: decoration,
        child: widget.child,
      );
    }

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: content,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NeuContainer
// ─────────────────────────────────────────────────────────────────────────────

class NeuContainer extends StatelessWidget {
  final Widget child;
  final bool isDark;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final bool inset;

  const NeuContainer({
    required this.child,
    required this.isDark,
    this.radius = 14,
    this.padding,
    this.inset = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Neu.currentTheme;

    if (theme == AppVisualTheme.glass) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: padding,
            decoration: Neu.containerDecoration(isDark,
                radius: radius, insetStyle: inset),
            child: child,
          ),
        ),
      );
    }

    if (theme == AppVisualTheme.clay) {
      final clayR      = radius * 1.6;
      final decoration = Neu.containerDecoration(isDark,
          radius: radius, insetStyle: inset);
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(clayR),
          boxShadow: decoration.boxShadow,
        ),
        child: _ClayWrapper(
          isDark: isDark,
          radius: clayR,
          surfaceColor: decoration.color ?? Neu.base(isDark),
          padding: padding,
          child: child,
        ),
      );
    }

    return Container(
      padding: padding,
      decoration:
      Neu.containerDecoration(isDark, radius: radius, insetStyle: inset),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NeuIconButton
// ─────────────────────────────────────────────────────────────────────────────

class NeuIconButton extends StatefulWidget {
  final Widget icon;
  final VoidCallback onTap;
  final bool isDark;
  final double size;

  const NeuIconButton({
    required this.icon,
    required this.onTap,
    required this.isDark,
    this.size = 40,
    super.key,
  });

  @override
  State<NeuIconButton> createState() => _NeuIconButtonState();
}

class _NeuIconButtonState extends State<NeuIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isClay    = Neu.currentTheme == AppVisualTheme.clay;
    final btnRadius = widget.size * 0.3;
    final clayR     = btnRadius * 1.6;
    final decoration = Neu.pressableDecoration(
      widget.isDark,
      pressed: _pressed,
      radius: btnRadius,
    );

    Widget btn;

    if (isClay) {
      btn = SizedBox(
        width: widget.size,
        height: widget.size,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(clayR),
            boxShadow: decoration.boxShadow,
          ),
          child: _ClayWrapper(
            isDark: widget.isDark,
            radius: clayR,
            surfaceColor: decoration.color ?? Neu.base(widget.isDark),
            child: Center(child: widget.icon),
          ),
        ),
      );
    } else {
      btn = AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: widget.size,
        height: widget.size,
        decoration: decoration,
        child: Center(child: widget.icon),
      );
    }

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: btn,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NeuField
// ─────────────────────────────────────────────────────────────────────────────

class NeuField extends StatefulWidget {
  final bool isDark;
  final String label;
  final String? hint;
  final IconData? icon;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final Function(String)? onChanged;
  final VoidCallback? onSubmitted;
  final int? maxLines;
  final int? minLines;
  final TextInputAction? textInputAction;
  final TextStyle? style;

  const NeuField({
    required this.isDark,
    required this.controller,
    this.label = '',
    this.hint,
    this.icon,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.maxLines = 1,
    this.minLines,
    this.textInputAction,
    this.style,
    super.key,
  });

  @override
  State<NeuField> createState() => _NeuFieldState();
}

class _NeuFieldState extends State<NeuField> {
  late FocusNode _focus;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus = widget.focusNode ?? FocusNode();
    _focus.addListener(() {
      if (mounted) setState(() => _focused = _focus.hasFocus);
    });
  }

  @override
  void dispose() {
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme  = Neu.currentTheme;
    final isDark = widget.isDark;
    final ter    = Neu.textTertiary(isDark);

    if (theme == AppVisualTheme.material) {
      return TextField(
        controller: widget.controller,
        focusNode: _focus,
        maxLines: widget.maxLines,
        minLines: widget.minLines,
        textInputAction: widget.textInputAction,
        onChanged: widget.onChanged,
        onSubmitted:
        widget.onSubmitted != null ? (_) => widget.onSubmitted!() : null,
        style: widget.style ??
            TextStyle(fontSize: 14, color: Neu.textPrimary(isDark)),
        decoration: Neu.fieldDecoration(isDark, widget.label,
            icon: widget.icon, hint: widget.hint),
      );
    }

    if (theme == AppVisualTheme.glass) {
      final bs = Neu.fieldBorderStyle(isDark);
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              color: Neu.inputFill(isDark),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _focused ? bs.focused : bs.idle,
                width: _focused ? bs.focusedWidth : bs.idleWidth,
              ),
            ),
            child: _textField(isDark, ter),
          ),
        ),
      );
    }

    final fieldRadius = switch (theme) {
      AppVisualTheme.clay  => 16.0,
      AppVisualTheme.bento => 0.0,
      _                    => 10.0,
    };

    final bs      = Neu.fieldBorderStyle(isDark);
    final shadows = _focused
        ? Neu.inputFocusShadow(isDark)
        : Neu.inputShadow(isDark);

    // Clay: use _ClayWrapper for inner shadow effect on the field too
    if (theme == AppVisualTheme.clay) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(fieldRadius),
          boxShadow: shadows,
          border: Border.all(
            color: _focused ? bs.focused : bs.idle,
            width: _focused ? bs.focusedWidth : bs.idleWidth,
          ),
        ),
        child: _ClayWrapper(
          isDark: isDark,
          radius: fieldRadius,
          surfaceColor: Neu.inputFill(isDark),
          child: _textField(isDark, ter),
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: Neu.inputFill(isDark),
        borderRadius: BorderRadius.circular(fieldRadius),
        boxShadow: shadows,
        border: Border.all(
          color: _focused ? bs.focused : bs.idle,
          width: _focused ? bs.focusedWidth : bs.idleWidth,
        ),
      ),
      child: _textField(isDark, ter),
    );
  }

  Widget _textField(bool isDark, Color ter) => TextField(
    controller: widget.controller,
    focusNode: _focus,
    maxLines: widget.maxLines,
    minLines: widget.minLines,
    textInputAction: widget.textInputAction,
    onChanged: widget.onChanged,
    onSubmitted:
    widget.onSubmitted != null ? (_) => widget.onSubmitted!() : null,
    style: widget.style ??
        TextStyle(fontSize: 14, color: Neu.textPrimary(isDark)),
    decoration: InputDecoration(
      labelText: widget.label.isNotEmpty ? widget.label : null,
      hintText: widget.hint,
      prefixIcon: widget.icon != null
          ? Icon(widget.icon, size: 18, color: ter)
          : null,
      filled: false,
      contentPadding:
      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      labelStyle: TextStyle(fontSize: 13, color: ter),
      hintStyle: TextStyle(fontSize: 13, color: ter),
    ),
  );
}