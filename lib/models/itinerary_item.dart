// lib/models/itinerary_item.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../neu_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Modern Itinerary Timeline with Neumorphic Cards
// ─────────────────────────────────────────────────────────────────────────────

class ModernItineraryBuilder extends StatefulWidget {
  final List<ItineraryItem> items;
  final Function(int) onDelete;
  final VoidCallback onAddItem;
  final Function() onChanged;
  final ScrollController? scrollController;

  // ── Search highlight props ─────────────────────────────────────────────────
  final String searchQuery;
  final String activeItemId;
  final Map<String, GlobalKey> itemKeys;

  const ModernItineraryBuilder({
    required this.items,
    required this.onDelete,
    required this.onAddItem,
    required this.onChanged,
    this.scrollController,
    this.searchQuery = '',
    this.activeItemId = '',
    Map<String, GlobalKey>? itemKeys,
    super.key,
  }) : itemKeys = itemKeys ?? const {};

  @override
  State<ModernItineraryBuilder> createState() => _ModernItineraryBuilderState();
}

class _ModernItineraryBuilderState extends State<ModernItineraryBuilder> {
  late Map<String, bool> _expandedItems;

  @override
  void initState() {
    super.initState();
    _expandedItems = {for (final item in widget.items) item.id: false};
  }

