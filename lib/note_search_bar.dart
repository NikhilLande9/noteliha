// lib/widgets/note_search_bar.dart
//
// In-Note Search with Highlighted Results
// ─────────────────────────────────────────
// Drop this widget into NoteEditorScreen's Column, above the Expanded body.
// It sits in a collapsible bar that appears when the user taps the search icon
// added to the AppBar. It scans plain text across the note's content, title,
// and checklist items, highlights every occurrence in amber, and lets the user
// cycle forward/backward through matches.
//
// HOW TO INTEGRATE
// ────────────────
// 1. Add `final _searchKey = GlobalKey<NoteInNoteSearchBarState>();`
//    and `bool _showSearch = false;` to _NoteEditorScreenState.
//
// 2. In the AppBar actions list, add before the MoreMenu:
//      NeuIconButton(
//        isDark: isDark,
//        icon: Icon(Icons.search_rounded, size: 20, color: textSub),
//        onTap: () => setState(() => _showSearch = !_showSearch),
//      ),
//
// 3. In the body Column (between the divider and the Expanded), add:
//      if (_showSearch)
//        NoteInNoteSearchBar(
//          key: _searchKey,
//          isDark: isDark,
//          accent: accent,
//          noteContent: _contentCtrl.text,
//          noteTitle: _titleCtrl.text,
//          checklistItems: _editing.checklistItems,
//        ),
//
// 4. To highlight in the _RichTextField, supply a SearchHighlightDelegate
//    (see HighlightedRichTextField below) that wraps TextPainter spans.
//    For a quick no-dependency approach the search bar scrolls the plain
//    TextField to the match position using a ScrollController passed in.

import 'package:flutter/material.dart';
import '../models.dart';
import '../neu_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Match record
// ─────────────────────────────────────────────────────────────────────────────

class _Match {
  final String source; // 'title' | 'content' | 'checklist:{id}'
  final int start;
  final int end;

  const _Match({required this.source, required this.start, required this.end});
}

// ─────────────────────────────────────────────────────────────────────────────
// NoteInNoteSearchBar
// ─────────────────────────────────────────────────────────────────────────────

class NoteInNoteSearchBar extends StatefulWidget {
  final bool isDark;
  final Color accent;

  /// Plain text of the note body (pass _RichContentCodec.plainText(controller.text))
  final String noteContent;
  final String noteTitle;
  final List<ChecklistItem> checklistItems;

  // ── Additional note type content ──────────────────────────────────────────
  final List<ItineraryItem> itineraryItems;
  final List<MealPlanItem> mealPlanItems;
  final RecipeData? recipeData;

  /// Optional: called with the char-offset of the active match within noteContent
  /// so the parent can scroll the editor TextField to that position.
  final void Function(int charOffset)? onContentMatch;

  /// Optional: called whenever the search query or active match changes so the
  /// parent can drive rich-text highlight painting.
  /// Parameters: (query, activeCharOffset) where activeCharOffset is -1 when
  /// there is no active content match.
  final void Function(String query, int activeCharOffset)? onHighlightChanged;

  /// Optional: called when the active match is inside a structured list
  /// (checklist, itinerary, mealplan, recipe).
  /// Parameters: (source tag e.g. 'checklist:{id}', resolved item index in its
  /// own list) so the parent can scroll the right ListView to that item.
  final void Function(String source, int itemIndex)? onStructuredMatch;

  const NoteInNoteSearchBar({
    super.key,
    required this.isDark,
    required this.accent,
    required this.noteContent,
    required this.noteTitle,
    required this.checklistItems,
    this.itineraryItems = const [],
    this.mealPlanItems = const [],
    this.recipeData,
    this.onContentMatch,
    this.onHighlightChanged,
    this.onStructuredMatch,
  });

  @override
  State<NoteInNoteSearchBar> createState() => NoteInNoteSearchBarState();
}

