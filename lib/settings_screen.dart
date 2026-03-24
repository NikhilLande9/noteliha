// lib/settings_screen.dart
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models.dart';
import 'theme_helper.dart';
import 'neu_theme.dart';
import 'notes_provider.dart';

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

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final prov = Provider.of<NotesProvider>(context);
    final settings = Provider.of<AppSettingsProvider>(context);
    final accent = Theme.of(context).colorScheme.primary;
    final base = Neu.base(isDark);

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
          'Settings',
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
                _SectionHeader(text: 'Account', isDark: isDark),
                NeuContainer(
                  isDark: isDark,
                  radius: 16,
                  child: prov.user == null
                      ? _SignInTile(prov: prov, isDark: isDark, accent: accent)
                      : _LoggedInTile(
                          prov: prov, isDark: isDark, accent: accent),
                ),

                const SizedBox(height: 24),

                // ── Appearance ───────────────────────────────────────────────
                _SectionHeader(text: 'Appearance', isDark: isDark),
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
                        title: 'Dark Mode',
                        subtitle: settings.isDarkMode ? 'On' : 'Off',
                        value: settings.isDarkMode,
                        accent: accent,
                        onChanged: (_) => settings.toggleDarkMode(),
                      ),

                      _NeuDivider(isDark: isDark),

                      // App color picker
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                        child: Text('App Color',
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
                        child: Text('Visual Style',
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
                _SectionHeader(text: 'Data', isDark: isDark),
                NeuContainer(
                  isDark: isDark,
                  radius: 16,
                  child: _NeuActionTile(
                    icon: Icons.delete_sweep_outlined,
                    title: 'Recycle Bin',
                    subtitle: 'View and restore deleted notes',
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

                // ── Web App ──────────────────────────────────────────────────
                _SectionHeader(text: 'Web App', isDark: isDark),
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
                                    'Access on any device',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: Neu.textPrimary(isDark),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Open noteliha in your browser — no install needed.',
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

                // ── About ────────────────────────────────────────────────────
                _SectionHeader(text: 'About', isDark: isDark),
                NeuContainer(
                  isDark: isDark,
                  radius: 16,
                  child: Column(
                    children: [
                      _NeuInfoTile(
                        icon: Icons.info_outline_rounded,
                        title: 'Version',
                        trailing: Text('1.0.0',
                            style: TextStyle(
                                color: Neu.textTertiary(isDark), fontSize: 13)),
                        isDark: isDark,
                        accent: accent,
                      ),
                      _NeuDivider(isDark: isDark),
                      _NeuInfoTile(
                        icon: Icons.storage_rounded,
                        title: 'Storage',
                        subtitle: 'Offline-first with Google Drive sync',
                        isDark: isDark,
                        accent: accent,
                      ),
                      _NeuDivider(isDark: isDark),
                      _NeuLinkTile(
                        icon: Icons.menu_book_rounded,
                        label: 'Documentation',
                        subtitle: 'noteliha.navkon.com',
                        url: 'https://noteliha.navkon.com',
                        isDark: isDark,
                        accent: accent,
                      ),
                      _NeuDivider(isDark: isDark),
                      _NeuLinkTile(
                        icon: Icons.privacy_tip_outlined,
                        label: 'Privacy Policy',
                        subtitle: 'How your data is handled',
                        url: 'https://noteliha.navkon.com/PRIVACY_POLICY.html',
                        isDark: isDark,
                        accent: accent,
                      ),
                      _NeuDivider(isDark: isDark),
                      _NeuLinkTile(
                        icon: Icons.gavel_rounded,
                        label: 'Terms of Service',
                        subtitle: 'Rules & agreements',
                        url:
                            'https://noteliha.navkon.com/TERMS_OF_SERVICE.html',
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
                '${Neu.visualThemeName(theme)} is Premium',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    color: Neu.textPrimary(isDark)),
              ),
              const SizedBox(height: 8),
              Text(
                'Unlock this visual style to give your notes a unique look.',
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
                child: Text('Maybe later',
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
          const SnackBar(
            content: Text('Could not open link'),
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
                  'Open',
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isError = prov.syncStatus == SyncStatus.error;
    final bgColor = isError
        ? colorScheme.errorContainer
        : prov.syncStatus == SyncStatus.syncing
            ? colorScheme.secondaryContainer
            : colorScheme.primaryContainer;
    final fgColor =
        isError ? colorScheme.onErrorContainer : colorScheme.onPrimaryContainer;

    final showRetry = prov.driveCheckFailed && !prov.isCheckingDrive;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      color: bgColor,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          prov.isSyncing || prov.isCheckingDrive
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: fgColor))
              : Icon(
                  isError
                      ? Icons.error_outline_rounded
                      : Icons.check_circle_outline_rounded,
                  size: 18,
                  color: fgColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(prov.syncStatusMessage ?? '',
                style: TextStyle(fontSize: 13, color: fgColor)),
          ),
          if (showRetry) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: prov.retryDriveCheck,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: fgColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Retry',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: fgColor),
                ),
              ),
            ),
          ],
        ],
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
                Text('Sign in with Google',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Neu.textPrimary(isDark))),
                const SizedBox(height: 2),
                Text('Sync notes across devices',
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
            child: Text('Sign In',
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
            content: const Row(
              children: [
                Icon(Icons.wifi_off_rounded, color: Colors.white, size: 18),
                SizedBox(width: 10),
                Text('No internet connection'),
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
                      prov.user!.displayName ?? 'Google User',
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
                  child: Text('Checking Drive for existing backup…',
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
                    'Drive check failed',
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
                    'Retry',
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
          title: 'Upload Backup',
          subtitle: _isChecking
              ? 'Waiting for Drive check…'
              : _checkFailed
                  ? 'Retry the Drive check first'
                  : _hasRemoteBackup
                      ? 'Push local changes to Google Drive'
                      : 'Create your first backup on Google Drive',
          isDark: isDark,
          accent: accent,
          enabled: !_isChecking && !_checkFailed,
          onTap: () => _confirmAction(
            context,
            'Upload Backup',
            'Push all pending local changes to Google Drive?',
            () => _runWithNetworkCheck(context, prov.uploadNotes),
          ),
        ),

        _NeuDivider(isDark: isDark),

        _NeuActionTile(
          icon: Icons.cloud_download_outlined,
          title: 'Restore from Drive',
          subtitle: _isChecking
              ? 'Checking Drive…'
              : _checkFailed
                  ? 'Retry the Drive check first'
                  : _hasRemoteBackup
                      ? 'Merge notes from Google Drive'
                      : 'No backup found — upload first',
          isDark: isDark,
          accent: accent,
          enabled: !_isChecking && !_checkFailed && _hasRemoteBackup,
          onTap: () => _confirmAction(
            context,
            'Restore from Drive',
            'Download notes from Drive and merge with local? Conflicts will be flagged for review.',
            () => _runWithNetworkCheck(context, prov.downloadNotes),
          ),
        ),

        _NeuDivider(isDark: isDark),

        _NeuActionTile(
          icon: Icons.logout_rounded,
          title: 'Sign Out',
          isDark: isDark,
          accent: Colors.red.shade400,
          enabled: true,
          isDestructive: true,
          onTap: () => _confirmAction(
            context,
            'Sign Out',
            'Your notes will remain on this device.',
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
                          label: 'Cancel',
                          isDark: isDark,
                          onTap: () => Navigator.pop(ctx, false)),
                      const SizedBox(width: 10),
                      _NeuDialogBtn(
                          label: 'Confirm',
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
          const SnackBar(
            content: Text('Could not open link'),
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
        title: Text('Recycle Bin',
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
                  Text('Recycle bin is empty',
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
                                n.title.isNotEmpty ? n.title : '(Untitled)',
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
      'Empty Recycle Bin',
      'Permanently delete all notes? This cannot be undone.',
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
      'Permanently Delete',
      'Are you sure? This cannot be undone.',
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
                          label: 'Cancel',
                          isDark: isDark,
                          onTap: () => Navigator.pop(ctx, false)),
                      const SizedBox(width: 10),
                      _NeuDialogBtn(
                          label: 'Delete',
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
