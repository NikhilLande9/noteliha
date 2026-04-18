// ─────────────────────────────────────────────────────────────────────────────
// Enums - App-wide constants
// ─────────────────────────────────────────────────────────────────────────────

enum NoteType { normal, checklist, itinerary, mealPlan, recipe, drawing }

enum ColorTheme { default_, sunset, orange, forest, lavender, rose }

enum SyncStatus { idle, syncing, error }

enum AppTheme { amber, teal, indigo, rose, slate }

enum DriveAccountState {
  unknown, // Not yet checked (checking in progress)
  newUser, // Signed in, no manifest found on Drive → first-time user
  returningUser // Signed in, manifest found on Drive → existing backup present
}

/// Visual style theme — controls shadows, surfaces, and borders app-wide.
/// To add a new purchasable theme: add a value here and a case in neu_theme.dart.
enum AppVisualTheme {
  material,   // Flat Material 3 — clean, no shadows
  neumorphic, // Soft extruded clay — raised/inset shadows
  clay,       // Rounded pastel blobs — thick soft shadows, puffy shapes
  glass,      // Frosted glass — blur + translucent surfaces
  bento,      // Japanese grid boxes — sharp borders, bold accent corners
}