// lib/note_editor_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';

import 'models.dart';
import 'theme_helper.dart';
import 'neu_theme.dart';
import 'notes_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Note Editor Screen
// ─────────────────────────────────────────────────────────────────────────────

class NoteEditorScreen extends StatefulWidget {
  final Note? note;
  final NoteType noteType;

  const NoteEditorScreen(
      {super.key, this.note, this.noteType = NoteType.normal});

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen>
    with SingleTickerProviderStateMixin {
  late Note _editing;
  late TextEditingController _titleCtrl;
  late TextEditingController _contentCtrl;
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;

  // ── Saving indicator ───────────────────────────────────────────────────────
  bool _showSaved = false;

  // ── Undo / Redo stack ──────────────────────────────────────────────────────
  final List<_NoteSnapshot> _undoStack = [];
  final List<_NoteSnapshot> _redoStack = [];
  Timer? _undoDebounce;
  static const _kUndoMaxDepth = 50;

  bool get _canUndo => _undoStack.isNotEmpty;
  bool get _canRedo => _redoStack.isNotEmpty;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  final Map<String, FocusNode> _checklistFocusNodes = {};

  // ── Checklist options ──────────────────────────────────────────────────────
  bool _checklistCompact = false;

  // Key to reach _RichTextFieldState.applyFormat() directly
  final _richFieldKey = GlobalKey<_RichTextFieldState>();

  static const _categories = ['General', 'Work', 'Personal', 'Ideas'];

  @override
  void initState() {
    super.initState();
    _editing = widget.note != null
        ? widget.note!.copyWith(
      // Deep-copy each ChecklistItem so the editor works on independent
      // objects. A shallow List.from() keeps the same item references,
      // meaning direct field mutations (item.checked = v) write straight
      // through to the Hive-stored note without an explicit save.
      checklistItems: widget.note!.checklistItems
          .map((i) => i.copyWith()).toList(),
      itineraryItems: List.from(widget.note!.itineraryItems),
      mealPlanItems:  List.from(widget.note!.mealPlanItems),
      imageIds:       List.from(widget.note!.imageIds),
    )
        : Note(
      id: const Uuid().v4(),
      title: '',
      content: '',
      updatedAt: DateTime.now(),
      noteType: widget.noteType,
      colorTheme: _defaultColorForTheme(),
    );

    _titleCtrl = TextEditingController(text: _editing.title);
    _contentCtrl = TextEditingController(text: _editing.content);
    _titleCtrl.addListener(_pushSnapshot);
    _contentCtrl.addListener(_pushSnapshot);

    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  // ── Push a snapshot (debounced so rapid typing merges into one entry) ──────
  void _pushSnapshot() {
    _undoDebounce?.cancel();
    _undoDebounce = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      final snap = _NoteSnapshot(
        title:   _titleCtrl.text,
        content: _contentCtrl.text,
      );
      if (_undoStack.isNotEmpty && _undoStack.last == snap) return;
      _undoStack.add(snap);
      if (_undoStack.length > _kUndoMaxDepth) _undoStack.removeAt(0);
      _redoStack.clear();
      if (mounted) setState(() {});
    });
  }

  void _undo() {
    if (!_canUndo) return;
    _undoDebounce?.cancel();
    _redoStack.add(_NoteSnapshot(
      title:   _titleCtrl.text,
      content: _contentCtrl.text,
    ));
    _applySnapshot(_undoStack.removeLast());
  }

  void _redo() {
    if (!_canRedo) return;
    _undoDebounce?.cancel();
    _undoStack.add(_NoteSnapshot(
      title:   _titleCtrl.text,
      content: _contentCtrl.text,
    ));
    _applySnapshot(_redoStack.removeLast());
  }

  void _applySnapshot(_NoteSnapshot snap) {
    _titleCtrl.removeListener(_pushSnapshot);
    _contentCtrl.removeListener(_pushSnapshot);
    _titleCtrl.value   = TextEditingValue(text: snap.title);
    _contentCtrl.value = TextEditingValue(text: snap.content);
    _titleCtrl.addListener(_pushSnapshot);
    _contentCtrl.addListener(_pushSnapshot);
    setState(() {});
  }

  ColorTheme _defaultColorForTheme() {
    final appTheme =
        Provider.of<AppSettingsProvider>(context, listen: false).appTheme;
    return switch (appTheme) {
      AppTheme.amber  => ColorTheme.sunset,
      AppTheme.teal   => ColorTheme.default_,
      AppTheme.indigo => ColorTheme.lavender,
      AppTheme.rose   => ColorTheme.rose,
      AppTheme.slate  => ColorTheme.forest,
    };
  }

  @override
  void dispose() {
    _undoDebounce?.cancel();
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _fadeCtrl.dispose();
    for (final fn in _checklistFocusNodes.values) {
      fn.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      setState(() => _isLoading = true);
      final image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null && mounted) {
        final prov = Provider.of<NotesProvider>(context, listen: false);
        final imageId = await prov.saveImage(File(image.path));
        setState(() => _editing.imageIds.add(imageId));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not pick image: $e'),
            behavior: SnackBarBehavior.floating,
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(10))),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Validation helper ──────────────────────────────────────────────────────
  bool _hasContent() {
    final title   = _titleCtrl.text.trim();
    final content = _RichContentCodec.plainText(_contentCtrl.text).trim();
    return title.isNotEmpty ||
        content.isNotEmpty ||
        _editing.checklistItems.any((i) => i.text.isNotEmpty) ||
        _editing.itineraryItems.any((i) => i.location.isNotEmpty) ||
        _editing.mealPlanItems.isNotEmpty ||
        _editing.imageIds.isNotEmpty ||
        (_editing.recipeData != null &&
            (_editing.recipeData!.ingredientRows
                .any((r) => r.name.isNotEmpty) ||
                _editing.recipeData!.steps.any((s) => s.text.isNotEmpty)));
  }

