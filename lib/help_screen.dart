// lib/help_screen.dart
//
// Help & Support screen
// ─────────────────────────────────────────────────────────────────────────────
// Sections:
//   1. Quick Guide  — read-only feature cards, one per note type / major feature
//   2. FAQ          — expandable accordion, collapsed by default
//   3. Feedback & Support — Report a Bug + Request a Feature → pre-filled email
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'language.dart';
import 'neu_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────────────────────────────────────

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base   = Neu.base(isDark);
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: base,
      appBar: AppBar(
        backgroundColor: base,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: NeuIconButton(
          isDark: isDark,
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: Neu.textSecondary(isDark)),
          onTap: () => Navigator.pop(context),
        ),
        leadingWidth: 56,
        title: Text(
          context.tr('help_and_support'),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Neu.textPrimary(isDark),
            letterSpacing: -0.5,
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 8, 16, MediaQuery.of(context).padding.bottom + 32),
        children: [
          // ── Quick Guide ──────────────────────────────────────────────────────
          _SectionHeader(text: context.tr('quick_guide'), isDark: isDark),
          _ExpandableQuickGuide(isDark: isDark, accent: accent),

          const SizedBox(height: 28),

          // ── FAQ ──────────────────────────────────────────────────────────────
          _SectionHeader(text: context.tr('faq'), isDark: isDark),
          _ExpandableFaqSection(isDark: isDark, accent: accent),

          const SizedBox(height: 28),

          // ── Feedback & Support ───────────────────────────────────────────────
          _SectionHeader(
              text: context.tr('feedback_and_support'), isDark: isDark),
          NeuContainer(
            isDark: isDark,
            radius: 16,
            child: Column(
              children: [
                _FeedbackTile(
                  isDark: isDark,
                  accent: accent,
                  icon: Icons.bug_report_outlined,
                  title: context.tr('report_a_bug'),
                  subtitle: context.tr('report_a_bug_subtitle'),
                  emailSubject: '[Noteliha] Bug Report',
                  emailBody:
                  'Describe the bug:\n\n'
                      'Steps to reproduce:\n1.\n2.\n3.\n\n'
                      'Expected behaviour:\n\n'
                      'Actual behaviour:\n\n'
                      'Device / OS:\n',
                ),
                _NeuDivider(isDark: isDark),
                _FeedbackTile(
                  isDark: isDark,
                  accent: accent,
                  icon: Icons.lightbulb_outline_rounded,
                  title: context.tr('request_a_feature'),
                  subtitle: context.tr('request_a_feature_subtitle'),
                  emailSubject: '[Noteliha] Feature Request',
                  emailBody:
                  'Feature idea:\n\n'
                      'Why would this be useful?\n\n'
                      'Any additional details:\n',
                ),
                _NeuDivider(isDark: isDark),
                _FeedbackTile(
                  isDark: isDark,
                  accent: accent,
                  icon: Icons.mail_outline_rounded,
                  title: context.tr('contact_developer'),
                  // FIX: was hardcoded 'support@navkon.com' — now uses translation key
                  subtitle: context.tr('contact_developer_subtitle'),
                  emailSubject: '[Noteliha] General Enquiry',
                  emailBody: '',
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
// Section header — matches settings_screen style exactly
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text;
  final bool isDark;
  const _SectionHeader({required this.text, required this.isDark});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 0, 10),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Divider — matches settings_screen
// ─────────────────────────────────────────────────────────────────────────────

class _NeuDivider extends StatelessWidget {
  final bool isDark;
  const _NeuDivider({required this.isDark});

  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    thickness: 1,
    indent: 16,
    endIndent: 16,
    color: Neu.textSecondary(isDark).withAlpha(30),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Expandable Quick Guide — 2-column grid with expand/collapse functionality
// ─────────────────────────────────────────────────────────────────────────────

class _ExpandableQuickGuide extends StatefulWidget {
  final bool isDark;
  final Color accent;
  const _ExpandableQuickGuide({required this.isDark, required this.accent});

  @override
  State<_ExpandableQuickGuide> createState() => _ExpandableQuickGuideState();
}

class _ExpandableQuickGuideState extends State<_ExpandableQuickGuide>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _ctrl.forward() : _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Expandable header
        NeuPressable(
          isDark: widget.isDark,
          radius: 16,
          onTap: _toggle,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  // FIX: was hardcoded 'Hide guide cards' / 'Show guide cards'
                  _expanded
                      ? context.tr('hide_guide_cards')
                      : context.tr('show_guide_cards'),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Neu.textPrimary(widget.isDark),
                  ),
                ),
              ),
              AnimatedRotation(
                turns: _expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 300),
                child: Icon(Icons.keyboard_arrow_down_rounded,
                    size: 20, color: Neu.textTertiary(widget.isDark)),
              ),
            ],
          ),
        ),
        // Animated content
        SizeTransition(
          sizeFactor: _anim,
          axisAlignment: -1,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _QuickGuideGrid(isDark: widget.isDark, accent: widget.accent),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick Guide Grid — 2-column grid with uniform card heights
// ─────────────────────────────────────────────────────────────────────────────

class _QuickGuideGrid extends StatelessWidget {
  final bool isDark;
  final Color accent;
  const _QuickGuideGrid({required this.isDark, required this.accent});

  @override
  Widget build(BuildContext context) {
    final cards = _guideCards(context);

    return Column(
      children: [
        for (int i = 0; i < cards.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cards[i]),
                  const SizedBox(width: 12),
                  if (i + 1 < cards.length)
                    Expanded(child: cards[i + 1])
                  else
                    const Expanded(child: SizedBox.shrink()),
                ],
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _guideCards(BuildContext context) => [
    _GuideCard(
      isDark: isDark,
      accent: accent,
      icon: Icons.note_rounded,
      title: context.tr('guide_notes_title'),
      points: [
        context.tr('guide_notes_p1'),
        context.tr('guide_notes_p2'),
        context.tr('guide_notes_p3'),
      ],
    ),
    _GuideCard(
      isDark: isDark,
      accent: accent,
      icon: Icons.check_box_rounded,
      title: context.tr('guide_checklist_title'),
      points: [
        context.tr('guide_checklist_p1'),
        context.tr('guide_checklist_p2'),
        context.tr('guide_checklist_p3'),
      ],
    ),
    _GuideCard(
      isDark: isDark,
      accent: accent,
      icon: Icons.flight_rounded,
      title: context.tr('guide_itinerary_title'),
      points: [
        context.tr('guide_itinerary_p1'),
        context.tr('guide_itinerary_p2'),
        context.tr('guide_itinerary_p3'),
      ],
    ),
    _GuideCard(
      isDark: isDark,
      accent: accent,
      icon: Icons.restaurant_menu_rounded,
      title: context.tr('guide_meal_plan_title'),
      points: [
        context.tr('guide_meal_plan_p1'),
        context.tr('guide_meal_plan_p2'),
        context.tr('guide_meal_plan_p3'),
      ],
    ),
    _GuideCard(
      isDark: isDark,
      accent: accent,
      icon: Icons.menu_book_rounded,
      title: context.tr('guide_recipe_title'),
      points: [
        context.tr('guide_recipe_p1'),
        context.tr('guide_recipe_p2'),
        context.tr('guide_recipe_p3'),
      ],
    ),
    _GuideCard(
      isDark: isDark,
      accent: accent,
      icon: Icons.brush_rounded,
      title: context.tr('guide_drawing_title'),
      points: [
        context.tr('guide_drawing_p1'),
        context.tr('guide_drawing_p2'),
        context.tr('guide_drawing_p3'),
      ],
    ),
    _GuideCard(
      isDark: isDark,
      accent: accent,
      icon: Icons.lock_rounded,
      title: context.tr('guide_security_title'),
      points: [
        context.tr('guide_security_p1'),
        context.tr('guide_security_p2'),
        context.tr('guide_security_p3'),
      ],
    ),
    _GuideCard(
      isDark: isDark,
      accent: accent,
      icon: Icons.cloud_sync_rounded,
      title: context.tr('guide_sync_title'),
      points: [
        context.tr('guide_sync_p1'),
        context.tr('guide_sync_p2'),
        context.tr('guide_sync_p3'),
      ],
    ),
    _GuideCard(
      isDark: isDark,
      accent: accent,
      icon: Icons.touch_app_rounded,
      title: context.tr('guide_controls_title'),
      points: [
        context.tr('guide_controls_p1'),
        context.tr('guide_controls_p2'),
        context.tr('guide_controls_p3'),
      ],
    ),
    _GuideCard(
      isDark: isDark,
      accent: accent,
      icon: Icons.manage_search_rounded,
      title: context.tr('guide_organisation_title'),
      points: [
        context.tr('guide_organisation_p1'),
        context.tr('guide_organisation_p2'),
        context.tr('guide_organisation_p3'),
      ],
    ),
  ];
}

class _GuideCard extends StatelessWidget {
  final bool isDark;
  final Color accent;
  final IconData icon;
  final String title;
  final List<String> points;

  const _GuideCard({
    required this.isDark,
    required this.accent,
    required this.icon,
    required this.title,
    required this.points,
  });

  void _showDetailModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _GuideDetailModal(
        isDark: isDark,
        accent: accent,
        icon: icon,
        title: title,
        points: points,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showDetailModal(context),
      child: NeuContainer(
        isDark: isDark,
        radius: 16,
        padding: const EdgeInsets.all(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 140),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.max,
            children: [
              // Icon + title row
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: accent.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 16, color: accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Neu.textPrimary(isDark),
                      ),
                    ),
                  ),
                  // Tap indicator
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: accent.withAlpha(120),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Bullet points
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: points.map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: accent.withAlpha(180),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            p,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.45,
                              color: Neu.textSecondary(isDark),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )).toList(),
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
// Guide Detail Modal — Full-screen view of guide card
// ─────────────────────────────────────────────────────────────────────────────

class _GuideDetailModal extends StatelessWidget {
  final bool isDark;
  final Color accent;
  final IconData icon;
  final String title;
  final List<String> points;

  const _GuideDetailModal({
    required this.isDark,
    required this.accent,
    required this.icon,
    required this.title,
    required this.points,
  });

  @override
  Widget build(BuildContext context) {
    final base = Neu.base(isDark);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: base,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Neu.textTertiary(isDark).withAlpha(60),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: accent.withAlpha(20),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, size: 24, color: accent),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Neu.textPrimary(isDark),
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    NeuIconButton(
                      isDark: isDark,
                      icon: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: Neu.textSecondary(isDark),
                      ),
                      onTap: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              // Divider
              Divider(
                height: 1,
                thickness: 1,
                color: Neu.textSecondary(isDark).withAlpha(30),
              ),
              // Content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    for (int i = 0; i < points.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: accent.withAlpha(18),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '${i + 1}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: accent,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  points[i],
                                  style: TextStyle(
                                    fontSize: 15,
                                    height: 1.6,
                                    color: Neu.textPrimary(isDark),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Expandable FAQ — accordion with expand/collapse functionality
// ─────────────────────────────────────────────────────────────────────────────

class _ExpandableFaqSection extends StatefulWidget {
  final bool isDark;
  final Color accent;
  const _ExpandableFaqSection({required this.isDark, required this.accent});

  @override
  State<_ExpandableFaqSection> createState() => _ExpandableFaqSectionState();
}

class _ExpandableFaqSectionState extends State<_ExpandableFaqSection>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _ctrl.forward() : _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Expandable header
        NeuPressable(
          isDark: widget.isDark,
          radius: 16,
          onTap: _toggle,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  // FIX: was hardcoded 'Hide FAQ' / 'Show FAQ'
                  _expanded
                      ? context.tr('hide_faq')
                      : context.tr('show_faq'),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Neu.textPrimary(widget.isDark),
                  ),
                ),
              ),
              AnimatedRotation(
                turns: _expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 300),
                child: Icon(Icons.keyboard_arrow_down_rounded,
                    size: 20, color: Neu.textTertiary(widget.isDark)),
              ),
            ],
          ),
        ),
        // Animated content
        SizeTransition(
          sizeFactor: _anim,
          axisAlignment: -1,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _FaqSection(isDark: widget.isDark, accent: widget.accent),
          ),
        ),
      ],
    );
  }
}

