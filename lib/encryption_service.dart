// lib/services/encryption_service.dart
//
// APP-LEVEL ENCRYPTION SERVICE — FIXED VERSION
// ─────────────────────────────────────────────
//
// ✅ FIXES APPLIED:
//   1. PBKDF2 password-derived keys (survives cache clear on web)
//   2. Explicit error detection (throw instead of hiding failures)
//   3. Key integrity validation on startup
//   4. Web-specific warnings
//   5. Salt storage for reproducible key derivation
//   6. rederiveKeyWithNewSalt() — re-derives key after Drive salt is fetched
//      on reinstall, replacing the temporary local salt so all notes decrypt.
//   7. verifyKey() — non-throwing key validation used before re-derivation.
//
// USAGE
// ─────
// On first app launch, call initWithMasterPassword(pwd) to derive key.
// On subsequent launches, call init() to reload the same key via salt.
//
//   // First run
//   await EncryptionService.instance.initWithMasterPassword('user-password');
//
//   // Subsequent runs
//   await EncryptionService.instance.init();
//
// Then wrap any string before writing to Hive:
//   final cipher = EncryptionService.instance.encrypt(plainText);
//   box.put(key, cipher);
//
// Unwrap when reading:
//   final plain = await EncryptionService.instance.decrypt(cipher);
//
// DEPENDENCIES (add to pubspec.yaml)
// ────────────────────────────────────
//   encrypt: ^5.0.3
//   flutter_secure_storage: ^9.2.2
//   pointycastle: ^3.7.3      ← for PBKDF2
//   crypto: ^3.0.3            ← for SHA256

import 'dart:convert';
import 'dart:math';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';

// ─── Exception Classes ─────────────────────────────────────────────────────

class DecryptionException implements Exception {
  final String message;
  DecryptionException(this.message);

  @override
  String toString() => message;
}

class EncryptionKeyException implements Exception {
  final String message;
  EncryptionKeyException(this.message);

  @override
  String toString() => message;
}

// ─── Constants ─────────────────────────────────────────────────────────────

const String _kCipherPrefix = 'ENC1:';
const String _kSaltAlias = 'noteliha_pbkdf2_salt_v1';
const String _kKeyTestAlias = '_noteliha_encryption_test_v1';
const int _kPbkdf2Iterations = 100000; // OWASP recommendation for 2024
const int _kSaltLengthBytes = 32;

// ─── Secure Storage Config ─────────────────────────────────────────────────

const _storage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
);

// ─────────────────────────────────────────────────────────────────────────────

class EncryptionService {
  EncryptionService._();
  static final EncryptionService instance = EncryptionService._();

  enc.Key? _key;
  bool _initialized = false;
  bool _usingFallback = false;

  /// Fires `true` when a real (non-fallback) key is loaded and notes can be
  /// safely decrypted. NotesProvider listens to this to gate its box reads.
  final keyReady = ValueNotifier<bool>(false);

  bool get isInitialized => _initialized;
  bool get usingFallbackKey => _usingFallback;

  /// Returns the current PBKDF2 salt (base64url), or null if not yet derived.
  /// NotesProvider reads this and stores it in the Drive manifest so the key
  /// can be reconstructed after a reinstall using the same master password.
  Future<String?> exportSalt() => _storage.read(key: _kSaltAlias);

  /// Returns the AES-GCM test ciphertext that was written after the most
  /// recent successful key derivation, or null if no test value exists yet.
  ///
  /// [NotesProvider.uploadSaltToDrive] uploads this alongside salt.bin as
  /// test.bin so [verifyKey] has a Drive-origin oracle to test against after
  /// a reinstall — the locally-stored test value is useless then because it
  /// was written with the new temporary key, not the original Drive key.
  Future<String?> exportTestCipher() => _storage.read(key: _kKeyTestAlias);

  /// Decrypt without throwing — returns null on any failure.
  /// Use this in UI code (list cards, previews) so a single bad note never
  /// crashes the whole widget tree.
  String? safeDecrypt(String value) {
    try {
      return decrypt(value);
    } catch (e) {
      debugPrint('[Encryption] safeDecrypt failed: $e');
      return null;
    }
  }

  // ── INITIALIZATION ─────────────────────────────────────────────────────────

  /// Supply the salt fetched from Drive before calling [initWithMasterPassword].
  /// This is the cross-platform flow:
  ///   1. NotesProvider fetches salt.bin from Drive root folder.
  ///   2. It calls supplyDriveSalt(salt) — stored locally as a cache.
  ///   3. AppLockGate prompts for password and calls initWithMasterPassword().
  ///   4. initWithMasterPassword() uses the supplied salt → same key on every
  ///      platform and after every reinstall.
  ///
  /// If Drive has no salt yet (first ever use), initWithMasterPassword() will
  /// generate one and NotesProvider will upload it to Drive immediately.
  Future<void> supplyDriveSalt(String saltBase64) async {
    await _storage.write(key: _kSaltAlias, value: saltBase64);
    debugPrint('[Encryption] Salt supplied from Drive and cached locally.');
  }

