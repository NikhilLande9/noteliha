// lib/settings_screen.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

import 'models.dart';
import 'theme_helper.dart';
import 'neu_theme.dart';
import 'notes_provider.dart';
import 'update_state.dart';
import 'language.dart';
import 'help_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Connectivity helper
// ─────────────────────────────────────────────────────────────────────────────

Future<bool> _hasInternet() async {
  // On web, dart:io is unavailable and cross-origin probes are CORS-blocked.
  // Skip the check entirely — if there's no internet the Drive call will
  // fail with its own error, which is already handled by the sync error banner.
  if (kIsWeb) return true;

  try {
    final result = await InternetAddress.lookup('google.com')
        .timeout(const Duration(seconds: 5));
    return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
  } catch (_) {
    return false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Settings Screen
// ─────────────────────────────────────────────────────────────────────────────

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _versionString = '…';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _versionString = '${info.version}+${info.buildNumber}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final prov = Provider.of<NotesProvider>(context);
    final settings = Provider.of<AppSettingsProvider>(context);
    final langProv = Provider.of<LanguageProvider>(context);
    final accent = Theme.of(context).colorScheme.primary;
    final base = Neu.base(isDark);

    final currentLangCode = langProv.languageCode;

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
          context.tr('settings'),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Neu.textPrimary(isDark),
            letterSpacing: -0.5,
          ),
        ),
      ),
      body: Column(
        children: [
          // Sync status banner
          if (prov.syncStatusMessage != null)
            _SyncBanner(prov: prov, isDark: isDark),

          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                  16, 8, 16, MediaQuery.of(context).padding.bottom + 24),
              children: [
                // ── Account ─────────────────────────────────────────────────
                _SectionHeader(text: context.tr('account'), isDark: isDark),
                NeuContainer(
                  isDark: isDark,
                  radius: 16,
                  child: prov.user == null
                      ? _SignInTile(prov: prov, isDark: isDark, accent: accent)
                      : _LoggedInTile(
                      prov: prov, isDark: isDark, accent: accent),
                ),

                const SizedBox(height: 24),

                // ── Language ─────────────────────────────────────────────────
                _SectionHeader(text: context.tr('language'), isDark: isDark),
                NeuContainer(
                  isDark: isDark,
                  radius: 16,
                  child: NeuPressable(
                    isDark: isDark,
                    radius: 16,
                    onTap: () => _showLanguagePicker(context, isDark, langProv),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        NeuContainer(
                          isDark: isDark,
                          radius: 10,
                          padding: const EdgeInsets.all(8),
                          child: Icon(Icons.language_rounded,
                              size: 18, color: accent),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.tr('language'),
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: Neu.textPrimary(isDark)),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                    () {
                                  final flag = AppTranslations.getLanguageFlag(
                                      currentLangCode);
                                  final english =
                                  AppTranslations.getLanguageName(
                                      currentLangCode);
                                  final native =
                                  AppTranslations.getNativeLanguageName(
                                      currentLangCode);
                                  return native != english
                                      ? '$flag  $english · $native'
                                      : '$flag  $english';
                                }(),
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Neu.textSecondary(isDark)),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            size: 18, color: Neu.textTertiary(isDark)),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // ── Appearance ───────────────────────────────────────────────
                _SectionHeader(text: context.tr('appearance'), isDark: isDark),
                NeuContainer(
                  isDark: isDark,
                  radius: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Dark mode toggle
                      _NeuSwitchTile(
                        isDark: isDark,
                        icon: settings.isDarkMode
                            ? Icons.dark_mode_rounded
                            : Icons.light_mode_rounded,
                        title: context.tr('dark_mode'),
                        subtitle: settings.isDarkMode
                            ? context.tr('on')
                            : context.tr('off'),
                        value: settings.isDarkMode,
                        accent: accent,
                        onChanged: (_) => settings.toggleDarkMode(),
                      ),

                      _NeuDivider(isDark: isDark),

                      // App color picker
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                        child: Text(context.tr('app_color'),
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: Neu.textPrimary(isDark))),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: AppTheme.values.map((theme) {
                            final isSelected = settings.appTheme == theme;
                            final color = AppSettingsProvider.seedColor(theme);
                            return GestureDetector(
                              onTap: () => settings.setAppTheme(theme),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: color
                                          .withAlpha(isSelected ? 255 : 160),
                                      shape: BoxShape.circle,
                                      boxShadow: isSelected
                                          ? Neu.raisedSm(isDark)
                                          : null,
                                      border: isSelected
                                          ? Border.all(
                                          color: Neu.textPrimary(isDark)
                                              .withAlpha(120),
                                          width: 2.5)
                                          : null,
                                    ),
                                    child: isSelected
                                        ? const Icon(Icons.check_rounded,
                                        color: Colors.white, size: 20)
                                        : null,
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    AppSettingsProvider.themeName(theme),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                      color: isSelected
                                          ? accent
                                          : Neu.textSecondary(isDark),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),

                      _NeuDivider(isDark: isDark),

                      // Visual theme picker
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                        child: Text(context.tr('visual_style'),
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: Neu.textPrimary(isDark))),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: AppVisualTheme.values.map((vt) {
                            final isSelected = settings.visualTheme == vt;
                            final isPremium = Neu.isPremium(vt);
                            return GestureDetector(
                              onTap: isPremium
                                  ? () => _showLockedDialog(context, isDark, vt)
                                  : () => settings.setVisualTheme(vt),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 80,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 8),
                                decoration: BoxDecoration(
                                  color: Neu.base(isDark),
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: isSelected
                                      ? Neu.inset(isDark)
                                      : Neu.raisedSm(isDark),
                                ),
                                child: Column(
                                  children: [
                                    Stack(
                                      alignment: Alignment.topRight,
                                      children: [
                                        Icon(
                                          Neu.visualThemeIcon(vt),
                                          size: 26,
                                          color: isSelected
                                              ? accent
                                              : Neu.textSecondary(isDark),
                                        ),
                                        if (isPremium)
                                          Positioned(
                                            top: -2,
                                            right: -4,
                                            child: Icon(
                                              Icons.lock_rounded,
                                              size: 12,
                                              color: Neu.textTertiary(isDark),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      Neu.visualThemeName(vt),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: isSelected
                                            ? accent
                                            : Neu.textSecondary(isDark),
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    AnimatedContainer(
                                      duration:
                                      const Duration(milliseconds: 200),
                                      width: isSelected ? 18 : 6,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? accent
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
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

                const SizedBox(height: 24),

                // ── Data ─────────────────────────────────────────────────────
                _SectionHeader(text: context.tr('data'), isDark: isDark),
                NeuContainer(
                  isDark: isDark,
                  radius: 16,
                  child: _NeuActionTile(
                    icon: Icons.delete_sweep_outlined,
                    title: context.tr('recycle_bin'),
                    subtitle: context.tr('deleted_notes'),
                    isDark: isDark,
                    accent: accent,
                    enabled: true,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const RecycleBinScreen()),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // ── Storage ──────────────────────────────────────────────────
                _SectionHeader(text: context.tr('storage'), isDark: isDark),
                NeuContainer(
                  isDark: isDark,
                  radius: 16,
                  child: _BackupRestoreSection(
                    prov: prov,
                    isDark: isDark,
                    accent: accent,
                  ),
                ),

                const SizedBox(height: 24),

                // ── Updates (Android only) ───────────────────────────────────
                if (!kIsWeb && Platform.isAndroid) ...[
                  _SectionHeader(text: context.tr('updates'), isDark: isDark),
                  NeuContainer(
                    isDark: isDark,
                    radius: 16,
                    child: _UpdateChecker(isDark: isDark, accent: accent),
                  ),
                  const SizedBox(height: 24),
                ],

                // ── Web App ──────────────────────────────────────────────────
                _SectionHeader(text: context.tr('web_app'), isDark: isDark),
                NeuContainer(
                  isDark: isDark,
                  radius: 16,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                        child: Row(
                          children: [
                            NeuContainer(
                              isDark: isDark,
                              radius: 10,
                              padding: const EdgeInsets.all(8),
                              child: Icon(Icons.public_rounded,
                                  size: 18, color: accent),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    context.tr('web_app_access_title'),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: Neu.textPrimary(isDark),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    context.tr('web_app_access_subtitle'),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Neu.textSecondary(isDark),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        child: _WebAppBanner(isDark: isDark, accent: accent),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── Share ────────────────────────────────────────────────────
                _SectionHeader(text: context.tr('share'), isDark: isDark),
                _ReferralCard(isDark: isDark, accent: accent),

                const SizedBox(height: 24),

                // ── Help & Support ───────────────────────────────────────────
                _SectionHeader(
                    text: context.tr('help_and_support'), isDark: isDark),
                NeuContainer(
                  isDark: isDark,
                  radius: 16,
                  child: NeuPressable(
                    isDark: isDark,
                    radius: 16,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const HelpScreen()),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        NeuContainer(
                          isDark: isDark,
                          radius: 10,
                          padding: const EdgeInsets.all(8),
                          child: Icon(Icons.help_outline_rounded,
                              size: 18, color: accent),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.tr('help_and_support'),
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    color: Neu.textPrimary(isDark)),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                context.tr('help_and_support_subtitle'),
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Neu.textSecondary(isDark)),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            size: 18, color: Neu.textTertiary(isDark)),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // ── About ────────────────────────────────────────────────────
                _SectionHeader(text: context.tr('about'), isDark: isDark),
                NeuContainer(
                  isDark: isDark,
                  radius: 16,
                  child: Column(
                    children: [
                      _NeuInfoTile(
                        icon: Icons.info_outline_rounded,
                        title: context.tr('version'),
                        trailing: Text(_versionString,
                            style: TextStyle(
                                color: Neu.textTertiary(isDark), fontSize: 13)),
                        isDark: isDark,
                        accent: accent,
                      ),
                      _NeuDivider(isDark: isDark),
                      _NeuInfoTile(
                        icon: Icons.storage_rounded,
                        title: context.tr('storage'),
                        subtitle: context.tr('storage_subtitle'),
                        isDark: isDark,
                        accent: accent,
                      ),
                      _NeuDivider(isDark: isDark),
                      _NeuLinkTile(
                        icon: Icons.menu_book_rounded,
                        label: context.tr('documentation'),
                        subtitle: 'noteliha.navkon.com', // cspell:disable-line
                        url: 'https://noteliha.navkon.com', // cspell:disable-line
                        isDark: isDark,
                        accent: accent,
                      ),
                      _NeuDivider(isDark: isDark),
                      _NeuLinkTile(
                        icon: Icons.privacy_tip_outlined,
                        label: context.tr('privacy_policy'),
                        subtitle: context.tr('privacy_policy_subtitle'),
                        url: 'https://noteliha.navkon.com/PRIVACY_POLICY.html', // cspell:disable-line
                        isDark: isDark,
                        accent: accent,
                      ),
                      _NeuDivider(isDark: isDark),
                      _NeuLinkTile(
                        icon: Icons.gavel_rounded,
                        label: context.tr('terms_of_service'),
                        subtitle: context.tr('terms_subtitle'),
                        url:
                        'https://noteliha.navkon.com/TERMS_OF_SERVICE.html', // cspell:disable-line
                        isDark: isDark,
                        accent: accent,
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
  }

  // ── Language picker bottom sheet ───────────────────────────────────────────

  void _showLanguagePicker(
      BuildContext context, bool isDark, LanguageProvider langProv) {
    final accent = Theme.of(context).colorScheme.primary;
    final base = Neu.base(isDark);
    final supported = AppTranslations.supportedLocales;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final filtered = supported.where((locale) {
              if (query.isEmpty) return true;
              final code = locale.languageCode;
              final englishName =
              AppTranslations.getLanguageName(code).toLowerCase();
              final nativeName =
              AppTranslations.getNativeLanguageName(code).toLowerCase();
              final q = query.toLowerCase();
              return englishName.contains(q) || nativeName.contains(q);
            }).toList();

            return Padding(
              padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Container(
                decoration: BoxDecoration(
                  color: base,
                  borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: Neu.raised(isDark),
                ),
                padding: EdgeInsets.fromLTRB(
                    20, 16, 20, MediaQuery.of(ctx).padding.bottom + 24),
                // Allow the sheet to grow up to 85 % of the screen
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.85,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle bar
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Neu.textTertiary(isDark).withAlpha(80),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    // Header: English + native name
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: AppTranslations.translate('language'),
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Neu.textPrimary(isDark),
                              letterSpacing: -0.3,
                            ),
                          ),
                              () {
                            final native =
                            AppTranslations.getNativeLanguageName(
                                AppTranslations.currentLocale.languageCode);
                            final english =
                            AppTranslations.translate('language');
                            if (native == english) return const TextSpan();
                            return TextSpan(
                              text: '  ·  $native',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                                color: Neu.textSecondary(isDark),
                                letterSpacing: 0,
                              ),
                            );
                          }(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Search field ──────────────────────────────────────────
                    NeuContainer(
                      isDark: isDark,
                      radius: 12,
                      padding: EdgeInsets.zero,
                      child: TextField(
                        autofocus: false,
                        onChanged: (v) => setSheetState(() => query = v),
                        style: TextStyle(
                            fontSize: 14, color: Neu.textPrimary(isDark)),
                        decoration: InputDecoration(
                          hintText:
                          AppTranslations.translate('search_language'),
                          hintStyle: TextStyle(
                              fontSize: 14, color: Neu.textTertiary(isDark)),
                          prefixIcon: Icon(Icons.search_rounded,
                              size: 18, color: Neu.textTertiary(isDark)),
                          suffixIcon: query.isNotEmpty
                              ? GestureDetector(
                            onTap: () => setSheetState(() => query = ''),
                            child: Icon(Icons.close_rounded,
                                size: 16,
                                color: Neu.textTertiary(isDark)),
                          )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ── Language list ─────────────────────────────────────────
                    Flexible(
                      child: filtered.isEmpty
                          ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            AppTranslations.translate(
                                'no_languages_found'),
                            style: TextStyle(
                                fontSize: 14,
                                color: Neu.textSecondary(isDark)),
                          ),
                        ),
                      )
                          : ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final locale = filtered[i];
                          final code = locale.languageCode;
                          final isSelected =
                              langProv.languageCode == code;
                          final englishName =
                          AppTranslations.getLanguageName(code);
                          final nativeName =
                          AppTranslations.getNativeLanguageName(code);
                          return NeuPressable(
                            isDark: isDark,
                            radius: 14,
                            onTap: () async {
                              await langProv.setLocale(locale);
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 11),
                            child: Row(
                              children: [
                                Text(
                                  AppTranslations.getLanguageFlag(code),
                                  style: const TextStyle(fontSize: 22),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        englishName,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: isSelected
                                              ? FontWeight.w700
                                              : FontWeight.w600,
                                          color: isSelected
                                              ? accent
                                              : Neu.textPrimary(isDark),
                                        ),
                                      ),
                                      if (nativeName != englishName) ...[
                                        const SizedBox(height: 1),
                                        Text(
                                          nativeName,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w400,
                                            color: isSelected
                                                ? accent.withAlpha(180)
                                                : Neu.textSecondary(
                                                isDark),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  Icon(Icons.check_rounded,
                                      size: 18, color: accent),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showLockedDialog(
      BuildContext context, bool isDark, AppVisualTheme theme) {
    final base = Neu.base(isDark);
    final accent = Theme.of(context).colorScheme.primary;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: base,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(20),
            boxShadow: Neu.raised(isDark),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_rounded, size: 36, color: accent),
              const SizedBox(height: 14),
              Text(
                '${Neu.visualThemeName(theme)} ${context.tr('is_premium')}',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    color: Neu.textPrimary(isDark)),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('premium_unlock_desc'),
                textAlign: TextAlign.center,
                style:
                TextStyle(fontSize: 13, color: Neu.textSecondary(isDark)),
              ),
              const SizedBox(height: 20),
              NeuPressable(
                isDark: isDark,
                radius: 12,
                onTap: () => Navigator.pop(ctx),
                padding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                child: Text(context.tr('maybe_later'),
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Neu.textSecondary(isDark))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Update Checker — Android only, hidden on web
// ─────────────────────────────────────────────────────────────────────────────

class _UpdateChecker extends StatelessWidget {
  final bool isDark;
  final Color accent;
  const _UpdateChecker({required this.isDark, required this.accent});

  @override
  Widget build(BuildContext context) {
    // Rebuild whenever the language changes so tr() returns fresh strings.
    context.watch<LanguageProvider>();
    return ListenableBuilder(
      listenable: UpdateStateNotifier.instance,
      builder: (context, _) {
        final updater = UpdateStateNotifier.instance;
        final state = updater.state;

        final isLoading = state == UpdateAvailableState.checking ||
            state == UpdateAvailableState.downloading;

        final label = switch (state) {
          UpdateAvailableState.idle => context.tr('check_for_updates'),
          UpdateAvailableState.checking => context.tr('checking_for_updates'),
          UpdateAvailableState.available => context.tr('update_available'),
          UpdateAvailableState.upToDate => context.tr('all_up_to_date'),
          UpdateAvailableState.downloading => context.tr('downloading'),
          UpdateAvailableState.error =>
          updater.errorMessage ?? context.tr('error'),
        };

        final icon = switch (state) {
          UpdateAvailableState.available => Icons.new_releases_rounded,
          UpdateAvailableState.upToDate => Icons.check_circle_outline_rounded,
          UpdateAvailableState.downloading => Icons.downloading_rounded,
          UpdateAvailableState.error => Icons.error_outline_rounded,
          _ => Icons.system_update_rounded,
        };

        final iconColor = switch (state) {
          UpdateAvailableState.upToDate => Colors.green.shade500,
          UpdateAvailableState.error => Colors.red.shade400,
          _ => accent,
        };

        return NeuPressable(
          isDark: isDark,
          radius: 0,
          onTap: isLoading
              ? () {}
              : state == UpdateAvailableState.available
              ? () async {
            final success =
            await UpdateStateNotifier.instance.startUpdate();
            if (success && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                // ignore: prefer_const_constructors
                SnackBar(
                  content: Text(context.tr('update_downloaded')),
                  behavior: SnackBarBehavior.floating,
                  // ignore: prefer_const_constructors
                  action: SnackBarAction(
                    label: context.tr('restart'),
                    onPressed: UpdateStateNotifier.completeUpdate,
                  ),
                  duration: const Duration(seconds: 8),
                ),
              );
            }
          }
              : () async {
            final result = await UpdateStateNotifier.instance
                .checkForUpdate(silent: false);
            if (context.mounted) {
              if (result == UpdateAvailableState.upToDate) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded,
                            color: Colors.white, size: 18),
                        const SizedBox(width: 10),
                        Text(context.tr('all_up_to_date')),
                      ],
                    ),
                    backgroundColor: Colors.green.shade600,
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 3),
                  ),
                );
              } else if (result == UpdateAvailableState.error) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        UpdateStateNotifier.instance.errorMessage ??
                            context.tr('update_check_failed')),
                    backgroundColor: Colors.red.shade600,
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 4),
                  ),
                );
              }
            }
          },
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              isLoading
                  ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: accent),
              )
                  : Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: state == UpdateAvailableState.error
                            ? Colors.red.shade400
                            : Neu.textPrimary(isDark),
                      ),
                    ),
                    if (state == UpdateAvailableState.available) ...[
                      const SizedBox(height: 2),
                      Text(
                        context.tr('tap_to_download'),
                        style: TextStyle(
                            fontSize: 12, color: Neu.textSecondary(isDark)),
                      ),
                    ],
                    if (state == UpdateAvailableState.upToDate) ...[
                      const SizedBox(height: 2),
                      Text(
                        context.tr('on_latest_version'),
                        style: TextStyle(
                            fontSize: 12, color: Neu.textSecondary(isDark)),
                      ),
                    ],
                  ],
                ),
              ),
              if (state == UpdateAvailableState.idle ||
                  state == UpdateAvailableState.available)
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: Neu.textTertiary(isDark)),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Web App Banner — URL display + open button
// ─────────────────────────────────────────────────────────────────────────────

class _WebAppBanner extends StatelessWidget {
  final bool isDark;
  final Color accent;

  const _WebAppBanner({required this.isDark, required this.accent});

  static const String _webUrl = 'https://note-liha.web.app/';

  Future<void> _launch(BuildContext context) async {
    final uri = Uri.parse(_webUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('could_not_open_link')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return NeuContainer(
      isDark: isDark,
      radius: 12,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.link_rounded, size: 16, color: Neu.textTertiary(isDark)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'note-liha.web.app',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: accent,
                letterSpacing: 0.1,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          NeuPressable(
            isDark: isDark,
            radius: 8,
            onTap: () => _launch(context),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.open_in_browser_rounded, size: 15, color: accent),
                const SizedBox(width: 5),
                Text(
                  context.tr('open'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: accent,
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
// Sync status banner
// ─────────────────────────────────────────────────────────────────────────────

class _SyncBanner extends StatelessWidget {
  final NotesProvider prov;
  final bool isDark;
  const _SyncBanner({required this.prov, required this.isDark});

  static ({int current, int total})? _parseProgress(String? msg) {
    if (msg == null) return null;
    final m = RegExp(r'\((\d+)\s*/\s*(\d+)\)').firstMatch(msg);
    if (m == null) return null;
    return (current: int.parse(m.group(1)!), total: int.parse(m.group(2)!));
  }

  static String _stripCounter(String? msg) =>
      (msg ?? '').replaceAll(RegExp(r'\s*\(\d+\s*/\s*\d+\)'), '').trim();

  @override
  Widget build(BuildContext context) {
    final isError = prov.syncStatus == SyncStatus.error;
    final isSyncing = prov.isSyncing || prov.isCheckingDrive;
    final showRetry = prov.driveCheckFailed && !prov.isCheckingDrive;
    final accent = Theme.of(context).colorScheme.primary;
    final progress = _parseProgress(prov.syncStatusMessage);
    final double? progressValue = (progress != null && progress.total > 0)
        ? progress.current / progress.total
        : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          color: Neu.base(isDark),
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              if (isSyncing && !isError)
                _WaveLoader(isDark: isDark)
              else
                Icon(
                  isError
                      ? Icons.error_outline_rounded
                      : Icons.check_circle_outline_rounded,
                  size: 18,
                  color:
                  isError ? Colors.red.shade400 : Neu.textSecondary(isDark),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Text(
                          _stripCounter(prov.syncStatusMessage),
                          key: ValueKey(_stripCounter(prov.syncStatusMessage)),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isError
                                ? Colors.red.shade400
                                : Neu.textPrimary(isDark),
                          ),
                        ),
                      ),
                    ),
                    if (progress != null) ...[
                      const SizedBox(width: 8),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 150),
                        child: Text(
                          '${progress.current} / ${progress.total}',
                          key: ValueKey(progress.current),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: accent,
                          ),
                        ),
                      ),
                    ],
                    if (showRetry) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: prov.retryDriveCheck,
                        child: Text(
                          context.tr('retry'),
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: accent,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (isSyncing)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: progressValue ?? 0, end: progressValue ?? 0),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOut,
            builder: (_, value, __) => LinearProgressIndicator(
              minHeight: 1.5,
              value: progressValue != null ? value : null,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation(
                accent.withAlpha(isDark ? 55 : 45),
              ),
            ),
          )
        else
          const SizedBox(height: 1.5),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Wave loader — five bars that rise and fall in a staggered sine pattern
// ─────────────────────────────────────────────────────────────────────────────

class _WaveLoader extends StatefulWidget {
  final bool isDark;
  const _WaveLoader({required this.isDark});

  @override
  State<_WaveLoader> createState() => _WaveLoaderState();
}

class _WaveLoaderState extends State<_WaveLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Neu.textSecondary(widget.isDark);
    return SizedBox(
      width: 22,
      height: 18,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          const bars = 5;
          const barW = 2.5;
          const gap = 1.5;
          const maxH = 14.0;
          const minH = 3.0;
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(bars, (i) {
              // Each bar offset by 1/bars of the cycle
              final phase = ((_ctrl.value - i / bars) % 1.0);
              // sin mapped from 0→1→0
              final t = (1 - (phase * 2 - 1).abs()).clamp(0.0, 1.0);
              final h = minH + (maxH - minH) * t;
              return Padding(
                padding: EdgeInsets.only(right: i < bars - 1 ? gap : 0),
                child: Container(
                  width: barW,
                  height: h,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(barW),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sign-in tile
// ─────────────────────────────────────────────────────────────────────────────

class _SignInTile extends StatelessWidget {
  final NotesProvider prov;
  final bool isDark;
  final Color accent;
  const _SignInTile(
      {required this.prov, required this.isDark, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          NeuContainer(
            isDark: isDark,
            radius: 24,
            padding: const EdgeInsets.all(10),
            child: Icon(Icons.person_outline_rounded, color: accent, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('sign_in_with_google'),
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Neu.textPrimary(isDark))),
                const SizedBox(height: 2),
                Text(context.tr('sync_your_notes'),
                    style: TextStyle(
                        fontSize: 12, color: Neu.textSecondary(isDark))),
              ],
            ),
          ),
          NeuPressable(
            isDark: isDark,
            radius: 10,
            onTap: prov.signIn,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(context.tr('sign_in'),
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13, color: accent)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Logged-in tile
// ─────────────────────────────────────────────────────────────────────────────

class _LoggedInTile extends StatelessWidget {
  final NotesProvider prov;
  final bool isDark;
  final Color accent;
  const _LoggedInTile(
      {required this.prov, required this.isDark, required this.accent});

  bool get _isChecking =>
      prov.isCheckingDrive ||
          (prov.driveAccountState == DriveAccountState.unknown &&
              !prov.driveCheckFailed);

  bool get _checkFailed => prov.driveCheckFailed;

  bool get _hasRemoteBackup =>
      prov.driveAccountState == DriveAccountState.returningUser;

  // ── Internet-guarded action runner ─────────────────────────────────────────
  Future<void> _runWithNetworkCheck(
      BuildContext context,
      VoidCallback action,
      ) async {
    final online = await _hasInternet();
    if (!online) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.wifi_off_rounded,
                    color: Colors.white, size: 18),
                const SizedBox(width: 10),
                Text(context.tr('no_internet')),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    action();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // User info
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              NeuContainer(
                isDark: isDark,
                radius: 28,
                child: ClipOval(
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: prov.user!.photoUrl != null
                        ? Image.network(prov.user!.photoUrl!, fit: BoxFit.cover)
                        : Center(
                      child: Text(
                        prov.user!.email[0].toUpperCase(),
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: accent),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      prov.user!.displayName ?? context.tr('google_user'),
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Neu.textPrimary(isDark)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      prov.user!.email,
                      style: TextStyle(
                          fontSize: 12, color: Neu.textSecondary(isDark)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        _NeuDivider(isDark: isDark),

        if (_isChecking)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child:
                  CircularProgressIndicator(strokeWidth: 2, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(context.tr('checking_drive'),
                      style: TextStyle(
                          fontSize: 13, color: Neu.textSecondary(isDark))),
                ),
              ],
            ),
          )
        else if (_checkFailed)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                Icon(Icons.cloud_off_rounded,
                    size: 16, color: Theme.of(context).colorScheme.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.tr('drive_check_failed'),
                    style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.error),
                  ),
                ),
                NeuPressable(
                  isDark: isDark,
                  radius: 8,
                  onTap: () =>
                      _runWithNetworkCheck(context, prov.retryDriveCheck),
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(
                    context.tr('retry'),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: accent),
                  ),
                ),
              ],
            ),
          ),

        _NeuActionTile(
          icon: Icons.cloud_upload_outlined,
          title: context.tr('upload_backup'),
          subtitle: _isChecking
              ? context.tr('waiting_drive_check')
              : _checkFailed
              ? context.tr('retry_drive_check_first')
              : _hasRemoteBackup
              ? context.tr('push_local_to_drive')
              : context.tr('create_first_backup'),
          isDark: isDark,
          accent: accent,
          enabled: !_isChecking && !_checkFailed,
          onTap: () => _confirmAction(
            context,
            context.tr('upload_backup'),
            context.tr('upload_backup_confirm'),
                () => _runWithNetworkCheck(context, prov.uploadNotes),
          ),
        ),

        _NeuDivider(isDark: isDark),

        _NeuActionTile(
          icon: Icons.cloud_download_outlined,
          title: context.tr('restore_from_drive'),
          subtitle: _isChecking
              ? context.tr('checking_drive_short')
              : _checkFailed
              ? context.tr('retry_drive_check_first')
              : _hasRemoteBackup
              ? context.tr('merge_from_drive')
              : context.tr('no_backup_found'),
          isDark: isDark,
          accent: accent,
          enabled: !_isChecking && !_checkFailed && _hasRemoteBackup,
          onTap: () => _confirmAction(
            context,
            context.tr('restore_from_drive'),
            context.tr('restore_from_drive_confirm'),
                () => _runWithNetworkCheck(context, prov.downloadNotes),
          ),
        ),

        _NeuDivider(isDark: isDark),

        _NeuActionTile(
          icon: Icons.logout_rounded,
          title: context.tr('sign_out'),
          isDark: isDark,
          accent: Colors.red.shade400,
          enabled: true,
          isDestructive: true,
          onTap: () => _confirmAction(
            context,
            context.tr('sign_out'),
            context.tr('sign_out_message'),
            prov.signOut,
          ),
        ),
      ],
    );
  }

  Future<void> _confirmAction(BuildContext context, String title,
      String message, VoidCallback action) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = Neu.base(isDark);
    final ok = await showDialog<bool>(
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
              Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                      color: Neu.textPrimary(isDark))),
              const SizedBox(height: 8),
              Text(message,
                  style: TextStyle(
                      fontSize: 13, color: Neu.textSecondary(isDark))),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _NeuDialogBtn(
                      label: context.tr('cancel'),
                      isDark: isDark,
                      onTap: () => Navigator.pop(ctx, false)),
                  const SizedBox(width: 10),
                  _NeuDialogBtn(
                      label: context.tr('confirm'),
                      isDark: isDark,
                      isPrimary: true,
                      onTap: () => Navigator.pop(ctx, true)),
                ],
              ),
            ],
          ),
        ),
      ),
    ) ??
        false;
    if (ok) action();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Backup & Restore Section — works independently of Google Sign-In
// ─────────────────────────────────────────────────────────────────────────────

class _BackupRestoreSection extends StatelessWidget {
  final NotesProvider prov;
  final bool isDark;
  final Color accent;

  const _BackupRestoreSection({
    required this.prov,
    required this.isDark,
    required this.accent,
  });

  // ── Auth gate — biometric or master password before export ─────────────────

  Future<bool> _authenticateBeforeExport(BuildContext context) async {
    // Attempt biometric first; fall back to master-password dialog.
    try {
      final authenticated = await prov.authenticateWithBiometrics();
      if (authenticated) return true;
    } catch (_) {
      // Biometrics unavailable or cancelled — fall through to password.
    }
    // Check mounted after the biometrics await before using context again.
    if (!context.mounted) return false;
    return _showPasswordConfirmDialog(context);
  }

  Future<bool> _showPasswordConfirmDialog(BuildContext context) async {
    final base = Neu.base(isDark);
    final controller = TextEditingController();
    bool obscure = true;
    String? errorText;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Dialog(
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
                Row(
                  children: [
                    Icon(Icons.lock_outline_rounded, size: 20, color: accent),
                    const SizedBox(width: 10),
                    Text(
                      context.tr('enter_password'),
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                          color: Neu.textPrimary(isDark)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr('export_auth_desc'),
                  style: TextStyle(
                      fontSize: 13, color: Neu.textSecondary(isDark)),
                ),
                const SizedBox(height: 16),
                NeuContainer(
                  isDark: isDark,
                  radius: 12,
                  padding: EdgeInsets.zero,
                  child: TextField(
                    controller: controller,
                    obscureText: obscure,
                    autofocus: true,
                    style: TextStyle(
                        fontSize: 14, color: Neu.textPrimary(isDark)),
                    decoration: InputDecoration(
                      hintText: context.tr('password'),
                      hintStyle: TextStyle(color: Neu.textTertiary(isDark)),
                      errorText: errorText,
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure
                              ? Icons.visibility_off_rounded
                              : Icons.visibility_rounded,
                          size: 18,
                          color: Neu.textTertiary(isDark),
                        ),
                        onPressed: () => setS(() => obscure = !obscure),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _NeuDialogBtn(
                        label: context.tr('cancel'),
                        isDark: isDark,
                        onTap: () => Navigator.pop(ctx, false)),
                    const SizedBox(width: 10),
                    _NeuDialogBtn(
                      label: context.tr('confirm'),
                      isDark: isDark,
                      isPrimary: true,
                      onTap: () async {
                        final correct =
                        await prov.verifyMasterPassword(controller.text);
                        if (!ctx.mounted) return;
                        if (correct) {
                          Navigator.pop(ctx, true);
                        } else {
                          setS(() =>
                          errorText = context.tr('incorrect_password'));
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ) ??
        false;

    controller.dispose();
    return ok;
  }

  // ── Export JSON ────────────────────────────────────────────────────────────

  Future<void> _exportNotesJson(BuildContext context) async {
    // Require biometric or master-password confirmation before exporting.
    final authed = await _authenticateBeforeExport(context);
    if (!authed) return;
    if (!context.mounted) return;

    // Capture context-dependent values before any further async gaps.
    final messenger = ScaffoldMessenger.of(context);
    final loadingMsg = context.tr('preparing_backup');
    final backupReadyMsg = context.tr('backup_ready');
    final exportFailedPrefix = context.tr('export_failed');

    _showLoadingSnackbar(context, loadingMsg);

    try {
      final bytes = await prov.exportNotesJson();
      final fileName =
          'noteliha_backup_${DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19)}.json';

      if (kIsWeb) {
        await Share.shareXFiles(
          [XFile.fromData(bytes, name: fileName, mimeType: 'application/json')],
          subject: 'Noteliha backup',
        );
      } else {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(bytes);
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'application/json')],
          subject: 'Noteliha backup',
        );
      }

      messenger.hideCurrentSnackBar();
      _showSuccessSnackbarOn(messenger, backupReadyMsg);
    } catch (e) {
      messenger.hideCurrentSnackBar();
      _showErrorSnackbarOn(messenger, '$exportFailedPrefix: $e');
    }
  }

  // ── Import JSON ────────────────────────────────────────────────────────────

  Future<void> _importNotesJson(BuildContext context) async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
    } catch (e) {
      if (context.mounted) {
        _showErrorSnackbar(
            context, '${context.tr('could_not_open_picker')}: $e');
      }
      return;
    }

    if (result == null || result.files.isEmpty) return;

    final pickedFile = result.files.first;
    final Uint8List? bytes = pickedFile.bytes ??
        (pickedFile.path != null
            ? await File(pickedFile.path!).readAsBytes()
            : null);

    if (bytes == null) {
      if (context.mounted) {
        _showErrorSnackbar(context, context.tr('could_not_read_file'));
      }
      return;
    }

    if (!context.mounted) return;

    // Detect whether the backup belongs to a different vault/salt and warn.
    final bool differentVault = await prov.isFromDifferentVault(bytes);
    if (differentVault) {
      if (!context.mounted) return;
      final proceed = await _showVaultMismatchDialog(context);
      if (!proceed) return;
    }

    if (!context.mounted) return;
    final confirmed = await _showImportConfirmDialog(context);
    if (!confirmed) return;

    // Capture context-dependent values before any further async gaps.
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final importingMsg = context.tr('importing_notes');
    final nothingNewMsg = context.tr('import_nothing_new');
    final importedPrefix = context.tr('imported');
    final noteSingular = context.tr('note');
    final notePlural = context.tr('notes_lower');
    final successSuffix = context.tr('successfully');
    final importFailedPrefix = context.tr('import_failed');

    _showLoadingSnackbarOn(messenger, importingMsg);

    try {
      final count = await prov.importNotesJson(bytes);
      messenger.hideCurrentSnackBar();
      _showSuccessSnackbarOn(
        messenger,
        count == 0
            ? nothingNewMsg
            : '$importedPrefix $count ${count == 1 ? noteSingular : notePlural} $successSuffix',
      );
    } on FormatException catch (e) {
      messenger.hideCurrentSnackBar();
      _showErrorSnackbarOn(messenger, e.message);
    } catch (e) {
      messenger.hideCurrentSnackBar();
      _showErrorSnackbarOn(messenger, '$importFailedPrefix: $e');
    }
  }

  // ── Vault mismatch warning dialog ──────────────────────────────────────────

  Future<bool> _showVaultMismatchDialog(BuildContext context) async {
    final base = Neu.base(isDark);
    final ok = await showDialog<bool>(
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
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 22, color: Colors.orange.shade400),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.tr('vault_mismatch_title'),
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                          color: Neu.textPrimary(isDark)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                context.tr('vault_mismatch_desc'),
                style: TextStyle(
                    fontSize: 13, color: Neu.textSecondary(isDark)),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _NeuDialogBtn(
                      label: context.tr('cancel'),
                      isDark: isDark,
                      onTap: () => Navigator.pop(ctx, false)),
                  const SizedBox(width: 10),
                  _NeuDialogBtn(
                      label: context.tr('import'),
                      isDark: isDark,
                      isPrimary: true,
                      onTap: () => Navigator.pop(ctx, true)),
                ],
              ),
            ],
          ),
        ),
      ),
    ) ??
        false;
    return ok;
  }

  // ── Import confirm dialog ──────────────────────────────────────────────────

  Future<bool> _showImportConfirmDialog(BuildContext context) async {
    final base = Neu.base(isDark);
    final ok = await showDialog<bool>(
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
              Text(context.tr('import_notes_title'),
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                      color: Neu.textPrimary(isDark))),
              const SizedBox(height: 8),
              Text(
                context.tr('import_notes_desc'),
                style: TextStyle(
                    fontSize: 13, color: Neu.textSecondary(isDark)),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _NeuDialogBtn(
                      label: context.tr('cancel'),
                      isDark: isDark,
                      onTap: () => Navigator.pop(ctx, false)),
                  const SizedBox(width: 10),
                  _NeuDialogBtn(
                      label: context.tr('import'),
                      isDark: isDark,
                      isPrimary: true,
                      onTap: () => Navigator.pop(ctx, true)),
                ],
              ),
            ],
          ),
        ),
      ),
    ) ??
        false;
    return ok;
  }

  // ── SnackBar helpers ───────────────────────────────────────────────────────

  void _showLoadingSnackbar(BuildContext context, String message) =>
      _showLoadingSnackbarOn(ScaffoldMessenger.of(context), message);

  void _showErrorSnackbar(BuildContext context, String message) =>
      _showErrorSnackbarOn(ScaffoldMessenger.of(context), message);

  void _showLoadingSnackbarOn(ScaffoldMessengerState messenger, String message) {
    messenger.showSnackBar(SnackBar(
      content: Row(children: [
        const SizedBox(
          width: 16,
          height: 16,
          child:
          CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Text(message),
      ]),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 30),
    ));
  }

  void _showSuccessSnackbarOn(ScaffoldMessengerState messenger, String message) {
    messenger.showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ]),
      backgroundColor: Colors.green.shade600,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
    ));
  }

  void _showErrorSnackbarOn(ScaffoldMessengerState messenger, String message) {
    messenger.showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error_outline_rounded, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ]),
      backgroundColor: Colors.red.shade600,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Upload Notes JSON ──────────────────────────────────────────────
        _NeuActionTile(
          icon: Icons.upload_file_outlined,
          title: context.tr('upload_notes_json'),
          subtitle: context.tr('upload_notes_json_ui_subtitle'),
          isDark: isDark,
          accent: accent,
          enabled: true,
          onTap: () => _importNotesJson(context),
        ),

        _NeuDivider(isDark: isDark),

        // ── Download Notes JSON ────────────────────────────────────────────
        _NeuActionTile(
          icon: Icons.download_for_offline_outlined,
          title: context.tr('download_notes_json'),
          subtitle: context.tr('download_notes_json_ui_subtitle'),
          isDark: isDark,
          accent: accent,
          enabled: true,
          onTap: () => _exportNotesJson(context),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small reusable row widgets
// ─────────────────────────────────────────────────────────────────────────────

class _NeuSwitchTile extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final Color accent;
  final ValueChanged<bool> onChanged;

  const _NeuSwitchTile({
    required this.isDark,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          NeuContainer(
            isDark: isDark,
            radius: 10,
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 18, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Neu.textPrimary(isDark))),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 12, color: Neu.textSecondary(isDark))),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: accent,
          ),
        ],
      ),
    );
  }
}