class _FaqSection extends StatelessWidget {
  final bool isDark;
  final Color accent;
  const _FaqSection({required this.isDark, required this.accent});

  @override
  Widget build(BuildContext context) {
    final items = _faqItems(context);
    return NeuContainer(
      isDark: isDark,
      radius: 16,
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i != 0) _NeuDivider(isDark: isDark),
            _FaqItem(
              isDark: isDark,
              accent: accent,
              question: items[i].$1,
              answer: items[i].$2,
            ),
          ],
        ],
      ),
    );
  }

  // FIX: All FAQ entries now use short snake_case translation keys instead of
  // full English sentences as lookup keys.
  List<(String, String)> _faqItems(BuildContext context) => [
    (
    context.tr('faq_lock_icon_q'),
    context.tr('faq_lock_icon_a'),
    ),
    (
    context.tr('faq_forgot_password_q'),
    context.tr('faq_forgot_password_a'),
    ),
    (
    context.tr('faq_sync_devices_q'),
    context.tr('faq_sync_devices_a'),
    ),
    (
    context.tr('faq_notes_missing_q'),
    context.tr('faq_notes_missing_a'),
    ),
    (
    context.tr('faq_no_account_q'),
    context.tr('faq_no_account_a'),
    ),
    (
    context.tr('faq_export_backup_q'),
    context.tr('faq_export_backup_a'),
    ),
    (
    context.tr('faq_canvas_preview_q'),
    context.tr('faq_canvas_preview_a'),
    ),
    (
    context.tr('faq_biometrics_q'),
    context.tr('faq_biometrics_a'),
    ),
    (
    context.tr('faq_reorder_checklist_q'),
    context.tr('faq_reorder_checklist_a'),
    ),
    (
    context.tr('faq_delete_note_q'),
    context.tr('faq_delete_note_a'),
    ),
    (
    context.tr('faq_recover_note_q'),
    context.tr('faq_recover_note_a'),
    ),
    (
    context.tr('faq_share_note_q'),
    context.tr('faq_share_note_a'),
    ),
    (
    context.tr('faq_change_colour_q'),
    context.tr('faq_change_colour_a'),
    ),
  ];
}