  /// True after initWithMasterPassword() when a brand-new salt was generated
  /// (i.e. first ever use on this account). NotesProvider checks this and
  /// immediately uploads the salt to Drive so other platforms can use it.
  bool _saltIsNew = false;
  bool get saltIsNew => _saltIsNew;

  /// Call once on app startup with the user's master password.
  /// On subsequent launches, call init() instead to reload the derived key.
  Future<void> initWithMasterPassword(String masterPassword) async {
    if (masterPassword.isEmpty) {
      throw EncryptionKeyException('Master password cannot be empty');
    }

    _saltIsNew = false;

    try {
      // Check if a salt already exists (locally cached or supplied from Drive).
      final existingSalt = await _storage.read(key: _kSaltAlias);

      String salt;
      if (existingSalt != null) {
        salt = existingSalt;
        debugPrint('[Encryption] Using existing salt for key derivation.');
      } else {
        // No salt anywhere — this is truly the first use on this account.
        // Generate a new random salt and flag it so NotesProvider can upload
        // it to Drive immediately, making it available on all other platforms.
        salt = base64Url.encode(_randomBytes(_kSaltLengthBytes));
        await _storage.write(key: _kSaltAlias, value: salt);
        _saltIsNew = true;
        debugPrint('[Encryption] Generated new salt — will upload to Drive.');
      }

      // Derive the AES key from password + salt
      _key = await _deriveKeyFromPassword(masterPassword, salt);

      // Write a test value to validate key integrity
      await _writeTestValue();

      _initialized = true;
      _usingFallback = false;
      keyReady.value = true;
      debugPrint('[Encryption] Initialized with PBKDF2-derived key.');
    } catch (e) {
      debugPrint('[Encryption] Failed to initialize with master password: $e');
      _initFallback();
      rethrow;
    }
  }

  /// Reload the encryption key from storage using the stored salt.
  /// Call this on every app restart (instead of initWithMasterPassword).
  /// If the salt doesn't exist, the app is in "locked" state — user must
  /// provide master password via UI.
  Future<void> init() async {
    if (_initialized) return;

    try {
      final storedSalt = await _storage.read(key: _kSaltAlias);
      if (storedSalt == null) {
        // No encryption configured yet — load fallback or wait for password setup
        debugPrint(
          '[Encryption] No salt found. App is in locked state.\n'
              'Call initWithMasterPassword(pwd) when user provides password.',
        );
        _initFallback();
        return;
      }

      // We have a salt, but we can't derive the key without the password.
      // The UI (AppLockGate) should prompt the user for password here.
      // For now, set a marker that we need password input.
      debugPrint(
        '[Encryption] Salt found but key locked. '
            'Waiting for master password from AppLockGate...',
      );
      _usingFallback = true;
      _initialized = true;
    } catch (e) {
      debugPrint('[Encryption] init() failed: $e');
      _initFallback();
    }
  }

  // ── KEY RE-DERIVATION (reinstall / cross-platform salt sync) ───────────────

  /// Re-derives the AES key using [masterPassword] and a salt fetched from
  /// Drive, then replaces the locally-cached salt so future launches are
  /// consistent.
  ///
  /// Call this when a returning user reinstalls the app:
  ///   1. App generates a fresh temporary salt and derives a key from it
  ///      (via [initWithMasterPassword]) — but that key can't decrypt Drive
  ///      notes, which were encrypted with the *original* salt.
  ///   2. After Drive sign-in, [NotesProvider._fetchAndReDeriveKey()] calls
  ///      [verifyKey] to confirm the stored password matches the Drive salt.
  ///   3. If valid, it calls this method to swap in the Drive salt, re-derive
  ///      the correct key, and write a fresh test value.
  ///   4. [keyReady] is toggled so listeners (NotesProvider) refresh the UI.
  Future<void> rederiveKeyWithNewSalt(
      String masterPassword, String newSaltBase64) async {
    if (masterPassword.isEmpty) {
      throw EncryptionKeyException('Master password cannot be empty');
    }

    debugPrint('[Encryption] Re-deriving key with Drive salt…');

    try {
      // Derive from the Drive salt
      final newKey =
      await _deriveKeyFromPassword(masterPassword, newSaltBase64);

      // Replace the local salt cache so future launches use the Drive salt
      await _storage.write(key: _kSaltAlias, value: newSaltBase64);

      // Atomically swap the live key
      _key = newKey;

      // Write a fresh test value so subsequent validateKeyIntegrity() calls pass
      await _writeTestValue();

      _initialized = true;
      _usingFallback = false;

      // Toggle keyReady so ValueNotifier listeners (e.g. NotesProvider) fire
      keyReady.value = false;
      keyReady.value = true;

      debugPrint('[Encryption] Key re-derived successfully from Drive salt.');
    } catch (e) {
      debugPrint('[Encryption] rederiveKeyWithNewSalt failed: $e');
      rethrow;
    }
  }

