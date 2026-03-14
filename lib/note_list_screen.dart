import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'models.dart';
import 'theme_helper.dart';
import 'notes_provider.dart';
import 'note_editor_screen.dart';
import 'settings_screen.dart';

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
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final noteColor =
        ThemeHelper.getThemeColor(note.colorTheme, isDarkMode: isDarkMode);
    final textColor = ThemeHelper.getTextColorForBackground(noteColor);
    final subColor = ThemeHelper.getSecondaryTextColorForBackground(noteColor);
    final preview = _previewText();

    return Material(
      color: noteColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => NoteEditorScreen(note: note))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (note.pinned)
                    Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(Icons.push_pin_rounded,
                            size: 14, color: textColor)),
                  Expanded(
                    child: Text(
                      note.title.isNotEmpty ? note.title : '(Untitled)',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                          color: textColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(DateFormat('MMM d').format(note.updatedAt),
                      style: TextStyle(
                          fontSize: 11,
                          color: subColor,
                          fontWeight: FontWeight.w500)),
                ],
              ),
              if (preview.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 13, color: subColor, height: 1.4)),
              ],
              if (note.imageIds.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.photo_library_outlined,
                        size: 13, color: subColor),
                    const SizedBox(width: 4),
                    Text(
                        '${note.imageIds.length} image${note.imageIds.length == 1 ? '' : 's'}',
                        style: TextStyle(fontSize: 11, color: subColor)),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  _Tag(
                    color: textColor,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ThemeHelper.getNoteTypeIcon(note.noteType),
                        const SizedBox(width: 4),
                        Text(
                            note.noteType.name[0].toUpperCase() +
                                note.noteType.name.substring(1),
                            style: TextStyle(
                                fontSize: 11,
                                color: textColor,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  _Tag(
                      color: textColor,
                      child: Text(note.category,
                          style: TextStyle(
                              fontSize: 11,
                              color: textColor,
                              fontWeight: FontWeight.w500))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final Color color;
  final Widget child;
  const _Tag({required this.color, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withAlpha(30), borderRadius: BorderRadius.circular(6)),
        child: child,
      );
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
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<NotesProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;
    final notes = _searchQuery.isEmpty ? prov.notes : prov.search(_searchQuery);

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        title: Row(
          children: [
            // SVG icon would go here: SvgPicture.asset('assets/icons/noteliha.svg', height: 28),
            const SizedBox(width: 8),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: 'note',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurface,
                      letterSpacing: -0.8,
                    ),
                  ),
                  TextSpan(
                    text: 'liha',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: colorScheme.primary,
                      letterSpacing: -0.8,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (prov.syncConflicts.isNotEmpty)
            IconButton(
              onPressed: () => _showConflictsSheet(context, prov),
              icon: Badge(
                  label: Text('${prov.syncConflicts.length}'),
                  child: const Icon(Icons.warning_amber_rounded)),
              tooltip: 'Sync conflicts',
            ),
          IconButton(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (q) {
                _debounceTimer?.cancel();
                _debounceTimer = Timer(const Duration(milliseconds: 300),
                    () => setState(() => _searchQuery = q));
              },
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search_rounded,
                    color: colorScheme.onSurfaceVariant),
                hintText: 'Search notes...',
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withAlpha(80),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        BorderSide(color: colorScheme.primary, width: 1.5)),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
      body: notes.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _searchQuery.isEmpty
                        ? Icons.note_add_outlined
                        : Icons.search_off_rounded,
                    size: 56,
                    color: colorScheme.onSurfaceVariant.withAlpha(100),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _searchQuery.isEmpty
                        ? 'No notes yet.\nTap + to create one.'
                        : 'No notes found.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 15,
                        height: 1.5),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
              itemCount: notes.length,
              itemBuilder: (c, i) {
                final n = notes[i];
                final hasConflict =
                    prov.syncConflicts.any((ns) => ns.noteId == n.id);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Dismissible(
                    key: Key(n.id),
                    background: Container(
                      decoration: BoxDecoration(
                          color: colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(14)),
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: Icon(Icons.delete_outline_rounded,
                          color: colorScheme.onErrorContainer),
                    ),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (_) async {
                      return await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Delete Note'),
                              content: const Text('Move to recycle bin?'),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel')),
                                FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Delete')),
                              ],
                            ),
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
                            top: 8,
                            right: 8,
                            child: Icon(Icons.warning_amber_rounded,
                                size: 16, color: Colors.orange.shade700),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showNoteTypeDialog(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Note'),
      ),
    );
  }

  void _showNoteTypeDialog(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                          color: colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(2)))),
              Text('Choose note type',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface)),
              const SizedBox(height: 12),
              ...NoteType.values.map((type) => ListTile(
                    leading: CircleAvatar(
                        backgroundColor: colorScheme.primaryContainer,
                        child: ThemeHelper.getNoteTypeIcon(type)),
                    title: Text(
                        type.name[0].toUpperCase() + type.name.substring(1),
                        style: const TextStyle(fontWeight: FontWeight.w500)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  NoteEditorScreen(noteType: type)));
                    },
                  )),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showConflictsSheet(BuildContext context, NotesProvider prov) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (_, scrollCtrl) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                          color: colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(2)))),
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Text('Sync Conflicts',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                  'These notes were modified on multiple devices. Choose how to resolve each conflict.',
                  style: TextStyle(
                      fontSize: 13, color: colorScheme.onSurfaceVariant)),
              const SizedBox(height: 12),
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
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                localNote.title.isNotEmpty
                                    ? localNote.title
                                    : '(Untitled)',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 15)),
                            const SizedBox(height: 4),
                            Text(
                              'Local: ${DateFormat('MMM d, HH:mm').format(localNote.updatedAt)}  •  Remote: ${DateFormat('MMM d, HH:mm').format(ns.conflict!.remoteVersion.updatedAt)}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              children: [
                                FilledButton.tonal(
                                  onPressed: () {
                                    prov.resolveConflictKeepLocal(ns.noteId);
                                    if (prov.syncConflicts.isEmpty) {
                                      Navigator.pop(ctx);
                                    }
                                  },
                                  child: const Text('Keep Local'),
                                ),
                                FilledButton.tonal(
                                  onPressed: () {
                                    prov.resolveConflictKeepRemote(ns.noteId);
                                    if (prov.syncConflicts.isEmpty) {
                                      Navigator.pop(ctx);
                                    }
                                  },
                                  child: const Text('Keep Remote'),
                                ),
                                OutlinedButton(
                                  onPressed: () {
                                    prov.resolveConflictKeepBoth(ns.noteId);
                                    if (prov.syncConflicts.isEmpty) {
                                      Navigator.pop(ctx);
                                    }
                                  },
                                  child: const Text('Keep Both'),
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