  void _save() {
    _editing.title = _titleCtrl.text.trim();

    // Serialise plain text + bold/italic ranges so formatting survives save.
    // Falls back to plain text for non-normal note types.
    final richState = _richFieldKey.currentState;
    _editing.content = richState != null
        ? richState.serialisedContent
        : _contentCtrl.text.trim();

    if (!_hasContent()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nothing to save — add some content first'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(10))),
        ),
      );
      return;
    }

    Provider.of<NotesProvider>(context, listen: false).updateNote(_editing);

    setState(() => _showSaved = true);
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) {
        setState(() => _showSaved = false);
        Navigator.pop(context);
      }
    });
  }

  // ── Note type display label ────────────────────────────────────────────────
  String _noteTypeLabel(NoteType type) => switch (type) {
    NoteType.normal    => 'Note',
    NoteType.checklist => 'Checklist',
    NoteType.itinerary => 'Itinerary',
    NoteType.mealPlan  => 'Meal Plan',
    NoteType.recipe    => 'Recipe',
  };

  @override
  Widget build(BuildContext context) {
    final isDark      = Theme.of(context).brightness == Brightness.dark;
    final cardBg      = Neu.cardTint(_editing.colorTheme, isDark);
    final accent      = Neu.accentFromTheme(_editing.colorTheme);
    final textPrimary = Neu.textPrimary(isDark);
    final textSub     = Neu.textSecondary(isDark);

    final editorTitle =
        '${widget.note == null ? 'New' : 'Edit'} ${_noteTypeLabel(_editing.noteType)}';

    return Scaffold(
      backgroundColor: cardBg,
      appBar: AppBar(
        backgroundColor: cardBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: NeuIconButton(
          isDark: isDark,
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: textSub),
          onTap: () => Navigator.pop(context),
        ),
        leadingWidth: 56,
        title: Text(
          editorTitle,
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: textPrimary),
        ),
        actions: [
          _UndoRedoButtons(
            isDark: isDark,
            canUndo: _canUndo,
            canRedo: _canRedo,
            onUndo: _undo,
            onRedo: _redo,
          ),
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: accent)),
            ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _showSaved
                ? Padding(
              key: const ValueKey('saved'),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded,
                      size: 16, color: accent),
                  const SizedBox(width: 4),
                  Text('Saved',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: accent)),
                ],
              ),
            )
                : _NeuSaveButton(
                key: const ValueKey('save'),
                isDark: isDark,
                accent: accent,
                onTap: _save),
          ),
          _MoreMenu(
            editing: _editing,
            isDark: isDark,
            checklistCompact: _checklistCompact,
            onPinToggle: () =>
                setState(() => _editing.pinned = !_editing.pinned),
            onAddImage: _pickImage,
            onColorChanged: (t) => setState(() => _editing.colorTheme = t),
            onDelete: widget.note != null ? _showDeleteConfirmation : null,
            onToggleCompact: _editing.noteType == NoteType.checklist
                ? () =>
                setState(() => _checklistCompact = !_checklistCompact)
                : null,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(isDark, accent, textPrimary, textSub),
              if (_editing.imageIds.isNotEmpty) _buildImageStrip(isDark),
              Divider(
                  height: 1,
                  thickness: 1,
                  indent: 16,
                  endIndent: 16,
                  color: Neu.textSecondary(isDark).withAlpha(40)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildBody(isDark),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
      bool isDark, Color accent, Color textPrimary, Color textSub) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 3,
            width: 40,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(2),
              boxShadow: [
                BoxShadow(
                    color: accent.withAlpha(80),
                    blurRadius: 6,
                    spreadRadius: 0),
              ],
            ),
          ),
          TextField(
            controller: _titleCtrl,
            decoration: InputDecoration(
              hintText: 'Title',
              border: InputBorder.none,
              hintStyle: TextStyle(
                  color: Neu.textTertiary(isDark),
                  fontSize: 26,
                  fontWeight: FontWeight.w700),
            ),
            style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: textPrimary),
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _categories.map((cat) {
                      final selected = _editing.category == cat;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _editing.category = cat),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: Neu.base(isDark),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: selected
                                  ? Neu.inset(isDark)
                                  : Neu.raisedSm(isDark),
                            ),
                            child: Text(
                              cat,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                color: selected
                                    ? accent
                                    : Neu.textSecondary(isDark),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _editing.pinned
                    ? Tooltip(
                  message: 'Pinned',
                  child: Icon(Icons.push_pin_rounded,
                      size: 18, color: accent),
                )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImageStrip(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SizedBox(
        height: 110,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: _editing.imageIds.length,
          itemBuilder: (context, index) {
            final imgId = _editing.imageIds[index];
            final prov  = Provider.of<NotesProvider>(context);
            final b64   = prov.getImage(imgId);

            return Container(
              margin: const EdgeInsets.only(right: 8),
              child: NeuContainer(
                isDark: isDark,
                radius: 12,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      b64 == null
                          ? SizedBox(
                        width: 100,
                        height: 110,
                        child: Icon(Icons.broken_image_outlined,
                            color: Neu.textSecondary(isDark)),
                      )
                          : Image.memory(
                        base64Decode(b64),
                        width: 100,
                        height: 110,
                        fit: BoxFit.cover,
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: GestureDetector(
                          onTap: () async {
                            final imageId = _editing.imageIds[index];
                            setState(() =>
                                _editing.imageIds.removeAt(index));
                            final p = Provider.of<NotesProvider>(context,
                                listen: false);
                            final referencedByOther = p.notes.any((n) =>
                            n.id != _editing.id &&
                                n.imageIds.contains(imageId));
                            if (!referencedByOther) {
                              await p.deleteImage(imageId);
                            }
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: Neu.base(isDark).withAlpha(200),
                              shape: BoxShape.circle,
                              boxShadow: Neu.raisedSm(isDark),
                            ),
                            padding: const EdgeInsets.all(4),
                            child: Icon(Icons.close_rounded,
                                size: 13,
                                color: Neu.textSecondary(isDark)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showDeleteConfirmation() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base   = Neu.base(isDark);

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: base,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(20),
            boxShadow: Neu.raised(isDark),
          ),
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Delete note?',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                      color: Neu.textPrimary(isDark))),
              const SizedBox(height: 8),
              Text('This note will be moved to the recycle bin.',
                  style: TextStyle(
                      fontSize: 14,
                      color: Neu.textSecondary(isDark))),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _NeuDialogButton(
                    label: 'Cancel',
                    isDark: isDark,
                    onTap: () => Navigator.pop(ctx),
                  ),
                  const SizedBox(width: 10),
                  _NeuDialogButton(
                    label: 'Delete',
                    isDark: isDark,
                    isDestructive: true,
                    onTap: () {
                      Provider.of<NotesProvider>(context, listen: false)
                          .softDelete(_editing.id);
                      Navigator.pop(ctx);
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(bool isDark) => switch (_editing.noteType) {
    NoteType.normal    => _buildNormal(isDark),
    NoteType.checklist => _buildChecklist(isDark),
    NoteType.itinerary => _buildItinerary(),
    NoteType.mealPlan  => _buildMealPlan(),
    NoteType.recipe    => _buildRecipe(isDark),
  };

  // ── Normal note with rich text toolbar ────────────────────────────────────
  Widget _buildNormal(bool isDark) {
    final accent    = Theme.of(context).colorScheme.primary;
    final textColor = Neu.textPrimary(isDark);
    final active    = _richFieldKey.currentState?.activeFormats ?? <_FormatType>{};

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              _FormatIconButton(
                icon: Icons.format_list_bulleted_rounded,
                isActive: active.contains(_FormatType.bullet),
                isDark: isDark,
                accent: accent,
                tooltip: 'Bullet list',
                onTap: () => _applyFormat(_FormatType.bullet),
              ),
              const SizedBox(width: 6),
              _FormatIconButton(
                icon: Icons.format_list_numbered_rounded,
                isActive: active.contains(_FormatType.numbered),
                isDark: isDark,
                accent: accent,
                tooltip: 'Numbered list',
                onTap: () => _applyFormat(_FormatType.numbered),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  'Select text for B / I',
                  style: TextStyle(
                    fontSize: 11,
                    color: Neu.textTertiary(isDark),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _RichTextField(
            key: _richFieldKey,
            isDark: isDark,
            controller: _contentCtrl,
            baseColor: textColor,
            onSelectionChanged: () => setState(() {}),
            onApplyFormat: _applyFormat,
          ),
        ),
      ],
    );
  }

  void _applyFormat(_FormatType type) {
    _richFieldKey.currentState?.applyFormat(type);
  }

  FocusNode _focusForItem(String id) =>
      _checklistFocusNodes.putIfAbsent(id, () => FocusNode());

  void _addChecklistItemAfter(int index) {
    final newItem = ChecklistItem(text: '');
    setState(() => _editing.checklistItems.insert(index + 1, newItem));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusForItem(newItem.id).requestFocus();
    });
  }

  Widget _buildChecklist(bool isDark) {
    final accent   = Theme.of(context).colorScheme.primary;
    final total    = _editing.checklistItems.length;
    final done     = _editing.checklistItems.where((i) => i.checked).length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Stepped progress bar ───────────────────────────────────────
              _SteppedProgressBar(
                total: total,
                done: done,
                isDark: isDark,
                accent: accent,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _ChecklistToolbarButton(
                    label: 'A→Z',
                    icon: Icons.sort_by_alpha_rounded,
                    isDark: isDark,
                    accent: accent,
                    onTap: () => setState(() {
                      _editing.checklistItems
                          .sort((a, b) => a.text.compareTo(b.text));
                    }),
                  ),
                  const SizedBox(width: 8),
                  _ChecklistToolbarButton(
                    label: _checklistCompact ? 'Expand' : 'Compact',
                    icon: _checklistCompact
                        ? Icons.unfold_more_rounded
                        : Icons.unfold_less_rounded,
                    isDark: isDark,
                    accent: accent,
                    onTap: () => setState(
                            () => _checklistCompact = !_checklistCompact),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 4),
            itemCount: _editing.checklistItems.length,
            itemBuilder: (_, i) {
              final item = _editing.checklistItems[i];
              return _ChecklistItemTile(
                key: ValueKey(item.id),
                item: item,
                isDark: isDark,
                compact: _checklistCompact,
                focusNode: _focusForItem(item.id),
                onChanged: (v) => setState(() {
                  // Replace with copyWith so the original Hive object
                  // is never mutated before an explicit save.
                  _editing.checklistItems[i] =
                      _editing.checklistItems[i].copyWith(checked: v);
                }),
                onDelete: () {
                  final focusIndex = (i - 1)
                      .clamp(0, _editing.checklistItems.length - 1);
                  final prevId = _editing.checklistItems.length > 1
                      ? _editing.checklistItems[focusIndex].id
                      : null;
                  setState(() => _editing.checklistItems.removeAt(i));
                  if (prevId != null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _focusForItem(prevId).requestFocus();
                    });
                  }
                },
                onTextChanged: (text) => setState(() {
                  _editing.checklistItems[i] =
                      _editing.checklistItems[i].copyWith(text: text);
                }),
                onSubmitted: () => _addChecklistItemAfter(i),
              );
            },
          ),
        ),
        _NeuAddRowButton(
          label: 'Add item',
          isDark: isDark,
          onTap: () {
            final newItem = ChecklistItem(text: '');
            setState(() => _editing.checklistItems.add(newItem));
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _focusForItem(newItem.id).requestFocus();
            });
          },
        ),
      ],
    );
  }

  Widget _buildItinerary() => ModernItineraryBuilder(
    items: _editing.itineraryItems,
    onDelete: (i) =>
        setState(() => _editing.itineraryItems.removeAt(i)),
    onAddItem: () => setState(() => _editing.itineraryItems
        .add(ItineraryItem(id: const Uuid().v4()))),
    onChanged: () => setState(() {}),
  );

  Widget _buildMealPlan() => ModernMealPlanBuilder(
    items: _editing.mealPlanItems,
    onDelete: (i) =>
        setState(() => _editing.mealPlanItems.removeAt(i)),
    onAddItem: () => setState(() =>
        _editing.mealPlanItems.add(MealPlanItem(id: const Uuid().v4()))),
    onChanged: () => setState(() {}),
  );

  Widget _buildRecipe(bool isDark) {
    _editing.recipeData ??= RecipeData();
    return _RecipeCard(
        data: _editing.recipeData!,
        isDark: isDark,
        onChanged: () => setState(() {}));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Undo / Redo snapshot
// ─────────────────────────────────────────────────────────────────────────────

class _NoteSnapshot {
  final String title;
  final String content;

  const _NoteSnapshot({required this.title, required this.content});

  @override
  bool operator ==(Object other) =>
      other is _NoteSnapshot &&
          title   == other.title &&
          content == other.content;

  @override
  int get hashCode => Object.hash(title, content);
}

// ─────────────────────────────────────────────────────────────────────────────
// Undo / Redo button pair in AppBar
// ─────────────────────────────────────────────────────────────────────────────

class _UndoRedoButtons extends StatelessWidget {
  final bool isDark;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  const _UndoRedoButtons({
    required this.isDark,
    required this.canUndo,
    required this.canRedo,
    required this.onUndo,
    required this.onRedo,
  });

  @override
  Widget build(BuildContext context) {
    final active   = Neu.textSecondary(isDark);
    final inactive = Neu.textTertiary(isDark).withAlpha(80);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _UndoBtn(
          isDark: isDark,
          icon: Icons.undo_rounded,
          enabled: canUndo,
          activeColor: active,
          inactiveColor: inactive,
          onTap: canUndo ? onUndo : null,
        ),
        const SizedBox(width: 2),
        _UndoBtn(
          isDark: isDark,
          icon: Icons.redo_rounded,
          enabled: canRedo,
          activeColor: active,
          inactiveColor: inactive,
          onTap: canRedo ? onRedo : null,
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

class _UndoBtn extends StatefulWidget {
  final bool isDark;
  final IconData icon;
  final bool enabled;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback? onTap;

  const _UndoBtn({
    required this.isDark,
    required this.icon,
    required this.enabled,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
  });

  @override
  State<_UndoBtn> createState() => _UndoBtnState();
}

class _UndoBtnState extends State<_UndoBtn> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:
      widget.enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: widget.enabled
          ? (_) {
        setState(() => _pressed = false);
        widget.onTap?.call();
      }
          : null,
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Neu.base(widget.isDark),
          borderRadius: BorderRadius.circular(9),
          boxShadow: _pressed
              ? Neu.inset(widget.isDark)
              : (widget.enabled ? Neu.raisedSm(widget.isDark) : []),
        ),
        child: Icon(
          widget.icon,
          size: 17,
          color:
          widget.enabled ? widget.activeColor : widget.inactiveColor,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Format type enum
// ─────────────────────────────────────────────────────────────────────────────

enum _FormatType { bold, italic, bullet, numbered }
// Public alias so note_list_screen.dart can use it via the FormatType name
typedef FormatType = _FormatType;

// ─────────────────────────────────────────────────────────────────────────────
// Rich content codec
//
// Serialises (plainText, List<_FmtRange>) into a JSON string stored in
// note.content, and deserialises it back on load.
//
// Format: {"t":"plain text","r":[[start,end,typeIndex],...]}
// Plain strings (no JSON) are loaded as-is with no ranges for backwards compat.
// ─────────────────────────────────────────────────────────────────────────────

/// Public codec — accessible from note_list_screen.dart and any other file
/// that needs to read plain text out of a stored note.content string.
class RichContentCodec {
  /// Encode plain text + ranges → JSON string saved to note.content.
  static String encode(String plainText, List<_FmtRange> ranges) {
    if (ranges.isEmpty) return plainText;
    final rangeList = ranges.map((r) => [r.start, r.end, r.type.index]).toList();
    return jsonEncode({'t': plainText, 'r': rangeList});
  }

  /// Decode note.content → (plainText, ranges).
  /// Returns (stored, []) gracefully for plain strings (backwards compat).
  static ({String text, List<_FmtRange> ranges}) decode(String stored) {
    if (stored.isEmpty) return (text: '', ranges: []);
    try {
      final map = jsonDecode(stored);
      if (map is Map && map.containsKey('t') && map.containsKey('r')) {
        final t = map['t'] as String;
        final r = (map['r'] as List).map((e) {
          final arr = e as List;
          return _FmtRange(
            start: arr[0] as int,
            end:   arr[1] as int,
            type:  _FormatType.values[arr[2] as int],
          );
        }).toList();
        return (text: t, ranges: r);
      }
    } catch (_) {}
    return (text: stored, ranges: <_FmtRange>[]);
  }

  /// Extract just the plain text — the only method most callers need.
  static String plainText(String stored) => decode(stored).text;
}

// Private alias so all internal editor code continues to compile unchanged.
typedef _RichContentCodec = RichContentCodec;

// ─────────────────────────────────────────────────────────────────────────────
// Bold / Italic range — metadata separate from the plain text string.
// List prefixes ARE stored in the string as real characters so cursor
// positions are always 1-to-1 with what Flutter renders.
// ─────────────────────────────────────────────────────────────────────────────

class _FmtRange {
  int start;
  int end;
  final _FormatType type; // bold or italic only

  _FmtRange({required this.start, required this.end, required this.type});

  bool overlaps(int s, int e) => start < e && end > s;

  _FmtRange copyWith({int? start, int? end}) =>
      _FmtRange(start: start ?? this.start, end: end ?? this.end, type: type);
}

// ─────────────────────────────────────────────────────────────────────────────
// Rich text controller
//
// Key design decisions that eliminate cursor/selection bugs:
//
//  1. The underlying string is PLAIN TEXT — no hidden marker characters.
//  2. List prefixes ("• " / "1. ") are REAL CHARACTERS in the string.
//  3. Bold / italic are stored as List<_FmtRange> metadata and applied in
//     buildTextSpan without ever touching the string.
//  4. syncRanges() keeps ranges anchored after every keystroke.
//  5. Ranges are serialised to JSON via _RichContentCodec on save and
//     deserialised on load so formatting persists across sessions.
// ─────────────────────────────────────────────────────────────────────────────

class _RichTextController extends TextEditingController {
  final Color baseColor;
  final List<_FmtRange> _ranges = [];

  /// Set to true before programmatic text changes (toggleList, toggleInline)
  /// so _onRichChanged skips syncRanges for that notification.
  bool _skipNextSync = false;

  _RichTextController({
    required this.baseColor,
    String? initialText,
    List<_FmtRange>? initialRanges,
  }) : super(text: initialText ?? '') {
    if (initialRanges != null) _ranges.addAll(initialRanges);
  }

  // ── Base style ─────────────────────────────────────────────────────────────

  TextStyle get _base => TextStyle(
    fontSize: 15.5,
    height: 1.6,
    color: baseColor,
    fontWeight: FontWeight.w400,
    fontStyle: FontStyle.normal,
    decoration: TextDecoration.none,
  );

  // ── Query ──────────────────────────────────────────────────────────────────

  Set<_FormatType> inlineFormatsAt(int offset) {
    final result = <_FormatType>{};
    for (final r in _ranges) {
      if (offset > r.start && offset <= r.end) result.add(r.type);
    }
    return result;
  }

  Set<_FormatType> listFormatsAt(int offset) {
    final t = text;
    if (t.isEmpty) return {};
    final ls       = _lineStart(t, offset);
    final lineText = _lineAt(t, ls);
    final result   = <_FormatType>{};
    if (lineText.startsWith('• ')) result.add(_FormatType.bullet);
    if (RegExp(r'^\d+\. ').hasMatch(lineText)) result.add(_FormatType.numbered);
    return result;
  }

  // ── Toggle bold / italic ───────────────────────────────────────────────────

  void toggleInline(_FormatType type, TextSelection sel) {
    assert(type == _FormatType.bold || type == _FormatType.italic);
    if (sel.isCollapsed) return;
    final s = sel.start;
    final e = sel.end;

    final covering = _ranges
        .where((r) => r.type == type && r.start <= s && r.end >= e)
        .toList();

    if (covering.isNotEmpty) {
      for (final r in covering) {
        _ranges.remove(r);
        if (r.start < s) _ranges.add(_FmtRange(start: r.start, end: s, type: type));
        if (r.end > e)   _ranges.add(_FmtRange(start: e, end: r.end, type: type));
      }
    } else {
      _ranges.removeWhere((r) => r.type == type && r.overlaps(s, e));
      _ranges.add(_FmtRange(start: s, end: e, type: type));
    }
    _skipNextSync = true;
    notifyListeners();
  }

  // ── Toggle bullet / numbered list ──────────────────────────────────────────

  void toggleList(_FormatType type, TextSelection sel) {
    assert(type == _FormatType.bullet || type == _FormatType.numbered);
    final t = text;
    if (t.isEmpty) return;

    final lineStarts = _lineStartsInSel(t, sel);
    final alreadyOn  = lineStarts.every((ls) {
      final lt = _lineAt(t, ls);
      return type == _FormatType.bullet
          ? lt.startsWith('• ')
          : RegExp(r'^\d+\. ').hasMatch(lt);
    });

    int numberedCounter = 1;
    if (type == _FormatType.numbered && !alreadyOn) {
      int pos = 0;
      while (pos < lineStarts.first) {
        if (RegExp(r'^\d+\. ').hasMatch(_lineAt(t, pos))) numberedCounter++;
        final nl = t.indexOf('\n', pos);
        if (nl == -1 || nl + 1 >= lineStarts.first) break;
        pos = nl + 1;
      }
    }

    final buf    = StringBuffer();
    int   offset = 0;
    while (offset <= t.length) {
      final nl      = t.indexOf('\n', offset);
      final lineEnd = nl == -1 ? t.length : nl;
      final line    = t.substring(offset, lineEnd);
      final inSel   = lineStarts.contains(offset);

      String out = line;
      if (inSel) {
        out = out.replaceFirst(RegExp(r'^• '), '');
        out = out.replaceFirst(RegExp(r'^\d+\. '), '');
        if (!alreadyOn) {
          out = type == _FormatType.bullet
              ? '• $out'
              : '${numberedCounter++}. $out';
        }
      }

      buf.write(out);
      if (nl == -1) break;
      buf.write('\n');
      offset = nl + 1;
    }

    final newText = buf.toString();
    final delta   = newText.length - t.length;
    _shiftRangesAfter(lineStarts.isEmpty ? 0 : lineStarts.first, delta);

    final newSelEnd = (sel.end + delta).clamp(0, newText.length);
    _skipNextSync = true;
    value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newSelEnd),
    );
  }

  // ── Range sync ─────────────────────────────────────────────────────────────
  //
  // Called from _onRichChanged after every keystroke.
  // Uses the controller's current cursor position as the authoritative edit
  // point instead of a fragile LCS prefix/suffix scan.
  //
  // Rules:
  //   • edit point = cursor position in the NEW text after the change
  //   • delta      = newText.length - oldText.length  (+insert / -delete)
  //   • Any range that starts AT or AFTER the edit point shifts by delta.
  //   • Any range that straddles the edit point: end shifts, start stays.
  //   • Ranges entirely before the edit point are untouched.
  //   • Zero-length ranges are discarded.

  void syncRanges(String oldText, String newText) {
    if (oldText == newText) return;
    final delta = newText.length - oldText.length;
    if (delta == 0) return; // pure replacement — offsets unchanged

    // Use the cursor (base offset in new value) as the edit point.
    // Falls back to prefix scan only when selection is invalid.
    int editPoint;
    final sel = selection;
    if (sel.isValid) {
      // After an insertion the cursor sits just after the inserted chars.
      // After a deletion the cursor sits at the deletion start.
      editPoint = delta > 0 ? sel.baseOffset - delta : sel.baseOffset;
      editPoint = editPoint.clamp(0, oldText.length);
    } else {
      // Fallback: find first differing character.
      editPoint = 0;
      final minLen = oldText.length < newText.length ? oldText.length : newText.length;
      while (editPoint < minLen && oldText[editPoint] == newText[editPoint]) {
        editPoint++;
      }
    }

    final updated = <_FmtRange>[];
    for (final r in _ranges) {
      int s = r.start, e = r.end;
      if (s >= editPoint) {
        // Entire range is after the edit — shift both endpoints.
        s = (s + delta).clamp(0, newText.length);
        e = (e + delta).clamp(0, newText.length);
      } else if (e > editPoint) {
        // Range straddles the edit point — only the end shifts.
        e = (e + delta).clamp(s, newText.length);
      }
      // Drop zero-length ranges.
      if (s < e) updated.add(r.copyWith(start: s, end: e));
    }
    _ranges..clear()..addAll(updated);
  }

  void _shiftRangesAfter(int point, int delta) {
    if (delta == 0) return;
    final updated = <_FmtRange>[];
    for (final r in _ranges) {
      int s = r.start, e = r.end;
      if (s >= point) {
        s = (s + delta).clamp(0, text.length);
        e = (e + delta).clamp(0, text.length);
      } else if (e > point) {
        e = (e + delta).clamp(s, text.length);
      }
      if (s < e) updated.add(r.copyWith(start: s, end: e));
    }
    _ranges..clear()..addAll(updated);
  }

  // ── buildTextSpan ──────────────────────────────────────────────────────────

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final t = value.text;
    if (t.isEmpty) return TextSpan(text: '', style: _base);

    final len    = t.length;
    final bold   = List<bool>.filled(len, false);
    final italic = List<bool>.filled(len, false);

    for (final r in _ranges) {
      if (r.type == _FormatType.bold) {
        for (int i = r.start; i < r.end && i < len; i++) bold[i] = true;
      } else {
        for (int i = r.start; i < r.end && i < len; i++) italic[i] = true;
      }
    }

    // List prefix chars (• / 1. etc.) are always bold, never italic —
    // regardless of any user range that may overlap them.
    int lineOff = 0;
    for (final line in t.split('\n')) {
      final m = RegExp(r'^(• |\d+\. )').firstMatch(line);
      if (m != null) {
        for (int i = lineOff; i < lineOff + m.end && i < len; i++) {
          bold[i]   = true;
          italic[i] = false;
        }
      }
      lineOff += line.length + 1;
    }

    final spans  = <InlineSpan>[];
    final lines  = t.split('\n');
    int   offset = 0;

    for (int li = 0; li < lines.length; li++) {
      final line = lines[li];
      int i = 0;
      while (i < line.length) {
        final co       = offset + i;
        final isBold   = co < len && bold[co];
        final isItalic = co < len && italic[co];
        int j = i + 1;
        while (j < line.length) {
          final nco = offset + j;
          if (nco >= len) break;
          if (bold[nco] != isBold || italic[nco] != isItalic) break;
          j++;
        }
        spans.add(TextSpan(
          text: line.substring(i, j),
          style: _base.copyWith(
            fontWeight: isBold   ? FontWeight.w800 : FontWeight.w400,
            fontStyle:  isItalic ? FontStyle.italic : FontStyle.normal,
          ),
        ));
        i = j;
      }
      offset += line.length;
      if (li < lines.length - 1) {
        spans.add(TextSpan(text: '\n', style: _base));
        offset += 1;
      }
    }

    return spans.isEmpty
        ? TextSpan(text: t, style: _base)
        : TextSpan(children: spans);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static int _lineStart(String text, int offset) {
    if (offset <= 0) return 0;
    final idx = text.lastIndexOf('\n', offset - 1);
    return idx == -1 ? 0 : idx + 1;
  }

  static String _lineAt(String text, int lineStart) {
    final nl = text.indexOf('\n', lineStart);
    return nl == -1 ? text.substring(lineStart) : text.substring(lineStart, nl);
  }

  static List<int> _lineStartsInSel(String text, TextSelection sel) {
    final starts = <int>[];
    final first  = _lineStart(text, sel.start);
    // For a collapsed selection (cursor only), treat the cursor's line as the
    // selected range so bullet/numbered toggling works without a text selection.
    final effectiveEnd = sel.isCollapsed ? sel.start + 1 : sel.end;
    var   pos    = first;
    while (pos <= text.length) {
      starts.add(pos);
      final nl = text.indexOf('\n', pos);
      if (nl == -1 || nl >= effectiveEnd) break;
      pos = nl + 1;
    }
    return starts;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// renderMarkdown — used in preview widgets, not in the editor.
// Reads the serialised content and renders bold/italic ranges as rich text.
// ─────────────────────────────────────────────────────────────────────────────

Widget renderMarkdown(String stored, TextStyle base) {
  final (:text, :ranges) = _RichContentCodec.decode(stored);
  if (ranges.isEmpty) return Text(text, style: base);

  final len    = text.length;
  final bold   = List<bool>.filled(len, false);
  final italic = List<bool>.filled(len, false);
  for (final r in ranges) {
    if (r.type == _FormatType.bold) {
      for (int i = r.start; i < r.end && i < len; i++) bold[i] = true;
    } else {
      for (int i = r.start; i < r.end && i < len; i++) italic[i] = true;
    }
  }

  final spans = <InlineSpan>[];
  int i = 0;
  while (i < len) {
    final isBold   = bold[i];
    final isItalic = italic[i];
    int j = i + 1;
    while (j < len && bold[j] == isBold && italic[j] == isItalic) j++;
    spans.add(TextSpan(
      text: text.substring(i, j),
      style: base.copyWith(
        fontWeight: isBold   ? FontWeight.w800 : FontWeight.w400,
        fontStyle:  isItalic ? FontStyle.italic : FontStyle.normal,
      ),
    ));
    i = j;
  }
  return RichText(text: TextSpan(children: spans));
}

// ─────────────────────────────────────────────────────────────────────────────
// Input formatter — handles Enter on list lines
// ─────────────────────────────────────────────────────────────────────────────

class _ListEnterFormatter extends TextInputFormatter {
  static final _bulletRe   = RegExp(r'^• ');
  static final _numberedRe = RegExp(r'^(\d+)\. ');

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.length != oldValue.text.length + 1) return newValue;
    final cursor = newValue.selection.baseOffset;
    if (cursor <= 0 || newValue.text[cursor - 1] != '\n') return newValue;

    final old    = oldValue.text;
    final oldCur = oldValue.selection.baseOffset;
    final ls     = _lineStart(old, oldCur);
    final lineText = _lineAt(old, ls);

    if (!_bulletRe.hasMatch(lineText) && !_numberedRe.hasMatch(lineText)) {
      return newValue;
    }

    final numMatch  = _numberedRe.firstMatch(lineText);
    final isBullet  = _bulletRe.hasMatch(lineText);
    final prefixLen = isBullet ? 2 : numMatch!.end;
    final content   = lineText.substring(prefixLen);

    if (content.isEmpty) {
      // Empty list line → exit list
      final newText = old.substring(0, ls) + old.substring(ls + prefixLen);
      return TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: ls),
      );
    }

    final nextPrefix = isBullet
        ? '• '
        : '${int.parse(numMatch!.group(1)!) + 1}. ';

    final before = newValue.text.substring(0, cursor);
    final after  = newValue.text.substring(cursor);
    final result = '$before$nextPrefix$after';

    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: cursor + nextPrefix.length),
    );
  }

  static int _lineStart(String text, int offset) {
    if (offset <= 0) return 0;
    final idx = text.lastIndexOf('\n', offset - 1);
    return idx == -1 ? 0 : idx + 1;
  }

  static String _lineAt(String text, int lineStart) {
    final nl = text.indexOf('\n', lineStart);
    return nl == -1 ? text.substring(lineStart) : text.substring(lineStart, nl);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Rich text field widget
// ─────────────────────────────────────────────────────────────────────────────

class _RichTextField extends StatefulWidget {
  final bool isDark;
  final TextEditingController controller; // holds serialised content
  final Color baseColor;
  final VoidCallback? onSelectionChanged;
  final void Function(_FormatType)? onApplyFormat;

  const _RichTextField({
    super.key,
    required this.isDark,
    required this.controller,
    required this.baseColor,
    this.onSelectionChanged,
    this.onApplyFormat,
  });

  @override
  State<_RichTextField> createState() => _RichTextFieldState();
}

class _RichTextFieldState extends State<_RichTextField> {
  late _RichTextController _richCtrl;
  String _prevPlainText = '';

  // ── Serialised content — call this from _save() ───────────────────────────
  String get serialisedContent =>
      _RichContentCodec.encode(_richCtrl.text.trim(), _richCtrl._ranges);

  // ── Active formats (read by toolbar via GlobalKey) ─────────────────────────

  Set<_FormatType> get activeFormats {
    final sel = _richCtrl.selection;
    if (!sel.isValid) return {};
    return {
      ..._richCtrl.inlineFormatsAt(sel.start),
      ..._richCtrl.listFormatsAt(sel.start),
    };
  }

  // ── Apply format ───────────────────────────────────────────────────────────

  void applyFormat(_FormatType type) {
    final sel = _richCtrl.selection;
    if (!sel.isValid) return;
    if (type == _FormatType.bold || type == _FormatType.italic) {
      _richCtrl.toggleInline(type, sel);
    } else {
      _richCtrl.toggleList(type, sel);
    }
    if (mounted) setState(() {});
  }

  // ── Listeners ──────────────────────────────────────────────────────────────

  void _onRichChanged() {
    final newPlain = _richCtrl.text;
    if (_richCtrl._skipNextSync) {
      // This change came from a programmatic toggleInline/toggleList call.
      // Ranges are already correct — just update _prevPlainText and mirror.
      _richCtrl._skipNextSync = false;
    } else {
      _richCtrl.syncRanges(_prevPlainText, newPlain);
    }
    _prevPlainText = newPlain;
    // Mirror plain text to parent controller (used by undo/snapshot/hasContent)
    if (widget.controller.text != newPlain) {
      widget.controller.value = _richCtrl.value;
    }
  }

  void _onParentChanged() {
    // Parent changed externally (undo/redo) — decode and reload
    final stored = widget.controller.text;
    final (:text, :ranges) = _RichContentCodec.decode(stored);
    if (_richCtrl.text != text) {
      _richCtrl._ranges
        ..clear()
        ..addAll(ranges);
      // Skip syncRanges in _onRichChanged — we just loaded authoritative ranges.
      _richCtrl._skipNextSync = true;
      _richCtrl.value = TextEditingValue(text: text);
      _prevPlainText  = text;
    }
  }

  void _onSelectionChanged() => widget.onSelectionChanged?.call();

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    // Decode stored content (may be plain text or JSON envelope)
    final (:text, :ranges) = _RichContentCodec.decode(widget.controller.text);
    _richCtrl = _RichTextController(
      baseColor:      widget.baseColor,
      initialText:    text,
      initialRanges:  ranges,
    );
    _prevPlainText = text;
    _richCtrl.addListener(_onRichChanged);
    _richCtrl.addListener(_onSelectionChanged);
    widget.controller.addListener(_onParentChanged);
  }

  @override
  void dispose() {
    _richCtrl.removeListener(_onRichChanged);
    _richCtrl.removeListener(_onSelectionChanged);
    widget.controller.removeListener(_onParentChanged);
    _richCtrl.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bs     = Neu.fieldBorderStyle(isDark);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: Neu.inputFill(isDark),
        borderRadius: BorderRadius.circular(10),
        boxShadow: Neu.inputShadow(isDark),
        border: Border.all(color: bs.idle, width: bs.idleWidth),
      ),
      child: TextField(
        controller: _richCtrl,
        maxLines: null,
        minLines: 8,
        inputFormatters: [_ListEnterFormatter()],
        contextMenuBuilder: (ctx, editableTextState) {
          final sel = _richCtrl.selection;
          final hasSelection = sel.isValid && !sel.isCollapsed;
          final active = activeFormats;
          final accent = Theme.of(ctx).colorScheme.primary;
          final isBold   = active.contains(_FormatType.bold);
          final isItalic = active.contains(_FormatType.italic);

          // Build the standard system buttons first, then prepend our own.
          final systemButtons = editableTextState.contextMenuButtonItems;

          // Bold and Italic buttons only appear when text is selected.
          final formatButtons = hasSelection
              ? [
            ContextMenuButtonItem(
              label: isBold ? '✓ Bold' : 'Bold',
              onPressed: () {
                ContextMenuController.removeAny();
                widget.onApplyFormat?.call(_FormatType.bold);
              },
            ),
            ContextMenuButtonItem(
              label: isItalic ? '✓ Italic' : 'Italic',
              onPressed: () {
                ContextMenuController.removeAny();
                widget.onApplyFormat?.call(_FormatType.italic);
              },
            ),
          ]
              : <ContextMenuButtonItem>[];

          return AdaptiveTextSelectionToolbar.buttonItems(
            anchors: editableTextState.contextMenuAnchors,
            buttonItems: [...formatButtons, ...systemButtons],
          );
        },
        decoration: InputDecoration(
          hintText: 'Start writing…',
          hintStyle: TextStyle(
            fontSize: 15.5,
            height: 1.6,
            color: Neu.textTertiary(isDark),
          ),
          filled: false,
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
        // Do NOT set style= — buildTextSpan owns all styling.
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Icon format button (bullet / numbered list)
// ─────────────────────────────────────────────────────────────────────────────

class _FormatIconButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final bool isDark;
  final Color accent;
  final String tooltip;
  final VoidCallback onTap;

  const _FormatIconButton({
    required this.icon,
    required this.isDark,
    required this.accent,
    required this.tooltip,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 36,
          height: 32,
          decoration: BoxDecoration(
            color: isActive ? accent.withAlpha(20) : Neu.base(isDark),
            borderRadius: BorderRadius.circular(8),
            boxShadow: isActive ? Neu.inset(isDark) : Neu.raisedSm(isDark),
            border: isActive
                ? Border.all(color: accent.withAlpha(80), width: 1)
                : null,
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 17,
            color: isActive ? accent : accent.withAlpha(160),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stepped progress bar
//
// Renders one segment per checklist task.  Each segment animates from empty
// to filled when its task is checked, and back when unchecked.
// Up to _kMaxSegments segments are shown; beyond that the bar collapses into
// a single smooth fill so the gaps don't become invisible.
// ─────────────────────────────────────────────────────────────────────────────

class _SteppedProgressBar extends StatefulWidget {
  final int total;
  final int done;
  final bool isDark;
  final Color accent;

  const _SteppedProgressBar({
    required this.total,
    required this.done,
    required this.isDark,
    required this.accent,
  });

  @override
  State<_SteppedProgressBar> createState() => _SteppedProgressBarState();
}

class _SteppedProgressBarState extends State<_SteppedProgressBar>
    with SingleTickerProviderStateMixin {
  // When total exceeds this we render a continuous bar instead of segments.
  static const int _kMaxSegments = 20;

  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  int _prevDone = 0;

  @override
  void initState() {
    super.initState();
    _prevDone = widget.done;
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.0).animate(_pulseCtrl);
  }

  @override
  void didUpdateWidget(_SteppedProgressBar old) {
    super.didUpdateWidget(old);
    if (widget.done != _prevDone) {
      // Pulse the label on every step change.
      _pulseCtrl.forward(from: 0);
      _prevDone = widget.done;
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total    = widget.total;
    final done     = widget.done;
    final accent   = widget.accent;
    final isDark   = widget.isDark;
    final allDone  = total > 0 && done == total;
    final progress = total > 0 ? done / total : 0.0;

    final trackColor = isDark
        ? accent.withAlpha(30)
        : accent.withAlpha(22);
    final fillColor  = allDone ? accent : accent;
    final textColor  = allDone ? accent : Neu.textSecondary(isDark);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Neu.base(isDark),
        borderRadius: BorderRadius.circular(10),
        boxShadow: Neu.inset(isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Label row ───────────────────────────────────────────────────────
          Row(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: Icon(
                  allDone
                      ? Icons.check_circle_rounded
                      : Icons.check_circle_outline_rounded,
                  key: ValueKey(allDone),
                  size: 15,
                  color: accent,
                ),
              ),
              const SizedBox(width: 8),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
                child: Text(
                  total == 0
                      ? 'No items yet'
                      : '$done / $total completed',
                ),
              ),
              if (allDone) ...[
                const SizedBox(width: 6),
                const Text('🎉', style: TextStyle(fontSize: 13)),
              ],
              const Spacer(),
              // Percentage badge — pops in once there's something to show.
              AnimatedOpacity(
                opacity: total > 0 ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 250),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: allDone ? accent : Neu.textTertiary(isDark),
                    letterSpacing: 0.3,
                  ),
                  child: Text('${(progress * 100).round()}%'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // ── Bar ─────────────────────────────────────────────────────────────
          if (total == 0)
          // Empty state: thin ghost track.
            Container(
              height: 6,
              decoration: BoxDecoration(
                color: trackColor,
                borderRadius: BorderRadius.circular(3),
              ),
            )
          else if (total > _kMaxSegments)
          // Continuous animated fill for long lists.
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Stack(
                children: [
                  // Track
                  Container(
                    height: 6,
                    color: trackColor,
                  ),
                  // Fill
                  AnimatedFractionallySizedBox(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                    widthFactor: progress,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: fillColor,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
          // Segmented bar — one slot per task.
            LayoutBuilder(
              builder: (ctx, constraints) {
                const gap     = 3.0;
                final barW    = constraints.maxWidth;
                final segW    = (barW - gap * (total - 1)) / total;

                return Row(
                  children: List.generate(total, (i) {
                    final filled = i < done;
                    // The most-recently-completed segment gets a little bounce.
                    final isNewlyFilled = filled && i == done - 1;

                    return Padding(
                      padding: EdgeInsets.only(right: i < total - 1 ? gap : 0),
                      child: _AnimatedSegment(
                        key: ValueKey(i),
                        width: segW,
                        filled: filled,
                        bounce: isNewlyFilled,
                        fillColor: fillColor,
                        trackColor: trackColor,
                        isDark: isDark,
                      ),
                    );
                  }),
                );
              },
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Single animated segment
// ─────────────────────────────────────────────────────────────────────────────

class _AnimatedSegment extends StatefulWidget {
  final double width;
  final bool   filled;
  final bool   bounce;
  final Color  fillColor;
  final Color  trackColor;
  final bool   isDark;

  const _AnimatedSegment({
    super.key,
    required this.width,
    required this.filled,
    required this.bounce,
    required this.fillColor,
    required this.trackColor,
    required this.isDark,
  });

  @override
  State<_AnimatedSegment> createState() => _AnimatedSegmentState();
}

class _AnimatedSegmentState extends State<_AnimatedSegment>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _fillAnim;
  late Animation<double>   _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );

    _fillAnim = CurvedAnimation(
      parent: _ctrl,
      curve:  Curves.easeOutCubic,
    );

    // The "bounce" overshoot on the fill height.
    _scaleAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.35)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.35, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 60,
      ),
    ]).animate(_ctrl);

    if (widget.filled) _ctrl.value = 1.0;
  }

  @override
  void didUpdateWidget(_AnimatedSegment old) {
    super.didUpdateWidget(old);
    if (widget.filled != old.filled) {
      if (widget.filled) {
        _ctrl.forward(from: 0);
      } else {
        _ctrl.reverse();
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final h      = 6.0;
        final scale  = widget.bounce ? _scaleAnim.value : 1.0;
        final radius = BorderRadius.circular(3);

        return SizedBox(
          width: widget.width,
          height: h * 1.35, // headroom for the bounce overshoot
          child: Align(
            alignment: Alignment.center,
            child: ClipRRect(
              borderRadius: radius,
              child: Stack(
                children: [
                  // Track
                  Container(
                    width:  widget.width,
                    height: h,
                    color:  widget.trackColor,
                  ),
                  // Fill — grows left→right via FractionallySizedBox
                  FractionallySizedBox(
                    widthFactor:  _fillAnim.value,
                    heightFactor: scale,
                    alignment:    Alignment.centerLeft,
                    child: Container(
                      decoration: BoxDecoration(
                        color:        widget.fillColor,
                        borderRadius: radius,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Checklist toolbar button
// ─────────────────────────────────────────────────────────────────────────────

class _ChecklistToolbarButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isDark;
  final Color accent;
  final VoidCallback onTap;

  const _ChecklistToolbarButton({
    required this.label,
    required this.icon,
    required this.isDark,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Neu.base(isDark),
          borderRadius: BorderRadius.circular(8),
          boxShadow: Neu.raisedSm(isDark),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: accent),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: accent)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AppBar save button
// ─────────────────────────────────────────────────────────────────────────────

class _NeuSaveButton extends StatefulWidget {
  final bool isDark;
  final Color accent;
  final VoidCallback onTap;

  const _NeuSaveButton({
    super.key,
    required this.isDark,
    required this.accent,
    required this.onTap,
  });

  @override
  State<_NeuSaveButton> createState() => _NeuSaveButtonState();
}

class _NeuSaveButtonState extends State<_NeuSaveButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Neu.base(widget.isDark),
            borderRadius: BorderRadius.circular(10),
            boxShadow: _pressed
                ? Neu.inset(widget.isDark)
                : Neu.raisedSm(widget.isDark),
          ),
          child: Text(
            'Save',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: widget.accent),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// More menu
// ─────────────────────────────────────────────────────────────────────────────

class _MoreMenu extends StatelessWidget {
  final Note editing;
  final bool isDark;
  final bool checklistCompact;
  final VoidCallback onPinToggle;
  final VoidCallback onAddImage;
  final Function(ColorTheme) onColorChanged;
  final VoidCallback? onDelete;
  final VoidCallback? onToggleCompact;

  const _MoreMenu({
    required this.editing,
    required this.isDark,
    required this.checklistCompact,
    required this.onPinToggle,
    required this.onAddImage,
    required this.onColorChanged,
    this.onDelete,
    this.onToggleCompact,
  });

  @override
  Widget build(BuildContext context) {
    final subColor = Neu.textSecondary(isDark);
    return PopupMenuButton<Object>(
      icon: Icon(Icons.more_vert_rounded, size: 22, color: subColor),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 3,
      onSelected: (v) {
        if (v == 'delete') {
          onDelete?.call();
        } else if (v == 'toggle_pin') {
          onPinToggle();
        } else if (v == 'add_image') {
          onAddImage();
        } else if (v == 'toggle_compact') {
          onToggleCompact?.call();
        } else if (v is ColorTheme) {
          onColorChanged(v);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'toggle_pin',
          child: Row(children: [
            Icon(editing.pinned
                ? Icons.push_pin_rounded
                : Icons.push_pin_outlined),
            const SizedBox(width: 10),
            Text(editing.pinned ? 'Unpin' : 'Pin'),
          ]),
        ),
        const PopupMenuItem(
          value: 'add_image',
          child: Row(children: [
            Icon(Icons.image_outlined),
            SizedBox(width: 10),
            Text('Add image'),
          ]),
        ),
        if (onToggleCompact != null)
          PopupMenuItem(
            value: 'toggle_compact',
            child: Row(children: [
              Icon(checklistCompact
                  ? Icons.unfold_more_rounded
                  : Icons.unfold_less_rounded),
              const SizedBox(width: 10),
              Text(checklistCompact ? 'Expand items' : 'Compact view'),
            ]),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          enabled: false,
          height: 28,
          child: Text('Color theme',
              style: TextStyle(fontSize: 11, color: Colors.black45)),
        ),
        ...ColorTheme.values.map((theme) {
          final color =
          ThemeHelper.getThemeColor(theme, isDarkMode: isDark);
          final selected = theme == editing.colorTheme;
          return PopupMenuItem(
            value: theme,
            child: Row(children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.black12),
                ),
              ),
              const SizedBox(width: 10),
              Text(ThemeHelper.getThemeName(theme)),
              if (selected) ...[
                const Spacer(),
                const Icon(Icons.check_rounded, size: 16),
              ],
            ]),
          );
        }),
        if (onDelete != null) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'delete',
            child: Row(children: [
              Icon(Icons.delete_outline_rounded,
                  color: Colors.red.shade400),
              const SizedBox(width: 10),
              Text('Delete',
                  style: TextStyle(color: Colors.red.shade400)),
            ]),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog button
// ─────────────────────────────────────────────────────────────────────────────

class _NeuDialogButton extends StatefulWidget {
  final String label;
  final bool isDark;
  final bool isDestructive;
  final VoidCallback onTap;

  const _NeuDialogButton({
    required this.label,
    required this.isDark,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  State<_NeuDialogButton> createState() => _NeuDialogButtonState();
}

class _NeuDialogButtonState extends State<_NeuDialogButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final labelColor = widget.isDestructive
        ? Colors.red.shade400
        : Neu.textSecondary(widget.isDark);

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: Neu.base(widget.isDark),
          borderRadius: BorderRadius.circular(12),
          boxShadow: _pressed
              ? Neu.inset(widget.isDark)
              : Neu.raisedSm(widget.isDark),
        ),
        child: Text(widget.label,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: labelColor)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add row button
// ─────────────────────────────────────────────────────────────────────────────

class _NeuAddRowButton extends StatelessWidget {
  final String label;
  final bool isDark;
  final VoidCallback onTap;

  const _NeuAddRowButton(
      {required this.label, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: NeuPressable(
        isDark: isDark,
        radius: 12,
        onTap: onTap,
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded,
                size: 18, color: Neu.textSecondary(isDark)),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Neu.textSecondary(isDark))),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Checklist item tile
// ─────────────────────────────────────────────────────────────────────────────

class _ChecklistItemTile extends StatefulWidget {
  final ChecklistItem item;
  final bool isDark;
  final bool compact;
  final FocusNode focusNode;
  final Function(bool) onChanged;
  final VoidCallback onDelete;
  final Function(String) onTextChanged;
  final VoidCallback onSubmitted;

  const _ChecklistItemTile({
    super.key,
    required this.item,
    required this.isDark,
    required this.focusNode,
    required this.onChanged,
    required this.onDelete,
    required this.onTextChanged,
    required this.onSubmitted,
    this.compact = false,
  });

  @override
  State<_ChecklistItemTile> createState() => _ChecklistItemTileState();
}

class _ChecklistItemTileState extends State<_ChecklistItemTile>
    with SingleTickerProviderStateMixin {
  late TextEditingController _ctrl;
  late AnimationController _strikeCtrl;
  late Animation<double> _strikeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.item.text);
    _strikeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _strikeAnim =
        CurvedAnimation(parent: _strikeCtrl, curve: Curves.easeInOut);
    if (widget.item.checked) _strikeCtrl.value = 1.0;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _strikeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark    = widget.isDark;
    final accent    = Theme.of(context).colorScheme.primary;
    final textColor = Neu.textPrimary(isDark);
    final subColor  = Neu.textSecondary(isDark);
    final vertPad   = widget.compact ? 1.0 : 2.0;

    return Dismissible(
      key: ValueKey(widget.item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: Icon(Icons.delete_sweep_outlined,
            color: Colors.red.shade400, size: 22),
      ),
      onDismissed: (_) => widget.onDelete(),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: vertPad),
        child: Row(
          children: [
            GestureDetector(
              onTap: () {
                final next = !widget.item.checked;
                widget.onChanged(next);
                if (next) {
                  _strikeCtrl.forward();
                } else {
                  _strikeCtrl.reverse();
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: widget.compact ? 20 : 22,
                height: widget.compact ? 20 : 22,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: Neu.base(isDark),
                  border: Border.all(
                    color: widget.item.checked ? accent : subColor,
                    width: 1.5,
                  ),
                  borderRadius:
                  BorderRadius.circular(widget.compact ? 5 : 6),
                  boxShadow: widget.item.checked
                      ? Neu.inset(isDark)
                      : Neu.raisedSm(isDark),
                ),
                child: widget.item.checked
                    ? Icon(Icons.check_rounded,
                    size: widget.compact ? 12 : 14, color: accent)
                    : null,
              ),
            ),
            Expanded(
              child: FadeTransition(
                opacity: Tween<double>(begin: 1.0, end: 0.45)
                    .animate(_strikeAnim),
                child: KeyboardListener(
                  focusNode: FocusNode(skipTraversal: true),
                  onKeyEvent: (event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey.keyLabel == 'Backspace' &&
                        _ctrl.text.isEmpty) {
                      widget.onDelete();
                    }
                  },
                  child: NeuField(
                    isDark: isDark,
                    controller: _ctrl,
                    focusNode: widget.focusNode,
                    hint: 'New item…',
                    textInputAction: TextInputAction.newline,
                    maxLines: null,
                    minLines: 1,
                    onChanged: widget.onTextChanged,
                    style: TextStyle(
                      fontSize: widget.compact ? 13.5 : 15,
                      decoration: widget.item.checked
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                      color: widget.item.checked ? subColor : textColor,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section label (recipe card)
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  final IconData icon;
  final bool isDark;

  const _SectionLabel(
      {required this.text, required this.icon, required this.isDark});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Icon(icon, size: 15, color: Neu.textSecondary(isDark)),
        const SizedBox(width: 6),
        Text(text,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Neu.textSecondary(isDark),
                letterSpacing: 0.5)),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Recipe Card
// ─────────────────────────────────────────────────────────────────────────────

class _RecipeCard extends StatefulWidget {
  final RecipeData data;
  final bool isDark;
  final VoidCallback onChanged;

  const _RecipeCard(
      {required this.data, required this.isDark, required this.onChanged});

  @override
  State<_RecipeCard> createState() => _RecipeCardState();
}

class _RecipeCardState extends State<_RecipeCard> {
  late TextEditingController _prep, _cook, _serv;

  final Map<String, TextEditingController> _nameCtrl = {};
  final Map<String, TextEditingController> _qtyCtrl  = {};
  final Map<String, TextEditingController> _unitCtrl = {};

  final Map<String, TextEditingController> _stepCtrl  = {};
  final Map<String, FocusNode>             _stepFocus = {};

  @override
  void initState() {
    super.initState();
    _prep = TextEditingController(text: widget.data.prepTime);
    _cook = TextEditingController(text: widget.data.cookTime);
    _serv = TextEditingController(text: widget.data.servings);
    _initIngredientControllers();
    _initStepControllers();
  }

  void _initIngredientControllers() {
    for (final row in widget.data.ingredientRows) {
      _nameCtrl[row.id] = TextEditingController(text: row.name);
      _qtyCtrl[row.id]  = TextEditingController(text: row.quantity);
      _unitCtrl[row.id] = TextEditingController(text: row.unit);
    }
  }

  void _initStepControllers() {
    for (final step in widget.data.steps) {
      _stepCtrl[step.id]  = TextEditingController(text: step.text);
      _stepFocus[step.id] = FocusNode();
    }
  }

  @override
  void dispose() {
    _prep.dispose();
    _cook.dispose();
    _serv.dispose();
    for (final c in _nameCtrl.values) c.dispose();
    for (final c in _qtyCtrl.values)  c.dispose();
    for (final c in _unitCtrl.values) c.dispose();
    for (final c in _stepCtrl.values) c.dispose();
    for (final f in _stepFocus.values) f.dispose();
    super.dispose();
  }

  void _addIngredientRow() {
    final row = IngredientRow();
    setState(() {
      widget.data.ingredientRows.add(row);
      _nameCtrl[row.id] = TextEditingController();
      _qtyCtrl[row.id]  = TextEditingController();
      _unitCtrl[row.id] = TextEditingController();
      widget.onChanged();
    });
  }

  void _removeIngredientRow(String id) {
    setState(() {
      widget.data.ingredientRows.removeWhere((r) => r.id == id);
      _nameCtrl[id]?.dispose();
      _nameCtrl.remove(id);
      _qtyCtrl[id]?.dispose();
      _qtyCtrl.remove(id);
      _unitCtrl[id]?.dispose();
      _unitCtrl.remove(id);
      widget.onChanged();
    });
  }

  void _addStep({int? afterIndex}) {
    final step = RecipeStep();
    setState(() {
      if (afterIndex != null &&
          afterIndex < widget.data.steps.length - 1) {
        widget.data.steps.insert(afterIndex + 1, step);
      } else {
        widget.data.steps.add(step);
      }
      _stepCtrl[step.id]  = TextEditingController();
      _stepFocus[step.id] = FocusNode();
      widget.onChanged();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _stepFocus[step.id]?.requestFocus();
    });
  }

  void _removeStep(String id) {
    final idx = widget.data.steps.indexWhere((s) => s.id == id);
    setState(() {
      widget.data.steps.removeWhere((s) => s.id == id);
      _stepCtrl[id]?.dispose();
      _stepCtrl.remove(id);
      _stepFocus[id]?.dispose();
      _stepFocus.remove(id);
      widget.onChanged();
    });
    if (idx > 0 && idx - 1 < widget.data.steps.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _stepFocus[widget.data.steps[idx - 1].id]?.requestFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final accent = Theme.of(context).colorScheme.primary;
    final ter    = Neu.textTertiary(isDark);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 12, bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
                child: _timeField(_prep, 'Prep', Icons.timer_outlined,
                    isDark, (v) {
                      widget.data.prepTime = v;
                      widget.onChanged();
                    })),
            const SizedBox(width: 8),
            Expanded(
                child: _timeField(_cook, 'Cook',
                    Icons.local_fire_department_outlined, isDark, (v) {
                      widget.data.cookTime = v;
                      widget.onChanged();
                    })),
            const SizedBox(width: 8),
            Expanded(
                child: _timeField(_serv, 'Serves',
                    Icons.people_outline_rounded, isDark, (v) {
                      widget.data.servings = v;
                      widget.onChanged();
                    })),
          ]),

          const SizedBox(height: 24),

          _SectionLabel(
              text: 'INGREDIENTS',
              icon: Icons.kitchen_outlined,
              isDark: isDark),
          const SizedBox(height: 8),

          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              SizedBox(
                width: 28,
                child: Text('#',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: ter,
                        letterSpacing: 0.5)),
              ),
              const SizedBox(width: 6),
              Expanded(
                  flex: 4,
                  child: Text('Ingredient',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: ter,
                          letterSpacing: 0.5))),
              const SizedBox(width: 6),
              Expanded(
                  flex: 2,
                  child: Text('Qty',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: ter,
                          letterSpacing: 0.5))),
              const SizedBox(width: 6),
              Expanded(
                  flex: 2,
                  child: Text('Unit',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: ter,
                          letterSpacing: 0.5))),
              const SizedBox(width: 32),
            ]),
          ),

          ...widget.data.ingredientRows.asMap().entries.map((entry) {
            final i   = entry.key;
            final row = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 28,
                    child: NeuContainer(
                      isDark: isDark,
                      radius: 8,
                      inset: true,
                      padding:
                      const EdgeInsets.symmetric(vertical: 10),
                      child: Text('${i + 1}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: accent)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 4,
                    child: _tableField(_nameCtrl[row.id]!, isDark,
                        'e.g. Flour',
                        onChanged: (v) {
                          row.name = v;
                          widget.onChanged();
                        }),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 2,
                    child: _tableField(_qtyCtrl[row.id]!, isDark, '200',
                        onChanged: (v) {
                          row.quantity = v;
                          widget.onChanged();
                        }),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 2,
                    child: _tableField(_unitCtrl[row.id]!, isDark, 'g',
                        onChanged: (v) {
                          row.unit = v;
                          widget.onChanged();
                        }),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: widget.data.ingredientRows.length > 1
                        ? () => _removeIngredientRow(row.id)
                        : null,
                    child: Icon(
                        Icons.remove_circle_outline_rounded,
                        size: 18,
                        color: widget.data.ingredientRows.length > 1
                            ? Colors.red.shade400
                            : ter),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 4),
          NeuPressable(
            isDark: isDark,
            radius: 10,
            onTap: _addIngredientRow,
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_rounded, size: 16, color: accent),
                const SizedBox(width: 6),
                Text('Add ingredient',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: accent)),
              ],
            ),
          ),

          const SizedBox(height: 24),

          _SectionLabel(
              text: 'INSTRUCTIONS',
              icon: Icons.format_list_numbered_rounded,
              isDark: isDark),
          const SizedBox(height: 8),

          ...widget.data.steps.asMap().entries.map((entry) {
            final i    = entry.key;
            final step = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: NeuContainer(
                      isDark: isDark,
                      radius: 14,
                      inset: true,
                      padding: const EdgeInsets.all(6),
                      child: Text('${i + 1}',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: accent)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: NeuField(
                      isDark: isDark,
                      controller: _stepCtrl[step.id]!,
                      focusNode: _stepFocus[step.id],
                      hint: 'Describe step ${i + 1}…',
                      maxLines: null,
                      minLines: 1,
                      textInputAction: TextInputAction.next,
                      onChanged: (v) {
                        step.text = v;
                        widget.onChanged();
                      },
                      onSubmitted: () => _addStep(afterIndex: i),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: GestureDetector(
                      onTap: widget.data.steps.length > 1
                          ? () => _removeStep(step.id)
                          : null,
                      child: Icon(
                          Icons.remove_circle_outline_rounded,
                          size: 18,
                          color: widget.data.steps.length > 1
                              ? Colors.red.shade400
                              : ter),
                    ),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 4),
          NeuPressable(
            isDark: isDark,
            radius: 10,
            onTap: () => _addStep(),
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_rounded, size: 16, color: accent),
                const SizedBox(width: 6),
                Text('Add step',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: accent)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeField(TextEditingController ctrl, String label,
      IconData icon, bool isDark, Function(String) onChanged) {
    return NeuField(
      isDark: isDark,
      controller: ctrl,
      label: label,
      icon: icon,
      onChanged: onChanged,
    );
  }

  Widget _tableField(
      TextEditingController ctrl, bool isDark, String hint,
      {required Function(String) onChanged}) {
    return NeuField(
      isDark: isDark,
      controller: ctrl,
      hint: hint,
      onChanged: onChanged,
      style: TextStyle(fontSize: 13, color: Neu.textPrimary(isDark)),
    );
  }
}