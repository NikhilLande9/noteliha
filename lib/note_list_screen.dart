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

  String _previewText() => switch (note.noteType) {
        NoteType.normal => note.content,
        NoteType.checklist =>
          '${note.checklistItems.length} items · ${note.checklistItems.where((i) => i.checked).length} done',
        NoteType.itinerary => '${note.itineraryItems.length} destinations',
        NoteType.mealPlan => '${note.mealPlanItems.length} days planned',
        NoteType.recipe => note.recipeData?.ingredients ?? note.content,
      };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Always vivid, fully opaque accent — visible in both light and dark
    final accentColor = Neu.accentFromTheme(note.colorTheme);
    final textColor = Neu.textPrimary(isDark);
    final subColor = Neu.textSecondary(isDark);
    final preview = _previewText();

    return NeuPressable(
      isDark: isDark,
      radius: 20,
      onTap: () => Navigator.push(
        context,
        _SlideRoute(builder: (_) => NoteEditorScreen(note: note)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Accent bar — subtle color cue from note theme
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

            // Title row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (note.pinned)
                  Padding(
                    padding: const EdgeInsets.only(right: 5, top: 1),
                    child: Icon(Icons.push_pin_rounded,
                        size: 13, color: accentColor.withAlpha(180)),
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

            // Preview
            if (preview.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                preview,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: subColor,
                  height: 1.45,
                ),
              ),
            ],

            // Image indicator
            if (note.imageIds.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(children: [
                Icon(Icons.photo_library_outlined, size: 12, color: subColor),
                const SizedBox(width: 3),
                Text(
                  '${note.imageIds.length} image${note.imageIds.length == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 11, color: subColor),
                ),
              ]),
            ],

            const SizedBox(height: 14),

            // Footer: type chip + date
            Row(
              children: [
                _NeuTypeChip(note: note, isDark: isDark, accent: accentColor),
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
              ],
            ),
          ],
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
            note.noteType.name[0].toUpperCase() +
                note.noteType.name.substring(1),
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

  /// Returns the raw IconData so we can apply our own color/size.
  static IconData _noteTypeIconData(NoteType type) => switch (type) {
        NoteType.normal    => Icons.note_rounded,
        NoteType.checklist => Icons.check_box_rounded,
        NoteType.itinerary => Icons.flight_rounded,
        NoteType.mealPlan  => Icons.restaurant_menu_rounded,
        NoteType.recipe    => Icons.menu_book_rounded,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// Note List Screen
// ─────────────────────────────────────────────────────────────────────────────

class NoteListScreen extends StatefulWidget {
  const NoteListScreen({super.key});

  @override
  State<NoteListScreen> createState() => _NoteListScreenState();
}

class _NoteListScreenState extends State<NoteListScreen> {
  String _searchQuery = '';
  bool _searchActive = false;
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
      if (n.checklistItems.any((i) => i.text.toLowerCase().contains(q))) {
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
              (m['value'] as String?)?.toLowerCase().contains(q) ?? false))) {
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

    final notes = _searchQuery.isEmpty
        ? prov.notes
        : _filterNotes(prov.notes, _searchQuery);

    final pinned = notes.where((n) => n.pinned).toList();
    final unpinned = notes.where((n) => !n.pinned).toList();

    return Scaffold(
      backgroundColor: base,
      appBar: _buildAppBar(context, prov, isDark),
      body: notes.isEmpty
          ? _buildEmptyState(isDark)
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
                child: Icon(Icons.warning_amber_rounded, color: subColor),
              ),
              onTap: () => _showConflictsSheet(context, prov),
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
    final base = Neu.base(isDark);
    final textColor = Neu.textPrimary(isDark);
    final subColor = Neu.textSecondary(isDark);

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: base,
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
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          prefixIcon:
              Icon(Icons.search_rounded, color: subColor, size: 18),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.close_rounded, size: 16, color: subColor),
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
            fontSize: 14, color: textColor, fontWeight: FontWeight.w500),
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
            child: _SectionLabel(text: 'Pinned', icon: Icons.push_pin_rounded, isDark: isDark),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _buildDismissibleCard(ctx, prov, pinned[i], isDark),
                childCount: pinned.length,
              ),
            ),
          ),
        ],
        if (unpinned.isNotEmpty) ...[
          if (pinned.isNotEmpty)
            SliverToBoxAdapter(
              child: _SectionLabel(text: 'Notes', icon: Icons.notes_rounded, isDark: isDark),
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
    final hasConflict = prov.syncConflicts.any((ns) => ns.noteId == n.id);

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
            Provider.of<NotesProvider>(context, listen: false).softDelete(n.id),
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
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
                final label =
                    type.name[0].toUpperCase() + type.name.substring(1);
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
                            builder: (_) => NoteEditorScreen(noteType: type)),
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
                                color: Theme.of(context).colorScheme.primary,
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
        ),
      ),
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
      backgroundColor: base,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (_, scrollCtrl) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                                      prov.resolveConflictKeepLocal(ns.noteId);
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
                                      prov.resolveConflictKeepBoth(ns.noteId);
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
        ),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
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
                fontWeight: FontWeight.w600, fontSize: 14, color: subColor)),
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
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: FadeTransition(
        opacity: animation,
        child: child,
      ),
    );
  }
}
