import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';

import 'models.dart';
import 'theme_helper.dart';
import 'notes_provider.dart';

class NoteEditorScreen extends StatefulWidget {
  final Note? note;
  final NoteType noteType;

  const NoteEditorScreen(
      {super.key, this.note, this.noteType = NoteType.normal});

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late Note _editing;
  late TextEditingController _titleCtrl;
  late TextEditingController _contentCtrl;
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _editing = widget.note != null
        ? widget.note!.copyWith(
            checklistItems: List.from(widget.note!.checklistItems),
            itineraryItems: List.from(widget.note!.itineraryItems),
            mealPlanItems: List.from(widget.note!.mealPlanItems),
            imageIds: List.from(widget.note!.imageIds),
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
  }

  ColorTheme _defaultColorForTheme() {
    final appTheme =
        Provider.of<AppSettingsProvider>(context, listen: false).appTheme;
    return switch (appTheme) {
      AppTheme.amber => ColorTheme.sunset,
      AppTheme.teal => ColorTheme.default_,
      AppTheme.indigo => ColorTheme.lavender,
      AppTheme.rose => ColorTheme.rose,
      AppTheme.slate => ColorTheme.forest,
    };
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error picking image: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _save() {
    _editing.title = _titleCtrl.text.trim();
    _editing.content = _contentCtrl.text.trim();

    if (_editing.title.isEmpty &&
        _editing.content.isEmpty &&
        _editing.checklistItems.isEmpty &&
        _editing.itineraryItems.isEmpty &&
        _editing.mealPlanItems.isEmpty &&
        _editing.imageIds.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Note cannot be empty')));
      return;
    }

    Provider.of<NotesProvider>(context, listen: false).updateNote(_editing);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final noteColor =
        ThemeHelper.getThemeColor(_editing.colorTheme, isDarkMode: isDarkMode);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.note == null ? 'New Note' : 'Edit Note'),
        backgroundColor: noteColor,
        actions: [
          if (_isLoading)
            const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))),
          IconButton(
              onPressed: _save, icon: const Icon(Icons.check), tooltip: 'Save'),
          PopupMenuButton<Object>(
            onSelected: (v) {
              if (v == 'delete') {
                _showDeleteConfirmation();
              } else if (v == 'toggle_pin') {
                setState(() => _editing.pinned = !_editing.pinned);
              } else if (v == 'add_image') {
                _pickImage();
              } else if (v is ColorTheme) {
                setState(() => _editing.colorTheme = v);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'toggle_pin',
                child: Row(children: [
                  Icon(_editing.pinned
                      ? Icons.push_pin
                      : Icons.push_pin_outlined),
                  const SizedBox(width: 8),
                  Text(_editing.pinned ? 'Unpin' : 'Pin')
                ]),
              ),
              const PopupMenuItem(value: 'add_image', child: Text('Add Image')),
              const PopupMenuDivider(),
              const PopupMenuItem(
                  enabled: false,
                  child: Text('Color Theme:', style: TextStyle(fontSize: 12))),
              ...ColorTheme.values.map((theme) => PopupMenuItem(
                    value: theme,
                    child: Row(
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: ThemeHelper.getThemeColor(theme,
                                isDarkMode: isDarkMode),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        Text(ThemeHelper.getThemeName(theme)),
                        if (theme == _editing.colorTheme)
                          const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Icon(Icons.check, size: 16)),
                      ],
                    ),
                  )),
              if (widget.note != null) ...[
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    Icon(Icons.delete_outline, color: colorScheme.error),
                    const SizedBox(width: 8),
                    Text('Delete', style: TextStyle(color: colorScheme.error))
                  ]),
                ),
              ],
            ],
          ),
        ],
      ),
      body: Container(
        color: noteColor,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(
                      hintText: 'Title', border: InputBorder.none),
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    const Text('Category:'),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: _editing.category,
                      underline: const SizedBox(),
                      items: ['General', 'Work', 'Personal', 'Ideas']
                          .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) => setState(() => _editing.category = v!),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(_editing.pinned
                          ? Icons.push_pin
                          : Icons.push_pin_outlined),
                      onPressed: () =>
                          setState(() => _editing.pinned = !_editing.pinned),
                    ),
                  ],
                ),
                if (_editing.imageIds.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 120,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _editing.imageIds.length,
                      itemBuilder: (context, index) {
                        final imgId = _editing.imageIds[index];
                        final prov = Provider.of<NotesProvider>(context);
                        final b64 = prov.getImage(imgId);
                        if (b64 == null) {
                          return Container(
                            width: 100,
                            height: 100,
                            margin: const EdgeInsets.all(4),
                            color: Colors.grey.shade300,
                            child:
                                const Icon(Icons.image_not_supported_outlined),
                          );
                        }
                        return Stack(
                          children: [
                            Padding(
                                padding: const EdgeInsets.all(4),
                                child: Image.memory(base64Decode(b64),
                                    width: 100,
                                    height: 100,
                                    fit: BoxFit.cover)),
                            Positioned(
                              top: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: () async {
                                  final imageId = _editing.imageIds[index];
                                  setState(
                                      () => _editing.imageIds.removeAt(index));
                                  final prov = Provider.of<NotesProvider>(
                                      context,
                                      listen: false);
                                  final referencedByOther = prov.notes.any(
                                      (n) =>
                                          n.id != _editing.id &&
                                          n.imageIds.contains(imageId));
                                  if (!referencedByOther) {
                                    await prov.deleteImage(imageId);
                                  }
                                },
                                child: Container(
                                  decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle),
                                  padding: const EdgeInsets.all(2),
                                  child: const Icon(Icons.close,
                                      size: 14, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Expanded(child: _buildBody()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Note'),
        content: const Text('Move to recycle bin?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Provider.of<NotesProvider>(context, listen: false)
                  .softDelete(_editing.id);
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() => switch (_editing.noteType) {
        NoteType.normal => _buildNormal(),
        NoteType.checklist => _buildChecklist(),
        NoteType.itinerary => _buildItinerary(),
        NoteType.mealPlan => _buildMealPlan(),
        NoteType.recipe => _buildRecipe(),
      };

  Widget _buildNormal() => TextField(
        controller: _contentCtrl,
        maxLines: null,
        expands: true,
        decoration: const InputDecoration(
            border: InputBorder.none, hintText: 'Start typing...'),
      );

  Widget _buildChecklist() => Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _editing.checklistItems.length,
              itemBuilder: (_, i) {
                final item = _editing.checklistItems[i];
                return _ChecklistItemTile(
                  item: item,
                  onChanged: (v) => setState(() => item.checked = v),
                  onDelete: () =>
                      setState(() => _editing.checklistItems.removeAt(i)),
                  onTextChanged: (text) => setState(() => item.text = text),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: ElevatedButton.icon(
              onPressed: () => setState(() => _editing.checklistItems
                  .add(ChecklistItem(id: const Uuid().v4(), text: ''))),
              icon: const Icon(Icons.add),
              label: const Text('Add Item'),
            ),
          ),
        ],
      );

  Widget _buildItinerary() => Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _editing.itineraryItems.length,
              itemBuilder: (_, i) {
                final item = _editing.itineraryItems[i];
                return _ItineraryItemCard(
                  item: item,
                  onDelete: () =>
                      setState(() => _editing.itineraryItems.removeAt(i)),
                  onChanged: () => setState(() {}),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: ElevatedButton.icon(
              onPressed: () => setState(() => _editing.itineraryItems
                  .add(ItineraryItem(id: const Uuid().v4()))),
              icon: const Icon(Icons.add),
              label: const Text('Add Destination'),
            ),
          ),
        ],
      );

  Widget _buildMealPlan() => Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _editing.mealPlanItems.length,
              itemBuilder: (_, i) {
                final item = _editing.mealPlanItems[i];
                return _MealPlanItemCard(
                  item: item,
                  onDelete: () =>
                      setState(() => _editing.mealPlanItems.removeAt(i)),
                  onChanged: () => setState(() {}),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: ElevatedButton.icon(
              onPressed: () => setState(() => _editing.mealPlanItems
                  .add(MealPlanItem(id: const Uuid().v4()))),
              icon: const Icon(Icons.add),
              label: const Text('Add Day'),
            ),
          ),
        ],
      );

  Widget _buildRecipe() {
    _editing.recipeData ??= RecipeData();
    return _RecipeCard(
        data: _editing.recipeData!, onChanged: () => setState(() {}));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Checklist Item Tile
// ─────────────────────────────────────────────────────────────────────────────

class _ChecklistItemTile extends StatefulWidget {
  final ChecklistItem item;
  final Function(bool) onChanged;
  final VoidCallback onDelete;
  final Function(String) onTextChanged;

  const _ChecklistItemTile({
    required this.item,
    required this.onChanged,
    required this.onDelete,
    required this.onTextChanged,
  });

  @override
  State<_ChecklistItemTile> createState() => _ChecklistItemTileState();
}

class _ChecklistItemTileState extends State<_ChecklistItemTile> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.item.text);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Checkbox(
              value: widget.item.checked,
              onChanged: (v) => widget.onChanged(v ?? false)),
          Expanded(
            child: TextField(
              controller: _ctrl,
              decoration: const InputDecoration(
                  border: InputBorder.none, hintText: 'Enter item...'),
              style: TextStyle(
                decoration: widget.item.checked
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
                color: widget.item.checked ? Colors.grey : null,
              ),
              onChanged: widget.onTextChanged,
            ),
          ),
          IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: widget.onDelete),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Itinerary Item Card
// ─────────────────────────────────────────────────────────────────────────────

class _ItineraryItemCard extends StatefulWidget {
  final ItineraryItem item;
  final VoidCallback onDelete;
  final VoidCallback onChanged;

  const _ItineraryItemCard(
      {required this.item, required this.onDelete, required this.onChanged});

  @override
  State<_ItineraryItemCard> createState() => _ItineraryItemCardState();
}

class _ItineraryItemCardState extends State<_ItineraryItemCard> {
  late TextEditingController _loc, _date, _arr, _dep, _notes;

  @override
  void initState() {
    super.initState();
    _loc = TextEditingController(text: widget.item.location);
    _date = TextEditingController(text: widget.item.date);
    _arr = TextEditingController(text: widget.item.arrivalTime);
    _dep = TextEditingController(text: widget.item.departureTime);
    _notes = TextEditingController(text: widget.item.notes);
  }

  @override
  void dispose() {
    _loc.dispose();
    _date.dispose();
    _arr.dispose();
    _dep.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _loc,
                      decoration: const InputDecoration(
                          labelText: 'Location', border: OutlineInputBorder()),
                      onChanged: (v) {
                        widget.item.location = v;
                        widget.onChanged();
                      },
                    ),
                  ),
                  IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: widget.onDelete),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                  controller: _date,
                  decoration: const InputDecoration(
                      labelText: 'Date', border: OutlineInputBorder()),
                  onChanged: (v) {
                    widget.item.date = v;
                    widget.onChanged();
                  }),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                      child: TextField(
                          controller: _arr,
                          decoration: const InputDecoration(
                              labelText: 'Arrival',
                              border: OutlineInputBorder()),
                          onChanged: (v) {
                            widget.item.arrivalTime = v;
                            widget.onChanged();
                          })),
                  const SizedBox(width: 8),
                  Expanded(
                      child: TextField(
                          controller: _dep,
                          decoration: const InputDecoration(
                              labelText: 'Departure',
                              border: OutlineInputBorder()),
                          onChanged: (v) {
                            widget.item.departureTime = v;
                            widget.onChanged();
                          })),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                  controller: _notes,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'Notes', border: OutlineInputBorder()),
                  onChanged: (v) {
                    widget.item.notes = v;
                    widget.onChanged();
                  }),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Meal Plan Item Card
