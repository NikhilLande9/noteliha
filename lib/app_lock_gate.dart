// lib/app_lock_gate.dart
//
// APP LOCK GATE WITH BUILT-IN ENCRYPTION INITIALIZATION
// ────────────────────────────────────────────────────────
//
// FLOW
// ────
//  ┌─ No password stored ──→ Create Password screen
//  │
//  └─ Password stored
//       │
//       └─ Biometric available? (native only)
//            │
//            ├─ Yes → Show biometric prompt immediately (no button tap needed)
//            │          ├─ Success  → derive key → Unlock
//            │          └─ Fail/Cancel → Password entry screen
//            │                              └─ Correct password → Unlock
//            │
//            └─ No  → Password entry screen directly
//                        └─ Correct password → Unlock
//
// ✅ Handles first-run password setup
// ✅ Biometric fires immediately on launch — no extra tap needed
// ✅ Any biometric failure/cancel falls through to password entry
// ✅ "Use Biometrics Instead" available from password entry screen
// ✅ Web: no biometrics, straight to password entry
// ✅ Initializes EncryptionService on successful unlock (any path)
// ✅ FIXED: Biometric dialog now properly appears on Android 16
// ✅ Stores master password securely so NotesProvider can re-derive the key
//    when a Drive salt is found after reinstall (cross-platform sync fix).

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import 'encryption_service.dart';
import 'language.dart';
import 'neu_theme.dart';
import 'notes_provider.dart';

const int kLockAfterSeconds = 30;
const String _kPinKey = 'noteliha_master_password_v1';
const String _kBioEnrolledKey = 'noteliha_bio_enrolled_v1';

/// Secure storage key under which the master password is persisted so that
/// [NotesProvider] can retrieve it when re-deriving the encryption key after
/// a Drive salt is fetched on reinstall.
///
/// This key is intentionally distinct from [_kPinKey] (which stores the pin
/// used for app-lock comparison) so the two concerns stay decoupled.  Both
/// keys hold the same plaintext password value — they are just separate
/// entries in the secure keychain.
const String kMasterPasswordForRederiveKey =
    'noteliha_master_password_encrypted_v1';

class AppLockGate extends StatefulWidget {
  final Widget child;
  const AppLockGate({required this.child, super.key});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  final _localAuth = LocalAuthentication();

  // ── State machine ──────────────────────────────────────────────────────────
  //
  //  _locked       false → show child (app content)
  //                true  → show lock screen
  //
  //  _setupMode    true  → first run, no password yet → create-password UI
  //
  //  _passwordMode true  → show password entry field
  //                false + _locked → biometric is in progress (show spinner)
  //
  //  _bioRunning   true  → biometric dialog is active (guard against re-entry)

  bool _locked = true;
  bool _passwordMode = false;
  bool _setupMode = false;
  bool _bioRunning = false;
  bool _checking = false;

  DateTime? _backgroundedAt;

  // UI
  final _passwordCtrl = TextEditingController();
  final _passwordConfCtrl = TextEditingController();
  String? _passwordError;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  // Bio-waiting animations
  late final AnimationController _pulseCtrl;
  late final AnimationController _ringCtrl;
  late final Animation<double> _pulseAnim;
  late final Animation<double> _ringAnim;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _ringAnim = CurvedAnimation(parent: _ringCtrl, curve: Curves.easeOut);

