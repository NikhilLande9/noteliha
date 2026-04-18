// lib/widgets/touch_writing_canvas.dart

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data model
// ─────────────────────────────────────────────────────────────────────────────

enum DrawTool { pen, highlighter, eraser }

class DrawPoint {
  final double x, y, pressure;
  const DrawPoint(this.x, this.y, [this.pressure = 1.0]);

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'p': pressure};
  factory DrawPoint.fromJson(Map j) =>
      DrawPoint((j['x'] as num).toDouble(), (j['y'] as num).toDouble(),
          (j['p'] as num? ?? 1.0).toDouble());
}

class Stroke {
  final List<DrawPoint> points;
  final Color color;
  final double width;
  final DrawTool tool;

  const Stroke({
    required this.points,
    required this.color,
    required this.width,
    required this.tool,
  });

  bool get isEraser => tool == DrawTool.eraser;

  Map<String, dynamic> toJson() => {
    'points': points.map((p) => p.toJson()).toList(),
    'color': color.toARGB32(),
    'width': width,
    'tool': tool.index,
  };

  factory Stroke.fromJson(Map<String, dynamic> j) => Stroke(
    points: (j['points'] as List)
        .map((p) => DrawPoint.fromJson(p as Map))
        .toList(),
    color: Color(j['color'] as int),
    width: (j['width'] as num).toDouble(),
    tool: DrawTool.values[j['tool'] as int? ?? 0],
  );
}

// Canvas data serialisation
String strokestoJson(List<Stroke> strokes) =>
    jsonEncode(strokes.map((s) => s.toJson()).toList());

