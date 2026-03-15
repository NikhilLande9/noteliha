// lib/models/checklist_item.dart
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

// ─────────────────────────────────────────────────────────────────────────────
// Checklist Item - Individual todo/task item
// ─────────────────────────────────────────────────────────────────────────────

class ChecklistItem {
  final String id;
  String text;
  bool checked;

  /// Nesting depth (0 = top-level, 1 = sub-task, etc.)
  int indent;

  /// When this item was first created — useful for stable ordering
  final DateTime createdAt;

  ChecklistItem({
    String? id,
    required this.text,
    this.checked = false,
    this.indent = 0,
    DateTime? createdAt,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now();

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'checked': checked,
    'indent': indent,
    'createdAt': createdAt.toIso8601String(),
  };

  /// Create from JSON — gracefully handles old data without new fields
  factory ChecklistItem.fromJson(Map<String, dynamic> json) => ChecklistItem(
    id: json['id'] as String? ?? _uuid.v4(),
    text: json['text'] as String? ?? '',
    checked: json['checked'] as bool? ?? false,
    indent: json['indent'] as int? ?? 0,
    createdAt: json['createdAt'] != null
        ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
        : DateTime.now(),
  );

  /// Copy with selective field overrides
  ChecklistItem copyWith({
    String? id,
    String? text,
    bool? checked,
    int? indent,
    DateTime? createdAt,
  }) =>
      ChecklistItem(
        id: id ?? this.id,
        text: text ?? this.text,
        checked: checked ?? this.checked,
        indent: indent ?? this.indent,
        createdAt: createdAt ?? this.createdAt,
      );

  /// Identity is based on [id] alone
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is ChecklistItem &&
              runtimeType == other.runtimeType &&
              id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'ChecklistItem(id: $id, text: "$text", checked: $checked, indent: $indent)';
}