class NoteInNoteSearchBarState extends State<NoteInNoteSearchBar>
    with SingleTickerProviderStateMixin {

  final _queryCtrl = TextEditingController();
  final _focusNode = FocusNode();

  List<_Match> _matches = [];
  int _activeIndex = -1;

  late AnimationController _slideCtrl;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 220));
    _slideAnim = Tween(begin: const Offset(0, -1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOut));
    _slideCtrl.forward();
    _queryCtrl.addListener(_runSearch);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    _queryCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(NoteInNoteSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.noteContent != widget.noteContent ||
        oldWidget.noteTitle != widget.noteTitle ||
        oldWidget.checklistItems != widget.checklistItems ||
        oldWidget.itineraryItems != widget.itineraryItems ||
        oldWidget.mealPlanItems != widget.mealPlanItems ||
        oldWidget.recipeData != widget.recipeData) {
      _runSearch();
    }
  }

  // ── Search logic ───────────────────────────────────────────────────────────

  void _runSearch() {
    final q = _queryCtrl.text.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() { _matches = []; _activeIndex = -1; });
      widget.onHighlightChanged?.call('', -1);
      return;
    }

    final found = <_Match>[];

    // Title
    _findAll(widget.noteTitle.toLowerCase(), q, 'title', found);

    // Body content (normal / drawing / recipe plain-text summary)
    _findAll(widget.noteContent.toLowerCase(), q, 'content', found);

    // Checklist items
    for (final item in widget.checklistItems) {
      _findAll(item.text.toLowerCase(), q, 'checklist:${item.id}', found);
    }

    // Itinerary items — search only the fields visible in the collapsed card
    // (location + notes). Date and time fields are abstract/metadata and should
    // not produce matches that confuse the user with phantom highlights.
    // One match per item maximum — we just need to know "does this item match"
    // so the user can navigate to it; per-field occurrence counting isn't needed.
    for (final item in widget.itineraryItems) {
      final source = 'itinerary:${item.id}';
      bool matched = false;
      if (item.location.isNotEmpty &&
          item.location.toLowerCase().contains(q)) {
        found.add(_Match(source: source, start: 0, end: q.length));
        matched = true;
      }
      if (!matched &&
          item.notes.isNotEmpty &&
          item.notes.toLowerCase().contains(q)) {
        found.add(_Match(source: source, start: 0, end: q.length));
      }
    }

    // Meal plan items — search only meal values (the user-entered text inside
    // each meal slot). The day label (e.g. "Monday") is a structural/navigation
    // element and not considered searchable content.
    // One match per day card maximum.
    for (final day in widget.mealPlanItems) {
      final source = 'mealplan:meal:${day.id}';
      bool dayMatched = false;
      for (final meal in day.meals) {
        if (dayMatched) break;
        final val = (meal['value'] as String?) ?? '';
        if (val.isNotEmpty && val.toLowerCase().contains(q)) {
          found.add(_Match(source: source, start: 0, end: q.length));
          dayMatched = true;
        }
      }
    }

    // Recipe — search ingredient names only (quantity/unit are structural) and
    // step text. Prep time, cook time, and servings are metadata fields shown
    // in small header chips and should not generate search matches.
    final r = widget.recipeData;
    if (r != null) {
      for (final row in r.ingredientRows) {
        if (row.name.isNotEmpty && row.name.toLowerCase().contains(q)) {
          found.add(_Match(
              source: 'recipe:ingredient:${row.id}', start: 0, end: q.length));
        }
      }
      for (final step in r.steps) {
        if (step.text.isNotEmpty && step.text.toLowerCase().contains(q)) {
          found.add(_Match(
              source: 'recipe:step:${step.id}', start: 0, end: q.length));
        }
      }
    }

    setState(() {
      _matches  = found;
      _activeIndex = found.isEmpty ? -1 : 0;
    });
    _notifyActive();
  }

  void _findAll(String haystack, String needle, String source, List<_Match> out) {
    int offset = 0;
    while (true) {
      final idx = haystack.indexOf(needle, offset);
      if (idx == -1) break;
      out.add(_Match(source: source, start: idx, end: idx + needle.length));
      offset = idx + 1;
    }
  }

  void _next() {
    if (_matches.isEmpty) return;
    setState(() => _activeIndex = (_activeIndex + 1) % _matches.length);
    _notifyActive();
  }

  void _prev() {
    if (_matches.isEmpty) return;
    setState(() =>
    _activeIndex = (_activeIndex - 1 + _matches.length) % _matches.length);
    _notifyActive();
  }

  void _notifyActive() {
    if (_activeIndex < 0 || _activeIndex >= _matches.length) {
      widget.onHighlightChanged?.call(_queryCtrl.text.trim(), -1);
      return;
    }
    final m = _matches[_activeIndex];
    final q = _queryCtrl.text.trim();

    if (m.source == 'content') {
      widget.onContentMatch?.call(m.start);
      widget.onHighlightChanged?.call(q, m.start);
    } else {
      widget.onHighlightChanged?.call(q, -1);

      // Resolve the matched item's index within its own list and notify the
      // parent so it can scroll the appropriate ListView to that item.
      if (widget.onStructuredMatch != null) {
        final source = m.source;
        int itemIndex = -1;

        if (source.startsWith('checklist:')) {
          final id = source.substring('checklist:'.length);
          itemIndex = widget.checklistItems.indexWhere((i) => i.id == id);
        } else if (source.startsWith('itinerary:')) {
          final id = source.substring('itinerary:'.length);
          itemIndex = widget.itineraryItems.indexWhere((i) => i.id == id);
        } else if (source.startsWith('mealplan:')) {
          // Both 'mealplan:day:{id}' and 'mealplan:meal:{id}' use the day id
          // (the last colon-separated segment).
          final id = source.split(':').last;
          itemIndex = widget.mealPlanItems.indexWhere((i) => i.id == id);
        } else if (source.startsWith('recipe:ingredient:')) {
          final id = source.substring('recipe:ingredient:'.length);
          itemIndex = widget.recipeData?.ingredientRows
              .indexWhere((r) => r.id == id) ??
              -1;
        } else if (source.startsWith('recipe:step:')) {
          final id = source.substring('recipe:step:'.length);
          itemIndex =
              widget.recipeData?.steps.indexWhere((s) => s.id == id) ?? -1;
        }

        if (itemIndex >= 0) {
          widget.onStructuredMatch?.call(source, itemIndex);
        }
      }
    }
  }

  // ── Public API for the parent to query current match info ──────────────────

  String get query => _queryCtrl.text.trim();

  /// Returns all matches in the given source for highlight painting.
  List<TextRange> matchRangesFor(String source) => _matches
      .where((m) => m.source == source)
      .map((m) => TextRange(start: m.start, end: m.end))
      .toList();

  int? activeOffsetIn(String source) {
    if (_activeIndex < 0) return null;
    final m = _matches[_activeIndex];
    return m.source == source ? m.start : null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark  = widget.isDark;
    final accent  = widget.accent;
    final primary = Neu.textPrimary(isDark);
    final sub     = Neu.textSecondary(isDark);
    final fill    = Neu.inputFill(isDark);

    final hasMatches = _matches.isNotEmpty;
    final label = hasMatches
        ? '${_activeIndex + 1} / ${_matches.length}'
        : (_queryCtrl.text.isEmpty ? '' : 'No results');

    return SlideTransition(
      position: _slideAnim,
      child: Container(
        color: Neu.base(isDark),
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
        child: Row(
          children: [
            // ── Search field ───────────────────────────────────────────────
            Expanded(
              child: Container(
                height: 38,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: Neu.inputShadow(isDark),
                ),
                child: TextField(
                  controller: _queryCtrl,
                  focusNode: _focusNode,
                  style: TextStyle(fontSize: 14, color: primary),
                  decoration: InputDecoration(
                    hintText: 'Search in note…',
                    hintStyle: TextStyle(fontSize: 14, color: sub),
                    prefixIcon: Icon(Icons.search_rounded, size: 18, color: sub),
                    border: InputBorder.none,
                    contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  ),
                  onSubmitted: (_) => _next(),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // ── Match counter ──────────────────────────────────────────────
            if (label.isNotEmpty)
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: hasMatches ? accent : sub)),
            const SizedBox(width: 4),

            // ── Prev ──────────────────────────────────────────────────────
            _NavBtn(
              icon: Icons.keyboard_arrow_up_rounded,
              enabled: hasMatches,
              isDark: isDark,
              onTap: _prev,
            ),

            // ── Next ──────────────────────────────────────────────────────
            _NavBtn(
              icon: Icons.keyboard_arrow_down_rounded,
              enabled: hasMatches,
              isDark: isDark,
              onTap: _next,
            ),
          ],
        ),
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final bool isDark;
  final VoidCallback onTap;
  const _NavBtn({
    required this.icon,
    required this.enabled,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = enabled
        ? Neu.textPrimary(isDark)
        : Neu.textTertiary(isDark).withAlpha(80);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 22, color: color),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SearchHighlightPainter
//
// A TextPainter-based widget that overlays amber highlight boxes on a block
// of plain text. Use this to wrap the note body text in the card preview
// (NoteCard) or any read-only display.
//
// For the editable TextField inside _RichTextField, use the
// _RichTextController.buildTextSpan approach instead:
//   In _RichTextController.buildTextSpan(), after building normal spans, call
//   _applySearchHighlights(spans, searchQuery) to overlay amber backgrounds.
// ─────────────────────────────────────────────────────────────────────────────

class HighlightedText extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle baseStyle;
  final int? maxLines;
  final Color highlightColor;
  final Color activeColor;
  final int activeMatchIndex; // -1 = no active match

  const HighlightedText({
    super.key,
    required this.text,
    required this.query,
    required this.baseStyle,
    this.maxLines,
    this.highlightColor = const Color(0xFFFFD600),
    this.activeColor = const Color(0xFFFF8F00),
    this.activeMatchIndex = -1,
  });

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return Text(text, style: baseStyle, maxLines: maxLines,
          overflow: TextOverflow.ellipsis);
    }

    final lower  = text.toLowerCase();
    final qLower = query.toLowerCase();
    final spans  = <InlineSpan>[];
    int i        = 0;
    int matchIdx = 0;

    while (i < text.length) {
      final idx = lower.indexOf(qLower, i);
      if (idx == -1) {
        spans.add(TextSpan(text: text.substring(i), style: baseStyle));
        break;
      }
      if (idx > i) {
        spans.add(TextSpan(text: text.substring(i, idx), style: baseStyle));
      }
      final isActive = matchIdx == activeMatchIndex;
      spans.add(TextSpan(
        text: text.substring(idx, idx + query.length),
        style: baseStyle.copyWith(
          backgroundColor: isActive ? activeColor : highlightColor,
          color: Colors.black87,
          fontWeight: FontWeight.w700,
        ),
      ));
      i = idx + query.length;
      matchIdx++;
    }

    return RichText(
      text: TextSpan(children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Extension on _RichTextController to apply search highlights
//
// Because _RichTextController is private to note_editor_screen.dart, add the
// snippet below directly inside _RichTextController.buildTextSpan():
//
//   // After assembling the normal styled spans list, apply search highlights:
//   if (_searchQuery.isNotEmpty) {
//     _overlaySearchHighlights(children, text, _searchQuery, _activeMatchOffset);
//   }
//
// Paste this static helper into _RichTextController:
// ─────────────────────────────────────────────────────────────────────────────

/// Overlays search-highlight BackgroundColorSpans onto an existing InlineSpan list.
/// Call this at the end of buildTextSpan before returning.
List<InlineSpan> overlaySearchHighlights(
    List<InlineSpan> spans,
    String fullText,
    String query, {
      int activeOffset = -1,
      Color highlight = const Color(0xFFFFD600),
      Color active    = const Color(0xFFFF8F00),
    }) {
  if (query.isEmpty) return spans;

  final lower  = fullText.toLowerCase();
  final qLower = query.toLowerCase();

  // Collect match ranges
  final ranges = <(int start, int end, bool isActive)>[];
  int offset = 0;
  while (true) {
    final idx = lower.indexOf(qLower, offset);
    if (idx == -1) break;
    final end = idx + query.length;
    ranges.add((idx, end, idx == activeOffset));
    offset = idx + 1;
  }
  if (ranges.isEmpty) return spans;

  // Re-build span list splitting at every highlight boundary.
  // We flatten all existing spans into a per-character style map first,
  // then re-chunk with highlight backgrounds applied.
  // (Fast enough for note-length text; avoids a full TextPainter round-trip.)
  final len    = fullText.length;
  final styles = List<TextStyle?>.filled(len, null);

  int charOff = 0;
  void walk(InlineSpan span, TextStyle? parent) {
    final resolved = span is TextSpan
        ? (parent ?? const TextStyle()).merge(span.style)
        : parent;
    if (span is TextSpan) {
      final t = span.text ?? '';
      for (int i = 0; i < t.length && charOff < len; i++, charOff++) {
        styles[charOff] = resolved;
      }
      for (final child in span.children ?? <InlineSpan>[]) {
        walk(child, resolved);
      }
    }
  }
  for (final s in spans) { walk(s, null); }

  // Build per-char highlight flag
  final hlColor  = List<Color?>.filled(len, null);
  for (final (start, end, isActive) in ranges) {
    for (int i = start; i < end && i < len; i++) {
      hlColor[i] = isActive ? active : highlight;
    }
  }

  // Re-chunk
  final result = <InlineSpan>[];
  int i = 0;
  while (i < len) {
    final base    = styles[i];
    final hl      = hlColor[i];
    int j = i + 1;
    while (j < len && styles[j] == base && hlColor[j] == hl) { j++; }
    result.add(TextSpan(
      text: fullText.substring(i, j),
      style: (base ?? const TextStyle()).copyWith(
        backgroundColor: hl,
        color: hl != null ? Colors.black87 : null,
        fontWeight: hl != null ? FontWeight.w700 : null,
      ),
    ));
    i = j;
  }
  return result;
}