class _NeuActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool isDark;
  final Color accent;
  final bool enabled;
  final bool isDestructive;
  final VoidCallback onTap;

  const _NeuActionTile({
    required this.icon,
    required this.title,
    required this.isDark,
    required this.accent,
    required this.enabled,
    required this.onTap,
    this.subtitle,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = enabled ? accent : Neu.textTertiary(isDark);
    return NeuPressable(
      isDark: isDark,
      radius: 0,
      onTap: enabled ? onTap : () {},
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: effectiveColor),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: enabled
                            ? (isDestructive
                            ? Colors.red.shade400
                            : Neu.textPrimary(isDark))
                            : Neu.textTertiary(isDark))),
                if (subtitle != null)
                  Text(subtitle!,
                      style: TextStyle(
                          fontSize: 12,
                          color: enabled
                              ? Neu.textSecondary(isDark)
                              : Neu.textTertiary(isDark))),
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

class _NeuInfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool isDark;
  final Color accent;

  const _NeuInfoTile({
    required this.icon,
    required this.title,
    required this.isDark,
    required this.accent,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: accent),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Neu.textPrimary(isDark))),
                if (subtitle != null)
                  Text(subtitle!,
                      style: TextStyle(
                          fontSize: 12, color: Neu.textSecondary(isDark))),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _NeuLinkTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final String url;
  final bool isDark;
  final Color accent;

  const _NeuLinkTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.url,
    required this.isDark,
    required this.accent,
  });

  Future<void> _launch(BuildContext context) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
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
      onTap: () => _launch(context),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: accent),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Neu.textPrimary(isDark))),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 12, color: Neu.textSecondary(isDark))),
              ],
            ),
          ),
          Icon(Icons.open_in_new_rounded,
              size: 15, color: Neu.textTertiary(isDark)),
        ],
      ),
    );
  }
}

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

