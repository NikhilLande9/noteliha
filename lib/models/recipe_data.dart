// lib/models/recipe_data.dart

// ─────────────────────────────────────────────────────────────────────────────
// Recipe Data - Recipe details
// ─────────────────────────────────────────────────────────────────────────────

class RecipeData {
  String ingredients;
  String instructions;
  String prepTime;
  String cookTime;
  String servings;

  RecipeData({
    this.ingredients = '',
    this.instructions = '',
    this.prepTime = '',
    this.cookTime = '',
    this.servings = '',
  });

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() => {
        'ingredients': ingredients,
        'instructions': instructions,
        'prepTime': prepTime,
        'cookTime': cookTime,
        'servings': servings,
      };

  /// Create from JSON
  factory RecipeData.fromJson(Map<String, dynamic> json) => RecipeData(
        ingredients: json['ingredients'] ?? '',
        instructions: json['instructions'] ?? '',
        prepTime: json['prepTime'] ?? '',
        cookTime: json['cookTime'] ?? '',
        servings: json['servings'] ?? '',
      );

  /// Copy with modifications
  RecipeData copyWith({
    String? ingredients,
    String? instructions,
    String? prepTime,
    String? cookTime,
    String? servings,
  }) =>
      RecipeData(
        ingredients: ingredients ?? this.ingredients,
        instructions: instructions ?? this.instructions,
        prepTime: prepTime ?? this.prepTime,
        cookTime: cookTime ?? this.cookTime,
        servings: servings ?? this.servings,
      );

  @override
  String toString() =>
      'RecipeData(servings: $servings, prepTime: $prepTime, cookTime: $cookTime)';
}
