import 'package:uuid/uuid.dart';
import 'package:hive/hive.dart';

import 'enums.dart';
import 'checklist_item.dart';
import 'itinerary_item.dart';
import 'meal_plan_item.dart';
import 'recipe_data.dart';
import 'drawing_data.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Main Note Model
// ─────────────────────────────────────────────────────────────────────────────

class Note {
  String id, title, content, category;
  DateTime updatedAt;
  bool deleted, pinned;
  NoteType noteType;
  ColorTheme colorTheme;
  List<ChecklistItem> checklistItems;
  List<ItineraryItem> itineraryItems;
  List<MealPlanItem> mealPlanItems;
  RecipeData? recipeData;
  DrawingData? drawingData;
  List<String> imageIds;

  Note({
    required this.id,
    required this.title,
    required this.content,
    required this.updatedAt,
    this.deleted = false,
    this.category = 'General',
    this.pinned = false,
    this.noteType = NoteType.normal,
    this.colorTheme = ColorTheme.default_,
    List<ChecklistItem>? checklistItems,
    List<ItineraryItem>? itineraryItems,
    List<MealPlanItem>? mealPlanItems,
    this.recipeData,
    this.drawingData,
    List<String>? imageIds,
  })  : checklistItems = checklistItems ?? [],
        itineraryItems = itineraryItems ?? [],
        mealPlanItems = mealPlanItems ?? [],
        imageIds = imageIds ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'updatedAt': updatedAt.toIso8601String(),
    'deleted': deleted,
    'category': category,
    'pinned': pinned,
    'noteType': noteType.index,
    'colorTheme': colorTheme.index,
    'checklistItems': checklistItems.map((i) => i.toJson()).toList(),
    'itineraryItems': itineraryItems.map((i) => i.toJson()).toList(),
    'mealPlanItems': mealPlanItems.map((i) => i.toJson()).toList(),
    'recipeData': recipeData?.toJson(),
    'drawingData': drawingData?.toJson(),
    'imageIds': imageIds,
  };

  factory Note.fromJson(Map<String, dynamic> j) => Note(
    id: j['id'] ?? const Uuid().v4(),
    title: j['title'] ?? '',
    content: j['content'] ?? '',
    updatedAt: DateTime.tryParse(j['updatedAt'] ?? '') ?? DateTime.now(),
    deleted: j['deleted'] ?? false,
    category: j['category'] ?? 'General',
    pinned: j['pinned'] ?? false,
    noteType: NoteType.values[j['noteType'] ?? 0],
    colorTheme: ColorTheme.values[j['colorTheme'] ?? 0],
    checklistItems: (j['checklistItems'] as List?)
        ?.map((i) =>
        ChecklistItem.fromJson(Map<String, dynamic>.from(i as Map)))
        .toList() ??
        [],
    itineraryItems: (j['itineraryItems'] as List?)
        ?.map((i) =>
        ItineraryItem.fromJson(Map<String, dynamic>.from(i as Map)))
        .toList() ??
        [],
    mealPlanItems: (j['mealPlanItems'] as List?)
        ?.map((i) =>
        MealPlanItem.fromJson(Map<String, dynamic>.from(i as Map)))
        .toList() ??
        [],
    recipeData: j['recipeData'] != null
        ? RecipeData.fromJson(
        Map<String, dynamic>.from(j['recipeData'] as Map))
        : null,
    drawingData: j['drawingData'] != null
        ? DrawingData.fromJson(
        Map<String, dynamic>.from(j['drawingData'] as Map))
        : null,
    imageIds: (j['imageIds'] as List?)?.cast<String>() ?? [],
  );

  Note copyWith({
    String? id,
    String? title,
    String? content,
    String? category,
    DateTime? updatedAt,
    bool? deleted,
    bool? pinned,
    NoteType? noteType,
    ColorTheme? colorTheme,
    List<ChecklistItem>? checklistItems,
    List<ItineraryItem>? itineraryItems,
    List<MealPlanItem>? mealPlanItems,
    RecipeData? recipeData,
    DrawingData? drawingData,
    List<String>? imageIds,
  }) =>
      Note(
        id: id ?? this.id,
        title: title ?? this.title,
        content: content ?? this.content,
        updatedAt: updatedAt ?? this.updatedAt,
        deleted: deleted ?? this.deleted,
        category: category ?? this.category,
        pinned: pinned ?? this.pinned,
        noteType: noteType ?? this.noteType,
        colorTheme: colorTheme ?? this.colorTheme,
        checklistItems: checklistItems ?? List.from(this.checklistItems),
        itineraryItems: itineraryItems ?? List.from(this.itineraryItems),
        mealPlanItems: mealPlanItems ?? List.from(this.mealPlanItems),
        recipeData: recipeData ?? this.recipeData,
        drawingData: drawingData ?? this.drawingData,
        imageIds: imageIds ?? List.from(this.imageIds),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Hive Adapter for Note serialization
// ─────────────────────────────────────────────────────────────────────────────

class NoteAdapter extends TypeAdapter<Note> {
  @override
  final typeId = 100;

  @override
  Note read(BinaryReader r) =>
      Note.fromJson(Map<String, dynamic>.from(r.read() as Map));

  @override
  void write(BinaryWriter w, Note obj) => w.write(obj.toJson());
}