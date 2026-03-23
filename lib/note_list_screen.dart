import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'models.dart';
import 'neu_theme.dart';
import 'notes_provider.dart';
import 'note_editor_screen.dart';
import 'settings_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Note Card — Neumorphic
// ─────────────────────────────────────────────────────────────────────────────

class NoteCard extends StatelessWidget {
  final Note note;
  const NoteCard({required this.note, super.key});

  // Returns a plain-text string for non-normal note types (checklist etc.)
  // and null for normal notes (which use _buildNormalPreview for rich text).
  String? _previewText() => switch (note.noteType) {
    NoteType.normal    => null, // handled by _buildNormalPreview
    NoteType.checklist => () {
      final total    = note.checklistItems.length;
      final done     = note.checklistItems.where((i) => i.checked).length;
      final itemWord = total == 1 ? 'item' : 'items';
      return '$total $itemWord · $done done';
    }(),
    NoteType.itinerary => '${note.itineraryItems.length} destinations',
    NoteType.mealPlan  => '${note.mealPlanItems.length} days planned',
    NoteType.recipe    => note.recipeData?.ingredients ??
        RichContentCodec.plainText(note.content),
  };

  // Builds a rich-text preview for normal notes, respecting bold/italic ranges.
  Widget _buildNormalPreview(Color subColor) {
    final decoded   = RichContentCodec.decode(note.content);
    final plainText = decoded.text;
    final ranges    = decoded.ranges;

    if (plainText.isEmpty) return const SizedBox.shrink();

    final base = TextStyle(
      fontSize: 12.5,
      color: subColor,
      height: 1.45,
      fontWeight: FontWeight.w400,
      fontStyle: FontStyle.normal,
    );

    final len    = plainText.length;
    final bold   = List<bool>.filled(len, false);
    final italic = List<bool>.filled(len, false);

    // Apply user-defined bold/italic ranges
    for (final r in ranges) {
      if (r.type == FormatType.bold) {
        for (int i = r.start; i < r.end && i < len; i++) { bold[i] = true; }
      } else {
        for (int i = r.start; i < r.end && i < len; i++) { italic[i] = true; }
      }
    }

    // Bold list prefix characters (• / 1. etc.) — does NOT override user italic
    int lineOff = 0;
    for (final line in plainText.split('\n')) {
      final m = RegExp(r'^(• |\d+\. )').firstMatch(line);
      if (m != null) {
        for (int i = lineOff; i < lineOff + m.end && i < len; i++) {
          bold[i] = true;   // prefix is always bold
          italic[i] = false; // prefix is never italic
        }
      }
      lineOff += line.length + 1;
    }

    // Build spans across the entire plain text (card preview is a single block)
    final spans  = <InlineSpan>[];
    int   i      = 0;
    while (i < len) {
      final isBold   = bold[i];
      final isItalic = italic[i];
      int j = i + 1;
      while (j < len && bold[j] == isBold && italic[j] == isItalic) { j++; }
      spans.add(TextSpan(
        text: plainText.substring(i, j),
        style: base.copyWith(
          fontWeight: isBold   ? FontWeight.w800 : FontWeight.w400,
          fontStyle:  isItalic ? FontStyle.italic  : FontStyle.normal,
        ),
      ));
      i = j;
    }

    return RichText(
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(children: spans),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final accentColor = Neu.accentFromTheme(note.colorTheme);
    final textColor = Neu.textPrimary(isDark);
    final subColor = Neu.textSecondary(isDark);
    final previewText = _previewText(); // null for normal notes

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: Neu.cardDecoration(note.colorTheme, isDark),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Navigator.push(
            context,
            _SlideRoute(builder: (_) => NoteEditorScreen(note: note)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 3,
                  width: 32,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: accentColor.withAlpha(isDark ? 180 : 200),
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withAlpha(80),
                        blurRadius: 6,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                ),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (note.pinned)
                      Padding(
                        padding: const EdgeInsets.only(right: 5, top: 1),
                        child: Icon(Icons.push_pin_rounded,
                            size: 13,
                            color: accentColor.withAlpha(180)),
                      ),
                    Expanded(
                      child: Text(
                        note.title.isNotEmpty ? note.title : 'Untitled',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          color: textColor,
                          height: 1.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                // Normal notes: rich preview with bold/italic.
                // All other types: plain text string.
                if (note.noteType == NoteType.normal) ...[
                  const SizedBox(height: 6),
                  _buildNormalPreview(subColor),
                ] else if (previewText != null && previewText.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    previewText,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: subColor,
                      height: 1.45,
                    ),
                  ),
                ],

                if (note.imageIds.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(children: [
                    Icon(Icons.photo_library_outlined,
                        size: 12, color: subColor),
                    const SizedBox(width: 3),
                    Text(
                      '${note.imageIds.length} image${note.imageIds.length == 1 ? '' : 's'}',
                      style: TextStyle(fontSize: 11, color: subColor),
                    ),
                  ]),
                ],

                const SizedBox(height: 14),

                Row(
                  children: [
                    _NeuTypeChip(
                        note: note, isDark: isDark, accent: accentColor),
                    const SizedBox(width: 6),
                    _NeuCategoryChip(
                        note: note, isDark: isDark, accent: accentColor),
                    const Spacer(),
                    Text(
                      _formatDate(note.updatedAt),
                      style: TextStyle(
                        fontSize: 10.5,
                        color: subColor,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Eye icon — opens full preview modal
                    GestureDetector(
                      onTap: () => _NotePreviewSheet.show(context, note),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Neu.base(isDark),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: Neu.raisedSm(isDark),
                        ),
                        child: Icon(
                          Icons.remove_red_eye_outlined,
                          size: 14,
                          color: subColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return DateFormat('EEEE').format(dt);
    return DateFormat('MMM d').format(dt);
  }
}

class _NeuTypeChip extends StatelessWidget {
  final Note note;
  final bool isDark;
  final Color accent;
  const _NeuTypeChip(
      {required this.note, required this.isDark, required this.accent});

  /// Human-readable label including space for MealPlan
  static String _noteTypeLabel(NoteType type) => switch (type) {
    NoteType.normal => 'Note',
    NoteType.checklist => 'Checklist',
    NoteType.itinerary => 'Itinerary',
    NoteType.mealPlan => 'Meal Plan',
    NoteType.recipe => 'Recipe',
  };

  @override
  Widget build(BuildContext context) {
    final labelColor = Neu.textSecondary(isDark);
    final iconColor = accent.withAlpha(isDark ? 230 : 200);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Neu.base(isDark),
        borderRadius: BorderRadius.circular(10),
        boxShadow: Neu.inset(isDark),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _noteTypeIconData(note.noteType),
            size: 13,
            color: iconColor,
          ),
          const SizedBox(width: 5),
          Text(
            _noteTypeLabel(note.noteType),
            style: TextStyle(
              fontSize: 10.5,
              color: labelColor,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }

  static IconData _noteTypeIconData(NoteType type) => switch (type) {
    NoteType.normal => Icons.note_rounded,
    NoteType.checklist => Icons.check_box_rounded,
    NoteType.itinerary => Icons.flight_rounded,
    NoteType.mealPlan => Icons.restaurant_menu_rounded,
    NoteType.recipe => Icons.menu_book_rounded,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Category chip — shown next to the type chip on each note card
// ─────────────────────────────────────────────────────────────────────────────

class _NeuCategoryChip extends StatelessWidget {
  final Note note;
  final bool isDark;
  final Color accent;

  const _NeuCategoryChip(
      {required this.note, required this.isDark, required this.accent});

  static IconData _categoryIcon(String category) => switch (category) {
    'Work'     => Icons.work_outline_rounded,
    'Personal' => Icons.person_outline_rounded,
    'Ideas'    => Icons.lightbulb_outline_rounded,
    _          => Icons.notes_rounded, // General + any custom category
  };

  @override
  Widget build(BuildContext context) {
    final labelColor = Neu.textSecondary(isDark);
    final iconColor  = accent.withAlpha(isDark ? 230 : 200);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Neu.base(isDark),
        borderRadius: BorderRadius.circular(10),
        boxShadow: Neu.inset(isDark),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_categoryIcon(note.category), size: 13, color: iconColor),
          const SizedBox(width: 5),
          Text(
            note.category,
            style: TextStyle(
              fontSize: 10.5,
              color: labelColor,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Note List Screen
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// Sort mode
// ─────────────────────────────────────────────────────────────────────────────

enum _SortMode {
  dateDesc,   // Newest first (default)
  dateAsc,    // Oldest first
  category,   // Grouped by category: General → Work → Personal → Ideas
}

class NoteListScreen extends StatefulWidget {
  const NoteListScreen({super.key});

  @override
  State<NoteListScreen> createState() => _NoteListScreenState();
}

class _NoteListScreenState extends State<NoteListScreen> {
  String _searchQuery = '';
  bool _searchActive = false;
  _SortMode _sortMode = _SortMode.dateDesc;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _debounceTimer;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _activateSearch() {
    setState(() {
      _searchActive = true;
      _searchQuery = '';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _deactivateSearch() {
    _debounceTimer?.cancel();
    _searchController.clear();
    _searchFocus.unfocus();
    setState(() {
      _searchActive = false;
      _searchQuery = '';
    });
  }

  List<Note> _filterNotes(List<Note> notes, String query) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return notes;
    return notes.where((n) {
      if (n.title.toLowerCase().contains(q)) return true;
      if (n.content.toLowerCase().contains(q)) return true;
      if (n.category.toLowerCase().contains(q)) return true;
      if (n.checklistItems
          .any((i) => i.text.toLowerCase().contains(q))) {
        return true;
      }
      if (n.itineraryItems.any((i) =>
      i.location.toLowerCase().contains(q) ||
          i.notes.toLowerCase().contains(q) ||
          i.date.toLowerCase().contains(q))) {
        return true;
      }
      if (n.mealPlanItems.any((i) =>
      i.day.toLowerCase().contains(q) ||
          i.meals.any((m) =>
          (m['value'] as String?)?.toLowerCase().contains(q) ??
              false))) {
        return true;
      }
      if (n.recipeData != null) {
        final r = n.recipeData!;
        if (r.ingredients.toLowerCase().contains(q)) return true;
        if (r.instructions.toLowerCase().contains(q)) return true;
      }
      return false;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final prov = Provider.of<NotesProvider>(context);
    final base = Neu.base(isDark);

    final allNotes = _searchQuery.isEmpty
        ? prov.notes
        : _filterNotes(prov.notes, _searchQuery);

    // Apply sort mode
    final notes = _sortedNotes(allNotes);

    final pinned   = notes.where((n) => n.pinned).toList();
    final unpinned = notes.where((n) => !n.pinned).toList();

    return Scaffold(
      backgroundColor: base,
      appBar: _buildAppBar(context, prov, isDark),
      body: allNotes.isEmpty
          ? _buildEmptyState(isDark)
          : _sortMode == _SortMode.category
          ? _buildCategoryList(context, prov, isDark, notes)
          : _buildNoteList(context, prov, isDark, pinned, unpinned),
      floatingActionButton: _buildFAB(context, isDark),
    );
  }

  PreferredSizeWidget _buildAppBar(
      BuildContext context, NotesProvider prov, bool isDark) {
    final textColor = Neu.textPrimary(isDark);
    final subColor = Neu.textSecondary(isDark);
    final accentColor = Theme.of(context).colorScheme.primary;

    return AppBar(
      backgroundColor: Neu.base(isDark),
      scrolledUnderElevation: 0,
      elevation: 0,
      titleSpacing: 20,
      title: _searchActive
          ? _buildSearchField(isDark)
          : _buildLogoTitle(isDark, accentColor, textColor),
      actions: [
        if (!_searchActive) ...[
          if (prov.syncConflicts.isNotEmpty)
            NeuIconButton(
              isDark: isDark,
              icon: Badge(
                label: Text('${prov.syncConflicts.length}'),
                child:
                Icon(Icons.warning_amber_rounded, color: subColor),
              ),
              onTap: () => _showConflictsSheet(context, prov),
            ),
          const SizedBox(width: 6),
          // Sort button — badge dot when non-default
          Stack(
            clipBehavior: Clip.none,
            children: [
              NeuIconButton(
                isDark: isDark,
                icon: Icon(Icons.sort_rounded, color: subColor),
                onTap: () => _showSortSheet(context, isDark),
              ),
              if (_sortMode != _SortMode.dateDesc)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 6),
          NeuIconButton(
            isDark: isDark,
            icon: Icon(Icons.search_rounded, color: subColor),
            onTap: _activateSearch,
          ),
          const SizedBox(width: 6),
          NeuIconButton(
            isDark: isDark,
            icon: Icon(Icons.settings_outlined, color: subColor),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ] else ...[
          TextButton(
            onPressed: _deactivateSearch,
            child: Text('Cancel',
                style: TextStyle(
                    color: accentColor, fontWeight: FontWeight.w600)),
          ),
        ],
        const SizedBox(width: 10),
      ],
    );
  }

  Widget _buildLogoTitle(bool isDark, Color accent, Color textColor) =>
      RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: 'note',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: textColor,
                letterSpacing: -0.8,
              ),
            ),
            TextSpan(
              text: 'liha',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: accent,
                letterSpacing: -0.8,
              ),
            ),
          ],
        ),
      );

  Widget _buildSearchField(bool isDark) {
    final textColor = Neu.textPrimary(isDark);
    final subColor = Neu.textSecondary(isDark);

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Neu.inputFill(isDark),
        borderRadius: BorderRadius.circular(12),
        boxShadow: Neu.inset(isDark),
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocus,
        onChanged: (q) {
          _debounceTimer?.cancel();
          _debounceTimer = Timer(const Duration(milliseconds: 250), () {
            if (mounted) setState(() => _searchQuery = q);
          });
        },
        decoration: InputDecoration(
          hintText: 'Search notes…',
          hintStyle: TextStyle(color: subColor, fontSize: 14),
          border: InputBorder.none,
          contentPadding:
          const EdgeInsets.symmetric(vertical: 10),
          prefixIcon:
          Icon(Icons.search_rounded, color: subColor, size: 18),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
            icon: Icon(Icons.close_rounded,
                size: 16, color: subColor),
            onPressed: () {
              _debounceTimer?.cancel();
              _searchController.clear();
              setState(() => _searchQuery = '');
              _searchFocus.requestFocus();
            },
          )
              : null,
        ),
        style: TextStyle(
            fontSize: 14,
            color: textColor,
            fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    final textColor = Neu.textPrimary(isDark);
    final subColor = Neu.textSecondary(isDark);
    final accentColor = Theme.of(context).colorScheme.primary;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          NeuContainer(
            isDark: isDark,
            radius: 36,
            padding: const EdgeInsets.all(22),
            child: Icon(
              _searchQuery.isEmpty
                  ? Icons.edit_note_rounded
                  : Icons.search_off_rounded,
              size: 36,
              color: accentColor.withAlpha(180),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _searchQuery.isEmpty ? 'No notes yet' : 'Nothing found',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _searchQuery.isEmpty
                ? 'Tap + to create your first note'
                : 'Try a different search term',
            style: TextStyle(fontSize: 14, color: subColor),
          ),
        ],
      ),
    );
  }

  // ── Category order ────────────────────────────────────────────────────────
  static const _categoryOrder = ['General', 'Work', 'Personal', 'Ideas'];

  List<Note> _sortedNotes(List<Note> notes) {
    final list = List<Note>.from(notes);
    switch (_sortMode) {
      case _SortMode.dateDesc:
      // Provider already returns pinned-first then date-desc; preserve it
        return list;
      case _SortMode.dateAsc:
        list.sort((a, b) {
          if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
          return a.updatedAt.compareTo(b.updatedAt);
        });
        return list;
      case _SortMode.category:
      // Sorted by category order, then pinned within each group, then date
        list.sort((a, b) {
          final aiRaw = _categoryOrder.indexOf(a.category);
          final biRaw = _categoryOrder.indexOf(b.category);
          final ai = aiRaw == -1 ? 99 : aiRaw;
          final bi = biRaw == -1 ? 99 : biRaw;
          if (ai != bi) return ai.compareTo(bi);
          if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
          return b.updatedAt.compareTo(a.updatedAt);
        });
        return list;
    }
  }

  void _showSortSheet(BuildContext context, bool isDark) {
    final base      = Neu.base(isDark);
    final textColor = Neu.textPrimary(isDark);
    final accent    = Theme.of(context).colorScheme.primary;

    showModalBottomSheet(
      context: context,
      backgroundColor: base,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) {
        final bottomInset = MediaQuery.of(context).padding.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Neu.textTertiary(isDark).withAlpha(80),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 12),
                child: Text('Sort by',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: textColor)),
              ),
              ...[
                (_SortMode.dateDesc, Icons.arrow_downward_rounded,  'Newest first'),
                (_SortMode.dateAsc,  Icons.arrow_upward_rounded,    'Oldest first'),
                (_SortMode.category, Icons.label_outline_rounded,   'Category'),
              ].map((entry) {
                final (mode, icon, label) = entry;
                final selected = _sortMode == mode;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: NeuPressable(
                    isDark: isDark,
                    radius: 14,
                    onTap: () {
                      setState(() => _sortMode = mode);
                      Navigator.pop(context);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 13),
                      child: Row(
                        children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: Neu.base(isDark),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: selected
                                  ? Neu.inset(isDark)
                                  : Neu.raisedSm(isDark),
                            ),
                            child: Icon(icon,
                                size: 17,
                                color: selected
                                    ? accent
                                    : Neu.textSecondary(isDark)),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(label,
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: selected
                                        ? accent
                                        : textColor)),
                          ),
                          if (selected)
                            Icon(Icons.check_rounded,
                                size: 18, color: accent),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  // Category view: one section per category that has notes
  Widget _buildCategoryList(
      BuildContext context,
      NotesProvider prov,
      bool isDark,
      List<Note> notes,
      ) {
    // Build ordered list of categories that actually have notes
    final present = <String>[];
    for (final cat in _categoryOrder) {
      if (notes.any((n) => n.category == cat)) present.add(cat);
    }
    // Any categories not in the known list (user-custom) go at the end
    for (final n in notes) {
      if (!present.contains(n.category)) present.add(n.category);
    }

    final categoryIcons = <String, IconData>{
      'General':  Icons.notes_rounded,
      'Work':     Icons.work_outline_rounded,
      'Personal': Icons.person_outline_rounded,
      'Ideas':    Icons.lightbulb_outline_rounded,
    };

    return CustomScrollView(
      slivers: [
        for (final cat in present) ...[
          SliverToBoxAdapter(
            child: _SectionLabel(
              text: cat,
              icon: categoryIcons[cat] ?? Icons.label_outline_rounded,
              isDark: isDark,
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
                14, 0, 14, present.last == cat ? 100 : 4),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                  final catNotes = notes
                      .where((n) => n.category == cat)
                      .toList();
                  return _buildDismissibleCard(
                      ctx, prov, catNotes[i], isDark);
                },
                childCount:
                notes.where((n) => n.category == cat).length,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildNoteList(
      BuildContext context,
      NotesProvider prov,
      bool isDark,
      List<Note> pinned,
      List<Note> unpinned,
      ) {
    return CustomScrollView(
      slivers: [
        if (pinned.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _SectionLabel(
                text: 'Pinned',
                icon: Icons.push_pin_rounded,
                isDark: isDark),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                    (ctx, i) =>
                    _buildDismissibleCard(ctx, prov, pinned[i], isDark),
                childCount: pinned.length,
              ),
            ),
          ),
        ],
        if (unpinned.isNotEmpty) ...[
          if (pinned.isNotEmpty)
            SliverToBoxAdapter(
              child: _SectionLabel(
                  text: 'Notes',
                  icon: Icons.notes_rounded,
                  isDark: isDark),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 100),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                    (ctx, i) =>
                    _buildDismissibleCard(ctx, prov, unpinned[i], isDark),
                childCount: unpinned.length,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDismissibleCard(
      BuildContext context, NotesProvider prov, Note n, bool isDark) {
    final hasConflict =
    prov.syncConflicts.any((ns) => ns.noteId == n.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: Key(n.id),
        background: Container(
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF2A1A1A)
                : const Color(0xFFFFE8E8),
            borderRadius: BorderRadius.circular(20),
            boxShadow: Neu.raised(isDark),
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.delete_outline_rounded,
                  color: Colors.red.shade400, size: 22),
              const SizedBox(height: 4),
              Text('Delete',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.red.shade400,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) async {
          return await showDialog<bool>(
            context: context,
            builder: (ctx) => _NeuAlertDialog(isDark: isDark),
          ) ??
              false;
        },
        onDismissed: (_) =>
            Provider.of<NotesProvider>(context, listen: false)
                .softDelete(n.id),
        child: Stack(
          children: [
            NoteCard(note: n),
            if (hasConflict)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                      color: Colors.orange, shape: BoxShape.circle),
                  child: const Icon(Icons.warning_amber_rounded,
                      size: 12, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFAB(BuildContext context, bool isDark) {
    final accent = Theme.of(context).colorScheme.primary;
    final onAccent = Theme.of(context).colorScheme.onPrimary;
    return GestureDetector(
      onTap: () => _showNoteTypeDialog(context, isDark),
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: accent.withAlpha(100),
              offset: const Offset(-4, -4),
              blurRadius: 10,
            ),
            BoxShadow(
              color: accent.withAlpha(160),
              offset: const Offset(4, 4),
              blurRadius: 10,
            ),
          ],
        ),
        child: Icon(Icons.add_rounded, size: 28, color: onAccent),
      ),
    );
  }

  void _showNoteTypeDialog(BuildContext context, bool isDark) {
    final base = Neu.base(isDark);
    final textColor = Neu.textPrimary(isDark);

    showModalBottomSheet(
      context: context,
      backgroundColor: base,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (context) {
        final bottomInset = MediaQuery.of(context).padding.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: base,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: Neu.inset(isDark),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 12),
                child: Text(
                  'New note',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              ...NoteType.values.map((type) {
                // Use the same human-readable label as the chip
                final label = _NeuTypeChip._noteTypeLabel(type);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: NeuPressable(
                    isDark: isDark,
                    radius: 14,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        _SlideRoute(
                            builder: (_) =>
                                NoteEditorScreen(noteType: type)),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: base,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: Neu.inset(isDark),
                            ),
                            child: Center(
                              child: Icon(
                                _NeuTypeChip._noteTypeIconData(type),
                                size: 18,
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Text(label,
                              style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 15,
                                  color: textColor)),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showConflictsSheet(BuildContext context, NotesProvider prov) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = Neu.base(isDark);
    final textColor = Neu.textPrimary(isDark);
    final subColor = Neu.textSecondary(isDark);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: base,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (_, scrollCtrl) {
          final bottomInset = MediaQuery.of(ctx).padding.bottom;
          return Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottomInset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: base,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: Neu.inset(isDark),
                    ),
                  ),
                ),
                Row(children: [
                  NeuContainer(
                    isDark: isDark,
                    radius: 10,
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.warning_amber_rounded,
                        color: Colors.orange.shade600, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Sync conflicts',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const Spacer(),
                  NeuContainer(
                    isDark: isDark,
                    radius: 20,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    child: Text(
                      '${prov.syncConflicts.length}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.orange.shade600),
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Text(
                  'These notes were modified on multiple devices.',
                  style: TextStyle(fontSize: 13, color: subColor),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    children: prov.syncConflicts.map((ns) {
                      final localNote = prov.notes.firstWhere(
                            (n) => n.id == ns.noteId,
                        orElse: () => Note(
                            id: ns.noteId,
                            title: '(Deleted)',
                            content: '',
                            updatedAt: DateTime.now()),
                      );
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: NeuContainer(
                          isDark: isDark,
                          radius: 16,
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                localNote.title.isNotEmpty
                                    ? localNote.title
                                    : 'Untitled',
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                    color: textColor),
                              ),
                              const SizedBox(height: 6),
                              Row(children: [
                                _ConflictTimestamp(
                                    label: 'Local',
                                    dt: localNote.updatedAt,
                                    isDark: isDark),
                                const SizedBox(width: 14),
                                _ConflictTimestamp(
                                    label: 'Remote',
                                    dt: ns.conflict!.remoteVersion.updatedAt,
                                    isDark: isDark),
                              ]),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: _NeuConflictButton(
                                      label: 'Keep local',
                                      icon: Icons.phone_android_rounded,
                                      isDark: isDark,
                                      onTap: () {
                                        prov.resolveConflictKeepLocal(
                                            ns.noteId);
                                        if (prov.syncConflicts.isEmpty) {
                                          Navigator.pop(ctx);
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _NeuConflictButton(
                                      label: 'Keep remote',
                                      icon: Icons.cloud_outlined,
                                      isDark: isDark,
                                      onTap: () {
                                        prov.resolveConflictKeepRemote(
                                            ns.noteId);
                                        if (prov.syncConflicts.isEmpty) {
                                          Navigator.pop(ctx);
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _NeuConflictButton(
                                      label: 'Keep both',
                                      icon: Icons.call_merge_rounded,
                                      isDark: isDark,
                                      onTap: () {
                                        prov.resolveConflictKeepBoth(
                                            ns.noteId);
                                        if (prov.syncConflicts.isEmpty) {
                                          Navigator.pop(ctx);
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Neumorphic Alert Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _NeuAlertDialog extends StatelessWidget {
  final bool isDark;
  const _NeuAlertDialog({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final base = Neu.base(isDark);
    final textColor = Neu.textPrimary(isDark);
    final subColor = Neu.textSecondary(isDark);

    return Dialog(
      backgroundColor: base,
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Container(
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(22),
          boxShadow: Neu.raised(isDark),
        ),
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Delete note?',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: textColor)),
            const SizedBox(height: 8),
            Text('This note will be moved to the recycle bin.',
                style: TextStyle(fontSize: 14, color: subColor)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _NeuTextButton(
                  label: 'Cancel',
                  isDark: isDark,
                  onTap: () => Navigator.pop(context, false),
                ),
                const SizedBox(width: 10),
                _NeuDeleteButton(
                  isDark: isDark,
                  onTap: () => Navigator.pop(context, true),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NeuTextButton extends StatefulWidget {
  final String label;
  final bool isDark;
  final VoidCallback onTap;
  const _NeuTextButton(
      {required this.label, required this.isDark, required this.onTap});

  @override
  State<_NeuTextButton> createState() => _NeuTextButtonState();
}

class _NeuTextButtonState extends State<_NeuTextButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final subColor = Neu.textSecondary(widget.isDark);
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
                color: subColor)),
      ),
    );
  }
}

class _NeuDeleteButton extends StatefulWidget {
  final bool isDark;
  final VoidCallback onTap;
  const _NeuDeleteButton({required this.isDark, required this.onTap});

  @override
  State<_NeuDeleteButton> createState() => _NeuDeleteButtonState();
}

class _NeuDeleteButtonState extends State<_NeuDeleteButton> {
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        padding:
        const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: _pressed
              ? (widget.isDark
              ? const Color(0xFF2A1A1A)
              : const Color(0xFFFFE8E8))
              : Neu.base(widget.isDark),
          borderRadius: BorderRadius.circular(12),
          boxShadow: _pressed
              ? Neu.inset(widget.isDark)
              : Neu.raisedSm(widget.isDark),
        ),
        child: Text('Delete',
            style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Colors.red.shade400)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small helpers
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  final IconData icon;
  final bool isDark;
  const _SectionLabel(
      {required this.text, required this.icon, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final subColor = Neu.textSecondary(isDark);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
      child: Row(children: [
        Icon(icon, size: 13, color: subColor),
        const SizedBox(width: 5),
        Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: subColor,
          ),
        ),
      ]),
    );
  }
}

class _ConflictTimestamp extends StatelessWidget {
  final String label;
  final DateTime dt;
  final bool isDark;
  const _ConflictTimestamp(
      {required this.label, required this.dt, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final subColor = Neu.textSecondary(isDark);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: subColor)),
        Text(
          DateFormat('MMM d, HH:mm').format(dt),
          style: TextStyle(fontSize: 11, color: subColor),
        ),
      ],
    );
  }
}

class _NeuConflictButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;
  const _NeuConflictButton(
      {required this.label,
        required this.icon,
        required this.isDark,
        required this.onTap});

  @override
  State<_NeuConflictButton> createState() => _NeuConflictButtonState();
}

class _NeuConflictButtonState extends State<_NeuConflictButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final accentColor = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Neu.base(widget.isDark),
          borderRadius: BorderRadius.circular(12),
          boxShadow: _pressed
              ? Neu.inset(widget.isDark)
              : Neu.raisedSm(widget.isDark),
        ),
        child: Column(
          children: [
            Icon(widget.icon, size: 16, color: accentColor),
            const SizedBox(height: 3),
            Text(widget.label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: accentColor)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Note Preview Sheet — full-content modal shown via eye icon
// ─────────────────────────────────────────────────────────────────────────────

class _NotePreviewSheet {
  static void show(BuildContext context, Note note) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _NotePreviewContent(note: note),
    );
  }
}

class _NotePreviewContent extends StatelessWidget {
  final Note note;
  const _NotePreviewContent({required this.note});

  @override
  Widget build(BuildContext context) {
    final isDark      = Theme.of(context).brightness == Brightness.dark;
    final base        = Neu.base(isDark);
    final accent      = Neu.accentFromTheme(note.colorTheme);
    final textPrimary = Neu.textPrimary(isDark);
    final textSub     = Neu.textSecondary(isDark);
    final textTer     = Neu.textTertiary(isDark);

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: base,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: Neu.raised(isDark),
        ),
        child: Column(
          children: [
            // ── Drag handle ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Neu.textTertiary(isDark).withAlpha(80),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // ── Header: accent bar + title + meta ─────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Accent bar
                  Container(
                    height: 3,
                    width: 36,
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
                  // Title row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          note.title.isNotEmpty ? note.title : 'Untitled',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Close button
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: base,
                            borderRadius: BorderRadius.circular(9),
                            boxShadow: Neu.raisedSm(isDark),
                          ),
                          child: Icon(Icons.close_rounded,
                              size: 16, color: textSub),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Meta row: type chip + date
                  Row(children: [
                    _NeuTypeChip(
                        note: note, isDark: isDark, accent: accent),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('MMM d, yyyy · HH:mm')
                          .format(note.updatedAt),
                      style: TextStyle(fontSize: 11, color: textTer),
                    ),
                    if (note.pinned) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.push_pin_rounded,
                          size: 13, color: accent.withAlpha(180)),
                    ],
                  ]),
                ],
              ),
            ),

            Divider(
                height: 1,
                thickness: 1,
                indent: 20,
                endIndent: 20,
                color: Neu.textSecondary(isDark).withAlpha(30)),

            // ── Scrollable content ─────────────────────────────────────────
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                children: [
                  _buildPreviewBody(context, isDark, accent, textPrimary, textSub),
                ],
              ),
            ),

            // ── Edit button ────────────────────────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 8, 20, MediaQuery.of(context).padding.bottom + 16),
              child: NeuPressable(
                isDark: isDark,
                radius: 14,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => NoteEditorScreen(note: note)),
                  );
                },
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.edit_rounded, size: 16, color: accent),
                    const SizedBox(width: 8),
                    Text(
                      'Edit note',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewBody(BuildContext context, bool isDark, Color accent,
      Color textPrimary, Color textSub) {
    return switch (note.noteType) {
      NoteType.normal    => _previewNormal(textPrimary, textSub),
      NoteType.checklist => _previewChecklist(isDark, accent, textPrimary, textSub),
      NoteType.itinerary => _previewItinerary(isDark, accent, textPrimary, textSub),
      NoteType.mealPlan  => _previewMealPlan(isDark, accent, textPrimary, textSub),
      NoteType.recipe    => _previewRecipe(isDark, accent, textPrimary, textSub),
    };
  }

  // ── Normal note ─────────────────────────────────────────────────────────────
  Widget _previewNormal(Color textPrimary, Color textSub) {
    // Decode stored content — handles JSON envelope (bold/italic) and
    // legacy plain strings (no ranges) transparently.
    final decoded   = RichContentCodec.decode(note.content);
    final plainText = decoded.text;
    final ranges    = decoded.ranges;

    if (plainText.isEmpty) {
      return Text('No content.', style: TextStyle(color: textSub, fontSize: 14));
    }

    final base   = TextStyle(fontSize: 15, color: textPrimary, height: 1.65);
    final len    = plainText.length;
    final bold   = List<bool>.filled(len, false);
    final italic = List<bool>.filled(len, false);

    for (final r in ranges) {
      if (r.type == FormatType.bold) {
        for (int i = r.start; i < r.end && i < len; i++) { bold[i] = true; }
      } else {
        for (int i = r.start; i < r.end && i < len; i++) { italic[i] = true; }
      }
    }

    // List prefix chars (• / 1. etc.) are always bold, never italic.
    int lineOff = 0;
    for (final line in plainText.split('\n')) {
      final m = RegExp(r'^(• |\d+\. )').firstMatch(line);
      if (m != null) {
        for (int i = lineOff; i < lineOff + m.end && i < len; i++) {
          bold[i]   = true;
          italic[i] = false;
        }
      }
      lineOff += line.length + 1;
    }

    // Build one RichText per line
    final lines   = plainText.split('\n');
    int   offset  = 0;
    final widgets = <Widget>[];

    for (final line in lines) {
      final lineLen = line.length;
      final spans   = <InlineSpan>[];
      int i = 0;
      while (i < lineLen) {
        final co       = offset + i;
        final isBold   = co < len && bold[co];
        final isItalic = co < len && italic[co];
        int j = i + 1;
        while (j < lineLen) {
          final nco = offset + j;
          if (nco >= len) break;
          if (bold[nco] != isBold || italic[nco] != isItalic) break;
          j++;
        }
        spans.add(TextSpan(
          text: line.substring(i, j),
          style: base.copyWith(
            fontWeight: isBold   ? FontWeight.w800 : FontWeight.w400,
            fontStyle:  isItalic ? FontStyle.italic  : FontStyle.normal,
          ),
        ));
        i = j;
      }
      widgets.add(RichText(
        text: TextSpan(
          children: spans.isEmpty
              ? [TextSpan(text: line, style: base)]
              : spans,
        ),
      ));
      offset += lineLen + 1;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  // ── Checklist ───────────────────────────────────────────────────────────────
  Widget _previewChecklist(bool isDark, Color accent,
      Color textPrimary, Color textSub) {
    if (note.checklistItems.isEmpty) {
      return Text('No items.', style: TextStyle(color: textSub, fontSize: 14));
    }
    final done  = note.checklistItems.where((i) => i.checked).length;
    final total = note.checklistItems.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Progress summary
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Neu.base(isDark),
            borderRadius: BorderRadius.circular(10),
            boxShadow: Neu.inset(isDark),
          ),
          child: Row(children: [
            Icon(Icons.check_circle_outline_rounded,
                size: 14, color: accent),
            const SizedBox(width: 8),
            Text(
              '$done / $total completed  •  ${total > 0 ? (done * 100 ~/ total) : 0}%',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: done == total && total > 0
                      ? accent
                      : textSub),
            ),
          ]),
        ),
        // Items
        ...note.checklistItems.map((item) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1, right: 10),
                child: Icon(
                  item.checked
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  size: 18,
                  color: item.checked ? accent : textSub,
                ),
              ),
              Expanded(
                child: Text(
                  item.text.isNotEmpty ? item.text : '(empty)',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: item.checked ? textSub : textPrimary,
                    decoration: item.checked
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
              ),
            ],
          ),
        )),
      ],
    );
  }

  // ── Itinerary ────────────────────────────────────────────────────────────────
  Widget _previewItinerary(bool isDark, Color accent,
      Color textPrimary, Color textSub) {
    if (note.itineraryItems.isEmpty) {
      return Text('No destinations.', style: TextStyle(color: textSub, fontSize: 14));
    }
    return Column(
      children: note.itineraryItems.asMap().entries.map((e) {
        final i    = e.key;
        final item = e.value;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Number bubble
              Container(
                width: 28,
                height: 28,
                margin: const EdgeInsets.only(right: 12, top: 2),
                decoration: BoxDecoration(
                  color: Neu.base(isDark),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: Neu.inset(isDark),
                ),
                child: Center(
                  child: Text('${i + 1}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: accent)),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.location.isNotEmpty ? item.location : 'Destination',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: textPrimary),
                    ),
                    if (item.date.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(children: [
                        Icon(Icons.calendar_today_outlined,
                            size: 12, color: textSub),
                        const SizedBox(width: 5),
                        Text(item.date,
                            style: TextStyle(fontSize: 12, color: textSub)),
                      ]),
                    ],
                    if (item.arrivalTime.isNotEmpty ||
                        item.departureTime.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(children: [
                        Icon(Icons.schedule_outlined,
                            size: 12, color: textSub),
                        const SizedBox(width: 5),
                        Text(
                          '${item.arrivalTime.isNotEmpty ? item.arrivalTime : 'TBD'}'
                              ' → '
                              '${item.departureTime.isNotEmpty ? item.departureTime : 'TBD'}',
                          style: TextStyle(fontSize: 12, color: textSub),
                        ),
                      ]),
                    ],
                    if (item.notes.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(item.notes,
                          style: TextStyle(
                              fontSize: 13, color: textSub, height: 1.5)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── Meal Plan ────────────────────────────────────────────────────────────────
  Widget _previewMealPlan(bool isDark, Color accent,
      Color textPrimary, Color textSub) {
    if (note.mealPlanItems.isEmpty) {
      return Text('No days planned.', style: TextStyle(color: textSub, fontSize: 14));
    }
    return Column(
      children: note.mealPlanItems.map((day) {
        final meals = day.meals
            .where((m) => (m['value'] as String?)?.isNotEmpty == true)
            .toList();
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: NeuContainer(
            isDark: isDark,
            radius: 14,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.calendar_today_outlined,
                      size: 13, color: accent),
                  const SizedBox(width: 6),
                  Text(
                    day.day.isNotEmpty ? day.day : 'Day',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: textPrimary),
                  ),
                ]),
                if (meals.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...meals.map((m) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${m['name'] ?? 'Meal'}: ',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: textSub),
                        ),
                        Expanded(
                          child: Text(
                            m['value'] as String,
                            style: TextStyle(
                                fontSize: 13, color: textPrimary),
                          ),
                        ),
                      ],
                    ),
                  )),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Recipe ───────────────────────────────────────────────────────────────────
  Widget _previewRecipe(bool isDark, Color accent,
      Color textPrimary, Color textSub) {
    final r = note.recipeData;
    if (r == null) {
      return Text('No recipe data.', style: TextStyle(color: textSub, fontSize: 14));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Time chips
        if (r.prepTime.isNotEmpty || r.cookTime.isNotEmpty ||
            r.servings.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (r.prepTime.isNotEmpty)
                _RecipeChip(
                    isDark: isDark, icon: Icons.timer_outlined,
                    label: 'Prep: ${r.prepTime}', accent: accent),
              if (r.cookTime.isNotEmpty)
                _RecipeChip(
                    isDark: isDark,
                    icon: Icons.local_fire_department_outlined,
                    label: 'Cook: ${r.cookTime}', accent: accent),
              if (r.servings.isNotEmpty)
                _RecipeChip(
                    isDark: isDark, icon: Icons.people_outline_rounded,
                    label: 'Serves: ${r.servings}', accent: accent),
            ],
          ),
        const SizedBox(height: 16),

        // Ingredients
        if (r.ingredientRows.any((row) => row.name.isNotEmpty)) ...[
          _PreviewSectionLabel(
              text: 'INGREDIENTS',
              icon: Icons.kitchen_outlined,
              color: textSub),
          const SizedBox(height: 8),
          ...r.ingredientRows.where((row) => row.name.isNotEmpty).map((row) =>
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(children: [
                  Text('• ', style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 13)),
                  if (row.quantity.isNotEmpty || row.unit.isNotEmpty)
                    Text(
                      '${row.quantity}${row.unit.isNotEmpty ? ' ${row.unit}' : ''}  ',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: textPrimary),
                    ),
                  Expanded(
                    child: Text(row.name,
                        style: TextStyle(fontSize: 13, color: textSub)),
                  ),
                ]),
              )),
          const SizedBox(height: 16),
        ],

        // Instructions
        if (r.steps.any((s) => s.text.isNotEmpty)) ...[
          _PreviewSectionLabel(
              text: 'INSTRUCTIONS',
              icon: Icons.format_list_numbered_rounded,
              color: textSub),
          const SizedBox(height: 8),
          ...r.steps.asMap().entries
              .where((e) => e.value.text.isNotEmpty)
              .map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.only(right: 10, top: 1),
                  decoration: BoxDecoration(
                    color: Neu.base(isDark),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: Neu.inset(isDark),
                  ),
                  child: Center(
                    child: Text('${e.key + 1}',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: accent)),
                  ),
                ),
                Expanded(
                  child: Text(e.value.text,
                      style: TextStyle(
                          fontSize: 14, color: textPrimary, height: 1.5)),
                ),
              ],
            ),
          )),
        ],
      ],
    );
  }
}

class _RecipeChip extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final String label;
  final Color accent;
  const _RecipeChip({
    required this.isDark,
    required this.icon,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Neu.base(isDark),
        borderRadius: BorderRadius.circular(10),
        boxShadow: Neu.inset(isDark),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: accent),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Neu.textSecondary(isDark))),
      ]),
    );
  }
}

class _PreviewSectionLabel extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;
  const _PreviewSectionLabel({
    required this.text,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 13, color: color),
    const SizedBox(width: 6),
    Text(text,
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: 0.5)),
  ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom page route — bottom-to-top slide
// ─────────────────────────────────────────────────────────────────────────────

class _SlideRoute<T> extends MaterialPageRoute<T> {
  _SlideRoute({required super.builder});

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.04),
        end: Offset.zero,
      ).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: FadeTransition(
        opacity: animation,
        child: child,
      ),
    );
  }
}