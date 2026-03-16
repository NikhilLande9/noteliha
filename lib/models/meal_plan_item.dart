// lib/models/meal_plan_item.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../neu_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Modern Meal Plan Timeline with Neumorphic Cards
// ─────────────────────────────────────────────────────────────────────────────

class ModernMealPlanBuilder extends StatefulWidget {
  final List<MealPlanItem> items;
  final Function(int) onDelete;
  final VoidCallback onAddItem;
  final Function() onChanged;

  const ModernMealPlanBuilder({
    required this.items,
    required this.onDelete,
    required this.onAddItem,
    required this.onChanged,
    super.key,
  });

  @override
  State<ModernMealPlanBuilder> createState() => _ModernMealPlanBuilderState();
}

class _ModernMealPlanBuilderState extends State<ModernMealPlanBuilder> {
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
                          return _MealPlanTimelineItem(
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
          child: _AddMealDayButton(onTap: widget.onAddItem, isDark: isDark),
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
              Icons.restaurant_outlined,
              size: 36,
              color: Neu.textSecondary(isDark),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No meals planned yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Neu.textPrimary(isDark),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add your first meal day to start planning',
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

class _MealPlanTimelineItem extends StatefulWidget {
  final MealPlanItem item;
  final int index;
  final bool isLast;
  final bool isExpanded;
  final bool isDark;
  final VoidCallback onToggleExpanded;
  final VoidCallback onDelete;
  final VoidCallback onChanged;

  const _MealPlanTimelineItem({
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
  State<_MealPlanTimelineItem> createState() => _MealPlanTimelineItemState();
}

class _MealPlanTimelineItemState extends State<_MealPlanTimelineItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _expandController;
  late Animation<double> _expandAnimation;
  late Map<String, TextEditingController> _mealControllers;

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

    _mealControllers = {
      for (final meal in widget.item.meals)
        meal['id'] as String:
            TextEditingController(text: meal['value'] as String? ?? ''),
    };
  }

  @override
  void didUpdateWidget(covariant _MealPlanTimelineItem oldWidget) {
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
    for (final c in _mealControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _updateMeal(String mealId, String value) {
    final idx = widget.item.meals.indexWhere((m) => m['id'] == mealId);
    if (idx != -1) {
      widget.item.meals[idx]['value'] = value;
      widget.onChanged();
    }
  }

  void _addMeal() {
    setState(() {
      final newId = const Uuid().v4();
      widget.item.meals.add({'id': newId, 'name': 'Meal', 'value': ''});
      _mealControllers[newId] = TextEditingController();
      widget.onChanged();
    });
  }

  void _removeMeal(String mealId) {
    setState(() {
      widget.item.meals.removeWhere((m) => m['id'] == mealId);
      _mealControllers[mealId]?.dispose();
      _mealControllers.remove(mealId);
      widget.onChanged();
    });
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
                    NeuContainer(
                      isDark: isDark,
                      radius: 16,
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: Center(
                          child: Icon(
                            Icons.restaurant_rounded,
                            size: 16,
                            color: accentColor,
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
              // Content
              Expanded(
                child: Column(
                  children: [
                    _MealPlanItemHeader(
                      item: widget.item,
                      isExpanded: widget.isExpanded,
                      isDark: isDark,
                      onTap: widget.onToggleExpanded,
                      onDelete: widget.onDelete,
                    ),
                    SizeTransition(
                      sizeFactor: _expandAnimation,
                      axisAlignment: -1,
                      child: _MealPlanItemExpanded(
                        item: widget.item,
                        mealControllers: _mealControllers,
                        isDark: isDark,
                        onUpdateMeal: _updateMeal,
                        onAddMeal: _addMeal,
                        onRemoveMeal: _removeMeal,
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

class _MealPlanItemHeader extends StatelessWidget {
  final MealPlanItem item;
  final bool isExpanded;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _MealPlanItemHeader({
    required this.item,
    required this.isExpanded,
    required this.isDark,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final subColor = Neu.textSecondary(isDark);

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
                child: _DatePickerButton(
                  day: item.day,
                  isDark: isDark,
                  onDateChanged: (newDate) {
                    item.day = newDate;
                  },
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
          if (item.meals.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.dining_rounded, size: 12, color: subColor),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  _mealPreview(),
                  style: TextStyle(fontSize: 12, color: subColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  String _mealPreview() {
    return item.meals
        .where((m) => (m['value'] as String?)?.isNotEmpty ?? false)
        .map((m) => m['value'])
        .join(' • ');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Date Picker Button
// ─────────────────────────────────────────────────────────────────────────────

class _DatePickerButton extends StatelessWidget {
  final String day;
  final bool isDark;
  final Function(String) onDateChanged;

  const _DatePickerButton({
    required this.day,
    required this.isDark,
    required this.onDateChanged,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = Neu.textPrimary(isDark);
    final subColor  = Neu.textSecondary(isDark);

    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _parseDate() ?? DateTime.now(),
          firstDate: DateTime.now().subtract(const Duration(days: 365)),
          lastDate: DateTime.now().add(const Duration(days: 365)),
        );
        if (picked != null) {
          final dayName = DateFormat('EEEE').format(picked);
          final date = DateFormat('MMM d').format(picked);
          onDateChanged('$dayName, $date');
        }
      },
      child: NeuContainer(
        isDark: isDark,
        radius: 10,
        inset: true,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.calendar_today_rounded, size: 15, color: subColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _formatDate(),
                style: TextStyle(
                  fontSize: 13,
                  color: textColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate() {
    if (day.isEmpty) {
      final today = DateTime.now();
      return '${DateFormat('EEEE').format(today)}, ${DateFormat('MMM d').format(today)}';
    }
    return day;
  }

  DateTime? _parseDate() {
    if (day.isEmpty) return null;
    try {
      final parts = day.split(',');
      if (parts.length == 2) {
        final date = DateFormat('MMM d').parse(parts[1].trim());
        final now = DateTime.now();
        return DateTime(now.year, date.month, date.day);
      }
    } catch (_) {}
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Expanded content
// ─────────────────────────────────────────────────────────────────────────────

class _MealPlanItemExpanded extends StatelessWidget {
  final MealPlanItem item;
  final Map<String, TextEditingController> mealControllers;
  final bool isDark;
  final Function(String, String) onUpdateMeal;
  final VoidCallback onAddMeal;
  final Function(String) onRemoveMeal;

  const _MealPlanItemExpanded({
    required this.item,
    required this.mealControllers,
    required this.isDark,
    required this.onUpdateMeal,
    required this.onAddMeal,
    required this.onRemoveMeal,
  });

  @override
  Widget build(BuildContext context) {
    final subColor = Neu.textSecondary(isDark);

    return NeuContainer(
      isDark: isDark,
      radius: 14,
      inset: true,
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          for (int i = 0; i < item.meals.length; i++) ...[
            _MealField(
              mealId: item.meals[i]['id'] as String,
              label: item.meals[i]['name'] as String? ?? 'Meal',
              controller: mealControllers[item.meals[i]['id']]!,
              isDark: isDark,
              onChanged: (v) => onUpdateMeal(item.meals[i]['id'] as String, v),
              onRemove: () => onRemoveMeal(item.meals[i]['id'] as String),
              showRemoveButton: item.meals.length > 1,
            ),
            if (i < item.meals.length - 1) const SizedBox(height: 8),
          ],
          const SizedBox(height: 12),
          // Add meal button
          NeuPressable(
            isDark: isDark,
            radius: 10,
            onTap: onAddMeal,
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_rounded, size: 16, color: subColor),
                const SizedBox(width: 6),
                Text(
                  'Add meal',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: subColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Meal Field
// ─────────────────────────────────────────────────────────────────────────────

class _MealField extends StatelessWidget {
  final String mealId;
  final String label;
  final TextEditingController controller;
  final bool isDark;
  final Function(String) onChanged;
  final VoidCallback onRemove;
  final bool showRemoveButton;

  const _MealField({
    required this.mealId,
    required this.label,
    required this.controller,
    required this.isDark,
    required this.onChanged,
    required this.onRemove,
    required this.showRemoveButton,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: NeuField(
            isDark: isDark,
            controller: controller,
            label: label,
            hint: 'What are you eating?',
            maxLines: null,
            minLines: 2,
            onChanged: onChanged,
          ),
        ),
        if (showRemoveButton) ...[
          const SizedBox(width: 8),
          NeuIconButton(
            isDark: isDark,
            size: 36,
            icon: Icon(Icons.close_rounded,
                size: 16, color: Colors.red.shade400),
            onTap: onRemove,
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add Meal Day Button
// ─────────────────────────────────────────────────────────────────────────────

class _AddMealDayButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool isDark;

  const _AddMealDayButton({required this.onTap, required this.isDark});

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
          Icon(Icons.add_rounded, size: 18, color: Neu.textSecondary(isDark)),
          const SizedBox(width: 8),
          Text(
            'Add day',
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
// MealPlanItem Model
// ─────────────────────────────────────────────────────────────────────────────

class MealPlanItem {
  String id;
  String day;
  List<Map<String, dynamic>> meals;

  MealPlanItem({
    required this.id,
    this.day = '',
    List<Map<String, dynamic>>? meals,
  }) : meals = meals ?? _defaultMeals();

  static List<Map<String, dynamic>> _defaultMeals() => [
        {'id': const Uuid().v4(), 'name': 'Breakfast', 'value': ''},
        {'id': const Uuid().v4(), 'name': 'Lunch',     'value': ''},
        {'id': const Uuid().v4(), 'name': 'Dinner',    'value': ''},
        {'id': const Uuid().v4(), 'name': 'Snacks',    'value': ''},
      ];

  Map<String, dynamic> toJson() => {'id': id, 'day': day, 'meals': meals};

  factory MealPlanItem.fromJson(Map<String, dynamic> json) => MealPlanItem(
        id: json['id'] ?? const Uuid().v4(),
        day: json['day'] ?? '',
        meals: (json['meals'] as List?)?.cast<Map<String, dynamic>>() ??
            _defaultMeals(),
      );

  MealPlanItem copyWith({
    String? id,
    String? day,
    List<Map<String, dynamic>>? meals,
  }) =>
      MealPlanItem(
        id: id ?? this.id,
        day: day ?? this.day,
        meals: meals ?? List.from(this.meals),
      );

  @override
  String toString() => 'MealPlanItem(id: $id, day: $day)';
}
