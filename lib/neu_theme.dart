// lib/neu_theme.dart
// ─────────────────────────────────────────────────────────────────────────────
// Shared Visual Theme Tokens
//
// HOW TO ADD A NEW THEME:
//   1. Add a value to AppVisualTheme in models/enums.dart
//   2. Add a case to each switch in this file
//   3. Add it to the settings screen picker
//   No screen files need to change.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'models.dart';

class Neu {
  // Active visual theme — set once from AppSettingsProvider on startup/change.
  static AppVisualTheme _theme = AppVisualTheme.neumorphic;

  /// Called by AppSettingsProvider whenever the user changes visual theme.
  static void setTheme(AppVisualTheme theme) => _theme = theme;

  static AppVisualTheme get currentTheme => _theme;

  // ── Base surface ───────────────────────────────────────────────────────────
  static Color base(bool isDark) => switch (_theme) {
        AppVisualTheme.material   => isDark ? const Color(0xFF1C1B1F) : Colors.white,
        AppVisualTheme.neumorphic => isDark ? const Color(0xFF1E2128) : const Color(0xFFE8EAF0),
      };

  // ── Text hierarchy ─────────────────────────────────────────────────────────
  static Color textPrimary(bool isDark) => switch (_theme) {
        AppVisualTheme.material   => isDark ? Colors.white : const Color(0xFF1C1B1F),
        AppVisualTheme.neumorphic => isDark ? const Color(0xFFECEEF5) : const Color(0xFF1E2128),
      };

  static Color textSecondary(bool isDark) => switch (_theme) {
        AppVisualTheme.material   => isDark ? const Color(0xFFCAC4D0) : const Color(0xFF49454F),
        AppVisualTheme.neumorphic => isDark ? const Color(0xFFADB3C4) : const Color(0xFF5A5E6E),
      };

  static Color textTertiary(bool isDark) => switch (_theme) {
        AppVisualTheme.material   => isDark ? const Color(0xFF938F99) : const Color(0xFF79747E),
        AppVisualTheme.neumorphic => isDark ? const Color(0xFF7A8090) : const Color(0xFF8A8D9A),
      };

  // ── Shadows ────────────────────────────────────────────────────────────────
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
      };

  // ── Card border — Material uses borders instead of shadows ─────────────────
  static BorderSide cardBorder(bool isDark) => switch (_theme) {
        AppVisualTheme.material => BorderSide(
            color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE0E0E0),
            width: 1),
        AppVisualTheme.neumorphic => BorderSide.none,
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
    final ter = Neu.textTertiary(isDark);
    return InputDecoration(
      labelText: label.isNotEmpty ? label : null,
      hintText: hint,
      prefixIcon: icon != null ? Icon(icon, size: 18, color: ter) : null,
      filled: true,
      fillColor: base(isDark),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: _theme == AppVisualTheme.material
            ? BorderSide(color: textTertiary(isDark).withAlpha(80))
            : BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      labelStyle: TextStyle(fontSize: 13, color: ter),
      hintStyle: TextStyle(fontSize: 13, color: ter),
    );
  }

  // ── Container decoration helper ────────────────────────────────────────────
  static BoxDecoration containerDecoration(
    bool isDark, {
    double radius = 14,
    bool insetStyle = false,
  }) =>
      BoxDecoration(
        color: base(isDark),
        borderRadius: BorderRadius.circular(radius),
        border: _theme == AppVisualTheme.material
            ? Border.fromBorderSide(cardBorder(isDark))
            : null,
        boxShadow: insetStyle ? inset(isDark) : raised(isDark),
      );

  // ── Theme metadata for settings UI ────────────────────────────────────────
  static String visualThemeName(AppVisualTheme t) => switch (t) {
        AppVisualTheme.material   => 'Material',
        AppVisualTheme.neumorphic => 'Neumorphic',
      };

  static IconData visualThemeIcon(AppVisualTheme t) => switch (t) {
        AppVisualTheme.material   => Icons.layers_outlined,
        AppVisualTheme.neumorphic => Icons.blur_on_rounded,
      };

  /// Set to true for themes that require purchase.
  static bool isPremium(AppVisualTheme t) => switch (t) {
        AppVisualTheme.material   => false,
        AppVisualTheme.neumorphic => false,
      };
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
    final isMaterial = Neu.currentTheme == AppVisualTheme.material;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        padding: widget.padding,
        decoration: BoxDecoration(
          color: _pressed && isMaterial
              ? Neu.textTertiary(widget.isDark).withAlpha(20)
              : Neu.base(widget.isDark),
          borderRadius: BorderRadius.circular(widget.radius),
          border: isMaterial
              ? Border.fromBorderSide(Neu.cardBorder(widget.isDark))
              : null,
          boxShadow:
              _pressed ? Neu.inset(widget.isDark) : Neu.raised(widget.isDark),
        ),
        child: widget.child,
      ),
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
    final isMaterial = Neu.currentTheme == AppVisualTheme.material;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Neu.base(isDark),
        borderRadius: BorderRadius.circular(radius),
        border: isMaterial
            ? Border.fromBorderSide(Neu.cardBorder(isDark))
            : null,
        boxShadow: inset ? Neu.inset(isDark) : Neu.raised(isDark),
      ),
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
    final isMaterial = Neu.currentTheme == AppVisualTheme.material;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: _pressed && isMaterial
              ? Neu.textTertiary(widget.isDark).withAlpha(20)
              : Neu.base(widget.isDark),
          borderRadius: BorderRadius.circular(widget.size * 0.3),
          border: isMaterial
              ? Border.fromBorderSide(Neu.cardBorder(widget.isDark))
              : null,
          boxShadow: _pressed
              ? Neu.inset(widget.isDark)
              : Neu.raisedSm(widget.isDark),
        ),
        child: Center(child: widget.icon),
      ),
    );
  }
}
