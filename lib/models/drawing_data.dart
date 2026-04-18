// lib/models/drawing_data.dart
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

// ─────────────────────────────────────────────────────────────────────────────
// DrawingPoint — a single point in a stroke, or null to lift the pen
// ─────────────────────────────────────────────────────────────────────────────

class DrawingPoint {
  final double x;
  final double y;

  /// ARGB integer — store as int so it survives JSON round-trips without loss.
  final int color;

  /// Stroke width in logical pixels.
  final double strokeWidth;

  /// True for the last point of a stroke (pen lifted).
  /// Consecutive points with [isEndOfStroke] == false form one continuous path.
  final bool isEndOfStroke;

  const DrawingPoint({
    required this.x,
    required this.y,
    required this.color,
    required this.strokeWidth,
    this.isEndOfStroke = false,
  });

  /// Convenience getter — reconstructs a Flutter Color from the stored int.
  Color get flutterColor => Color(color);

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'color': color,
        'strokeWidth': strokeWidth,
        'isEndOfStroke': isEndOfStroke,
      };

  factory DrawingPoint.fromJson(Map<String, dynamic> j) => DrawingPoint(
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        color: j['color'] as int? ?? 0xFF000000,
        strokeWidth: (j['strokeWidth'] as num?)?.toDouble() ?? 4.0,
        isEndOfStroke: j['isEndOfStroke'] as bool? ?? false,
      );

  DrawingPoint copyWith({
    double? x,
    double? y,
    int? color,
    double? strokeWidth,
    bool? isEndOfStroke,
  }) =>
      DrawingPoint(
        x: x ?? this.x,
        y: y ?? this.y,
        color: color ?? this.color,
        strokeWidth: strokeWidth ?? this.strokeWidth,
        isEndOfStroke: isEndOfStroke ?? this.isEndOfStroke,
      );

  @override
  String toString() =>
      'DrawingPoint(x: $x, y: $y, sw: $strokeWidth, end: $isEndOfStroke)';
}

// ─────────────────────────────────────────────────────────────────────────────
// DrawingStroke — one continuous pen-down → pen-up gesture
// ─────────────────────────────────────────────────────────────────────────────

class DrawingStroke {
  final String id;
  final List<DrawingPoint> points;
  final int color;
  final double strokeWidth;

  /// True when this stroke was drawn with the eraser tool.
  final bool isEraser;

  DrawingStroke({
    String? id,
    required this.points,
    required this.color,
    required this.strokeWidth,
    this.isEraser = false,
  }) : id = id ?? _uuid.v4();

  Color get flutterColor => Color(color);

  Map<String, dynamic> toJson() => {
        'id': id,
        'points': points.map((p) => p.toJson()).toList(),
        'color': color,
        'strokeWidth': strokeWidth,
        'isEraser': isEraser,
      };

  factory DrawingStroke.fromJson(Map<String, dynamic> j) => DrawingStroke(
        id: j['id'] as String? ?? _uuid.v4(),
        points: (j['points'] as List? ?? [])
            .map((p) => DrawingPoint.fromJson(Map<String, dynamic>.from(p as Map)))
            .toList(),
        color: j['color'] as int? ?? 0xFF000000,
        strokeWidth: (j['strokeWidth'] as num?)?.toDouble() ?? 4.0,
        isEraser: j['isEraser'] as bool? ?? false,
      );

  DrawingStroke copyWith({
    String? id,
    List<DrawingPoint>? points,
    int? color,
    double? strokeWidth,
    bool? isEraser,
  }) =>
      DrawingStroke(
        id: id ?? this.id,
        points: points ?? List.from(this.points),
        color: color ?? this.color,
        strokeWidth: strokeWidth ?? this.strokeWidth,
        isEraser: isEraser ?? this.isEraser,
      );

  @override
  String toString() =>
      'DrawingStroke(id: $id, points: ${points.length}, eraser: $isEraser)';
}

// ─────────────────────────────────────────────────────────────────────────────
// DrawingData — the top-level model stored in Note.drawingData
// ─────────────────────────────────────────────────────────────────────────────

class DrawingData {
  /// All strokes in draw order (index 0 = bottom-most).
  List<DrawingStroke> strokes;

  /// Canvas background color as an ARGB int.
  /// Defaults to transparent so the note's ColorTheme shows through.
  int backgroundColor;

  /// Width the canvas was originally painted at (logical pixels).
  /// Used to scale strokes proportionally when the canvas is a different size.
  double? canvasWidth;

  /// Height the canvas was originally painted at (logical pixels).
  double? canvasHeight;

  DrawingData({
    List<DrawingStroke>? strokes,
    this.backgroundColor = 0x00000000, // transparent
    this.canvasWidth,
    this.canvasHeight,
  }) : strokes = strokes ?? [];

  // ── Convenience helpers ────────────────────────────────────────────────────

  bool get isEmpty => strokes.isEmpty;
  int get strokeCount => strokes.length;

  /// Add a new stroke and return its id.
  String addStroke(DrawingStroke stroke) {
    strokes.add(stroke);
    return stroke.id;
  }

  /// Remove the last stroke (undo).
  DrawingStroke? undoLastStroke() {
    if (strokes.isEmpty) return null;
    return strokes.removeLast();
  }

  /// Remove all strokes (clear canvas).
  void clear() => strokes.clear();

  // ── Serialization ──────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'strokes': strokes.map((s) => s.toJson()).toList(),
        'backgroundColor': backgroundColor,
        if (canvasWidth != null) 'canvasWidth': canvasWidth,
        if (canvasHeight != null) 'canvasHeight': canvasHeight,
      };

  factory DrawingData.fromJson(Map<String, dynamic> j) => DrawingData(
        strokes: (j['strokes'] as List? ?? [])
            .map((s) =>
                DrawingStroke.fromJson(Map<String, dynamic>.from(s as Map)))
            .toList(),
        backgroundColor: j['backgroundColor'] as int? ?? 0x00000000,
        canvasWidth: (j['canvasWidth'] as num?)?.toDouble(),
        canvasHeight: (j['canvasHeight'] as num?)?.toDouble(),
      );

  DrawingData copyWith({
    List<DrawingStroke>? strokes,
    int? backgroundColor,
    double? canvasWidth,
    double? canvasHeight,
  }) =>
      DrawingData(
        strokes: strokes ?? this.strokes.map((s) => s.copyWith()).toList(),
        backgroundColor: backgroundColor ?? this.backgroundColor,
        canvasWidth: canvasWidth ?? this.canvasWidth,
        canvasHeight: canvasHeight ?? this.canvasHeight,
      );

  @override
  String toString() =>
      'DrawingData(strokes: ${strokes.length}, bg: $backgroundColor)';
}
