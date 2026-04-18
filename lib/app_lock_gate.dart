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

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
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
  final _passwordCtrl    = TextEditingController();
  final _passwordConfCtrl = TextEditingController();
  String? _passwordError;
  bool _obscurePassword = true;
  bool _obscureConfirm  = true;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkLock(onResume: false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
            _locked      = true;
            _setupMode   = true;
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
        debugPrint('[AppLockGate] Biometrics not properly available, falling back to password');
        if (mounted) {
          setState(() {
            _bioRunning = false;
            _passwordMode = true;
            _passwordError = 'Biometrics not available on this device';
          });
        }
        return;
      }

      // Give the UI a moment to settle before showing the dialog
      // This ensures the activity is in the correct state to display overlays
      await Future.delayed(const Duration(milliseconds: 150));

      if (!mounted) {
        setState(() => _bioRunning = false);
        return;
      }

      // ENHANCED OPTIONS: These settings force the dialog to appear properly
      final authed = await _localAuth.authenticate(
        localizedReason: 'Verify your identity to access your notes',
        options: const AuthenticationOptions(
          // Use biometricOnly: true to force only biometric methods
          // Set to false if you want to allow device PIN/pattern as fallback
          biometricOnly: true,
          // stickyAuth keeps the dialog visible even if the app is backgrounded
          stickyAuth: true,
          // sensitiveTransaction adds extra security context
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

      // Provide more specific error messages
      String errorMsg = 'Biometric authentication failed';
      if (e.toString().contains('NotAvailable')) {
        errorMsg = 'Biometric authentication not available';
      } else if (e.toString().contains('LockedOut')) {
        errorMsg = 'Too many attempts. Please use password.';
      } else if (e.toString().contains('NotEnrolled')) {
        errorMsg = 'No biometrics enrolled on device';
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
          _locked       = false;
          _passwordMode = false;
          _passwordError = null;
        });
      }
    } catch (e) {
      debugPrint('[AppLockGate] Encryption init failed: $e');
      if (mounted) {
        setState(() {
          _passwordError = e is DecryptionException
              ? 'Encryption key is invalid. Password may be incorrect or data corrupted.'
              : 'Failed to initialize encryption: ${e.toString()}';
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
      debugPrint('[AppLockGate] Master password stored for Drive salt re-derivation.');
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
      setState(() => _passwordError = 'Password cannot be empty');
      return;
    }

    if (_setupMode) {
      // ── First-run password setup ────────────────────────────────────────
      if (password.length < 4) {
        setState(() => _passwordError = 'Minimum 4 characters required');
        return;
      }
      if (password != confirm) {
        setState(() => _passwordError = 'Passwords do not match');
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
        setState(() => _passwordError = 'No password stored. Please restart.');
        return;
      }

      if (password != stored) {
        setState(() => _passwordError = 'Incorrect password');
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
    final base = isDark ? const Color(0xFF1A1A1A) : const Color(0xFFFAF8F5);
    isDark ? const Color(0xFF242424) : const Color(0xFFFFFFFF);
    final primary =
    isDark ? const Color(0xFFE0E0E0) : const Color(0xFF1A1A1A);
    final subtle = isDark ? const Color(0xFF9E9E9E) : const Color(0xFF666666);
    final accent = Theme.of(context).colorScheme.primary;
    final inputFill =
    isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF0F0F0);

    return Scaffold(
      backgroundColor: base,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Icon + Title ────────────────────────────────────────────
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
                  'Your notes are encrypted.',
                  style: TextStyle(fontSize: 14, color: subtle),
                ),
                const SizedBox(height: 36),

                // ── Body ────────────────────────────────────────────────────
                if (_setupMode)
                  _buildSetupUI(primary, subtle, accent, inputFill)
                else if (_passwordMode)
                  _buildPasswordUI(primary, subtle, accent, inputFill)
                else
                  _buildBioWaiting(subtle),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── First-run: create password ─────────────────────────────────────────────

  Widget _buildSetupUI(
      Color primary, Color subtle, Color accent, Color inputFill) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Create Master Password',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600, color: primary)),
        const SizedBox(height: 8),
        Text(
          'You will use this password to unlock your notes.\n'
              'Make it strong — it cannot be recovered if lost.',
          style: TextStyle(fontSize: 13, color: subtle),
        ),
        const SizedBox(height: 24),
        _PasswordField(
          controller: _passwordCtrl,
          hint: 'Password',
          subtle: subtle,
          inputFill: inputFill,
          obscure: _obscurePassword,
          onToggleObscure: () =>
              setState(() => _obscurePassword = !_obscurePassword),
        ),
        const SizedBox(height: 12),
        _PasswordField(
          controller: _passwordConfCtrl,
          hint: 'Confirm Password',
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
            label: 'Set Password', accent: accent, onPressed: _submitPassword),
      ],
    );
  }

  // ── Password entry (biometric fallback, or no biometric hardware) ──────────

  Widget _buildPasswordUI(
      Color primary, Color subtle, Color accent, Color inputFill) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Enter Password',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600, color: primary)),
        const SizedBox(height: 8),
        Text(
          'Enter your master password to access your notes.',
          style: TextStyle(fontSize: 13, color: subtle),
        ),
        const SizedBox(height: 24),
        _PasswordField(
          controller: _passwordCtrl,
          hint: 'Password',
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
            label: 'Unlock', accent: accent, onPressed: _submitPassword),

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
                    _passwordMode  = false;
                    _passwordError = null;
                  });
                  await _tryBiometric(stored);
                }
              },
              icon: Icon(
                  _bioRunning ? Icons.hourglass_empty : Icons.fingerprint_rounded,
                  size: 18,
                  color: _bioRunning ? subtle : const Color(0xFF00897B)
              ),
              label: Text(
                _bioRunning ? 'Authenticating...' : 'Use Biometrics Instead',
                style: TextStyle(
                    color: _bioRunning ? subtle : const Color(0xFF00897B)
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── Biometric in progress ──────────────────────────────────────────────────

  Widget _buildBioWaiting(Color subtle) {
    return Column(
      children: [
        const SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(
              strokeWidth: 2.5, color: Color(0xFF00897B)),
        ),
        const SizedBox(height: 16),
        Text('Waiting for biometric…',
            style: TextStyle(fontSize: 13, color: subtle)),
        const SizedBox(height: 24),
        TextButton.icon(
          onPressed: () => setState(() => _passwordMode = true),
          icon: Icon(Icons.password_rounded, size: 16, color: subtle),
          label:
          Text('Use Password Instead', style: TextStyle(color: subtle)),
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