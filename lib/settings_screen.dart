import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'models.dart';
import 'theme_helper.dart';
import 'notes_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Settings Screen
// ─────────────────────────────────────────────────────────────────────────────

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<NotesProvider>(context);
    final settings = Provider.of<AppSettingsProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
          title: const Text('Settings'), backgroundColor: colorScheme.surface),
      body: Column(
        children: [
          if (prov.syncStatusMessage != null)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              color: prov.syncStatus == SyncStatus.error
                  ? colorScheme.errorContainer
                  : prov.syncStatus == SyncStatus.syncing
                      ? colorScheme.secondaryContainer
                      : colorScheme.primaryContainer,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  prov.isSyncing || prov.isCheckingDrive
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        )
                      : Icon(
                          prov.syncStatus == SyncStatus.error
                              ? Icons.error_outline_rounded
                              : Icons.check_circle_outline_rounded,
                          size: 18,
                          color: prov.syncStatus == SyncStatus.error
                              ? colorScheme.onErrorContainer
                              : colorScheme.onPrimaryContainer,
                        ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      prov.syncStatusMessage ?? '',
                      style: TextStyle(
                        fontSize: 13,
                        color: prov.syncStatus == SyncStatus.error
                            ? colorScheme.onErrorContainer
                            : colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                const _SectionHeader(title: 'Account'),
                Card(
                  child: prov.user == null
                      ? ListTile(
                          leading: CircleAvatar(
                            backgroundColor: colorScheme.primaryContainer,
                            child: Icon(Icons.person_outline_rounded,
                                color: colorScheme.onPrimaryContainer),
                          ),
                          title: const Text('Sign in with Google',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: const Text('Sync notes across devices'),
                          trailing: FilledButton.tonal(
                              onPressed: prov.signIn,
                              child: const Text('Sign In')),
                        )
                      : _LoggedInTile(prov: prov, colorScheme: colorScheme),
                ),
                const SizedBox(height: 20),
                const _SectionHeader(title: 'Appearance'),
                Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        secondary: Icon(
                          settings.isDarkMode
                              ? Icons.dark_mode_rounded
                              : Icons.light_mode_rounded,
                          color: colorScheme.primary,
                        ),
                        title: const Text('Dark Mode',
                            style: TextStyle(fontWeight: FontWeight.w500)),
                        subtitle: Text(settings.isDarkMode ? 'On' : 'Off'),
                        value: settings.isDarkMode,
                        onChanged: (_) => settings.toggleDarkMode(),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                        child: Text('App Color',
                            style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: colorScheme.onSurface)),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: AppTheme.values.map((theme) {
                            final isSelected = settings.appTheme == theme;
                            final color = AppSettingsProvider.seedColor(theme);
                            return GestureDetector(
                              onTap: () => settings.setAppTheme(theme),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color:
                                      color.withAlpha(isSelected ? 255 : 180),
                                  shape: BoxShape.circle,
                                  border: isSelected
                                      ? Border.all(
                                          color: colorScheme.onSurface,
                                          width: 3)
                                      : null,
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                              color: color.withAlpha(120),
                                              blurRadius: 10,
                                              spreadRadius: 2)
                                        ]
                                      : null,
                                ),
                                child: isSelected
                                    ? const Icon(Icons.check_rounded,
                                        color: Colors.white, size: 22)
                                    : null,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        child: Center(
                          child: Text(
                            AppSettingsProvider.themeName(settings.appTheme),
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.primary),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const _SectionHeader(title: 'About'),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.info_outline_rounded,
                            color: colorScheme.primary),
                        title: const Text('Version'),
                        trailing: Text('1.0.0',
                            style:
                                TextStyle(color: colorScheme.onSurfaceVariant)),
                      ),
                      ListTile(
                        leading: Icon(Icons.storage_rounded,
                            color: colorScheme.primary),
                        title: const Text('Storage'),
                        subtitle:
                            const Text('Offline-first with Google Drive sync'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Logged In Tile
// ─────────────────────────────────────────────────────────────────────────────

class _LoggedInTile extends StatelessWidget {
  final NotesProvider prov;
  final ColorScheme colorScheme;
  const _LoggedInTile({required this.prov, required this.colorScheme});

  bool get _isChecking =>
      prov.isCheckingDrive ||
      prov.driveAccountState == DriveAccountState.unknown;

  bool get _hasRemoteBackup =>
      prov.driveAccountState == DriveAccountState.returningUser;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundImage: prov.user!.photoUrl != null
                    ? NetworkImage(prov.user!.photoUrl!)
                    : null,
                backgroundColor: colorScheme.primaryContainer,
                child: prov.user!.photoUrl == null
                    ? Text(
                        prov.user!.email[0].toUpperCase(),
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onPrimaryContainer),
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(prov.user!.displayName ?? 'Google User',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(prov.user!.email,
                        style: TextStyle(
                            fontSize: 13, color: colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (_isChecking)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Text('Checking Drive for existing backup…',
                    style: TextStyle(
                        fontSize: 13, color: colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ListTile(
          leading: Icon(Icons.cloud_upload_outlined,
              color: _isChecking
                  ? colorScheme.onSurface.withAlpha(80)
                  : colorScheme.primary),
          title: Text(
            'Upload Backup',
            style: TextStyle(
              color: _isChecking ? colorScheme.onSurface.withAlpha(80) : null,
            ),
          ),
          subtitle: Text(
            _isChecking
                ? 'Waiting for Drive check…'
                : _hasRemoteBackup
                    ? 'Push local changes to Google Drive'
                    : 'Create your first backup on Google Drive',
            style: TextStyle(
              fontSize: 12,
              color: _isChecking ? colorScheme.onSurface.withAlpha(60) : null,
            ),
          ),
          onTap: _isChecking
              ? null
              : () => _confirmAction(
                    context,
                    'Upload Backup',
                    'Push all pending local changes to Google Drive?',
                    prov.uploadNotes,
                  ),
        ),
        ListTile(
          leading: Icon(
            Icons.cloud_download_outlined,
            color: (!_isChecking && _hasRemoteBackup)
                ? colorScheme.primary
                : colorScheme.onSurface.withAlpha(80),
          ),
          title: Text(
            'Restore from Drive',
            style: TextStyle(
              color: (!_isChecking && _hasRemoteBackup)
                  ? null
                  : colorScheme.onSurface.withAlpha(80),
            ),
          ),
          subtitle: Text(
            _isChecking
                ? 'Checking Drive…'
                : _hasRemoteBackup
                    ? 'Merge notes from Google Drive'
                    : 'No backup found — upload first',
            style: TextStyle(
              fontSize: 12,
              color: (!_isChecking && _hasRemoteBackup)
                  ? null
                  : colorScheme.onSurface.withAlpha(60),
            ),
          ),
          onTap: (!_isChecking && _hasRemoteBackup)
              ? () => _confirmAction(
                    context,
                    'Restore from Drive',
                    'Download notes from Drive and merge with local? Conflicts will be flagged for review.',
                    prov.downloadNotes,
                  )
              : null,
        ),
        ListTile(
          leading:
              Icon(Icons.delete_sweep_outlined, color: colorScheme.primary),
          title: const Text('Recycle Bin'),
          subtitle: const Text('View deleted notes'),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const RecycleBinScreen())),
        ),
        const Divider(height: 1),
        ListTile(
          leading: Icon(Icons.logout_rounded, color: colorScheme.error),
          title: Text('Sign Out', style: TextStyle(color: colorScheme.error)),
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
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Confirm')),
            ],
          ),
        ) ??
        false;
    if (ok) action();
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 0, 8),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: Theme.of(context).colorScheme.primary),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Recycle Bin Screen
// ─────────────────────────────────────────────────────────────────────────────

class RecycleBinScreen extends StatelessWidget {
  const RecycleBinScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prov = Provider.of<NotesProvider>(context);
    final items = prov.recycleBin;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recycle Bin'),
        actions: [
          if (items.isNotEmpty)
            IconButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Empty Recycle Bin'),
                    content: const Text(
                        'Permanently delete all notes? This cannot be undone.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Delete All')),
                    ],
                  ),
                );
                if (ok == true) {
                  final deleteTasks = List.from(items)
                      .map((n) => prov.hardDelete(n.id))
                      .toList();
                  await Future.wait(deleteTasks);
                }
              },
              icon: const Icon(Icons.delete_forever),
              tooltip: 'Empty Recycle Bin',
            ),
        ],
      ),
      body: items.isEmpty
          ? const Center(child: Text('Recycle bin is empty'))
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (_, i) {
                final n = items[i];
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: ListTile(
                    title: Text(n.title.isNotEmpty ? n.title : '(Untitled)'),
                    subtitle: Text(n.content,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.restore, color: Colors.blue),
                          onPressed: () => prov.restore(n.id),
                          tooltip: 'Restore',
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_forever,
                              color: Colors.red),
                          tooltip: 'Delete Permanently',
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Permanently Delete'),
                                content: const Text(
                                    'Are you sure? This cannot be undone.'),
                                actions: [
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(ctx, false),
                                      child: const Text('Cancel')),
                                  FilledButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Delete')),
                                ],
                              ),
                            );
                            if (ok == true) prov.hardDelete(n.id);
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
