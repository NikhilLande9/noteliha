// lib/models/recipe_data.dart
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

// ─────────────────────────────────────────────────────────────────────────────
// Ingredient row — one table row: name, quantity, unit
// ─────────────────────────────────────────────────────────────────────────────

class IngredientRow {
  final String id;
  String name;
  String quantity;
  String unit;

  IngredientRow({
    String? id,
    this.name = '',
    this.quantity = '',
    this.unit = '',
  }) : id = id ?? _uuid.v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'quantity': quantity,
        'unit': unit,
      };

  factory IngredientRow.fromJson(Map<String, dynamic> j) => IngredientRow(
        id: j['id'] as String? ?? _uuid.v4(),
        name: j['name'] as String? ?? '',
        quantity: j['quantity'] as String? ?? '',
        unit: j['unit'] as String? ?? '',
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Recipe Step — one numbered instruction step
// ─────────────────────────────────────────────────────────────────────────────

class RecipeStep {
  final String id;
  String text;

  RecipeStep({String? id, this.text = ''}) : id = id ?? _uuid.v4();

  Map<String, dynamic> toJson() => {'id': id, 'text': text};

  factory RecipeStep.fromJson(Map<String, dynamic> j) => RecipeStep(
        id: j['id'] as String? ?? _uuid.v4(),
        text: j['text'] as String? ?? '',
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// RecipeData
// ─────────────────────────────────────────────────────────────────────────────

class RecipeData {
  String prepTime;
  String cookTime;
  String servings;

  // Structured ingredients table
  List<IngredientRow> ingredientRows;

  // Structured step-by-step instructions
  List<RecipeStep> steps;

  // Legacy flat strings — kept for backwards-compat migration only
  String ingredients;
  String instructions;

  RecipeData({
    this.prepTime = '',
    this.cookTime = '',
    this.servings = '',
    List<IngredientRow>? ingredientRows,
    List<RecipeStep>? steps,
    this.ingredients = '',
    this.instructions = '',
  })  : ingredientRows = ingredientRows ?? [IngredientRow()],
        steps = steps ?? [RecipeStep()];

  Map<String, dynamic> toJson() => {
        'prepTime': prepTime,
        'cookTime': cookTime,
        'servings': servings,
        'ingredientRows': ingredientRows.map((r) => r.toJson()).toList(),
        'steps': steps.map((s) => s.toJson()).toList(),
        // Write legacy fields so old builds can still read them
        'ingredients': ingredients,
        'instructions': instructions,
      };

  factory RecipeData.fromJson(Map<String, dynamic> j) {
    // Migrate legacy flat strings into structured rows/steps on first load
    List<IngredientRow> rows;
    if (j['ingredientRows'] != null) {
      rows = (j['ingredientRows'] as List)
          .map((e) => IngredientRow.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } else {
      // Legacy migration: one row per line of the old ingredients string
      final legacy = j['ingredients'] as String? ?? '';
      rows = legacy.isEmpty
          ? [IngredientRow()]
          : legacy
              .split('\n')
              .where((l) => l.trim().isNotEmpty)
              .map((l) => IngredientRow(name: l.trim()))
              .toList();
    }

    List<RecipeStep> steps;
    if (j['steps'] != null) {
      steps = (j['steps'] as List)
          .map((e) => RecipeStep.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } else {
      // Legacy migration: one step per line
      final legacy = j['instructions'] as String? ?? '';
      steps = legacy.isEmpty
          ? [RecipeStep()]
          : legacy
              .split('\n')
              .where((l) => l.trim().isNotEmpty)
              .map((l) => RecipeStep(text: l.trim()))
              .toList();
    }

    return RecipeData(
      prepTime: j['prepTime'] ?? '',
      cookTime: j['cookTime'] ?? '',
      servings: j['servings'] ?? '',
      ingredientRows: rows.isEmpty ? [IngredientRow()] : rows,
      steps: steps.isEmpty ? [RecipeStep()] : steps,
      ingredients: j['ingredients'] ?? '',
      instructions: j['instructions'] ?? '',
    );
  }

  RecipeData copyWith({
    String? prepTime,
    String? cookTime,
    String? servings,
    List<IngredientRow>? ingredientRows,
    List<RecipeStep>? steps,
  }) =>
      RecipeData(
        prepTime: prepTime ?? this.prepTime,
        cookTime: cookTime ?? this.cookTime,
        servings: servings ?? this.servings,
        ingredientRows: ingredientRows ?? List.from(this.ingredientRows),
        steps: steps ?? List.from(this.steps),
        ingredients: ingredients,
        instructions: instructions,
      );

  @override
  String toString() =>
      'RecipeData(servings: $servings, ingredients: ${ingredientRows.length} rows, steps: ${steps.length})';
}