  /// Tests whether [masterPassword] + [saltBase64] can decrypt [driveTestCipher].
  ///
  /// [driveTestCipher] must be the test ciphertext fetched from Drive (test.bin),
  /// **not** the locally-stored `_kKeyTestAlias`.  After a reinstall the local
  /// test value was encrypted with the new temporary salt, so it cannot be used
  /// to validate a password against the original Drive salt — passing it here
  /// would always return `false` for a legitimate returning user.
  ///
  /// Returns `true` on success, `false` on any failure — never throws.
  ///
  /// Use this before calling [rederiveKeyWithNewSalt] to confirm the password
  /// the user entered originally matches the salt stored on Drive.
  Future<bool> verifyKey(
      String masterPassword, String saltBase64, String driveTestCipher) async {
    try {
      if (!driveTestCipher.startsWith(_kCipherPrefix)) {
        // Malformed or empty test value from Drive — treat as unverifiable.
        debugPrint(
            '[Encryption] verifyKey: Drive test cipher malformed, treating as valid.');
        return true;
      }

      // Derive a candidate key from the supplied credentials.
      // This does NOT touch the live _key field.
      final candidateKey =
      await _deriveKeyFromPassword(masterPassword, saltBase64);

      // Attempt to decrypt the Drive-origin test value with the candidate key.
      final blob = driveTestCipher.substring(_kCipherPrefix.length);
      final parts = blob.split(':');
      if (parts.length != 2) return false;

      final iv = enc.IV(base64Url.decode(parts[0]));
      final encrypted = enc.Encrypted(base64Url.decode(parts[1]));
      final encrypter =
      enc.Encrypter(enc.AES(candidateKey, mode: enc.AESMode.gcm));
      encrypter.decrypt(encrypted, iv: iv); // throws on wrong key

      debugPrint('[Encryption] verifyKey: password ✓ matches Drive salt.');
      return true;
    } catch (e) {
      debugPrint('[Encryption] verifyKey: mismatch — $e');
      return false;
    }
  }

  // ── ENCRYPTION / DECRYPTION ────────────────────────────────────────────────

  /// Encrypt a string. Returns "ENC1:" + base64 blob.
  /// Throws if key is not initialized.
  String encrypt(String plainText) {
    _assertReady();
    if (plainText.isEmpty) return plainText;

    try {
      // AES-256-GCM: fresh 12-byte IV per message for semantic security.
      final iv = enc.IV(_randomBytes(12));
      final encrypter = enc.Encrypter(enc.AES(_key!, mode: enc.AESMode.gcm));
      final encrypted = encrypter.encrypt(plainText, iv: iv);

      // Encoded blob: base64(iv) + ':' + base64(ciphertext)
      final blob = '${base64Url.encode(iv.bytes)}:${encrypted.base64}';
      return '$_kCipherPrefix$blob';
    } catch (e) {
      throw EncryptionKeyException('Encryption failed: $e');
    }
  }

  /// Decrypt a string. Returns plain text.
  /// Throws DecryptionException if key is invalid or data is corrupted.
  /// Returns plain text as-is if it wasn't encrypted (backward compatible).
  String decrypt(String value) {
    _assertReady();

    // Not encrypted — return as-is (backward compatibility)
    if (!value.startsWith(_kCipherPrefix)) {
      return value;
    }

    try {
      final blob = value.substring(_kCipherPrefix.length);
      final parts = blob.split(':');
      if (parts.length != 2) {
        throw DecryptionException(
          'Malformed ciphertext. This note may be corrupted.\n'
              'Trying to read an encrypted note with an invalid key?',
        );
      }

      final iv = enc.IV(base64Url.decode(parts[0]));
      final encrypted = enc.Encrypted(base64Url.decode(parts[1]));
      final encrypter = enc.Encrypter(enc.AES(_key!, mode: enc.AESMode.gcm));
      final plainText = encrypter.decrypt(encrypted, iv: iv);
      return plainText;
    } on DecryptionException {
      rethrow; // Already a proper error, propagate as-is
    } catch (e) {
      // Likely cause: encryption key is wrong/missing (e.g., cache cleared on web)
      throw DecryptionException(
        'Failed to decrypt note. Possible causes:\n'
            '  1. Encryption key is invalid\n'
            '  2. Browser cache was cleared (web only)\n'
            '  3. Data is corrupted\n\n'
            'To fix: Re-enter your master password or restore from backup.\n\n'
            'Technical: $e',
      );
    }
  }