    _checkLock(onResume: false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseCtrl.dispose();
    _ringCtrl.dispose();
    _passwordCtrl.dispose();
    _passwordConfCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _backgroundedAt = DateTime.now();
        break;
      case AppLifecycleState.resumed:
        final bg = _backgroundedAt;
        if (bg != null) {
          final elapsed = DateTime.now().difference(bg).inSeconds;
          if (elapsed >= kLockAfterSeconds) _checkLock(onResume: true);
        }
        break;
      default:
        break;
    }
  }

  // ── Core lock check ────────────────────────────────────────────────────────

  Future<void> _checkLock({required bool onResume}) async {
    if (_checking || _bioRunning) return;
    _checking = true;

    try {
      final storedPassword = await _storage.read(key: _kPinKey);

      // ── First run: no password set up yet ─────────────────────────────────
      if (storedPassword == null) {
        if (mounted) {
          setState(() {
            _locked = true;
            _setupMode = true;
            _passwordMode = true;
          });
        }
        return;
      }

      // ── Password exists: lock the app ─────────────────────────────────────
      if (mounted) setState(() => _locked = true);

      // On web local_auth is unsupported — go straight to password entry.
      if (kIsWeb) {
        if (mounted) setState(() => _passwordMode = true);
        return;
      }

      // ── Try biometric immediately (native only) ────────────────────────────
      // Always attempt biometrics on native platforms. The _tryBiometric method
      // handles all edge cases (no hardware, no enrolled biometrics, errors)
      // and automatically falls back to password entry when needed.
      await _tryBiometric(storedPassword);
    } catch (e) {
      debugPrint('[AppLockGate] _checkLock error: $e');
      if (mounted) setState(() => _passwordMode = true);
    } finally {
      _checking = false;
    }
  }

  // ── Biometric ──────────────────────────────────────────────────────────────
  // ENHANCED VERSION: Forces the system biometric dialog to appear properly

  Future<void> _tryBiometric(String storedPassword) async {
    if (_bioRunning) {
      debugPrint('[AppLockGate] Biometric already running, skipping');
      return;
    }

    if (mounted) setState(() => _bioRunning = true);

    try {
      // CRITICAL: Check device support before attempting authentication
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      final availableBiometrics = await _localAuth.getAvailableBiometrics();

      debugPrint('[AppLockGate] Device supported: $isDeviceSupported');
      debugPrint('[AppLockGate] Can check biometrics: $canCheck');
      debugPrint('[AppLockGate] Available biometrics: $availableBiometrics');

      if (!isDeviceSupported || !canCheck || availableBiometrics.isEmpty) {
        debugPrint(
            '[AppLockGate] Biometrics not properly available, falling back to password');
        if (mounted) {
          setState(() {
            _bioRunning = false;
            _passwordMode = true;
            _passwordError =
                AppTranslations.translate('biometrics_not_available');
          });
        }
        return;
      }

      // Give the UI a moment to settle before showing the dialog.
      // This ensures the activity is in the correct state to display overlays.
      await Future.delayed(const Duration(milliseconds: 150));

      if (!mounted) {
        setState(() => _bioRunning = false);
        return;
      }

      // ENHANCED OPTIONS: These settings force the dialog to appear properly.
      final authed = await _localAuth.authenticate(
        localizedReason: AppTranslations.translate('biometric_reason'),
        options: const AuthenticationOptions(
          // Use biometricOnly: true to force only biometric methods.
          // Set to false if you want to allow device PIN/pattern as fallback.
          biometricOnly: true,
          // stickyAuth keeps the dialog visible even if the app is backgrounded.
          stickyAuth: true,
          // sensitiveTransaction adds extra security context.
          sensitiveTransaction: true,
        ),
      );

      if (!mounted) return;

      if (authed) {
        debugPrint('[AppLockGate] Biometric authentication successful');
        // Mark biometrics as enrolled/working so future launches skip password.
        await _storage.write(key: _kBioEnrolledKey, value: 'true');
        await _initializeEncryption(storedPassword);
      } else {
        debugPrint('[AppLockGate] Biometric authentication cancelled by user');
        // Cancelled by user → fall through to password entry.
        setState(() {
          _passwordMode = true;
          _bioRunning = false;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('[AppLockGate] Biometric error: $e');
      debugPrint('[AppLockGate] Stack trace: $stackTrace');

      // Provide more specific error messages.
      String errorMsg = AppTranslations.translate('biometric_auth_failed');
      if (e.toString().contains('NotAvailable')) {
        errorMsg = AppTranslations.translate('biometric_not_available');
      } else if (e.toString().contains('LockedOut')) {
        errorMsg = AppTranslations.translate('biometric_locked_out');
      } else if (e.toString().contains('NotEnrolled')) {
        errorMsg = AppTranslations.translate('biometric_not_enrolled');
      }

      // NotAvailable, PermanentlyLockedOut, etc. → fall through to password.
      if (mounted) {
        setState(() {
          _passwordMode = true;
          _bioRunning = false;
          _passwordError = errorMsg;
        });
      }
    } finally {
      if (mounted && _bioRunning) {
        setState(() => _bioRunning = false);
      }
    }
  }

  // ── Encryption init (called on successful auth via any path) ──────────────

  Future<void> _initializeEncryption(String password) async {
    try {
      await EncryptionService.instance.initWithMasterPassword(password);
      await EncryptionService.instance.validateKeyIntegrity();

      // Persist the master password so NotesProvider can re-derive the key
      // when a Drive salt is fetched after a reinstall on this device.
      // This is stored under a separate key from _kPinKey to keep the
      // app-lock comparison logic decoupled from the re-derivation flow.
      await _storeEncryptedPassword(password);

      // On web the keyReady ValueNotifier listener in NotesProvider.init() may
      // have fired before the Hive box was fully open, so the note list stays
      // empty even though notes exist in storage. Explicitly telling the provider
      // the key is ready and then reloading from Hive guarantees the UI reflects
      // all saved notes immediately after unlock on every platform.
      if (mounted) {
        final notesProvider =
        Provider.of<NotesProvider>(context, listen: false);
        notesProvider.onEncryptionReady();
        await notesProvider.reloadNotes();
      }

      if (mounted) {
        setState(() {
          _locked = false;
          _passwordMode = false;
          _passwordError = null;
        });
      }
    } catch (e) {
      debugPrint('[AppLockGate] Encryption init failed: $e');
      if (mounted) {
        setState(() {
          _passwordError = e is DecryptionException
              ? AppTranslations.translate('encryption_key_invalid')
              : '${AppTranslations.translate('encryption_init_failed')}: ${e.toString()}';
          _passwordMode = true;
        });
      }
    }
  }

  // ── Master-password secure storage helpers ────────────────────────────────

  /// Stores [password] under [kMasterPasswordForRederiveKey] so that
  /// [NotesProvider] can retrieve it when re-deriving the encryption key after
  /// a Drive salt is discovered on reinstall.
  Future<void> _storeEncryptedPassword(String password) async {
    try {
      await _storage.write(
        key: kMasterPasswordForRederiveKey,
        value: password,
      );
      debugPrint(
          '[AppLockGate] Master password stored for Drive salt re-derivation.');
    } catch (e) {
      // Non-fatal: if storage fails the re-derivation will prompt the user for
      // their password interactively via the mismatch dialog in NotesProvider.
      debugPrint('[AppLockGate] Failed to store master password: $e');
    }
  }

  // ── Password submission ────────────────────────────────────────────────────

  Future<void> _submitPassword() async {
    final password = _passwordCtrl.text.trim();
    final confirm = _passwordConfCtrl.text.trim();

    if (password.isEmpty) {
      setState(() => _passwordError =
          AppTranslations.translate('password_cannot_be_empty'));
      return;
    }

    if (_setupMode) {
      // ── First-run password setup ────────────────────────────────────────
      if (password.length < 4) {
        setState(() =>
        _passwordError = AppTranslations.translate('password_min_length'));
        return;
      }
      if (password != confirm) {
        setState(() => _passwordError =
            AppTranslations.translate('passwords_do_not_match'));
        return;
      }

      await _storage.write(key: _kPinKey, value: password);
      await _initializeEncryption(password);
      setState(() {
        _setupMode = false;
        _passwordError = null;
      });
    } else {
      // ── Unlock with stored password ─────────────────────────────────────
      final stored = await _storage.read(key: _kPinKey);
      if (stored == null) {
        setState(() =>
        _passwordError = AppTranslations.translate('no_password_stored'));
        return;
      }

      if (password != stored) {
        setState(() =>
        _passwordError = AppTranslations.translate('incorrect_password'));
        return;
      }

      await _initializeEncryption(password);
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_locked) {
      return widget.child;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = Neu.base(isDark);
    final primary = Neu.textPrimary(isDark);
    final subtle = Neu.textSecondary(isDark);
    final accent = Theme.of(context).colorScheme.primary;
    final inputFill = Neu.inputFill(isDark);

    return Scaffold(
      backgroundColor: base,
      body: SafeArea(
        child: Stack(
          children: [
            // ── Language picker button (top-right) ──────────────────────────
            Positioned(
              top: 8,
              right: 12,
              child: Consumer<LanguageProvider>(
                builder: (ctx, langProv, _) => TextButton(
                  onPressed: () =>
                      _showLanguagePicker(context, isDark, langProv),
                  style: TextButton.styleFrom(
                    foregroundColor: subtle,
                    padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        AppTranslations.getLanguageFlag(langProv.languageCode),
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(width: 6),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            AppTranslations.getLanguageName(
                                langProv.languageCode),
                            style: TextStyle(fontSize: 12, color: subtle),
                          ),
                              () {
                            final native =
                            AppTranslations.getNativeLanguageName(
                                langProv.languageCode);
                            final english = AppTranslations.getLanguageName(
                                langProv.languageCode);
                            if (native == english) {
                              return const SizedBox.shrink();
                            }
                            return Text(
                              native,
                              style: TextStyle(
                                  fontSize: 10, color: subtle.withAlpha(160)),
                            );
                          }(),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Main lock content ───────────────────────────────────────────
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── Icon + Title ──────────────────────────────────────
                        Container(
                          width: 72,
                          height: 72,
                          margin: const EdgeInsets.only(bottom: 24),
                          decoration: BoxDecoration(
                            color: accent.withAlpha(25),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(Icons.lock_rounded, size: 40, color: accent),
                        ),
                        Text(
                          'noteliha',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: primary,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          AppTranslations.translate('notes_are_encrypted'),
                          style: TextStyle(fontSize: 14, color: subtle),
                        ),
                        const SizedBox(height: 20),

                        // ── Feature highlights ───────────────────────────────────
                        _buildFeatureGrid(subtle, accent),

                        const SizedBox(height: 28),

                        // ── Divider ──────────────────────────────────────────────
                        Divider(
                          color: subtle.withAlpha(40),
                          thickness: 1,
                          height: 1,
                        ),
                        const SizedBox(height: 28),

                        // ── Body ────────────────────────────────────────────────
                        if (_setupMode)
                          _buildSetupUI(primary, subtle, accent, inputFill)
                        else if (_passwordMode)
                          _buildPasswordUI(primary, subtle, accent, inputFill)
                        else
                          _buildBioWaiting(subtle, accent),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Language picker (same sheet as SettingsScreen) ────────────────────────

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
                ),
                padding: EdgeInsets.fromLTRB(
                    20, 16, 20, MediaQuery.of(ctx).padding.bottom + 24),
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
                          color: Neu.textSecondary(isDark).withAlpha(80),
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

                    // Search field
                    Container(
                      decoration: BoxDecoration(
                        color: Neu.inputFill(isDark),
                        borderRadius: BorderRadius.circular(12),
                      ),
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

                    // Language list
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
                          final textPrimary = Neu.textPrimary(isDark);
                          final textSecondary = Neu.textSecondary(isDark);

                          return InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () async {
                              await langProv.setLocale(locale);
                              if (ctx.mounted) Navigator.pop(ctx);
                              // Rebuild lock screen strings
                              if (mounted) setState(() {});
                            },
                            child: Padding(
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
                                                : textPrimary,
                                          ),
                                        ),
                                        if (nativeName !=
                                            englishName) ...[
                                          const SizedBox(height: 1),
                                          Text(
                                            nativeName,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w400,
                                              color: isSelected
                                                  ? accent.withAlpha(180)
                                                  : textSecondary,
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

  // ── First-run: create password ─────────────────────────────────────────────

  Widget _buildSetupUI(
      Color primary, Color subtle, Color accent, Color inputFill) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppTranslations.translate('create_master_password'),
          style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600, color: primary),
        ),
        const SizedBox(height: 8),
        Text(
          AppTranslations.translate('password_description'),
          style: TextStyle(fontSize: 13, color: subtle),
        ),
        const SizedBox(height: 24),
        _PasswordField(
          controller: _passwordCtrl,
          hint: AppTranslations.translate('password'),
          subtle: subtle,
          inputFill: inputFill,
          obscure: _obscurePassword,
          onToggleObscure: () =>
              setState(() => _obscurePassword = !_obscurePassword),
        ),
        const SizedBox(height: 12),
        _PasswordField(
          controller: _passwordConfCtrl,
          hint: AppTranslations.translate('confirm_password'),
          subtle: subtle,
          inputFill: inputFill,
          obscure: _obscureConfirm,
          onToggleObscure: () =>
              setState(() => _obscureConfirm = !_obscureConfirm),
          errorText: _passwordError,
          onSubmitted: (_) => _submitPassword(),
        ),
        const SizedBox(height: 24),
        _PrimaryButton(
          label: AppTranslations.translate('set_password'),
          accent: accent,
          onPressed: _submitPassword,
        ),
      ],
    );
  }

  // ── Password entry (biometric fallback, or no biometric hardware) ──────────

  Widget _buildPasswordUI(
      Color primary, Color subtle, Color accent, Color inputFill) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppTranslations.translate('enter_password'),
          style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600, color: primary),
        ),
        const SizedBox(height: 8),
        Text(
          AppTranslations.translate('enter_master_password'),
          style: TextStyle(fontSize: 13, color: subtle),
        ),
        const SizedBox(height: 24),
        _PasswordField(
          controller: _passwordCtrl,
          hint: AppTranslations.translate('password'),
          subtle: subtle,
          inputFill: inputFill,
          obscure: _obscurePassword,
          onToggleObscure: () =>
              setState(() => _obscurePassword = !_obscurePassword),
          errorText: _passwordError,
          onSubmitted: (_) => _submitPassword(),
        ),
        const SizedBox(height: 24),
        _PrimaryButton(
          label: AppTranslations.translate('unlock'),
          accent: accent,
          onPressed: _submitPassword,
        ),

        // Offer to retry biometrics (native only)
        if (!kIsWeb) ...[
          const SizedBox(height: 16),
          Center(
            child: TextButton.icon(
              onPressed: _bioRunning
                  ? null
                  : () async {
                final stored = await _storage.read(key: _kPinKey);
                if (stored != null && mounted) {
                  setState(() {
                    _passwordMode = false;
                    _passwordError = null;
                  });
                  await _tryBiometric(stored);
                }
              },
              icon: Icon(
                _bioRunning ? Icons.hourglass_empty : Icons.fingerprint_rounded,
                size: 18,
                color: _bioRunning ? subtle : accent,
              ),
              label: Text(
                _bioRunning
                    ? AppTranslations.translate('authenticating')
                    : AppTranslations.translate('use_biometrics_instead'),
                style: TextStyle(
                  color: _bioRunning ? subtle : accent,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── Feature highlights grid ────────────────────────────────────────────────

  Widget _buildFeatureGrid(Color subtle, Color accent) {
    // 6 features in a 2×3 grid + 1 full-width item below
    const gridFeatures = [
      (Icons.wifi_off_rounded, 'Offline first'),
      (Icons.language_rounded, '80 languages + RTL'),
      (Icons.select_all_rounded, 'Multi-select & share'),
      (Icons.restaurant_menu_rounded, 'Meal plans & itineraries'),
      (Icons.block_rounded, 'No ads · No IAP · No account'),
      (Icons.cloud_sync_rounded, 'Google Drive sync'),
    ];
    const fullWidthFeature = (
    Icons.fingerprint_rounded,
    'Encrypted notes & drawings with Biometric unlock',
    );

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark
        ? accent.withAlpha(14)
        : accent.withAlpha(10);
    final borderColor = accent.withAlpha(isDark ? 30 : 22);

    Widget featureChip(IconData icon, String label, {bool wide = false}) {
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: wide ? 14 : 10,
          vertical: wide ? 10 : 9,
        ),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: wide ? MainAxisSize.min : MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: accent.withAlpha(200)),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: subtle,
                  height: 1.3,
                ),
                textAlign: wide ? TextAlign.left : TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 2×3 grid
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 2.8,
          children: gridFeatures
              .map((f) => featureChip(f.$1, f.$2))
              .toList(),
        ),
        const SizedBox(height: 8),
        // 7th full-width chip
        SizedBox(
          width: double.infinity,
          child: featureChip(fullWidthFeature.$1, fullWidthFeature.$2, wide: true),
        ),
      ],
    );
  }

  // ── Biometric in progress ──────────────────────────────────────────────────

  Widget _buildBioWaiting(Color subtle, Color accent) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Animated fingerprint with radiating rings ──────────────────────
        SizedBox(
          width: 120,
          height: 120,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outermost ring — slowest fade
              AnimatedBuilder(
                animation: _ringAnim,
                builder: (_, __) {
                  final t = _ringAnim.value;
                  return Opacity(
                    opacity: (1.0 - t).clamp(0.0, 1.0) * 0.25,
                    child: Container(
                      width: 40 + t * 80,
                      height: 40 + t * 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: accent, width: 1.5),
                      ),
                    ),
                  );
                },
              ),
              // Middle ring — offset by half a cycle
              AnimatedBuilder(
                animation: _ringCtrl,
                builder: (_, __) {
                  final t = (((_ringCtrl.value + 0.4) % 1.0));
                  final curved = Curves.easeOut.transform(t);
                  return Opacity(
                    opacity: (1.0 - curved).clamp(0.0, 1.0) * 0.35,
                    child: Container(
                      width: 40 + curved * 80,
                      height: 40 + curved * 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: accent, width: 1.5),
                      ),
                    ),
                  );
                },
              ),
              // Inner ring — offset by a quarter cycle
              AnimatedBuilder(
                animation: _ringCtrl,
                builder: (_, __) {
                  final t = (((_ringCtrl.value + 0.7) % 1.0));
                  final curved = Curves.easeOut.transform(t);
                  return Opacity(
                    opacity: (1.0 - curved).clamp(0.0, 1.0) * 0.45,
                    child: Container(
                      width: 40 + curved * 80,
                      height: 40 + curved * 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: accent, width: 1.5),
                      ),
                    ),
                  );
                },
              ),
              // Pulsing icon background
              ScaleTransition(
                scale: _pulseAnim,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withAlpha(20),
                  ),
                ),
              ),
              // Fingerprint icon
              ScaleTransition(
                scale: _pulseAnim,
                child: Icon(
                  Icons.fingerprint_rounded,
                  size: 44,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),

        // ── Status label ───────────────────────────────────────────────────
        Text(
          AppTranslations.translate('waiting_for_biometric'),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Neu.textPrimary(
                Theme.of(context).brightness == Brightness.dark),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          AppTranslations.translate('use_your_fingerprint_or_face'),
          style: TextStyle(fontSize: 13, color: subtle),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),

        // ── Fallback button ────────────────────────────────────────────────
        TextButton.icon(
          onPressed: () => setState(() => _passwordMode = true),
          style: TextButton.styleFrom(
            foregroundColor: subtle,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: subtle.withAlpha(60)),
            ),
          ),
          icon: Icon(Icons.password_rounded, size: 16, color: subtle),
          label: Text(
            AppTranslations.translate('use_password_instead'),
            style: TextStyle(color: subtle, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

// ── Public helper — used by NotesProvider ─────────────────────────────────────

/// Retrieves the master password stored by [AppLockGate] after a successful
/// unlock.  Returns `null` if no password has been stored yet.
///
/// Exposed as a top-level function so [NotesProvider] can call it without
/// holding a reference to the widget state.
Future<String?> getStoredMasterPassword() async {
  const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  try {
    return await storage.read(key: kMasterPasswordForRederiveKey);
  } catch (e) {
    debugPrint('[AppLockGate] getStoredMasterPassword failed: $e');
    return null;
  }
}

// ── Reusable form widgets ──────────────────────────────────────────────────────

class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final Color subtle;
  final Color inputFill;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final String? errorText;
  final ValueChanged<String>? onSubmitted;

  const _PasswordField({
    required this.controller,
    required this.hint,
    required this.subtle,
    required this.inputFill,
    required this.obscure,
    required this.onToggleObscure,
    this.errorText,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: TextInputType.text,
      maxLength: 128,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: subtle.withAlpha(128)),
        counterText: '',
        filled: true,
        fillColor: inputFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        errorText: errorText,
        errorStyle: const TextStyle(color: Colors.redAccent),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            size: 18,
            color: subtle,
          ),
          onPressed: onToggleObscure,
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final Color accent;
  final VoidCallback onPressed;

  const _PrimaryButton(
      {required this.label, required this.accent, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}