List<Stroke> strokesFromJson(String? json) {
  if (json == null || json.isEmpty) return [];
  try {
    final list = jsonDecode(json) as List;
    return list.map((e) => Stroke.fromJson(e as Map<String, dynamic>)).toList();
  } catch (_) {
    return [];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Painter
// ─────────────────────────────────────────────────────────────────────────────

class _CanvasPainter extends CustomPainter {
  final List<Stroke> strokes;
  final Stroke? activeStroke;
  final Color bgColor;

  const _CanvasPainter({
    required this.strokes,
    required this.bgColor,
    this.activeStroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRect(
        Offset.zero & size, Paint()..color = bgColor);

    // Committed strokes + active stroke
    final all = [...strokes, if (activeStroke != null) activeStroke!];
    for (final stroke in all) {
      _drawStroke(canvas, stroke);
    }
  }

  void _drawStroke(Canvas canvas, Stroke stroke) {
    if (stroke.points.isEmpty) return;

    final paint = Paint()
      ..color = stroke.isEraser ? bgColor : stroke.color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..blendMode = stroke.isEraser ? BlendMode.clear : BlendMode.srcOver;

    if (stroke.tool == DrawTool.highlighter) {
      paint
        ..color = stroke.color.withAlpha(80)
        ..blendMode = BlendMode.multiply;
    }

    if (stroke.points.length == 1) {
      final p = stroke.points.first;
      paint
        ..style = PaintingStyle.fill
        ..strokeWidth = 0;
      canvas.drawCircle(
          Offset(p.x, p.y), stroke.width * p.pressure * 0.5, paint);
      return;
    }

    // Catmull-Rom → cubic Bézier for smooth curves
    final path = Path();
    final pts  = stroke.points;
    path.moveTo(pts[0].x, pts[0].y);

    for (int i = 0; i < pts.length - 1; i++) {
      final p0 = i > 0 ? pts[i - 1] : pts[i];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = i + 2 < pts.length ? pts[i + 2] : pts[i + 1];

      final cp1x = p1.x + (p2.x - p0.x) / 6;
      final cp1y = p1.y + (p2.y - p0.y) / 6;
      final cp2x = p2.x - (p3.x - p1.x) / 6;
      final cp2y = p2.y - (p3.y - p1.y) / 6;

      // Variable width via pressure: scale base width by average pressure
      final avgPressure = (p1.pressure + p2.pressure) / 2;
      paint.strokeWidth = stroke.width * avgPressure;

      path.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.x, p2.y);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CanvasPainter old) =>
      old.strokes != strokes ||
          old.activeStroke != activeStroke ||
          old.bgColor != bgColor;
}

// ─────────────────────────────────────────────────────────────────────────────
// TouchWritingCanvas widget
// ─────────────────────────────────────────────────────────────────────────────

class TouchWritingCanvas extends StatefulWidget {
  final bool isDark;

  /// JSON string from Note.content — pass '' for a blank canvas.
  final String initialJson;

  /// Called whenever the canvas changes. Parent should persist the result.
  final void Function(String json) onChanged;

  const TouchWritingCanvas({
    super.key,
    required this.isDark,
    required this.initialJson,
    required this.onChanged,
  });

  @override
  State<TouchWritingCanvas> createState() => TouchWritingCanvasState();
}

class TouchWritingCanvasState extends State<TouchWritingCanvas> {
  // Stroke history
  final List<Stroke> _strokes    = [];
  final List<Stroke> _undoBuffer = []; // redo stack (popped strokes)
  Stroke? _active;

  // Tool state
  DrawTool _tool     = DrawTool.pen;
  Color    _penColor = Colors.black87;
  double   _width    = 3.0;

  // Export key
  final _repaintKey = GlobalKey();

  bool get _canUndo => _strokes.isNotEmpty;
  bool get _canRedo => _undoBuffer.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _strokes.addAll(strokesFromJson(widget.initialJson));
    _penColor = widget.isDark ? Colors.white : Colors.black87;
  }

  void _notify() => widget.onChanged(strokestoJson(_strokes));

  // ── Pointer events ──────────────────────────────────────────────────────────

  void _onPointerDown(PointerEvent e) {
    final color = _tool == DrawTool.eraser
        ? _bgColor
        : (_tool == DrawTool.highlighter
        ? _penColor.withAlpha(120)
        : _penColor);
    _active = Stroke(
      points: [DrawPoint(e.localPosition.dx, e.localPosition.dy, _pressure(e))],
      color: color,
      width: _tool == DrawTool.highlighter ? _width * 4 : _width,
      tool: _tool,
    );
    setState(() {});
  }

  void _onPointerMove(PointerEvent e) {
    if (_active == null) return;
    _active!.points.add(
        DrawPoint(e.localPosition.dx, e.localPosition.dy, _pressure(e)));
    setState(() {});
  }

  void _onPointerUp(PointerEvent e) {
    if (_active == null) return;
    _strokes.add(_active!);
    _undoBuffer.clear(); // new stroke clears redo
    _active = null;
    setState(() {});
    _notify();
  }

  double _pressure(PointerEvent e) =>
      e.pressure == 0.0 ? 1.0 : e.pressure.clamp(0.1, 1.0);

  Color get _bgColor =>
      widget.isDark ? const Color(0xFF1E2128) : Colors.white;

  // ── Undo / Redo ─────────────────────────────────────────────────────────────

  void undo() {
    if (!_canUndo) return;
    _undoBuffer.add(_strokes.removeLast());
    setState(() {});
    _notify();
  }

  void redo() {
    if (!_canRedo) return;
    _strokes.add(_undoBuffer.removeLast());
    setState(() {});
    _notify();
  }

  void clear() {
    // Save all strokes to undo buffer (in reverse order for redo)
    _undoBuffer.clear();
    _undoBuffer.addAll(_strokes.reversed);
    _strokes.clear();
    setState(() {});
    _notify();
  }

  // ── Export ───────────────────────────────────────────────────────────────────

  Future<Uint8List?> exportPng() async {
    try {
      final boundary = _repaintKey.currentContext!.findRenderObject()!
      as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('[TouchCanvas] exportPng failed: $e');
      return null;
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bg     = _bgColor;

    return Column(
      children: [
        // ── Toolbar ──────────────────────────────────────────────────────────
        _Toolbar(
          isDark: isDark,
          activeTool: _tool,
          activeColor: _penColor,
          strokeWidth: _width,
          canUndo: _canUndo,
          canRedo: _canRedo,
          onToolChanged: (t) => setState(() => _tool = t),
          onColorChanged: (c) => setState(() => _penColor = c),
          onWidthChanged: (w) => setState(() => _width = w),
          onUndo: undo,
          onRedo: redo,
          onClear: () => showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Clear canvas?'),
              content: const Text('All strokes will be removed.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel')),
                TextButton(
                    onPressed: () { Navigator.pop(ctx); clear(); },
                    child: const Text('Clear',
                        style: TextStyle(color: Colors.redAccent))),
              ],
            ),
          ),
          onExport: () async {
            final bytes = await exportPng();
            if (bytes != null && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Drawing exported'),
                behavior: SnackBarBehavior.floating,
              ));
            }
          },
        ),

        // ── Canvas ───────────────────────────────────────────────────────────
        Expanded(
          child: RepaintBoundary(
            key: _repaintKey,
            child: Listener(
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp:   _onPointerUp,
              onPointerCancel: (_) => setState(() => _active = null),
              child: CustomPaint(
                painter: _CanvasPainter(
                  strokes:      _strokes,
                  activeStroke: _active,
                  bgColor:      bg,
                ),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Toolbar
// ─────────────────────────────────────────────────────────────────────────────

class _Toolbar extends StatelessWidget {
  final bool isDark;
  final DrawTool activeTool;
  final Color activeColor;
  final double strokeWidth;
  final bool canUndo, canRedo;
  final void Function(DrawTool) onToolChanged;
  final void Function(Color) onColorChanged;
  final void Function(double) onWidthChanged;
  final VoidCallback onUndo, onRedo, onClear, onExport;

  const _Toolbar({
    required this.isDark,
    required this.activeTool,
    required this.activeColor,
    required this.strokeWidth,
    required this.canUndo,
    required this.canRedo,
    required this.onToolChanged,
    required this.onColorChanged,
    required this.onWidthChanged,
    required this.onUndo,
    required this.onRedo,
    required this.onClear,
    required this.onExport,
  });

  static const _palette = [
    // ── Monochrome ──────────────────────────────────────────────────────
    Colors.black,
    Color(0xFF424242), // dark gray
    Color(0xFF9E9E9E), // medium gray
    Colors.white,

    // ── Primary Colors ──────────────────────────────────────────────────
    Color(0xFFE53935), // red
    Color(0xFFD81B60), // pink
    Color(0xFF8E24AA), // purple
    Color(0xFF5E35B1), // deep purple
    Color(0xFF3949AB), // indigo
    Color(0xFF1E88E5), // blue

    // ── Secondary Colors ────────────────────────────────────────────────
    Color(0xFF039BE5), // light blue
    Color(0xFF00ACC1), // cyan
    Color(0xFF00897B), // teal
    Color(0xFF43A047), // green
    Color(0xFF7CB342), // light green
    Color(0xFFC0CA33), // lime

    // ── Warm Colors ─────────────────────────────────────────────────────
    Color(0xFFFDD835), // yellow
    Color(0xFFFFB300), // amber
    Color(0xFFFB8C00), // orange
    Color(0xFFFF7043), // deep orange

    // ── Earth Tones ─────────────────────────────────────────────────────
    Color(0xFF6D4C41), // brown
    Color(0xFF78909C), // blue gray
    Color(0xFF8D6E63), // light brown
  ];

  @override
  Widget build(BuildContext context) {
    final bg   = isDark ? const Color(0xFF2A2E38) : const Color(0xFFF0F0F0);
    final sub  = isDark ? const Color(0xFFADB3C4) : const Color(0xFF5A5E6E);
    final prim = isDark ? Colors.white : Colors.black87;

    return Container(
      height: 52,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // Tool buttons
          _ToolBtn(
            icon: Icons.edit_rounded,
            tooltip: 'Pen',
            active: activeTool == DrawTool.pen,
            isDark: isDark,
            onTap: () => onToolChanged(DrawTool.pen),
          ),
          _ToolBtn(
            icon: Icons.brush_rounded,
            tooltip: 'Highlighter',
            active: activeTool == DrawTool.highlighter,
            isDark: isDark,
            onTap: () => onToolChanged(DrawTool.highlighter),
          ),
          _ToolBtn(
            icon: Icons.auto_fix_high_rounded,
            tooltip: 'Eraser',
            active: activeTool == DrawTool.eraser,
            isDark: isDark,
            onTap: () => onToolChanged(DrawTool.eraser),
          ),

          Container(
              width: 1, height: 28, color: sub.withAlpha(60),
              margin: const EdgeInsets.symmetric(horizontal: 4)),

          // Color picker (tap to open)
          GestureDetector(
            onTap: () => _showColorPicker(context),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                  color: activeColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: sub.withAlpha(120), width: 1.5)),
            ),
          ),
          const SizedBox(width: 8),

          // Width slider
          SizedBox(
            width: 80,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                trackHeight: 2,
              ),
              child: Slider(
                value: strokeWidth.clamp(1.0, 20.0),
                min: 1.0,
                max: 20.0,
                activeColor: Theme.of(context).colorScheme.primary,
                inactiveColor: sub.withAlpha(80),
                onChanged: onWidthChanged,
              ),
            ),
          ),

          const Spacer(),

          // Undo
          IconButton(
            icon: Icon(Icons.undo_rounded,
                color: canUndo ? prim : sub.withAlpha(60)),
            tooltip: 'Undo',
            onPressed: canUndo ? onUndo : null,
            iconSize: 20,
          ),
          // Redo
          IconButton(
            icon: Icon(Icons.redo_rounded,
                color: canRedo ? prim : sub.withAlpha(60)),
            tooltip: 'Redo',
            onPressed: canRedo ? onRedo : null,
            iconSize: 20,
          ),
          // Clear
          IconButton(
            icon: Icon(Icons.delete_sweep_rounded, color: sub),
            tooltip: 'Clear',
            onPressed: onClear,
            iconSize: 20,
          ),
        ],
      ),
    );
  }

  void _showColorPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          spacing: 16,
          runSpacing: 12,
          children: _palette.map((c) {
            final isSelected = c.toARGB32() == activeColor.toARGB32();
            return GestureDetector(
              onTap: () {
                onColorChanged(c);
                Navigator.pop(ctx);
              },
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? Colors.blue
                        : Colors.grey.withAlpha(80),
                    width: isSelected ? 3 : 1.5,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check_rounded,
                    color: Colors.blue, size: 20)
                    : null,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _ToolBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool active;
  final bool isDark;
  final VoidCallback onTap;

  const _ToolBtn({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final sub    = isDark ? const Color(0xFFADB3C4) : const Color(0xFF5A5E6E);
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 36,
          height: 36,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: active ? accent.withAlpha(30) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: active ? accent : sub),
        ),
      ),
    );
  }
}