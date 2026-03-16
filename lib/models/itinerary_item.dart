// lib/models/itinerary_item.dart
import 'package:flutter/material.dart';
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

  const ModernItineraryBuilder({
    required this.items,
    required this.onDelete,
    required this.onAddItem,
    required this.onChanged,
    super.key,
  });

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
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      sliver: SliverList.builder(
                        itemCount: widget.items.length,
                        itemBuilder: (context, index) {
                          final item = widget.items[index];
                          final isLast = index == widget.items.length - 1;
                          final isExpanded = _expandedItems[item.id] ?? false;
                          return _ItineraryTimelineItem(
                            key: ValueKey(item.id),
                            item: item,
                            index: index,
                            isLast: isLast,
                            isExpanded: isExpanded,
                            isDark: isDark,
                            onToggleExpanded: () => _toggleExpanded(item.id),
                            onDelete: () {
                              widget.onDelete(index);
                              setState(() => _expandedItems.remove(item.id));
                            },
                            onChanged: widget.onChanged,
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
// Timeline Item
// ─────────────────────────────────────────────────────────────────────────────

class _ItineraryTimelineItem extends StatefulWidget {
  final ItineraryItem item;
  final int index;
  final bool isLast;
  final bool isExpanded;
  final bool isDark;
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
  late TextEditingController _dateCtrl;
  late TextEditingController _arrivalCtrl;
  late TextEditingController _departureCtrl;
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

    _locationCtrl  = TextEditingController(text: widget.item.location);
    _dateCtrl      = TextEditingController(text: widget.item.date);
    _arrivalCtrl   = TextEditingController(text: widget.item.arrivalTime);
    _departureCtrl = TextEditingController(text: widget.item.departureTime);
    _notesCtrl     = TextEditingController(text: widget.item.notes);
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
    _dateCtrl.dispose();
    _arrivalCtrl.dispose();
    _departureCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _updateItem() {
    widget.item.location      = _locationCtrl.text;
    widget.item.date          = _dateCtrl.text;
    widget.item.arrivalTime   = _arrivalCtrl.text;
    widget.item.departureTime = _departureCtrl.text;
    widget.item.notes         = _notesCtrl.text;
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final accentColor = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Timeline spine
              SizedBox(
                width: 40,
                child: Column(
                  children: [
                    // Numbered circle — neumorphic raised
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
                    // Connector line
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
              // Content
              Expanded(
                child: Column(
                  children: [
                    _TimelineItemHeader(
                      item: widget.item,
                      isExpanded: widget.isExpanded,
                      isDark: isDark,
                      onTap: widget.onToggleExpanded,
                      onDelete: widget.onDelete,
                    ),
                    SizeTransition(
                      sizeFactor: _expandAnimation,
                      axisAlignment: -1,
                      child: _TimelineItemExpanded(
                        locationCtrl:  _locationCtrl,
                        dateCtrl:      _dateCtrl,
                        arrivalCtrl:   _arrivalCtrl,
                        departureCtrl: _departureCtrl,
                        notesCtrl:     _notesCtrl,
                        isDark:        isDark,
                        onChanged:     _updateItem,
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
// Header (collapsed view)
// ─────────────────────────────────────────────────────────────────────────────

class _TimelineItemHeader extends StatelessWidget {
  final ItineraryItem item;
  final bool isExpanded;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _TimelineItemHeader({
    required this.item,
    required this.isExpanded,
    required this.isDark,
    required this.onTap,
    required this.onDelete,
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
                child: Text(
                  item.location.isNotEmpty ? item.location : 'Destination',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              // Delete button
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
        ],
      ),
    );
  }

  String _formatTimeRange() {
    final a = item.arrivalTime.isNotEmpty   ? item.arrivalTime   : 'TBD';
    final d = item.departureTime.isNotEmpty ? item.departureTime : 'TBD';
    return '$a – $d';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Expanded content
// ─────────────────────────────────────────────────────────────────────────────

class _TimelineItemExpanded extends StatelessWidget {
  final TextEditingController locationCtrl;
  final TextEditingController dateCtrl;
  final TextEditingController arrivalCtrl;
  final TextEditingController departureCtrl;
  final TextEditingController notesCtrl;
  final bool isDark;
  final VoidCallback onChanged;

  const _TimelineItemExpanded({
    required this.locationCtrl,
    required this.dateCtrl,
    required this.arrivalCtrl,
    required this.departureCtrl,
    required this.notesCtrl,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return NeuContainer(
      isDark: isDark,
      radius: 14,
      inset: true,
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _NeuField(
            label: 'Location',
            icon: Icons.location_on_outlined,
            controller: locationCtrl,
            isDark: isDark,
            onChanged: onChanged,
          ),
          const SizedBox(height: 8),
          _NeuField(
            label: 'Date',
            icon: Icons.calendar_today_outlined,
            controller: dateCtrl,
            isDark: isDark,
            onChanged: onChanged,
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: _NeuField(
                label: 'Arrival',
                icon: Icons.flight_land_outlined,
                controller: arrivalCtrl,
                isDark: isDark,
                onChanged: onChanged,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _NeuField(
                label: 'Departure',
                icon: Icons.flight_takeoff_outlined,
                controller: departureCtrl,
                isDark: isDark,
                onChanged: onChanged,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          _NeuField(
            label: 'Notes',
            icon: Icons.notes_outlined,
            controller: notesCtrl,
            isDark: isDark,
            maxLines: 2,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Neumorphic text field
// ─────────────────────────────────────────────────────────────────────────────

class _NeuField extends StatelessWidget {
  final String label;
  final IconData icon;
  final TextEditingController controller;
  final bool isDark;
  final VoidCallback onChanged;
  final int maxLines;

  const _NeuField({
    required this.label,
    required this.icon,
    required this.controller,
    required this.isDark,
    required this.onChanged,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return NeuField(
      isDark: isDark,
      controller: controller,
      label: label,
      icon: icon,
      maxLines: maxLines,
      onChanged: (_) => onChanged(),
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