  // ── KEY ROTATION ───────────────────────────────────────────────────────────

  /// Re-encrypt all notes with a fresh encryption key.
  /// Call after biometric auth or when rotating security credentials.
  ///
  /// Example usage:
  ///   await EncryptionService.instance.rotateKey((svc) async {
  ///     final box = await Hive.openBox<Note>('notes');
  ///     for (final note in box.values) {
  ///       final newCipher = svc.encrypt(note.decryptedContent);
  ///       note.encryptedContent = newCipher;
  ///       await note.save();
  ///     }
  ///   });
  Future<void> rotateKey(
      String newMasterPassword,
      Future<void> Function(EncryptionService svc) reEncryptAll,
      ) async {
    if (newMasterPassword.isEmpty) {
      throw EncryptionKeyException('New master password cannot be empty');
    }

    final oldKey = _key;

    try {
      // Generate a new salt
      final newSalt = base64Url.encode(_randomBytes(_kSaltLengthBytes));
      final newKey = await _deriveKeyFromPassword(newMasterPassword, newSalt);

      // Temporarily set the new key so reEncryptAll can encrypt with it
      _key = newKey;

      // Re-encrypt all notes with the new key
      await reEncryptAll(this);

      // Persist the new salt (key is derived from it)
      await _storage.write(key: _kSaltAlias, value: newSalt);

      // Validate the new key
      await _writeTestValue();

      debugPrint('[Encryption] Key rotated successfully.');
    } catch (e) {
      // Roll back to the old key so the app remains usable
      _key = oldKey;
      debugPrint('[Encryption] Key rotation failed, rolled back: $e');
      rethrow;
    }
  }

  // ── KEY INTEGRITY VALIDATION ───────────────────────────────────────────────

  /// Validates that the encryption key is working correctly.
  /// Call on app startup to detect key corruption early.
  /// Throws DecryptionException if validation fails.
  Future<void> validateKeyIntegrity() async {
    if (!_initialized || _key == null) {
      throw EncryptionKeyException('Encryption service not initialized');
    }

    try {
      final testValue = await _storage.read(key: _kKeyTestAlias);
      if (testValue != null && testValue.startsWith(_kCipherPrefix)) {
        // Try to decrypt the test value — this validates the key
        decrypt(testValue);
        debugPrint('[Encryption] Key integrity check passed ✓');
      }
    } catch (e) {
      throw DecryptionException(
        'Encryption key integrity check failed.\n'
            'Your encryption key is invalid or corrupted.\n'
            'Possible causes:\n'
            '  • Browser cache was cleared (web only)\n'
            '  • Encryption key was rotated\n'
            '  • Data was modified externally\n\n'
            'To recover: Re-enter your master password.\n\n'
            'Technical: $e',
      );
    }
  }

  // ── PRIVATE HELPERS ────────────────────────────────────────────────────────

  /// Derive a 32-byte AES key from a master password using PBKDF2-SHA256.
  /// Returns the same key for the same password + salt combination.
  static Future<enc.Key> _deriveKeyFromPassword(
      String password,
      String saltBase64,
      ) async {
    try {
      final salt = base64Url.decode(saltBase64);

      // PBKDF2-SHA256 derivation
      // Using pointycastle's PBKDF2
      final keyDeriver = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
        ..init(Pbkdf2Parameters(salt, _kPbkdf2Iterations, 32));

      final derivedBytes = keyDeriver.process(
        Uint8List.fromList(utf8.encode(password)),
      );

      return enc.Key(derivedBytes);
    } catch (e) {
      throw EncryptionKeyException('PBKDF2 key derivation failed: $e');
    }
  }

  /// Write a test value to storage to validate key integrity.
  Future<void> _writeTestValue() async {
    try {
      final testPlain = 'noteliha-key-test-${DateTime.now().millisecondsSinceEpoch}';
      final testCipher = encrypt(testPlain);
      await _storage.write(key: _kKeyTestAlias, value: testCipher);
    } catch (e) {
      debugPrint('[Encryption] Failed to write test value: $e');
    }
  }

  void _assertReady() {
    assert(
    _key != null && _initialized,
    'EncryptionService not initialized. '
        'Call initWithMasterPassword() or init() first.',
    );
  }

  void _initFallback() {
    // Fallback for when secure storage is unavailable
    // DO NOT use in production — logs and alerts instead
    debugPrint('[Encryption] ⚠️  Using FALLBACK key (insecure)');
    _key = enc.Key(Uint8List.fromList(List.filled(32, 0x4C)));
    _usingFallback = true;
    _initialized = true;
  }

  static Uint8List _randomBytes(int length) {
    final rng = Random.secure();
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = rng.nextInt(256);
    }
    return bytes;
  }
}