class _FaqItem extends StatefulWidget {
  final bool isDark;
  final Color accent;
  final String question;
  final String answer;

  const _FaqItem({
    required this.isDark,
    required this.accent,
    required this.question,
    required this.answer,
  });

  @override
  State<_FaqItem> createState() => _FaqItemState();
}

class _FaqItemState extends State<_FaqItem>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _ctrl.forward() : _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Question row — always visible, tappable
        NeuPressable(
          isDark: widget.isDark,
          radius: 0,
          onTap: _toggle,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: widget.accent.withAlpha(18),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    'Q',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: widget.accent,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.question,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Neu.textPrimary(widget.isDark),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedRotation(
                turns: _expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 250),
                child: Icon(Icons.keyboard_arrow_down_rounded,
                    size: 18, color: Neu.textTertiary(widget.isDark)),
              ),
            ],
          ),
        ),
        // Answer — animated expand/collapse
        SizeTransition(
          sizeFactor: _anim,
          axisAlignment: -1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(52, 0, 16, 14),
            child: Text(
              widget.answer,
              style: TextStyle(
                fontSize: 13,
                height: 1.55,
                color: Neu.textSecondary(widget.isDark),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Feedback tile — opens pre-filled email via url_launcher
// ─────────────────────────────────────────────────────────────────────────────

class _FeedbackTile extends StatelessWidget {
  final bool isDark;
  final Color accent;
  final IconData icon;
  final String title;
  final String subtitle;
  final String emailSubject;
  final String emailBody;

  const _FeedbackTile({
    required this.isDark,
    required this.accent,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.emailSubject,
    required this.emailBody,
  });

  Future<void> _openEmail(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'support@navkon.com',
      queryParameters: {
        'subject': emailSubject,
        if (emailBody.isNotEmpty) 'body': emailBody,
      },
    );
    if (!await launchUrl(uri)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            // FIX: key 'could_not_open_link' now exists in english.json
            content: Text(context.tr('could_not_open_link')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return NeuPressable(
      isDark: isDark,
      radius: 0,
      onTap: () => _openEmail(context),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: accent),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Neu.textPrimary(isDark),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Neu.textSecondary(isDark),
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded,
              size: 18, color: Neu.textTertiary(isDark)),
        ],
      ),
    );
  }
}