// ─────────────────────────────────────────────────────────────────────────────

class _MealPlanItemCard extends StatefulWidget {
  final MealPlanItem item;
  final VoidCallback onDelete;
  final VoidCallback onChanged;

  const _MealPlanItemCard(
      {required this.item, required this.onDelete, required this.onChanged});

  @override
  State<_MealPlanItemCard> createState() => _MealPlanItemCardState();
}

class _MealPlanItemCardState extends State<_MealPlanItemCard> {
  late TextEditingController _day, _bfast, _lunch, _dinner, _snacks;

  @override
  void initState() {
    super.initState();
    _day = TextEditingController(text: widget.item.day);
    _bfast = TextEditingController(text: widget.item.breakfast);
    _lunch = TextEditingController(text: widget.item.lunch);
    _dinner = TextEditingController(text: widget.item.dinner);
    _snacks = TextEditingController(text: widget.item.snacks);
  }

  @override
  void dispose() {
    _day.dispose();
    _bfast.dispose();
    _lunch.dispose();
    _dinner.dispose();
    _snacks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                      child: TextField(
                          controller: _day,
                          decoration: const InputDecoration(
                              labelText: 'Day', border: OutlineInputBorder()),
                          onChanged: (v) {
                            widget.item.day = v;
                            widget.onChanged();
                          })),
                  IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: widget.onDelete),
                ],
              ),
              const SizedBox(height: 8),
              for (final pair in [
                (_bfast, 'Breakfast', (String v) => widget.item.breakfast = v),
                (_lunch, 'Lunch', (String v) => widget.item.lunch = v),
                (_dinner, 'Dinner', (String v) => widget.item.dinner = v),
                (_snacks, 'Snacks', (String v) => widget.item.snacks = v),
              ]) ...[
                TextField(
                  controller: pair.$1,
                  decoration: InputDecoration(
                      labelText: pair.$2, border: const OutlineInputBorder()),
                  onChanged: (v) {
                    pair.$3(v);
                    widget.onChanged();
                  },
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Recipe Card
// ─────────────────────────────────────────────────────────────────────────────

class _RecipeCard extends StatefulWidget {
  final RecipeData data;
  final VoidCallback onChanged;

  const _RecipeCard({required this.data, required this.onChanged});

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
    _prep.dispose();
    _cook.dispose();
    _serv.dispose();
    _ingr.dispose();
    _inst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: TextField(
                        controller: _prep,
                        decoration: const InputDecoration(
                            labelText: 'Prep Time',
                            border: OutlineInputBorder()),
                        onChanged: (v) {
                          widget.data.prepTime = v;
                          widget.onChanged();
                        })),
                const SizedBox(width: 8),
                Expanded(
                    child: TextField(
                        controller: _cook,
                        decoration: const InputDecoration(
                            labelText: 'Cook Time',
                            border: OutlineInputBorder()),
                        onChanged: (v) {
                          widget.data.cookTime = v;
                          widget.onChanged();
                        })),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
                controller: _serv,
                decoration: const InputDecoration(
                    labelText: 'Servings', border: OutlineInputBorder()),
                onChanged: (v) {
                  widget.data.servings = v;
                  widget.onChanged();
                }),
            const SizedBox(height: 16),
            const Text('Ingredients',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
                controller: _ingr,
                maxLines: 6,
                decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'List ingredients...'),
                onChanged: (v) {
                  widget.data.ingredients = v;
                  widget.onChanged();
                }),
            const SizedBox(height: 16),
            const Text('Instructions',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
                controller: _inst,
                maxLines: 8,
                decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Step-by-step instructions...'),
                onChanged: (v) {
                  widget.data.instructions = v;
                  widget.onChanged();
                }),
            const SizedBox(height: 24),
          ],
        ),
      );
}
