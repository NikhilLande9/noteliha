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
    final isDark      = Theme.of(context).brightness == Brightness.dark;
    final base        = Neu.base(isDark);
    final accent      = Neu.accentFromTheme(_editing.colorTheme);
    final textPrimary = Neu.textPrimary(isDark);
    final textSub     = Neu.textSecondary(isDark);

    return Scaffold(
      backgroundColor: base,
      appBar: AppBar(
        backgroundColor: base,
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

  Widget _buildNormal(bool isDark) => TextField(
        controller: _contentCtrl,
        maxLines: null,
        expands: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: 'Start writing…',
          hintStyle: TextStyle(color: Neu.textTertiary(isDark)),
        ),
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
                  child: TextField(
                    controller: _ctrl,
                    focusNode: widget.focusNode,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'New item…',
                      hintStyle:
                          TextStyle(color: Neu.textTertiary(isDark)),
                    ),
                    style: TextStyle(
                      fontSize: 15,
                      decoration: widget.item.checked
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                      color: widget.item.checked ? subColor : textColor,
                    ),
                    textInputAction: TextInputAction.next,
                    onChanged: widget.onTextChanged,
                    onSubmitted: (_) => widget.onSubmitted(),
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
  late TextEditingController _prep, _cook, _serv, _ingr, _inst;

  @override
  void initState() {
    super.initState();
    _prep = TextEditingController(text: widget.data.prepTime);
    _cook = TextEditingController(text: widget.data.cookTime);
    _serv = TextEditingController(text: widget.data.servings);
    _ingr = TextEditingController(text: widget.data.ingredients);
    _inst = TextEditingController(text: widget.data.instructions);
  }

  @override
  void dispose() {
    for (final c in [_prep, _cook, _serv, _ingr, _inst]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 12, bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: _neuField(
                isDark, _prep, 'Prep time',
                icon: Icons.timer_outlined,
                onChanged: (v) {
                  widget.data.prepTime = v;
                  widget.onChanged();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _neuField(
                isDark, _cook, 'Cook time',
                icon: Icons.local_fire_department_outlined,
                onChanged: (v) {
                  widget.data.cookTime = v;
                  widget.onChanged();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _neuField(
                isDark, _serv, 'Servings',
                icon: Icons.people_outline_rounded,
                onChanged: (v) {
                  widget.data.servings = v;
                  widget.onChanged();
                },
              ),
            ),
          ]),
          const SizedBox(height: 20),
          _SectionLabel(
              text: 'INGREDIENTS',
              icon: Icons.kitchen_outlined,
              isDark: isDark),
          const SizedBox(height: 6),
          _neuField(
            isDark, _ingr, '',
            hint: 'One ingredient per line…',
            maxLines: 6,
            onChanged: (v) {
              widget.data.ingredients = v;
              widget.onChanged();
            },
          ),
          const SizedBox(height: 20),
          _SectionLabel(
              text: 'INSTRUCTIONS',
              icon: Icons.format_list_numbered_rounded,
              isDark: isDark),
          const SizedBox(height: 6),
          _neuField(
            isDark, _inst, '',
            hint: 'Step-by-step instructions…',
            maxLines: 8,
            onChanged: (v) {
              widget.data.instructions = v;
              widget.onChanged();
            },
          ),
        ],
      ),
    );
  }

  Widget _neuField(
    bool isDark,
    TextEditingController ctrl,
    String label, {
    IconData? icon,
    String? hint,
    int maxLines = 1,
    required Function(String) onChanged,
  }) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      onChanged: onChanged,
      style: TextStyle(fontSize: 13, color: Neu.textPrimary(isDark)),
      decoration: Neu.fieldDecoration(isDark, label, icon: icon, hint: hint),
    );
  }
}
