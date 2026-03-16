// lib/note_editor_screen.dart
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
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  final Map<String, FocusNode> _checklistFocusNodes = {};

  static const _categories = ['General', 'Work', 'Personal', 'Ideas'];

  @override
  void initState() {
    super.initState();
    _editing = widget.note != null
        ? widget.note!.copyWith(
            checklistItems: List.from(widget.note!.checklistItems),
            itineraryItems: List.from(widget.note!.itineraryItems),
            mealPlanItems:  List.from(widget.note!.mealPlanItems),
            imageIds:       List.from(widget.note!.imageIds),
          )
        : Note(
            id:        const Uuid().v4(),
            title:     '',
            content:   '',
            updatedAt: DateTime.now(),
            noteType:  widget.noteType,
            colorTheme: _defaultColorForTheme(),
          );

    _titleCtrl   = TextEditingController(text: _editing.title);
    _contentCtrl = TextEditingController(text: _editing.content);

    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
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

  void _save() {
    _editing.title   = _titleCtrl.text.trim();
    _editing.content = _contentCtrl.text.trim();

    if (_editing.title.isEmpty &&
        _editing.content.isEmpty &&
        _editing.checklistItems.isEmpty &&
        _editing.itineraryItems.isEmpty &&
        _editing.mealPlanItems.isEmpty &&
        _editing.imageIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Note is empty'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(10))),
        ),
      );
      return;
    }

    Provider.of<NotesProvider>(context, listen: false).updateNote(_editing);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    // cardTint() returns Neu.base() for neumorphic, tinted color for material.
    // No theme check needed here — neu_theme.dart owns that decision.
    final cardBg  = Neu.cardTint(_editing.colorTheme, isDark);
    final accent      = Neu.accentFromTheme(_editing.colorTheme);
    final textPrimary = Neu.textPrimary(isDark);
    final textSub     = Neu.textSecondary(isDark);

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
          widget.note == null ? 'New Note' : 'Edit Note',
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: textPrimary),
        ),
        actions: [
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: accent)),
            ),
          _NeuSaveButton(isDark: isDark, accent: accent, onTap: _save),
          _MoreMenu(
            editing: _editing,
            isDark: isDark,
            onPinToggle: () =>
                setState(() => _editing.pinned = !_editing.pinned),
            onAddImage: _pickImage,
            onColorChanged: (t) => setState(() => _editing.colorTheme = t),
            onDelete:
                widget.note != null ? _showDeleteConfirmation : null,
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
          // Accent bar matching note theme
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

  Widget _buildNormal(bool isDark) => NeuField(
        isDark: isDark,
        controller: _contentCtrl,
        maxLines: null,
        minLines: 8,
        hint: 'Start writing…',
        style: TextStyle(
            fontSize: 15.5,
            height: 1.6,
            color: Neu.textPrimary(isDark)),
      );

  FocusNode _focusForItem(String id) =>
      _checklistFocusNodes.putIfAbsent(id, () => FocusNode());

  void _addChecklistItemAfter(int index) {
    final newItem = ChecklistItem(text: '');
    setState(() => _editing.checklistItems.insert(index + 1, newItem));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusForItem(newItem.id).requestFocus();
    });
  }

  Widget _buildChecklist(bool isDark) => Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 8),
              itemCount: _editing.checklistItems.length,
              itemBuilder: (_, i) {
                final item = _editing.checklistItems[i];
                return _ChecklistItemTile(
                  key: ValueKey(item.id),
                  item: item,
                  isDark: isDark,
                  focusNode: _focusForItem(item.id),
                  onChanged: (v) => setState(() => item.checked = v),
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
                  onTextChanged: (text) => item.text = text,
                  onSubmitted:   () => _addChecklistItemAfter(i),
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
// AppBar save button
// ─────────────────────────────────────────────────────────────────────────────

class _NeuSaveButton extends StatefulWidget {
  final bool isDark;
  final Color accent;
  final VoidCallback onTap;
  const _NeuSaveButton(
      {required this.isDark, required this.accent, required this.onTap});

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
  final VoidCallback onPinToggle;
  final VoidCallback onAddImage;
  final Function(ColorTheme) onColorChanged;
  final VoidCallback? onDelete;

  const _MoreMenu({
    required this.editing,
    required this.isDark,
    required this.onPinToggle,
    required this.onAddImage,
    required this.onColorChanged,
    this.onDelete,
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
// Dialog button (cancel / delete)
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
        padding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
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
            Icon(Icons.add_rounded, size: 18,
                color: Neu.textSecondary(isDark)),
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
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            // Animated checkbox
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
                width: 22,
                height: 22,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: Neu.base(isDark),
                  border: Border.all(
                    color: widget.item.checked ? accent : subColor,
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: widget.item.checked
                      ? Neu.inset(isDark)
                      : Neu.raisedSm(isDark),
                ),
                child: widget.item.checked
                    ? Icon(Icons.check_rounded, size: 14, color: accent)
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
                    textInputAction: TextInputAction.next,
                    onChanged: widget.onTextChanged,
                    onSubmitted: widget.onSubmitted,
                    style: TextStyle(
                      fontSize: 15,
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
// Recipe Card — ingredient table + step-by-step instructions
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

  // Ingredient table controllers keyed by row id
  final Map<String, TextEditingController> _nameCtrl = {};
  final Map<String, TextEditingController> _qtyCtrl  = {};
  final Map<String, TextEditingController> _unitCtrl = {};

  // Step controllers keyed by step id
  final Map<String, TextEditingController> _stepCtrl     = {};
  final Map<String, FocusNode>             _stepFocus    = {};

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
    _prep.dispose(); _cook.dispose(); _serv.dispose();
    for (final c in _nameCtrl.values) { c.dispose(); }
    for (final c in _qtyCtrl.values)  { c.dispose(); }
    for (final c in _unitCtrl.values) { c.dispose(); }
    for (final c in _stepCtrl.values) { c.dispose(); }
    for (final f in _stepFocus.values) { f.dispose(); }
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
      _nameCtrl[id]?.dispose(); _nameCtrl.remove(id);
      _qtyCtrl[id]?.dispose();  _qtyCtrl.remove(id);
      _unitCtrl[id]?.dispose(); _unitCtrl.remove(id);
      widget.onChanged();
    });
  }

  void _addStep({int? afterIndex}) {
    final step = RecipeStep();
    setState(() {
      if (afterIndex != null && afterIndex < widget.data.steps.length - 1) {
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
      _stepCtrl[id]?.dispose();  _stepCtrl.remove(id);
      _stepFocus[id]?.dispose(); _stepFocus.remove(id);
      widget.onChanged();
    });
    // Focus previous step
    if (idx > 0 && idx - 1 < widget.data.steps.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _stepFocus[widget.data.steps[idx - 1].id]?.requestFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark  = widget.isDark;
    final accent  = Theme.of(context).colorScheme.primary;
    final ter     = Neu.textTertiary(isDark);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 12, bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Time chips ─────────────────────────────────────────────────────
          Row(children: [
            Expanded(child: _timeField(_prep, 'Prep', Icons.timer_outlined,
                isDark, (v) { widget.data.prepTime = v; widget.onChanged(); })),
            const SizedBox(width: 8),
            Expanded(child: _timeField(_cook, 'Cook',
                Icons.local_fire_department_outlined, isDark,
                (v) { widget.data.cookTime = v; widget.onChanged(); })),
            const SizedBox(width: 8),
            Expanded(child: _timeField(_serv, 'Serves',
                Icons.people_outline_rounded, isDark,
                (v) { widget.data.servings = v; widget.onChanged(); })),
          ]),

          const SizedBox(height: 24),

          // ── Ingredients table ──────────────────────────────────────────────
          _SectionLabel(text: 'INGREDIENTS', icon: Icons.kitchen_outlined,
              isDark: isDark),
          const SizedBox(height: 8),

          // Header row
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              SizedBox(
                width: 28,
                child: Text('#',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                        color: ter, letterSpacing: 0.5)),
              ),
              const SizedBox(width: 6),
              Expanded(flex: 4,
                  child: Text('Ingredient',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: ter, letterSpacing: 0.5))),
              const SizedBox(width: 6),
              Expanded(flex: 2,
                  child: Text('Qty',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: ter, letterSpacing: 0.5))),
              const SizedBox(width: 6),
              Expanded(flex: 2,
                  child: Text('Unit',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: ter, letterSpacing: 0.5))),
              const SizedBox(width: 32), // space for delete button
            ]),
          ),

          // Ingredient rows
          ...widget.data.ingredientRows.asMap().entries.map((entry) {
            final i   = entry.key;
            final row = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Serial number
                  SizedBox(
                    width: 28,
                    child: NeuContainer(
                      isDark: isDark,
                      radius: 8,
                      inset: true,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text('${i + 1}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700,
                              color: accent)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Ingredient name
                  Expanded(
                    flex: 4,
                    child: _tableField(_nameCtrl[row.id]!, isDark, 'e.g. Flour',
                        onChanged: (v) { row.name = v; widget.onChanged(); }),
                  ),
                  const SizedBox(width: 6),
                  // Quantity
                  Expanded(
                    flex: 2,
                    child: _tableField(_qtyCtrl[row.id]!, isDark, '200',
                        onChanged: (v) { row.quantity = v; widget.onChanged(); }),
                  ),
                  const SizedBox(width: 6),
                  // Unit
                  Expanded(
                    flex: 2,
                    child: _tableField(_unitCtrl[row.id]!, isDark, 'g',
                        onChanged: (v) { row.unit = v; widget.onChanged(); }),
                  ),
                  const SizedBox(width: 6),
                  // Delete
                  GestureDetector(
                    onTap: widget.data.ingredientRows.length > 1
                        ? () => _removeIngredientRow(row.id)
                        : null,
                    child: Icon(Icons.remove_circle_outline_rounded,
                        size: 18,
                        color: widget.data.ingredientRows.length > 1
                            ? Colors.red.shade400
                            : ter),
                  ),
                ],
              ),
            );
          }),

          // Add ingredient button
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
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                        color: accent)),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Instructions ───────────────────────────────────────────────────
          _SectionLabel(text: 'INSTRUCTIONS',
              icon: Icons.format_list_numbered_rounded, isDark: isDark),
          const SizedBox(height: 8),

          ...widget.data.steps.asMap().entries.map((entry) {
            final i    = entry.key;
            final step = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Step number bubble
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: NeuContainer(
                      isDark: isDark,
                      radius: 14,
                      inset: true,
                      padding: const EdgeInsets.all(6),
                      child: Text('${i + 1}',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w800,
                              color: accent)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Step text field
                  Expanded(
                    child: NeuField(
                      isDark: isDark,
                      controller: _stepCtrl[step.id]!,
                      focusNode: _stepFocus[step.id],
                      hint: 'Describe step ${i + 1}…',
                      maxLines: null,
                      minLines: 1,
                      textInputAction: TextInputAction.next,
                      onChanged: (v) { step.text = v; widget.onChanged(); },
                      onSubmitted: () => _addStep(afterIndex: i),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Delete step
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: GestureDetector(
                      onTap: widget.data.steps.length > 1
                          ? () => _removeStep(step.id)
                          : null,
                      child: Icon(Icons.remove_circle_outline_rounded,
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

          // Add step button
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
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                        color: accent)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeField(TextEditingController ctrl, String label, IconData icon,
      bool isDark, Function(String) onChanged) {
    return NeuField(
      isDark: isDark,
      controller: ctrl,
      label: label,
      icon: icon,
      onChanged: onChanged,
    );
  }

  Widget _tableField(TextEditingController ctrl, bool isDark, String hint,
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
