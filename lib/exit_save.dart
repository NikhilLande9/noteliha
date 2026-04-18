// ─────────────────────────────────────────────────────────────────────────────
// Exit Warning / Exit Save
// ─────────────────────────────────────────────────────────────────────────────
//
// WHAT IT DOES
// ─────────────
// When the user taps the back button (or swipes) without saving, the editor
// detects unsaved changes and shows a bottom-sheet with three choices:
//
//   [Save & Exit]   [Discard]   [Keep Editing]
//
// "Save & Exit" auto-saves silently and pops.
// "Discard"     pops without saving (existing note unchanged; new note abandoned).
// "Keep Editing" dismisses the sheet so the user can continue.
//
// HOW TO INTEGRATE
// ─────────────────
// Replace the existing `return Scaffold(…)` in NoteEditorScreen.build() with
// the PopScope-wrapped version shown below. The key change is wrapping the
// Scaffold in a PopScope with canPop: false and onPopInvokedWithResult.
//
// Also replace the back-button NeuIconButton's onTap handler from
//   onTap: () => Navigator.pop(context)
// to:
//   onTap: _handleBackNavigation
//
// PASTE THESE INTO _NoteEditorScreenState
// ─────────────────────────────────────────

// ignore_for_file: unused_element

import 'dart:async';

import 'package:flutter/material.dart';
import '../models.dart';
import '../neu_theme.dart';

// ─── Mixin — add to _NoteEditorScreenState ───────────────────────────────────
//
// Usage:
//   class _NoteEditorScreenState extends State<NoteEditorScreen>
//       with SingleTickerProviderStateMixin, ExitSaveMixin {
//
// Then call _handleBackNavigation() from the back-button onTap and from
// the PopScope.onPopInvokedWithResult callback.

mixin ExitSaveMixin<T extends StatefulWidget> on State<T> {
  // Subclass must implement these:
  bool hasUnsavedChanges();
  void performSave(); // silent save, no navigation
  Note get editingNote; // the in-progress Note object

  bool _exitSheetOpen = false;

  /// Call this from the AppBar back button AND from PopScope.onPopInvokedWithResult.
  Future<bool> handleBackNavigation() async {
    if (!hasUnsavedChanges()) {
      Navigator.of(context).pop();
      return true;
    }
    await _showExitSheet();
    return false; // PopScope must not auto-pop; we handle it manually.
  }

  Future<void> _showExitSheet() async {
    if (_exitSheetOpen) return;
    _exitSheetOpen = true;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = Neu.base(isDark);
    final primary = Neu.textPrimary(isDark);
    final sub = Neu.textSecondary(isDark);
    final accent = Theme.of(context).colorScheme.primary;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: base,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                  color: sub.withAlpha(80),
                  borderRadius: BorderRadius.circular(2)),
            ),
            Icon(Icons.edit_note_rounded, size: 36, color: accent),
            const SizedBox(height: 12),
            Text('Unsaved changes',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: primary)),
            const SizedBox(height: 8),
            Text('What would you like to do?',
                style: TextStyle(fontSize: 14, color: sub)),
            const SizedBox(height: 28),

            // Save & Exit
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop(); // close sheet
                  performSave();
                  Navigator.of(context).pop(); // exit editor
                },
                icon: const Icon(Icons.save_rounded, size: 18),
                label: const Text('Save & Exit'),
                style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14))),
              ),
            ),
            const SizedBox(height: 10),

            // Discard
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop(); // close sheet
                  Navigator.of(context).pop(); // exit without saving
                },
                icon: const Icon(Icons.delete_outline_rounded,
                    size: 18, color: Colors.redAccent),
                label: const Text('Discard changes'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14))),
              ),
            ),
            const SizedBox(height: 10),

            // Keep Editing
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: TextButton.styleFrom(
                    foregroundColor: sub,
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('Keep Editing'),
              ),
            ),
          ],
        ),
      ),
    );

    _exitSheetOpen = false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// INTEGRATION SNIPPET — copy into _NoteEditorScreenState
// ─────────────────────────────────────────────────────────────────────────────

// ┌─────────────────────────────────────────────────────────────────────────┐
// │  ADD to class declaration:                                              │
// │    with SingleTickerProviderStateMixin, ExitSaveMixin                   │
// │                                                                         │
// │  ADD these overrides inside _NoteEditorScreenState:                     │
// └─────────────────────────────────────────────────────────────────────────┘

// @override
// bool hasUnsavedChanges() {
//   // True when there is content AND it differs from the stored note.
//   final savedTitle   = widget.note?.title   ?? '';
//   final savedContent = widget.note?.content ?? '';
//   final currentTitle   = _titleCtrl.text.trim();
//   final currentContent = _richFieldKey.currentState?.serialisedContent
//       ?? _contentCtrl.text.trim();
//   return _hasContent() &&
//       (currentTitle != savedTitle || currentContent != savedContent);
// }

// @override
// void performSave() {
//   _editing.title = _titleCtrl.text.trim();
//   final richState = _richFieldKey.currentState;
//   _editing.content = richState != null
//       ? richState.serialisedContent
//       : _contentCtrl.text.trim();
//   Provider.of<NotesProvider>(context, listen: false).updateNote(_editing);
// }

// @override
// Note get editingNote => _editing;

// ┌─────────────────────────────────────────────────────────────────────────┐
// │  REPLACE the Scaffold return in build() with:                           │
// └─────────────────────────────────────────────────────────────────────────┘

// return PopScope(
//   canPop: false,
//   onPopInvokedWithResult: (didPop, _) async {
//     if (!didPop) await handleBackNavigation();
//   },
//   child: Scaffold( /* existing Scaffold content unchanged */ ),
// );

// ┌─────────────────────────────────────────────────────────────────────────┐
// │  REPLACE the back-button NeuIconButton's onTap:                         │
// └─────────────────────────────────────────────────────────────────────────┘

// onTap: () => handleBackNavigation(),

// ─────────────────────────────────────────────────────────────────────────────
// Auto-save Timer (optional enhancement)
// ─────────────────────────────────────────────────────────────────────────────
// Automatically saves the note every 30 seconds while it is open.
// No user interaction required. Add this mixin alongside ExitSaveMixin.

mixin AutoSaveMixin<T extends StatefulWidget> on State<T> {
  static const _kAutoSaveInterval = Duration(seconds: 30);
  Timer? _autoSaveTimer;

  void startAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer.periodic(_kAutoSaveInterval, (_) => _doAutoSave());
  }

  void stopAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
  }

  void _doAutoSave() {
    if (!mounted) return;
    // Subclass must implement performSave() (via ExitSaveMixin)
    if (this is ExitSaveMixin) {
      (this as ExitSaveMixin).performSave();
      debugPrint('[AutoSave] Note saved.');
    }
  }

  @override
  void dispose() {
    stopAutoSave();
    super.dispose();
  }
}