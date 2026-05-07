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
import 'language.dart';

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
    final accent = Theme.of(context).colorScheme.primary;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _ExitSaveSheet(
        isDark: isDark,
        accent: accent,
        onSaveExit: () {
          Navigator.of(ctx).pop();
          performSave();
          Navigator.of(context).pop();
        },
        onDiscard: () {
          Navigator.of(ctx).pop();
          Navigator.of(context).pop();
        },
        onKeepEditing: () => Navigator.of(ctx).pop(),
      ),
    );

    _exitSheetOpen = false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ExitSaveSheet — the bottom-sheet widget, styled with NeuContainer /
// NeuPressable so it inherits the active visual theme automatically.
// ─────────────────────────────────────────────────────────────────────────────

class _ExitSaveSheet extends StatelessWidget {
  final bool isDark;
  final Color accent;
  final VoidCallback onSaveExit;
  final VoidCallback onDiscard;
  final VoidCallback onKeepEditing;

  const _ExitSaveSheet({
    required this.isDark,
    required this.accent,
    required this.onSaveExit,
    required this.onDiscard,
    required this.onKeepEditing,
  });

  @override
  Widget build(BuildContext context) {
    final base = Neu.base(isDark);
    final primary = Neu.textPrimary(isDark);
    final sub = Neu.textSecondary(isDark);
    final ter = Neu.textTertiary(isDark);

    return Container(
      decoration: BoxDecoration(
        color: base,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: Neu.raised(isDark),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        MediaQuery.of(context).padding.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Drag handle ────────────────────────────────────────────────────
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: ter.withAlpha(80),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── Icon badge ─────────────────────────────────────────────────────
          NeuContainer(
            isDark: isDark,
            radius: 18,
            padding: const EdgeInsets.all(14),
            child: Icon(Icons.edit_note_rounded, size: 28, color: accent),
          ),
          const SizedBox(height: 16),

          // ── Title ──────────────────────────────────────────────────────────
          Text(
            AppTranslations.translate('unsaved_changes'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: primary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            AppTranslations.translate('what_would_you_like'),
            style: TextStyle(fontSize: 13, color: sub),
          ),
          const SizedBox(height: 28),

          // ── Save & Exit ────────────────────────────────────────────────────
          NeuPressable(
            isDark: isDark,
            radius: 14,
            onTap: onSaveExit,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            child: Row(
              children: [
                NeuContainer(
                  isDark: isDark,
                  radius: 10,
                  padding: const EdgeInsets.all(8),
                  child: Icon(Icons.save_rounded, size: 18, color: accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppTranslations.translate('save_and_exit'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AppTranslations.translate('save_and_exit_desc'),
                        style: TextStyle(fontSize: 11, color: sub),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 18, color: ter),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // ── Discard ────────────────────────────────────────────────────────
          NeuPressable(
            isDark: isDark,
            radius: 14,
            onTap: onDiscard,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            child: Row(
              children: [
                NeuContainer(
                  isDark: isDark,
                  radius: 10,
                  padding: const EdgeInsets.all(8),
                  child: const Icon(Icons.delete_outline_rounded,
                      size: 18, color: Colors.redAccent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppTranslations.translate('discard_changes'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.redAccent,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AppTranslations.translate('discard_changes_desc'),
                        style: TextStyle(fontSize: 11, color: sub),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 18, color: ter),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // ── Keep Editing ───────────────────────────────────────────────────
          NeuPressable(
            isDark: isDark,
            radius: 14,
            onTap: onKeepEditing,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            child: Center(
              child: Text(
                AppTranslations.translate('keep_editing'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: sub,
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