  void _toggleExpanded(String itemId) {
    setState(() {
      _expandedItems[itemId] = !(_expandedItems[itemId] ?? false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Expanded(
          child: widget.items.isEmpty
              ? _buildEmptyState(isDark)
              : CustomScrollView(
            controller: widget.scrollController,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                sliver: SliverList.builder(
                  itemCount: widget.items.length,
                  itemBuilder: (context, index) {
                    final item = widget.items[index];
                    final isLast = index == widget.items.length - 1;
                    final isExpanded = _expandedItems[item.id] ?? false;
                    final itemKey = widget.itemKeys.putIfAbsent(
                        item.id, () => GlobalKey());
                    final isActive = item.id == widget.activeItemId &&
                        widget.searchQuery.isNotEmpty;
                    return Container(
                      key: itemKey,
                      decoration: isActive
                          ? BoxDecoration(
                        color: const Color(0xFFFFD600).withAlpha(45),
                        borderRadius: BorderRadius.circular(14),
                      )
                          : null,
                      child: _ItineraryTimelineItem(
                        key: ValueKey(item.id),
                        item: item,
                        index: index,
                        isLast: isLast,
                        isExpanded: isExpanded,
                        isDark: isDark,
                        searchQuery: widget.searchQuery,
                        onToggleExpanded: () => _toggleExpanded(item.id),
                        onDelete: () {
                          widget.onDelete(index);
                          setState(() => _expandedItems.remove(item.id));
                        },
                        onChanged: widget.onChanged,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: _AddDestinationButton(onTap: widget.onAddItem, isDark: isDark),
        ),
      ],
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          NeuContainer(
            isDark: isDark,
            radius: 36,
            padding: const EdgeInsets.all(22),
            child: Icon(
              Icons.location_on_outlined,
              size: 36,
              color: Neu.textSecondary(isDark),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No destinations yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Neu.textPrimary(isDark),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add your first destination to start planning',
            style: TextStyle(fontSize: 13, color: Neu.textSecondary(isDark)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Timeline Item (stateful — owns controllers + expand animation)
// ─────────────────────────────────────────────────────────────────────────────

class _ItineraryTimelineItem extends StatefulWidget {
  final ItineraryItem item;
  final int index;
  final bool isLast;
  final bool isExpanded;
  final bool isDark;
  final String searchQuery;
  final VoidCallback onToggleExpanded;
  final VoidCallback onDelete;
  final VoidCallback onChanged;

  const _ItineraryTimelineItem({
    required this.item,
    required this.index,
    required this.isLast,
    required this.isExpanded,
    required this.isDark,
    required this.onToggleExpanded,
    required this.onDelete,
    required this.onChanged,
    this.searchQuery = '',
    super.key,
  });

  @override
  State<_ItineraryTimelineItem> createState() => _ItineraryTimelineItemState();
}

class _ItineraryTimelineItemState extends State<_ItineraryTimelineItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;

  late TextEditingController _locationCtrl;
  late TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _expandAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _expandController, curve: Curves.easeInOut),
    );
    if (widget.isExpanded) _expandController.forward();

    _locationCtrl = TextEditingController(text: widget.item.location);
    _notesCtrl    = TextEditingController(text: widget.item.notes);
  }

  @override
  void didUpdateWidget(covariant _ItineraryTimelineItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isExpanded != oldWidget.isExpanded) {
      if (widget.isExpanded) {
        _expandController.forward();
      } else {
        _expandController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _expandController.dispose();
    _locationCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _notifyChanged() {
    widget.item.location = _locationCtrl.text;
    widget.item.notes    = _notesCtrl.text;
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final isDark      = widget.isDark;
    final accentColor = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Timeline spine ─────────────────────────────────────────
              SizedBox(
                width: 40,
                child: Column(
                  children: [
                    NeuContainer(
                      isDark: isDark,
                      radius: 16,
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: Center(
                          child: Text(
                            '${widget.index + 1}',
                            style: TextStyle(
                              color: accentColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (!widget.isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                accentColor.withAlpha(120),
                                accentColor.withAlpha(30),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // ── Card content ───────────────────────────────────────────
              Expanded(
                child: Column(
                  children: [
                    _TimelineItemHeader(
                      item: widget.item,
                      isExpanded: widget.isExpanded,
                      isDark: isDark,
                      searchQuery: widget.searchQuery,
                      onTap: widget.onToggleExpanded,
                      onDelete: widget.onDelete,
                    ),
                    SizeTransition(
                      sizeFactor: _expandAnimation,
                      axisAlignment: -1,
                      child: _TimelineItemExpanded(
                        item:         widget.item,
                        locationCtrl: _locationCtrl,
                        notesCtrl:    _notesCtrl,
                        isDark:       isDark,
                        onChanged:    _notifyChanged,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Collapsed header row
// ─────────────────────────────────────────────────────────────────────────────

class _TimelineItemHeader extends StatelessWidget {
  final ItineraryItem item;
  final bool isExpanded;
  final bool isDark;
  final String searchQuery;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _TimelineItemHeader({
    required this.item,
    required this.isExpanded,
    required this.isDark,
    required this.onTap,
    required this.onDelete,
    this.searchQuery = '',
  });

  @override
  Widget build(BuildContext context) {
    final textColor = Neu.textPrimary(isDark);
    final subColor  = Neu.textSecondary(isDark);

    return NeuPressable(
      isDark: isDark,
      radius: 14,
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _HighlightedText(
                  text: item.location.isNotEmpty ? item.location : 'Destination',
                  query: searchQuery,
                  baseStyle: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onDelete,
                child: Icon(Icons.close_rounded, size: 16, color: subColor),
              ),
              const SizedBox(width: 8),
              Icon(
                isExpanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                size: 20,
                color: subColor,
              ),
            ],
          ),
          if (item.date.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              Icon(Icons.calendar_today_outlined, size: 12, color: subColor),
              const SizedBox(width: 5),
              Text(item.date,
                  style: TextStyle(fontSize: 12, color: subColor)),
            ]),
          ],
          if (item.arrivalTime.isNotEmpty || item.departureTime.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.schedule_outlined, size: 12, color: subColor),
              const SizedBox(width: 5),
              Text(
                _formatTimeRange(),
                style: TextStyle(fontSize: 12, color: subColor),
              ),
            ]),
          ],
          // ── Duration pill — shown only when both times are set ──────────
          if (_duration() != null) ...[
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.timelapse_rounded, size: 12, color: subColor),
              const SizedBox(width: 5),
              Text(
                _duration()!,
                style: TextStyle(
                  fontSize: 12,
                  color: subColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  String _formatTimeRange() {
    final a = item.arrivalTime.isNotEmpty   ? item.arrivalTime   : 'TBD';
    final d = item.departureTime.isNotEmpty ? item.departureTime : 'TBD';
    return '$a → $d';
  }

  /// Returns a human-readable duration string like "2 hrs 30 min" or "45 min"
  /// when both arrival and departure are set and departure is after arrival.
  /// Returns null otherwise so the row is hidden.
  String? _duration() {
    if (item.arrivalTime.isEmpty || item.departureTime.isEmpty) return null;

    TimeOfDay? parseTime(String s) {
      final parts = s.split(':');
      if (parts.length != 2) return null;
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h == null || m == null) return null;
      return TimeOfDay(hour: h, minute: m);
    }

    final arrival   = parseTime(item.arrivalTime);
    final departure = parseTime(item.departureTime);
    if (arrival == null || departure == null) return null;

    final arrMins = arrival.hour   * 60 + arrival.minute;
    final depMins = departure.hour * 60 + departure.minute;

    // Handle overnight spans (e.g. 22:00 → 02:00 = 4 hrs)
    final diff = depMins >= arrMins
        ? depMins - arrMins
        : (24 * 60 - arrMins) + depMins;

    if (diff <= 0) return null;

    final hrs = diff ~/ 60;
    final min = diff % 60;

    if (hrs == 0)         return '$min min';
    if (min == 0)         return '$hrs ${hrs == 1 ? 'hr' : 'hrs'}';
    return '$hrs ${hrs == 1 ? 'hr' : 'hrs'} $min min';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Expanded form — location + date picker + time pickers + notes
// ─────────────────────────────────────────────────────────────────────────────

class _TimelineItemExpanded extends StatefulWidget {
  final ItineraryItem item;
  final TextEditingController locationCtrl;
  final TextEditingController notesCtrl;
  final bool isDark;
  final VoidCallback onChanged;

  const _TimelineItemExpanded({
    required this.item,
    required this.locationCtrl,
    required this.notesCtrl,
    required this.isDark,
    required this.onChanged,
  });

  @override
  State<_TimelineItemExpanded> createState() => _TimelineItemExpandedState();
}

class _TimelineItemExpandedState extends State<_TimelineItemExpanded> {
  // ── Date helpers ────────────────────────────────────────────────────────────

  /// Parse stored date string ("Mon, Jan 6") back to a DateTime for the picker.
  DateTime? _parseDate(String stored) {
    if (stored.isEmpty) return null;
    try {
      // Format saved by _pickDate: "EEE, MMM d"
      final parts = stored.split(', ');
      if (parts.length == 2) {
        final d = DateFormat('MMM d').parse(parts[1].trim());
        final now = DateTime.now();
        return DateTime(now.year, d.month, d.day);
      }
    } catch (_) {}
    return null;
  }

  Future<void> _pickDate() async {
    final initial = _parseDate(widget.item.date) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null && mounted) {
      setState(() {
        widget.item.date =
        '${DateFormat('EEE').format(picked)}, ${DateFormat('MMM d').format(picked)}';
      });
      widget.onChanged();
    }
  }

  // ── Time helpers ────────────────────────────────────────────────────────────

  /// Parse stored time string ("14:30") back to a TimeOfDay.
  TimeOfDay? _parseTime(String stored) {
    if (stored.isEmpty) return null;
    try {
      final parts = stored.split(':');
      if (parts.length == 2) {
        return TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        );
      }
    } catch (_) {}
    return null;
  }

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickArrival() async {
    final initial = _parseTime(widget.item.arrivalTime) ?? TimeOfDay.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked != null && mounted) {
      setState(() => widget.item.arrivalTime = _formatTime(picked));
      widget.onChanged();
    }
  }

  Future<void> _pickDeparture() async {
    final initial = _parseTime(widget.item.departureTime) ??
        (_parseTime(widget.item.arrivalTime) ?? TimeOfDay.now());
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked != null && mounted) {
      setState(() => widget.item.departureTime = _formatTime(picked));
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;

    return NeuContainer(
      isDark: isDark,
      radius: 14,
      inset: true,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Location text field ─────────────────────────────────────────
          NeuField(
            isDark: isDark,
            controller: widget.locationCtrl,
            label: 'Location',
            icon: Icons.location_on_outlined,
            onChanged: (_) => widget.onChanged(),
          ),

          const SizedBox(height: 10),

          // ── Date picker button ──────────────────────────────────────────
          _PickerButton(
            isDark: isDark,
            icon: Icons.calendar_today_rounded,
            label: widget.item.date.isNotEmpty
                ? widget.item.date
                : 'Pick date',
            hasValue: widget.item.date.isNotEmpty,
            onTap: _pickDate,
            onClear: widget.item.date.isNotEmpty
                ? () => setState(() {
              widget.item.date = '';
              widget.onChanged();
            })
                : null,
          ),

          const SizedBox(height: 10),

          // ── Arrival & Departure time pickers side by side ───────────────
          Row(
            children: [
              Expanded(
                child: _PickerButton(
                  isDark: isDark,
                  icon: Icons.flight_land_outlined,
                  label: widget.item.arrivalTime.isNotEmpty
                      ? widget.item.arrivalTime
                      : 'Arrival',
                  hasValue: widget.item.arrivalTime.isNotEmpty,
                  onTap: _pickArrival,
                  onClear: widget.item.arrivalTime.isNotEmpty
                      ? () => setState(() {
                    widget.item.arrivalTime = '';
                    widget.onChanged();
                  })
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PickerButton(
                  isDark: isDark,
                  icon: Icons.flight_takeoff_outlined,
                  label: widget.item.departureTime.isNotEmpty
                      ? widget.item.departureTime
                      : 'Departure',
                  hasValue: widget.item.departureTime.isNotEmpty,
                  onTap: _pickDeparture,
                  onClear: widget.item.departureTime.isNotEmpty
                      ? () => setState(() {
                    widget.item.departureTime = '';
                    widget.onChanged();
                  })
                      : null,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // ── Notes text field ────────────────────────────────────────────
          NeuField(
            isDark: isDark,
            controller: widget.notesCtrl,
            label: 'Notes',
            icon: Icons.notes_outlined,
            maxLines: 2,
            onChanged: (_) => widget.onChanged(),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable tappable picker button (date or time)
// Mirrors the style of _DatePickerButton in meal_plan_item.dart
// ─────────────────────────────────────────────────────────────────────────────

class _PickerButton extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final String label;
  final bool hasValue;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _PickerButton({
    required this.isDark,
    required this.icon,
    required this.label,
    required this.hasValue,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = hasValue
        ? Neu.textPrimary(isDark)
        : Neu.textSecondary(isDark);
    final subColor = Neu.textSecondary(isDark);

    return GestureDetector(
      onTap: onTap,
      child: NeuContainer(
        isDark: isDark,
        radius: 10,
        inset: true,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 15, color: subColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                  hasValue ? FontWeight.w600 : FontWeight.w400,
                  color: textColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onClear != null)
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close_rounded, size: 14, color: subColor),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add Destination Button
// ─────────────────────────────────────────────────────────────────────────────

class _AddDestinationButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool isDark;

  const _AddDestinationButton({required this.onTap, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return NeuPressable(
      isDark: isDark,
      radius: 14,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_location_outlined,
              size: 18, color: Neu.textSecondary(isDark)),
          const SizedBox(width: 8),
          Text(
            'Add destination',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Neu.textSecondary(isDark),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Highlighted text — wraps matched query spans in amber background
// ─────────────────────────────────────────────────────────────────────────────

class _HighlightedText extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle baseStyle;
  final int? maxLines;
  final TextOverflow? overflow;

  const _HighlightedText({
    required this.text,
    required this.query,
    required this.baseStyle,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return Text(text, style: baseStyle, maxLines: maxLines, overflow: overflow);
    }
    final lower = text.toLowerCase();
    final qLower = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;
    while (start < text.length) {
      final idx = lower.indexOf(qLower, start);
      if (idx == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx)));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + query.length),
        style: const TextStyle(
          backgroundColor: Color(0xFFFFD600),
          color: Colors.black,
          fontWeight: FontWeight.w700,
        ),
      ));
      start = idx + query.length;
    }
    return RichText(
      text: TextSpan(style: baseStyle, children: spans),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ItineraryItem Model
// ─────────────────────────────────────────────────────────────────────────────

class ItineraryItem {
  String id;
  String location;
  String date;
  String arrivalTime;
  String departureTime;
  String notes;

  ItineraryItem({
    required this.id,
    this.location = '',
    this.date = '',
    this.arrivalTime = '',
    this.departureTime = '',
    this.notes = '',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'location': location,
    'date': date,
    'arrivalTime': arrivalTime,
    'departureTime': departureTime,
    'notes': notes,
  };

  factory ItineraryItem.fromJson(Map<String, dynamic> json) => ItineraryItem(
    id: json['id'] ?? const Uuid().v4(),
    location: json['location'] ?? '',
    date: json['date'] ?? '',
    arrivalTime: json['arrivalTime'] ?? '',
    departureTime: json['departureTime'] ?? '',
    notes: json['notes'] ?? '',
  );

  ItineraryItem copyWith({
    String? id,
    String? location,
    String? date,
    String? arrivalTime,
    String? departureTime,
    String? notes,
  }) =>
      ItineraryItem(
        id: id ?? this.id,
        location: location ?? this.location,
        date: date ?? this.date,
        arrivalTime: arrivalTime ?? this.arrivalTime,
        departureTime: departureTime ?? this.departureTime,
        notes: notes ?? this.notes,
      );

  @override
  String toString() =>
      'ItineraryItem(id: $id, location: $location, date: $date)';
}