class _NeuDialogBtn extends StatefulWidget {
  final String label;
  final bool isDark;
  final bool isPrimary;
  final VoidCallback onTap;
  const _NeuDialogBtn({
    required this.label,
    required this.isDark,
    required this.onTap,
    this.isPrimary = false,
  });

  @override
  State<_NeuDialogBtn> createState() => _NeuDialogBtnState();
}

class _NeuDialogBtnState extends State<_NeuDialogBtn> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final labelColor =
    widget.isPrimary ? accent : Neu.textSecondary(widget.isDark);
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: Neu.base(widget.isDark),
          borderRadius: BorderRadius.circular(12),
          boxShadow:
          _pressed ? Neu.inset(widget.isDark) : Neu.raisedSm(widget.isDark),
        ),
        child: Text(widget.label,
            style: TextStyle(
                fontWeight: FontWeight.w600, fontSize: 14, color: labelColor)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Referral Card
// ─────────────────────────────────────────────────────────────────────────────

class _ReferralCard extends StatelessWidget {
  final bool isDark;
  final Color accent;
  const _ReferralCard({required this.isDark, required this.accent});

  static const _playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.navkonlab.noteliha';

  Future<void> _share(BuildContext context) async {
    await Share.share(
      context.tr('share_app_message').replaceAll('{url}', _playStoreUrl),
      subject: context.tr('share_app_subject'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return NeuContainer(
      isDark: isDark,
      radius: 16,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                NeuContainer(
                  isDark: isDark,
                  radius: 10,
                  padding: const EdgeInsets.all(8),
                  child: Icon(Icons.favorite_rounded, size: 18, color: accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('enjoying_app'),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Neu.textPrimary(isDark),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.tr('share_app_subtitle'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Neu.textSecondary(isDark),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: NeuPressable(
                    isDark: isDark,
                    radius: 12,
                    onTap: () => _share(context),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.share_rounded, size: 16, color: accent),
                        const SizedBox(width: 8),
                        Text(
                          context.tr('share'),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: NeuPressable(
                    isDark: isDark,
                    radius: 12,
                    onTap: () async {
                      final uri = Uri.parse(_playStoreUrl);
                      if (await canLaunchUrl(uri)) launchUrl(uri);
                    },
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.star_rounded,
                            size: 16, color: Neu.textSecondary(isDark)),
                        const SizedBox(width: 8),
                        Text(
                          context.tr('rate_us'),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: Neu.textSecondary(isDark),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Recycle Bin Screen
// ─────────────────────────────────────────────────────────────────────────────

class RecycleBinScreen extends StatelessWidget {
  const RecycleBinScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final prov = Provider.of<NotesProvider>(context);
    final items = prov.recycleBin;
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Neu.base(isDark),
      appBar: AppBar(
        backgroundColor: Neu.base(isDark),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: NeuIconButton(
          isDark: isDark,
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: Neu.textSecondary(isDark)),
          onTap: () => Navigator.pop(context),
        ),
        leadingWidth: 56,
        title: Text(context.tr('recycle_bin'),
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Neu.textPrimary(isDark))),
        actions: [
          if (items.isNotEmpty)
            NeuIconButton(
              isDark: isDark,
              icon: Icon(Icons.delete_forever_rounded,
                  size: 20, color: Colors.red.shade400),
              onTap: () => _confirmEmptyBin(context, isDark, prov, items),
            ),
          const SizedBox(width: 10),
        ],
      ),
      body: items.isEmpty
          ? Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NeuContainer(
              isDark: isDark,
              radius: 36,
              padding: const EdgeInsets.all(22),
              child: Icon(Icons.delete_outline_rounded,
                  size: 36, color: Neu.textSecondary(isDark)),
            ),
            const SizedBox(height: 16),
            Text(context.tr('recycle_bin_empty'),
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Neu.textPrimary(isDark))),
          ],
        ),
      )
          : ListView.builder(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, MediaQuery.of(context).padding.bottom + 24),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final n = items[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: NeuContainer(
              isDark: isDark,
              radius: 16,
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          n.title.isNotEmpty
                              ? n.title
                              : '(${context.tr('untitled')})',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Neu.textPrimary(isDark)),
                        ),
                        if (n.content.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            n.content,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                color: Neu.textSecondary(isDark)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  NeuIconButton(
                    isDark: isDark,
                    size: 36,
                    icon: Icon(Icons.restore_rounded,
                        size: 18, color: accent),
                    onTap: () => prov.restore(n.id),
                  ),
                  const SizedBox(width: 8),
                  NeuIconButton(
                    isDark: isDark,
                    size: 36,
                    icon: Icon(Icons.delete_forever_rounded,
                        size: 18, color: Colors.red.shade400),
                    onTap: () =>
                        _confirmDelete(context, isDark, prov, n.id),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _confirmEmptyBin(
      BuildContext context, bool isDark, NotesProvider prov, List items) async {
    final ok = await _dialog(
      context,
      isDark,
      context.tr('empty_recycle_bin'),
      context.tr('empty_bin_confirmation'),
    );
    if (ok) {
      await Future.wait(List.from(items).map((n) => prov.hardDelete(n.id)));
    }
  }

  void _confirmDelete(
      BuildContext context, bool isDark, NotesProvider prov, String id) async {
    final ok = await _dialog(
      context,
      isDark,
      context.tr('permanently_delete'),
      context.tr('are_you_sure_cannot_undo'),
    );
    if (ok) prov.hardDelete(id);
  }

  Future<bool> _dialog(
      BuildContext context, bool isDark, String title, String message) async {
    final base = Neu.base(isDark);
    return await showDialog<bool>(
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
              Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                      color: Neu.textPrimary(isDark))),
              const SizedBox(height: 8),
              Text(message,
                  style: TextStyle(
                      fontSize: 13, color: Neu.textSecondary(isDark))),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _NeuDialogBtn(
                      label: context.tr('cancel'),
                      isDark: isDark,
                      onTap: () => Navigator.pop(ctx, false)),
                  const SizedBox(width: 10),
                  _NeuDialogBtn(
                      label: context.tr('delete'),
                      isDark: isDark,
                      isPrimary: false,
                      onTap: () => Navigator.pop(ctx, true)),
                ],
              ),
            ],
          ),
        ),
      ),
    ) ??
        false;
  }
}