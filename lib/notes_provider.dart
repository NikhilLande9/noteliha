import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show pow, min;
import 'dart:typed_data';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_lock_gate.dart' show getStoredMasterPassword, kMasterPasswordForRederiveKey;
import 'models.dart';
import 'user_metadata_service.dart';
import 'encryption_service.dart';

const String kNotesBox = 'notes_box_v4';
const String kImagesBox = 'images_box_v1';
const String kSearchIndexBox = 'search_index_box_v2';
const String kSyncStateBox = 'sync_state_box_v3';

// ── Web OAuth client ID ───────────────────────────────────────────────────────
// Replace this with your actual Web client ID from the Google Cloud Console.
// On Android/iOS the ID is read from google-services.json / GoogleService-Info.plist
// so this value is only used when running on the web.
const String _kWebClientId =
    '986108762069-tfo8ft6c8od7f63untc9sgla36j97oba.apps.googleusercontent.com';
const String kDriveRootName = '.liha_notes_app';
const String kDriveNotesDir = 'notes';
const String kDriveImagesDir = 'images';
const String kManifestName = 'manifest.json';
const String kSaltFileName = 'salt.bin'; // Cross-platform encryption salt
const String kTestFileName = 'test.bin'; // Drive-origin oracle for verifyKey

const int kInitialBackoffMs = 500;
const double kBackoffMultiplier = 1.5;
const int kMaxRetries = 5;
const int kMaxBackoffMs = 30000;

class NotesProvider extends ChangeNotifier {
  Box<dynamic>? _notesBox;
  Box<String>? _imagesBox;
  Box<String>? _searchIndexBox;
  Box<dynamic>? _syncStateBox;

  late final GoogleSignIn _googleSignIn;
  GoogleSignInAccount? _currentUser;

  SyncState _syncState = SyncState();
  SyncStatus _syncStatus = SyncStatus.idle;
  String? _syncStatusMessage;
  Timer? _syncStatusTimer;

  DriveAccountState _driveAccountState = DriveAccountState.unknown;
  bool _isCheckingDrive = false;
  bool _driveCheckFailed = false;

  DriveAccountState get driveAccountState => _driveAccountState;
  bool get isCheckingDrive => _isCheckingDrive;

  /// True when the last Drive manifest check ended with an error.
  /// The UI can surface a "Retry" button when this is true.
  bool get driveCheckFailed => _driveCheckFailed;

  GoogleSignInAccount? get user => _currentUser;
  SyncStatus get syncStatus => _syncStatus;
  String? get syncStatusMessage => _syncStatusMessage;
  bool get isSyncing => _syncStatus == SyncStatus.syncing;
  List<NoteSync> get syncConflicts => _syncState.conflicts;

  bool _encryptionReady = false;

  /// Call this from AppLockGate after EncryptionService has been initialized
  /// with the user's master password. Until this is called, [notes] returns
  /// an empty list so no decrypt attempt is made before the key is loaded.
  void onEncryptionReady() {
    _encryptionReady = true;
    _rebuildSearchIndex();
    notifyListeners();

    // If this was the very first password setup (brand new salt was generated),
    // upload the salt to Drive immediately so all other platforms can use it.
    if (EncryptionService.instance.saltIsNew) {
      unawaited(uploadSaltToDrive());
    }
  }

  List<Note> get notes {
    // Safety check: return empty list if encryption isn't ready
    if (_notesBox == null || !_encryptionReady) return [];
    return _notesBox!.values.cast<Note>().where((n) => !n.deleted).toList()
      ..sort((a, b) => a.pinned != b.pinned
          ? (a.pinned ? -1 : 1)
          : b.updatedAt.compareTo(a.updatedAt));
  }

  List<Note> get recycleBin {
    // Safety check: return empty list if encryption isn't ready
    if (!_encryptionReady || _notesBox == null) return [];
    return _notesBox!.values.cast<Note>().where((n) => n.deleted).toList();
  }

  NotesProvider() {
    _googleSignIn = GoogleSignIn(
      scopes: [
        'email',
        'profile',
        drive.DriveApi.driveFileScope,
      ],
      clientId: kIsWeb ? _kWebClientId : null,
    );
  }

  Future<void> init() async {
    try {
      _notesBox = await Hive.openBox<dynamic>(kNotesBox);
      _imagesBox = await Hive.openBox<String>(kImagesBox);
      _searchIndexBox = await Hive.openBox<String>(kSearchIndexBox);
      _syncStateBox = await Hive.openBox<dynamic>(kSyncStateBox);

      _loadSyncState();
      // Don't rebuild the search index or expose notes yet — the encryption
      // key is not loaded until the user passes AppLockGate. The keyReady
      // listener below will trigger both once the key is available.

      // ── Wait for AppLockGate to supply the master password ───────────────────
      // EncryptionService.keyReady fires true the moment initWithMasterPassword()
      // succeeds. We listen once, then remove ourselves to avoid double-fires on
      // key rotation.
      void onKeyReady() {
        if (EncryptionService.instance.keyReady.value) {
          onEncryptionReady();
        }
      }
      EncryptionService.instance.keyReady.addListener(onKeyReady);

      // If the key is already loaded (e.g. hot-restart in dev), fire immediately.
      if (EncryptionService.instance.keyReady.value) {
        onEncryptionReady();
      }

      // ── Notify immediately so the note list renders on the first frame ──────
      // This must happen before signInSilently() is called. On some platforms
      // signInSilently() triggers onCurrentUserChanged synchronously, which
      // fires _checkDriveManifestExists() and its own notifyListeners() calls
      // before the one below would have had a chance to run. Notifying here
      // guarantees the UI sees the fully-loaded local notes right away,
      // regardless of sign-in / network state.
      notifyListeners();

      _googleSignIn.onCurrentUserChanged.listen((account) async {
        _currentUser = account;
        if (account != null) {
          // Fire-and-forget: write/update the Firestore user document.
          // This never throws — errors are caught inside the service.
          unawaited(UserMetadataService.instance.upsertOnSignIn(
            googleId: account.id,
            email: account.email,
          ));

          final alreadySyncedOnThisDevice = _syncState.manifestFileId != null &&
              _syncState.accountEmail == account.email;

          if (alreadySyncedOnThisDevice) {
            _driveAccountState = DriveAccountState.returningUser;
          } else {
            // On web, the OAuth token is written to the browser credential
            // store asynchronously after onCurrentUserChanged fires.
            // A short delay lets the token settle so authenticatedClient()
            // succeeds on the first attempt instead of needing several retries.
            if (kIsWeb) await Future.delayed(const Duration(milliseconds: 500));
            await _checkDriveManifestExists();
          }
        } else {
          _driveAccountState = DriveAccountState.unknown;
        }
        notifyListeners();
      });

      // On web, signInSilently() triggers google.accounts.id.prompt() (the
      // One Tap / FedCM flow) which produces console warnings about deprecated
      // UI status methods and fails if FedCM is blocked in browser settings.
      // On web we skip the silent sign-in entirely at startup — the user signs
      // in explicitly via the "Sign In" button, which uses the standard popup
      // flow and does not trigger One Tap. Session state is restored across
      // page reloads automatically by the google_sign_in_web credential cache.
      if (!kIsWeb) {
        // signInSilently() can trigger onCurrentUserChanged before it returns,
        // so local notes are already visible by the time that happens.
        _currentUser = await _googleSignIn.signInSilently();
      }
      notifyListeners();
    } catch (e, st) {
      debugPrint('Init error: $e');
      if (!kIsWeb) {
        FirebaseCrashlytics.instance.recordError(e, st, reason: 'init failed');
      }
      // Surface auth-configuration errors immediately so they're visible in settings.
      if (e.toString().contains('appClientId') ||
          e.toString().contains('clientId')) {
        _setStatus(_friendlyAuthError(e), isError: true);
      }
      notifyListeners();
    }
  }

  Future<void> _checkDriveManifestExists() async {
    if (_currentUser == null) return;
    _isCheckingDrive = true;
    _driveCheckFailed = false;
    _setStatus('Checking Drive for existing backup…',
        isSyncing: true, persistent: true);
    notifyListeners();

    try {
      // Race the whole check against a 15-second wall-clock timeout so the UI
      // is never stuck in an indefinite "checking…" state.
      await Future.any([
        _doCheckDriveManifest(),
        Future.delayed(const Duration(seconds: 15)).then((_) {
          // Only treat it as a timeout if the check is still running.
          if (_isCheckingDrive) {
            throw TimeoutException('Drive check timed out after 15 seconds',
                const Duration(seconds: 15));
          }
        }),
      ]);
    } on TimeoutException catch (e) {
      debugPrint('Drive check timeout: $e');
      _driveAccountState = DriveAccountState.unknown;
      _driveCheckFailed = true;
      _setStatus('Drive check timed out. Tap "Retry" to try again.',
          isError: true);
    } catch (e) {
      debugPrint('Drive check error: $e');
      _driveAccountState = DriveAccountState.unknown;
      _driveCheckFailed = true;
      _setStatus('Could not check Drive. Tap "Retry" to try again.',
          isError: true);
    } finally {
      _isCheckingDrive = false;
      notifyListeners();
    }
  }

  /// Inner work for [_checkDriveManifestExists] — separated so the timeout
  /// wrapper above stays readable.
  Future<void> _doCheckDriveManifest() async {
    final client = await _getAuthenticatedClient();
    final api = drive.DriveApi(client);

    final rootList = await _retry(
          () => api.files.list(
        q: "name = '$kDriveRootName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false",
        $fields: 'files(id)',
        pageSize: 1,
      ),
      name: 'checkRootFolder',
    );

    if (rootList.files?.isEmpty ?? true) {
      _driveAccountState = DriveAccountState.newUser;
      _setStatus('No backup found. Upload to create first backup.',
          persistent: true);
      return;
    }

    final rootId = rootList.files!.first.id!;
    _syncState.rootFolderId = rootId;

    // ── Fetch salt from Drive and supply to EncryptionService ────────────────
    // This must happen before the user enters their password so the same salt
    // is used on every platform. If no salt exists on Drive yet, this is a
    // no-op and a new salt will be generated when the password is submitted.
    //
    // The fetched salt string is returned so _fetchAndReDeriveKey can reuse it
    // directly — avoiding a second Drive round-trip to download the same file.
    final driveSaltBase64 = await _fetchAndSupplyDriveSalt(api, rootId);

    // ── Re-derive encryption key if salt mismatch detected (reinstall fix) ───
    // After a reinstall, the user's first unlock generates a *new* temporary
    // local salt. When Drive sign-in happens subsequently we have the *real*
    // (original) salt.  _fetchAndReDeriveKey checks whether the current key
    // matches the Drive salt and, if not, silently re-derives the correct key
    // so all existing notes can be decrypted.
    //
    // We pass the already-fetched salt in so the method can skip its own
    // salt.bin download (null means no salt exists on Drive — skip rederive).
    await _fetchAndReDeriveKey(api, rootId, knownDriveSaltBase64: driveSaltBase64);

    final manifestList = await _retry(
          () => api.files.list(
        q: "name = '$kManifestName' and '$rootId' in parents and trashed = false",
        $fields: 'files(id)',
        pageSize: 1,
      ),
      name: 'checkManifest',
    );

    if (manifestList.files?.isNotEmpty ?? false) {
      _syncState.manifestFileId = manifestList.files!.first.id;
      _persistSyncState();
      _driveAccountState = DriveAccountState.returningUser;
      _setStatus('Existing backup found. Sync to merge notes from cloud.',
          persistent: true);
    } else {
      _persistSyncState();
      _driveAccountState = DriveAccountState.newUser;
      _setStatus('No backup found. Upload to create first backup.',
          persistent: true);
    }
  }

  /// Fetches salt.bin from the Drive root folder, supplies it to
  /// EncryptionService, and returns the raw base64 salt string so the caller
  /// can pass it directly to [_fetchAndReDeriveKey] — avoiding a second
  /// Drive round-trip to download the same file.
  ///
  /// Returns `null` if salt.bin does not exist on Drive yet (first ever use)
  /// or if the fetch fails (non-fatal).
  Future<String?> _fetchAndSupplyDriveSalt(
      drive.DriveApi api, String rootFolderId) async {
    try {
      final list = await _retry(
            () => api.files.list(
          q: "name = '$kSaltFileName' and '$rootFolderId' in parents and trashed = false",
          $fields: 'files(id)',
          pageSize: 1,
        ),
        name: 'findSalt',
      );

      if (list.files?.isEmpty ?? true) {
        debugPrint('[Salt] No salt.bin on Drive — first use or pre-salt backup.');
        return null;
      }

      final fileId = list.files!.first.id!;
      final response = await _retry(
            () => api.files.get(fileId,
            downloadOptions: drive.DownloadOptions.fullMedia),
        name: 'fetchSalt',
      );
      if (response is! drive.Media) return null;

      final bytes = await response.stream.expand((c) => c).toList();
      final saltBase64 = utf8.decode(bytes);
      await EncryptionService.instance.supplyDriveSalt(saltBase64);
      debugPrint('[Salt] Salt fetched from Drive and supplied to EncryptionService.');
      return saltBase64;
    } catch (e) {
      // Non-fatal — if we cannot fetch the salt the user's local cached salt
      // (if any) will be used. Worst case they see the unreadable placeholder.
      debugPrint('[Salt] Could not fetch salt from Drive: $e');
      return null;
    }
  }

  // ── Key re-derivation after reinstall ────────────────────────────────────────────

  /// Checks whether the currently-loaded encryption key was derived from the
  /// Drive salt. If not (i.e. the user reinstalled and a new temporary salt
  /// was generated locally), re-derives the correct key using the Drive salt
  /// so all existing notes become readable again.
  ///
  /// [knownDriveSaltBase64] — when called from [_doCheckDriveManifest], pass
  /// the salt string already fetched by [_fetchAndSupplyDriveSalt] to avoid a
  /// second Drive round-trip for the same file. Pass `null` (or omit) only
  /// when calling standalone — the method will fetch salt.bin itself in that case.
  ///
  /// Flow:
  ///   1. Resolve the Drive salt (from parameter or a fresh fetch).
  ///   2. If the local salt already equals the Drive salt, the key is correct —
  ///      return immediately without touching anything (normal returning user).
  ///   3. Retrieve the master password stored by [AppLockGate] after unlock.
  ///   4. Call [EncryptionService.verifyKey] with the Drive-origin test cipher
  ///      as the oracle — this is the only ciphertext that was encrypted with
  ///      the original key, so it correctly validates the original password.
  ///   5. If valid, call [rederiveKeyWithNewSalt] to swap in the Drive salt.
  ///   6. If verification fails (password changed between installs), show the
  ///      mismatch dialog, verify the user-supplied password against test.bin,
  ///      then call [rederiveKeyWithNewSalt] with the verified password.
  ///   7. After successful re-derivation, rebuild the search index and notify
  ///      listeners so the note list refreshes immediately.
  Future<void> _fetchAndReDeriveKey(
      drive.DriveApi api, String rootFolderId,
      {String? knownDriveSaltBase64}) async {
    // Only attempt re-derivation if the encryption service has a ready key.
    // If the key isn't ready yet the user hasn't passed AppLockGate — skip.
    if (!EncryptionService.instance.keyReady.value) {
      debugPrint('[RederiveKey] Encryption key not ready yet — skipping.');
      return;
    }

    try {
      // ── Step 1: resolve the Drive salt ────────────────────────────────────────────────
      // Prefer the value already fetched by _fetchAndSupplyDriveSalt (passed
      // in via knownDriveSaltBase64) to avoid a duplicate Drive round-trip.
      // Fall back to fetching salt.bin ourselves only when called standalone.
      final String driveSaltBase64;
      if (knownDriveSaltBase64 != null) {
        driveSaltBase64 = knownDriveSaltBase64;
        debugPrint(
            '[RederiveKey] Using salt passed from _doCheckDriveManifest (no extra round-trip).');
      } else {
        final fetched = await _fetchAndSupplyDriveSalt(api, rootFolderId);
        if (fetched == null) {
          debugPrint('[RederiveKey] No salt.bin on Drive — nothing to re-derive.');
          return;
        }
        driveSaltBase64 = fetched;
      }

      // ── Step 2: short-circuit if local salt already matches Drive ────────────
      // Normal returning users (no reinstall) reach this branch. Their local
      // salt equals the Drive salt, so the key is already correct — skip the
      // expensive PBKDF2 re-derivation entirely.
      final localSalt = await EncryptionService.instance.exportSalt();
      if (localSalt == driveSaltBase64) {
        debugPrint(
            '[RederiveKey] Local salt already matches Drive — no re-derivation needed.');
        return;
      }

      debugPrint(
          '[RederiveKey] Salt mismatch detected (reinstall). Fetching Drive test oracle…');


      // ── Step 3: fetch test.bin from Drive (the verification oracle) ────────
      // test.bin contains the AES-GCM ciphertext that was written when the key
      // was first set up. It was encrypted with the *original* salt, making it
      // the only reliable oracle for verifyKey after a reinstall — the local
      // _kKeyTestAlias was overwritten with the new temporary key on first unlock.
      String? driveTestCipher;
      try {
        final testList = await _retry(
              () => api.files.list(
            q: "name = '$kTestFileName' and '$rootFolderId' in parents and trashed = false",
            $fields: 'files(id)',
            pageSize: 1,
          ),
          name: 'rederive:findTest',
        );

        if (testList.files?.isNotEmpty ?? false) {
          final testFileId = testList.files!.first.id!;
          final testResponse = await _retry(
                () => api.files.get(testFileId,
                downloadOptions: drive.DownloadOptions.fullMedia),
            name: 'rederive:fetchTest',
          );
          if (testResponse is drive.Media) {
            final testBytes =
            await testResponse.stream.expand((c) => c).toList();
            driveTestCipher = utf8.decode(testBytes);
          }
        }
      } catch (e) {
        // Non-fatal: if test.bin is missing (pre-existing backup before this
        // feature was added) we proceed to the password dialog directly.
        debugPrint('[RederiveKey] Could not fetch test.bin: $e');
      }

      if (driveTestCipher == null) {
        // test.bin doesn't exist on Drive yet (backup created before this
        // feature). Fall through to the password dialog — the user will verify
        // manually, and test.bin will be created on next uploadSaltToDrive().
        debugPrint(
            '[RederiveKey] No test.bin on Drive — skipping auto-verify, showing dialog.');
        final enteredPassword =
        await _showPasswordMismatchDialog(driveSaltBase64, null);
        if (enteredPassword == null) {
          debugPrint('[RederiveKey] User cancelled password re-entry.');
          return;
        }
        await _applyRederivation(enteredPassword, driveSaltBase64);
        return;
      }

      // ── Step 4: retrieve the master password stored after last unlock ──────
      final storedPassword = await _getStoredMasterPassword();

      if (storedPassword == null) {
        debugPrint('[RederiveKey] No stored password — cannot auto-verify Drive salt.');
        final enteredPassword =
        await _showPasswordMismatchDialog(driveSaltBase64, driveTestCipher);
        if (enteredPassword == null) {
          debugPrint('[RederiveKey] User cancelled password re-entry.');
          return;
        }
        await _applyRederivation(enteredPassword, driveSaltBase64);
        return;
      }

      // ── Step 5: verify stored password against the Drive-origin oracle ──────
      // We pass driveTestCipher here — NOT the local _kKeyTestAlias.
      // The local value was encrypted with the new temporary salt and is
      // therefore the wrong oracle for validating the original password.
      final isValid = await EncryptionService.instance
          .verifyKey(storedPassword, driveSaltBase64, driveTestCipher);

      if (isValid) {
        debugPrint(
            '[RederiveKey] Stored password matches Drive salt — re-deriving key.');
        await _applyRederivation(storedPassword, driveSaltBase64);
        return;
      }

      // ── Step 6: stored password doesn't match — prompt for original ────────
      // This can happen if the user changed their password between installs, or
      // if the stored password was somehow corrupted.
      debugPrint(
          '[RederiveKey] Stored password does not match Drive salt. Showing dialog.');
      final enteredPassword =
      await _showPasswordMismatchDialog(driveSaltBase64, driveTestCipher);

      if (enteredPassword == null) {
        debugPrint('[RederiveKey] User cancelled password re-entry.');
        return;
      }
      await _applyRederivation(enteredPassword, driveSaltBase64);
    } catch (e) {
      // Non-fatal — if re-derivation fails, notes show the unreadable
      // placeholder but the app continues to function.
      debugPrint('[RederiveKey] Re-derivation failed (non-fatal): $e');
    }
  }

  /// Calls [EncryptionService.rederiveKeyWithNewSalt], persists the verified
  /// password for future sessions, and refreshes the note list.
  ///
  /// Extracted from [_fetchAndReDeriveKey] so every success path
  /// (auto-verify, manual dialog) goes through the same post-derivation steps.
  Future<void> _applyRederivation(
      String password, String driveSaltBase64) async {
    await EncryptionService.instance
        .rederiveKeyWithNewSalt(password, driveSaltBase64);

    // Persist the verified password so future sessions can auto-verify.
    const secureStorage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );
    await secureStorage.write(
        key: kMasterPasswordForRederiveKey, value: password);

    _encryptionReady = true;
    _rebuildSearchIndex();
    notifyListeners();
    debugPrint('[RederiveKey] Key re-derived and notes refreshed.');
  }

  /// Returns the master password stored by [AppLockGate] after a successful
  /// unlock, or `null` if none has been stored yet.
  Future<String?> _getStoredMasterPassword() async {
    try {
      return await getStoredMasterPassword();
    } catch (e) {
      debugPrint('[RederiveKey] Could not read stored master password: $e');
      return null;
    }
  }

  /// Shows a modal dialog prompting the user to enter their *original* master
  /// password (the one they used before reinstalling the app).
  ///
  /// [driveTestCipher] is the ciphertext fetched from Drive's test.bin and is
  /// passed directly to [EncryptionService.verifyKey] as the oracle.  Pass
  /// `null` only when test.bin does not exist on Drive yet (pre-existing backup
  /// from before this feature was added) — in that case verification is skipped
  /// and the entered password is returned unverified, which is safe because the
  /// subsequent [rederiveKeyWithNewSalt] call will fail if the key is wrong.
  ///
  /// Returns the verified password string, or `null` if the user cancels.
  Future<String?> _showPasswordMismatchDialog(
      String driveSaltBase64, String? driveTestCipher) async {
    // navigatorKey / global context is unavailable in a provider; use the
    // last built context captured via BuildContext stored in a typical Flutter
    // setup. As a safe fallback we store a BuildContext reference.
    // NOTE: This method requires a valid widget context.  If _navigatorContext
    // is null (e.g. called before any widget has set it) we skip the dialog.
    final ctx = _navigatorContext;
    if (ctx == null || !ctx.mounted) {
      debugPrint('[RederiveKey] No context available for password dialog.');
      return null;
    }

    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    final accent = Theme.of(ctx).colorScheme.primary;
    final base = isDark ? const Color(0xFF1A1A1A) : const Color(0xFFFAF8F5);
    final subtle =
    isDark ? const Color(0xFF9E9E9E) : const Color(0xFF666666);
    final inputFill =
    isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF0F0F0);
    final primary =
    isDark ? const Color(0xFFE0E0E0) : const Color(0xFF1A1A1A);

    final controller = TextEditingController();
    String? errorText;
    bool obscure = true;
    bool isVerifying = false;

    // Shared verification logic — used by both onSubmitted and the button.
    // When driveTestCipher is null (pre-existing backup, no test.bin yet)
    // we skip cryptographic verification and return the password as-is; the
    // rederiveKeyWithNewSalt call will fail loudly if the password is wrong.
    Future<bool> verifyInput(String pwd, StateSetter setDialogState) async {
      if (driveTestCipher == null) return true;
      final valid = await EncryptionService.instance
          .verifyKey(pwd, driveSaltBase64, driveTestCipher);
      if (!valid) {
        setDialogState(() {
          errorText = 'Incorrect password — try again';
          isVerifying = false;
        });
      }
      return valid;
    }

    return showDialog<String>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (_, setDialogState) {
            return Dialog(
              backgroundColor: base,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              child: Container(
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: isDark
                          ? Colors.black.withAlpha(80)
                          : Colors.black.withAlpha(20),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Icon + title ────────────────────────────────────────
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: accent.withAlpha(25),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child:
                          Icon(Icons.key_rounded, size: 20, color: accent),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Original Password Required',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Your notes were encrypted with a different password. '
                          'Enter the password you used before reinstalling the app '
                          'to restore access.',
                      style: TextStyle(fontSize: 13, color: subtle),
                    ),
                    const SizedBox(height: 20),

                    // ── Password field ──────────────────────────────────────
                    TextField(
                      controller: controller,
                      obscureText: obscure,
                      autofocus: true,
                      keyboardType: TextInputType.text,
                      maxLength: 128,
                      onSubmitted: (_) async {
                        if (isVerifying) return;
                        final pwd = controller.text.trim();
                        if (pwd.isEmpty) {
                          setDialogState(
                                  () => errorText = 'Password cannot be empty');
                          return;
                        }
                        setDialogState(() {
                          isVerifying = true;
                          errorText = null;
                        });
                        final valid =
                        await verifyInput(pwd, setDialogState);
                        if (!dialogCtx.mounted) return;
                        if (valid) Navigator.of(dialogCtx).pop(pwd);
                      },
                      decoration: InputDecoration(
                        hintText: 'Original master password',
                        hintStyle: TextStyle(color: subtle.withAlpha(128)),
                        counterText: '',
                        filled: true,
                        fillColor: inputFill,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        errorText: errorText,
                        errorStyle:
                        const TextStyle(color: Colors.redAccent),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscure
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            size: 18,
                            color: subtle,
                          ),
                          onPressed: () =>
                              setDialogState(() => obscure = !obscure),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Action buttons ──────────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isVerifying
                                ? null
                                : () => Navigator.of(dialogCtx).pop(null),
                            style: OutlinedButton.styleFrom(
                              padding:
                              const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              side: BorderSide(
                                  color: subtle.withAlpha(80)),
                            ),
                            child: Text('Cancel',
                                style: TextStyle(color: subtle)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: isVerifying
                                ? null
                                : () async {
                              final pwd = controller.text.trim();
                              if (pwd.isEmpty) {
                                setDialogState(() => errorText =
                                'Password cannot be empty');
                                return;
                              }
                              setDialogState(() {
                                isVerifying = true;
                                errorText = null;
                              });
                              final valid =
                              await verifyInput(pwd, setDialogState);
                              if (!dialogCtx.mounted) return;
                              if (valid) Navigator.of(dialogCtx).pop(pwd);
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: accent,
                              padding:
                              const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: isVerifying
                                ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white.withAlpha(200),
                              ),
                            )
                                : const Text('Verify'),
                          ),
                        ),
                      ],
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

  // ── Navigator context (set by a widget listening to this provider) ──────────

  /// A BuildContext from the widget tree, used solely for showing the
  /// [_showPasswordMismatchDialog].  Set this from a top-level widget via
  /// [setNavigatorContext] after the widget is mounted.
  BuildContext? _navigatorContext;

  /// Call this from the root widget (e.g. inside a [Builder] in MaterialApp's
  /// `builder` callback) to give NotesProvider a context it can use to show
  /// the password re-entry dialog.
  ///
  /// ```dart
  /// // In MaterialApp builder:
  /// builder: (context, child) {
  ///   Provider.of<NotesProvider>(context, listen: false)
  ///       .setNavigatorContext(context);
  ///   return child!;
  /// },
  /// ```
  void setNavigatorContext(BuildContext context) {
    _navigatorContext = context;
  }

  /// Uploads the PBKDF2 salt to Drive root as salt.bin, and the AES-GCM test
  /// ciphertext as test.bin.
  ///
  /// Both files are written together so [verifyKey] always has a Drive-origin
  /// oracle that was encrypted with the *same* key as the user's notes.  After
  /// a reinstall the local test value is useless (it was written with a new
  /// temporary salt), so test.bin is the only reliable verification oracle.
  ///
  /// Called once after first-ever password setup (saltIsNew == true) and also
  /// after key rotation so all platforms stay in sync.
  Future<void> uploadSaltToDrive() async {
    if (_currentUser == null) return;
    try {
      final client = await _getAuthenticatedClient();
      final api = drive.DriveApi(client);
      await _ensureFolders(api);

      final salt = await EncryptionService.instance.exportSalt();
      if (salt == null) return;
      final testCipher = await EncryptionService.instance.exportTestCipher();
      if (testCipher == null) return;

      await _upsertDriveFile(
        api,
        fileName: kSaltFileName,
        content: utf8.encode(salt),
        parentId: _syncState.rootFolderId!,
        logTag: 'Salt',
      );

      await _upsertDriveFile(
        api,
        fileName: kTestFileName,
        content: utf8.encode(testCipher),
        parentId: _syncState.rootFolderId!,
        logTag: 'TestCipher',
      );

      debugPrint('[Salt] salt.bin and test.bin uploaded to Drive.');
    } catch (e) {
      debugPrint('[Salt] Failed to upload salt/test to Drive: $e');
    }
  }

  /// Upserts a small binary file in a Drive folder (creates or updates).
  /// Extracted so [uploadSaltToDrive] can reuse the same pattern for both
  /// salt.bin and test.bin without duplicating the list→update/create logic.
  Future<void> _upsertDriveFile(
      drive.DriveApi api, {
        required String fileName,
        required List<int> content,
        required String parentId,
        required String logTag,
      }) async {
    final encoded = content;
    final media = drive.Media(
      Stream.value(encoded),
      encoded.length,
      contentType: 'text/plain',
    );

    final list = await _retry(
          () => api.files.list(
        q: "name = '$fileName' and '$parentId' in parents and trashed = false",
        $fields: 'files(id)',
        pageSize: 1,
      ),
      name: 'find:$logTag',
    );

    if (list.files?.isNotEmpty ?? false) {
      await _retry(
            () => api.files.update(drive.File(), list.files!.first.id!,
            uploadMedia: media),
        name: 'update:$logTag',
      );
    } else {
      final file = drive.File()
        ..name = fileName
        ..parents = [parentId];
      await _retry(
            () => api.files.create(file, uploadMedia: media),
        name: 'create:$logTag',
      );
    }
  }

  /// Public method that lets the Settings UI trigger a manual retry after a
  /// failed Drive check.
  Future<void> retryDriveCheck() async {
    if (_isCheckingDrive || _currentUser == null) return;
    _driveCheckFailed = false;
    await _checkDriveManifestExists();
  }

  @override
  void dispose() {
    _syncStatusTimer?.cancel();
    super.dispose();
  }

  void _rebuildSearchIndex() {
    if (_notesBox == null || _searchIndexBox == null || !_encryptionReady) return;
    _searchIndexBox!.clear();
    for (final note in _notesBox!.values.cast<Note>()) {
      _updateSearchIndex(note);
    }
  }

  // ── Search index ────────────────────────────────────────────────────────────

  void _updateSearchIndex(Note note) {
    if (_searchIndexBox == null) return;
    if (note.deleted) {
      _searchIndexBox!.delete(note.id);
      return;
    }

    final buffer = StringBuffer();

    // Core fields
    buffer
      ..write(note.title)
      ..write(' ')
      ..write(note.content)
      ..write(' ')
      ..write(note.category)
      ..write(' ');

    // Checklist items
    for (final item in note.checklistItems) {
      buffer
        ..write(item.text)
        ..write(' ');
    }

    // Itinerary items
    for (final item in note.itineraryItems) {
      buffer
        ..write(item.location)
        ..write(' ')
        ..write(item.date)
        ..write(' ')
        ..write(item.notes)
        ..write(' ');
    }

    // Meal plan items
    for (final item in note.mealPlanItems) {
      buffer
        ..write(item.day)
        ..write(' ');
      for (final meal in item.meals) {
        buffer
          ..write(meal['value'] ?? '')
          ..write(' ');
      }
    }

    // Recipe
    if (note.recipeData != null) {
      buffer
        ..write(note.recipeData!.ingredients)
        ..write(' ')
        ..write(note.recipeData!.instructions)
        ..write(' ')
        ..write(note.recipeData!.prepTime)
        ..write(' ')
        ..write(note.recipeData!.cookTime)
        ..write(' ');
    }

    _searchIndexBox!.put(note.id, buffer.toString().toLowerCase());
  }

  List<Note> search(String query) {
    if (_searchIndexBox == null || _notesBox == null) return notes;
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return notes;
    return _searchIndexBox!.keys
        .where((k) => (_searchIndexBox!.get(k) ?? '').contains(q))
        .map((k) => _notesBox!.get(k))
        .whereType<Note>()
        .where((n) => !n.deleted)
        .toList()
      ..sort((a, b) => a.pinned != b.pinned
          ? (a.pinned ? -1 : 1)
          : b.updatedAt.compareTo(a.updatedAt));
  }

  // ── CRUD with encryption ────────────────────────────────────────────────────

  Future<void> addNote(
      String title,
      String content, {
        String category = 'General',
        NoteType noteType = NoteType.normal,
        ColorTheme colorTheme = ColorTheme.default_,
      }) async {
    if (_notesBox == null) return;
    if (title.isEmpty && content.isEmpty) return;

    // Encrypt content for normal and drawing notes on all platforms.
    // Web now derives the same key as mobile (salt fetched from Drive),
    // so encryption is safe and cross-platform.
    final encryptedContent = (noteType == NoteType.normal || noteType == NoteType.drawing)
        ? EncryptionService.instance.encrypt(content)
        : content;

    final note = Note(
      id: const Uuid().v4(),
      title: title.trim(),
      content: encryptedContent,
      updatedAt: DateTime.now(),
      category: category,
      noteType: noteType,
      colorTheme: colorTheme,
    );

    await _notesBox!.put(note.id, note);
    _updateSearchIndex(note);
    _syncState.markNoteDirty(note.id);
    _persistSyncState();
    notifyListeners();
  }

  Future<void> updateNote(Note note) async {
    if (_notesBox == null) return;

    // Encrypt content before saving (all platforms — same key via Drive salt).
    if (note.noteType == NoteType.normal || note.noteType == NoteType.drawing) {
      note.content = EncryptionService.instance.encrypt(note.content);
    }

    note.updatedAt = DateTime.now();
    await _notesBox!.put(note.id, note);
    _updateSearchIndex(note);
    _syncState.markNoteDirty(note.id);
    for (final imgId in note.imageIds) {
      final imgSync = _syncState.images[imgId];
      if (imgSync == null || !imgSync.existsOnDrive) {
        _syncState.markImageDirty(imgId);
      }
    }
    _persistSyncState();
    notifyListeners();
  }

  // Helper to get decrypted note content for display.
  // NEVER throws — returns a safe placeholder if the note cannot be decrypted
  // (e.g. wrong key after reinstall). This prevents a single bad note from
  // crashing the list widget tree.
  String getDecryptedContent(Note note) {
    if (!_encryptionReady) {
      debugPrint('[NotesProvider] getDecryptedContent called before encryption ready');
      return '';
    }

    if (note.noteType == NoteType.normal || note.noteType == NoteType.drawing) {
      final result = EncryptionService.instance.safeDecrypt(note.content);
      if (result == null) {
        debugPrint('[NotesProvider] Could not decrypt note ${note.id} — key mismatch');
        return kUndecryptablePlaceholder;
      }
      return result;
    }
    return note.content;
  }

  /// Sentinel value shown on note cards when a note cannot be decrypted.
  /// The note still exists in Hive — it just can't be read with the current key.
  static const String kUndecryptablePlaceholder =
      '⚠️ This note was encrypted with a different key and cannot be read. '
      'Restore the original device backup or re-enter the original password to recover it.';

  Future<void> softDelete(String id) async {
    final note = _notesBox?.get(id) as Note?;
    if (note != null) {
      note.deleted = true;
      note.updatedAt = DateTime.now();
      await _notesBox!.put(id, note);
      _updateSearchIndex(note);
      _syncState.markNoteDirty(id);
      _persistSyncState();
      notifyListeners();
    }
  }

  Future<void> restore(String id) async {
    final note = _notesBox?.get(id) as Note?;
    if (note != null) {
      note.deleted = false;
      note.updatedAt = DateTime.now();
      await _notesBox!.put(id, note);
      _updateSearchIndex(note);
      _syncState.markNoteDirty(id);
      _persistSyncState();
      notifyListeners();
    }
  }

  Future<void> hardDelete(String id) async {
    if (_notesBox == null) return;
    final note = _notesBox!.get(id) as Note?;
    if (note != null) {
      final allImageRefs = <String>{};
      for (final n in _notesBox!.values.cast<Note>()) {
        if (n.id != id && !n.deleted) allImageRefs.addAll(n.imageIds);
      }
      for (final imgId in note.imageIds) {
        if (!allImageRefs.contains(imgId)) {
          await deleteImage(imgId);
        }
      }
    }
    await _notesBox!.delete(id);
    _searchIndexBox?.delete(id);
    if (_syncState.notes[id] != null) {
      _syncState.notes[id] =
          _syncState.notes[id]!.copyWith(pendingUpload: true);
    }
    _persistSyncState();
    notifyListeners();
  }

  // ── Images ──────────────────────────────────────────────────────────────────

  Future<String> saveImage(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final imageId = const Uuid().v4();
    await _imagesBox?.put(imageId, _encodeImage(Uint8List.fromList(bytes)));
    _syncState.markImageDirty(imageId);
    _persistSyncState();
    return imageId;
  }

  String? getImage(String imageId) {
    final encoded = _imagesBox?.get(imageId);
    if (encoded == null) return null;
    return base64Encode(_decodeImage(encoded));
  }

  Future<void> deleteImage(String imageId) async {
    await _imagesBox?.delete(imageId);
    _syncState.images.remove(imageId);
    _persistSyncState();
  }

  // ── Auth ────────────────────────────────────────────────────────────────────

  /// Returns a human-readable message for common sign-in failures.
  String _friendlyAuthError(Object e) {
    final raw = e.toString();
    if (raw.contains('appClientId') ||
        raw.contains('clientId') ||
        raw.contains('CLIENT_ID')) {
      return 'Google Sign-In is not configured for this platform. '
          'Please add your Web Client ID to the app.';
    }
    if (raw.contains('network_error') ||
        raw.contains('SocketException') ||
        raw.contains('NetworkException')) {
      return 'No internet connection. Please check your network and try again.';
    }
    if (raw.contains('sign_in_canceled') ||
        raw.contains('PlatformException(sign_in_canceled')) {
      return 'Sign-in was cancelled.';
    }
    if (raw.contains('sign_in_failed') ||
        raw.contains('PlatformException(sign_in_failed')) {
      return 'Sign-in failed. Please try again.';
    }
    if (raw.contains('access_denied') || raw.contains('ApiException: 10')) {
      return 'Access denied. Make sure the app is authorised in your Google account.';
    }
    if (raw.contains('popup_closed') || raw.contains('popup_blocked')) {
      return 'The sign-in popup was closed or blocked. Please allow popups and try again.';
    }
    // FedCM / browser third-party sign-in blocked (common in Chrome when
    // "Block third-party sign-in" is enabled, or when FedCM rejects the request).
    if (raw.contains('FedCM') ||
        raw.contains('NetworkError') ||
        raw.contains('Error retrieving a token')) {
      return 'Sign-in was blocked by your browser. '
          'Check that third-party sign-in is allowed in your browser settings, '
          'then try again.';
    }
    // ClientException is thrown by the web HTTP client when the OAuth flow is
    // interrupted or returns an unexpected response — the raw message is a
    // JSON fragment and is not user-friendly.
    if (raw.contains('ClientException') ||
        raw.startsWith('{') ||
        raw.startsWith('Exception: {')) {
      return 'Sign-in could not be completed. '
          'Please try again, or sign out and back in if the problem persists.';
    }
    // Fallback: show only the first sentence of the exception, not the full stack.
    final firstLine = raw.split('\n').first.trim();
    return firstLine.length > 120
        ? '${firstLine.substring(0, 120)}…'
        : firstLine;
  }

  Future<void> signIn() async {
    try {
      _currentUser = await _googleSignIn.signIn();
      notifyListeners();
    } catch (e, st) {
      _setStatus(_friendlyAuthError(e), isError: true);
      if (!kIsWeb) {
        FirebaseCrashlytics.instance
            .recordError(e, st, reason: 'sign-in failed', fatal: false);
      }
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      _currentUser = null;
      _driveAccountState = DriveAccountState.unknown;
      notifyListeners();
    } catch (e) {
      debugPrint('Sign out error: $e');
    }
  }

  // ── Conflict resolution ─────────────────────────────────────────────────────

  Future<void> resolveConflictKeepLocal(String noteId) async {
    final ns = _syncState.notes[noteId];
    if (ns == null) return;
    _syncState.notes[noteId] =
        ns.copyWith(clearConflict: true, pendingUpload: true);
    _persistSyncState();
    notifyListeners();
  }

  Future<void> resolveConflictKeepRemote(String noteId) async {
    final ns = _syncState.notes[noteId];
    if (ns?.conflict == null) return;
    final remote = ns!.conflict!.remoteVersion;
    await _notesBox?.put(noteId, remote);
    _updateSearchIndex(remote);
    _syncState.notes[noteId] = ns.copyWith(
      clearConflict: true,
      pendingUpload: false,
      remoteVersion: remote.updatedAt,
      lastSyncedAt: DateTime.now(),
    );
    _persistSyncState();
    notifyListeners();
  }

  Future<void> resolveConflictKeepBoth(String noteId) async {
    final ns = _syncState.notes[noteId];
    if (ns?.conflict == null) return;
    final remote = ns!.conflict!.remoteVersion;
    final duplicate = remote.copyWith(
      id: const Uuid().v4(),
      title: '${remote.title} (Conflict copy)',
    );
    await _notesBox?.put(duplicate.id, duplicate);
    _updateSearchIndex(duplicate);
    _syncState.markNoteDirty(duplicate.id);
    _syncState.notes[noteId] = ns.copyWith(clearConflict: true);
    _persistSyncState();
    notifyListeners();
  }

  // ── Status helpers ──────────────────────────────────────────────────────────

  void _setStatus(String? msg,
      {bool isError = false, bool isSyncing = false, bool persistent = false}) {
    _syncStatusTimer?.cancel();
    _syncStatusMessage = msg;
    _syncStatus = msg == null
        ? SyncStatus.idle
        : (isError
        ? SyncStatus.error
        : (isSyncing ? SyncStatus.syncing : SyncStatus.idle));
    notifyListeners();

    if (msg != null && !isSyncing && !persistent) {
      _syncStatusTimer = Timer(const Duration(seconds: 4), () {
        _syncStatusMessage = null;
        _syncStatus = SyncStatus.idle;
        notifyListeners();
      });
    }
  }

  // ── Authenticated client with retry ─────────────────────────────────────────

  /// Obtains a valid authenticated HTTP client, retrying up to [_kAuthMaxRetries]
  /// times with [_kAuthRetryDelay] between attempts.
  ///
  /// We deliberately do **not** call `signInSilently(reAuthenticate: true)`
  /// here for either platform:
  /// - On **web** it triggers the deprecated popup OAuth flow, causing
  ///   Cross-Origin-Opener-Policy `window.closed` errors, a 403 on the
  ///   People API, and Google's "Auto re-authn" 10-minute rate-limit warning.
  /// - On **native** the `signInSilently()` call in `init()` already ensures
  ///   the token is fresh before any Drive operation is attempted, so a second
  ///   re-auth here is redundant.
  ///
  /// If no client is returned after all retries the user's session has truly
  /// expired and they must sign in again interactively.
  ///
  /// Throws an [Exception] if no valid client is obtained after all retries.
  static const int _kAuthMaxRetries = 5;
  static const Duration _kAuthRetryDelay = Duration(seconds: 2);

  Future<dynamic> _getAuthenticatedClient() async {
    for (int attempt = 1; attempt <= _kAuthMaxRetries; attempt++) {
      try {
        final client = await _googleSignIn.authenticatedClient();
        if (client != null) {
          debugPrint('[Auth] Got authenticated client on attempt $attempt');
          return client;
        }
        debugPrint(
            '[Auth] authenticatedClient() returned null on attempt $attempt');
      } catch (e) {
        debugPrint(
            '[Auth] authenticatedClient() threw on attempt $attempt: $e');
      }

      if (attempt < _kAuthMaxRetries) {
        debugPrint('[Auth] Retrying in ${_kAuthRetryDelay.inSeconds}s '
            '(attempt $attempt/$_kAuthMaxRetries)…');
        await Future.delayed(_kAuthRetryDelay);
      }
    }

    throw Exception(
        'Authentication failed: could not obtain an authenticated client '
            'after $_kAuthMaxRetries attempts. '
            'Please sign out and sign in again.');
  }

  // ── Retry logic ─────────────────────────────────────────────────────────────

  Future<T> _retry<T>(Future<T> Function() op,
      {String? name, int maxRetries = kMaxRetries}) async {
    for (int attempt = 0;; attempt++) {
      try {
        return await op();
      } catch (e) {
        if (attempt >= maxRetries) {
          debugPrint('[$name] failed after $maxRetries retries: $e');
          rethrow;
        }
        final ms = (kInitialBackoffMs * pow(kBackoffMultiplier, attempt))
            .toInt()
            .clamp(kInitialBackoffMs, kMaxBackoffMs);
        debugPrint(
            '[$name] retry ${attempt + 1}/$maxRetries after ${ms}ms: $e');
        await Future.delayed(Duration(milliseconds: ms));
      }
    }
  }

  // ── Sync state persistence ──────────────────────────────────────────────────

  void _loadSyncState() {
    final raw = _syncStateBox?.get('state');
    if (raw != null) {
      try {
        _syncState = SyncState.fromJson(
            raw is Map ? Map<String, dynamic>.from(raw) : {});
      } catch (e) {
        debugPrint('Failed to load sync state: $e');
        _syncState = SyncState();
      }
    }
  }

  void _persistSyncState() => _syncStateBox?.put('state', _syncState.toJson());

  // ── Image encoding ──────────────────────────────────────────────────────────

  String _encodeImage(Uint8List bytes) => jsonEncode(bytes);

  Uint8List _decodeImage(String encoded) {
    final list = jsonDecode(encoded) as List;
    return Uint8List.fromList(list.cast<int>());
  }

  // ── Drive folder management ─────────────────────────────────────────────────

  Future<void> _ensureFolders(drive.DriveApi api) async {
    _syncState.rootFolderId ??=
    await _findOrCreateFolder(api, kDriveRootName, parentId: null);
    _syncState.notesFolderId ??= await _findOrCreateFolder(api, kDriveNotesDir,
        parentId: _syncState.rootFolderId!);
    _syncState.imagesFolderId ??= await _findOrCreateFolder(
        api, kDriveImagesDir,
        parentId: _syncState.rootFolderId!);
    _persistSyncState();
  }

  Future<String> _findOrCreateFolder(drive.DriveApi api, String name,
      {required String? parentId}) async {
    final parentClause = parentId != null ? " and '$parentId' in parents" : '';
    final list = await _retry(
          () => api.files.list(
        q: "name = '$name' and mimeType = 'application/vnd.google-apps.folder' and trashed = false$parentClause",
        $fields: 'files(id)',
        pageSize: 1,
      ),
      name: 'findFolder:$name',
    );
    if (list.files?.isNotEmpty ?? false) return list.files!.first.id!;

    final meta = drive.File()
      ..name = name
      ..mimeType = 'application/vnd.google-apps.folder'
      ..parents = parentId != null ? [parentId] : null;
    final created =
    await _retry(() => api.files.create(meta), name: 'createFolder:$name');
    return created.id!;
  }

  // ── Manifest ────────────────────────────────────────────────────────────────

  Future<DriveManifest> _fetchManifest(drive.DriveApi api) async {
    if (_syncState.manifestFileId == null) {
      final list = await _retry(
            () => api.files.list(
          q: "name = '$kManifestName' and '${_syncState.rootFolderId}' in parents and trashed = false",
          $fields: 'files(id)',
          pageSize: 1,
        ),
        name: 'findManifest',
      );
      if (list.files?.isEmpty ?? true) {
        return DriveManifest.empty();
      }
      _syncState.manifestFileId = list.files!.first.id;
      _persistSyncState();
    }

    try {
      final response = await _retry(
            () => api.files.get(_syncState.manifestFileId!,
            downloadOptions: drive.DownloadOptions.fullMedia),
        name: 'fetchManifest',
      );
      if (response is! drive.Media) return DriveManifest.empty();
      final bytes = await response.stream.expand((c) => c).toList();
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      return DriveManifest.fromJson(json);
    } catch (e) {
      debugPrint('Could not fetch manifest: $e');
      return DriveManifest.empty();
    }
  }

  Future<void> _deleteOrphanedImagesFromDrive(drive.DriveApi api) async {
    final referencedImages = <String>{};
    if (_notesBox != null) {
      for (final note in _notesBox!.values.cast<Note>()) {
        if (!note.deleted) referencedImages.addAll(note.imageIds);
      }
    }

    for (final entry in _syncState.images.entries) {
      if (!referencedImages.contains(entry.key) && entry.value.existsOnDrive) {
        try {
          await _retry(
                () => api.files.delete(entry.value.driveFileId!),
            name: 'deleteOrphanedImage:${entry.key}',
          );
          _syncState.images.remove(entry.key);
          debugPrint('Deleted orphaned image ${entry.key} from Drive');
        } catch (e) {
          debugPrint('Failed to delete orphaned image ${entry.key}: $e');
        }
      }
    }
  }

  Future<void> _pushManifest(drive.DriveApi api) async {
    final allNotes = _notesBox?.values.cast<Note>().toList() ?? [];
    final noteMetadata = <String, Map<String, dynamic>>{};
    for (final n in allNotes) {
      noteMetadata[n.id] = {
        'updatedAt': n.updatedAt.toIso8601String(),
        'deleted': n.deleted,
      };
    }

    final allImageIds = _syncState.images.entries
        .where((e) => e.value.existsOnDrive)
        .map((e) => e.key)
        .toSet();

    final manifest = DriveManifest(
      generatedAt: DateTime.now(),
      noteMetadata: noteMetadata,
      imageIds: allImageIds,
    );

    final encoded = utf8.encode(jsonEncode(manifest.toJson()));
    final media = drive.Media(Stream.value(encoded), encoded.length,
        contentType: 'application/json');

    if (_syncState.manifestFileId != null) {
      await _retry(
            () => api.files.update(drive.File(), _syncState.manifestFileId!,
            uploadMedia: media),
        name: 'updateManifest',
      );
    } else {
      final file = drive.File()
        ..name = kManifestName
        ..parents = [_syncState.rootFolderId!];
      final created = await _retry(
              () => api.files.create(file, uploadMedia: media),
          name: 'createManifest');
      _syncState.manifestFileId = created.id;
      _persistSyncState();
    }
  }

  // ── Upload ──────────────────────────────────────────────────────────────────

  Future<void> uploadNotes() async {
    if (_currentUser == null || _notesBox == null) {
      _setStatus('Login required', isError: true);
      return;
    }
    if (isSyncing) return;

    _setStatus('Uploading…', isSyncing: true);

    try {
      final client = await _getAuthenticatedClient();
      final api = drive.DriveApi(client);
      await _ensureFolders(api);

      // Ensure salt.bin and test.bin are present on Drive (idempotent upsert).
      // This covers the case where the user set a password before ever signing
      // into Drive, so the onEncryptionReady() call in saltIsNew was a no-op
      // (no Drive session existed yet). After this point every upload guarantees
      // both files are in the Drive root folder and in sync with the local key.
      await uploadSaltToDrive();

      final dirtyNoteIds = _syncState.pendingNoteUploads;
      final dirtyImageIds = _syncState.pendingImageUploads;

      if (dirtyNoteIds.isEmpty && dirtyImageIds.isEmpty) {
        _setStatus('Nothing to upload');
        return;
      }

      for (final noteId in dirtyNoteIds) {
        final note = _notesBox!.get(noteId) as Note?;
        if (note == null) continue;
        await _uploadImagesForNote(api, note);
        await _uploadNote(api, note);
      }

      final notesWithImages = <String>{};
      if (_notesBox != null) {
        for (final note in _notesBox!.values.cast<Note>()) {
          if (!note.deleted) notesWithImages.addAll(note.imageIds);
        }
      }

      for (final imageId in dirtyImageIds) {
        if (!notesWithImages.contains(imageId)) {
          await _uploadImage(api, imageId);
        }
      }

      await _deleteOrphanedImagesFromDrive(api);
      await _pushManifest(api);

      _syncState.lastSyncCompletedAt = DateTime.now();
      _syncState.accountEmail = _currentUser?.email;
      _persistSyncState();

      _driveAccountState = DriveAccountState.returningUser;

      _setStatus('Upload complete ✓');
      notifyListeners();
    } catch (e, st) {
      _setStatus('Upload failed: $e', isError: true);
      debugPrint('Upload error: $e');
      if (!kIsWeb) {
        FirebaseCrashlytics.instance
            .recordError(e, st, reason: 'Drive upload failed');
      }
    } finally {
      if (_syncStatus == SyncStatus.syncing) {
        _syncStatus = SyncStatus.idle;
        notifyListeners();
      }
    }
  }

  Future<void> _uploadImage(drive.DriveApi api, String imageId) async {
    final imgSync = _syncState.images[imageId];
    if (imgSync?.existsOnDrive == true && imgSync?.pendingUpload == false) {
      return;
    }

    final rawData = _imagesBox?.get(imageId);
    if (rawData == null) {
      debugPrint('Image $imageId missing locally, skipping upload');
      return;
    }

    final bytes = _decodeImage(rawData);
    final media = drive.Media(Stream.value(bytes), bytes.length,
        contentType: 'application/octet-stream');

    String? fileId = imgSync?.driveFileId;
    if (fileId != null) {
      await _retry(
            () => api.files.update(drive.File(), fileId!, uploadMedia: media),
        name: 'updateImage:$imageId',
      );
    } else {
      final file = drive.File()
        ..name = '$imageId.bin'
        ..parents = [_syncState.imagesFolderId!];
      final created = await _retry(
              () => api.files.create(file, uploadMedia: media),
          name: 'createImage:$imageId');
      fileId = created.id;
    }

    _syncState.images[imageId] = ImageSync(
      imageId: imageId,
      driveFileId: fileId,
      pendingUpload: false,
      existsOnDrive: true,
    );
    _persistSyncState();
  }

  Future<void> _uploadNote(drive.DriveApi api, Note note) async {
    final encoded = utf8.encode(jsonEncode(note.toJson()));
    final media = drive.Media(Stream.value(encoded), encoded.length,
        contentType: 'application/json');

    final ns = _syncState.notes[note.id];
    String? fileId = ns?.driveFileId;

    if (fileId != null) {
      await _retry(
            () => api.files.update(drive.File(), fileId!, uploadMedia: media),
        name: 'updateNote:${note.id}',
      );
    } else if (!note.deleted) {
      final file = drive.File()
        ..name = '${note.id}.json'
        ..parents = [_syncState.notesFolderId!];
      final created = await _retry(
              () => api.files.create(file, uploadMedia: media),
          name: 'createNote:${note.id}');
      fileId = created.id;
    }

    _syncState.notes[note.id] = NoteSync(
      noteId: note.id,
      driveFileId: fileId,
      lastSyncedAt: DateTime.now(),
      remoteVersion: note.updatedAt,
      pendingUpload: false,
    );
    _persistSyncState();
  }

  Future<void> _uploadImagesForNote(drive.DriveApi api, Note note) async {
    const maxConcurrent = 3;
    final imageIds = note.imageIds.toList();

    for (int i = 0; i < imageIds.length; i += maxConcurrent) {
      final batch =
      imageIds.sublist(i, min(i + maxConcurrent, imageIds.length));
      await Future.wait(
        batch.map((imgId) async {
          final imgSync = _syncState.images[imgId];
          if (imgSync?.existsOnDrive == true &&
              imgSync?.pendingUpload == false) {
            return;
          }

          final rawData = _imagesBox?.get(imgId);
          if (rawData == null) {
            debugPrint('Image $imgId missing locally, skipping upload');
            return;
          }

          final bytes = _decodeImage(rawData);
          final media = drive.Media(Stream.value(bytes), bytes.length,
              contentType: 'application/octet-stream');

          String? fileId = imgSync?.driveFileId;
          if (fileId != null) {
            await _retry(
                  () => api.files.update(drive.File(), fileId!, uploadMedia: media),
              name: 'updateImage:$imgId',
            );
          } else {
            final file = drive.File()
              ..name = '$imgId.bin'
              ..parents = [_syncState.imagesFolderId!];
            final created = await _retry(
                    () => api.files.create(file, uploadMedia: media),
                name: 'createImage:$imgId');
            fileId = created.id;
          }

          _syncState.images[imgId] = ImageSync(
            imageId: imgId,
            driveFileId: fileId,
            pendingUpload: false,
            existsOnDrive: true,
          );
        }),
      );
    }
    _persistSyncState();
  }

  // ── Download ────────────────────────────────────────────────────────────────

  Future<void> downloadNotes() async {
    if (_currentUser == null || _notesBox == null) {
      _setStatus('Login required', isError: true);
      return;
    }
    if (isSyncing) return;

    _setStatus('Checking for updates…', isSyncing: true);

    try {
      final client = await _getAuthenticatedClient();
      final api = drive.DriveApi(client);
      await _ensureFolders(api);

      final manifest = await _fetchManifest(api);
      final toDownload = _diffManifest(manifest);

      if (toDownload.isEmpty) {
        _setStatus('Already up to date ✓');
        return;
      }

      _setStatus('Downloading ${toDownload.length} note(s)…', isSyncing: true);
      for (final noteId in toDownload) {
        await _downloadNote(api, manifest, noteId);
      }

      await _reconcileDeletedNotes(manifest);
      await _downloadMissingImages(api, manifest);
      _rebuildSearchIndex();

      _syncState.lastSyncCompletedAt = DateTime.now();
      _syncState.accountEmail = _currentUser?.email;
      _persistSyncState();
      _setStatus('Download complete ✓');
      notifyListeners();
    } catch (e, st) {
      _setStatus('Download failed: $e', isError: true);
      debugPrint('Download error: $e');
      if (!kIsWeb) {
        FirebaseCrashlytics.instance
            .recordError(e, st, reason: 'Drive download failed');
      }
    } finally {
      if (_syncStatus == SyncStatus.syncing) {
        _syncStatus = SyncStatus.idle;
        notifyListeners();
      }
    }
  }

  List<String> _diffManifest(DriveManifest manifest) {
    final toDownload = <String>[];

    for (final entry in manifest.noteMetadata.entries) {
      final noteId = entry.key;
      final metadata = entry.value;
      final remoteTs = DateTime.tryParse(metadata['updatedAt'] ?? '');
      if (remoteTs == null) continue;

      final ns = _syncState.notes[noteId];
      final localNote = _notesBox!.get(noteId) as Note?;

      if (localNote == null) {
        toDownload.add(noteId);
      } else if (ns?.remoteVersion == null ||
          remoteTs.isAfter(ns!.remoteVersion!)) {
        toDownload.add(noteId);
      }
    }

    return toDownload;
  }

  Future<void> _downloadNote(
      drive.DriveApi api, DriveManifest manifest, String noteId) async {
    final metadata = manifest.noteMetadata[noteId];
    String? fileId = _syncState.notes[noteId]?.driveFileId;
    if (fileId == null) {
      final list = await _retry(
            () => api.files.list(
          q: "name = '$noteId.json' and '${_syncState.notesFolderId}' in parents and trashed = false",
          $fields: 'files(id)',
          pageSize: 1,
        ),
        name: 'findNote:$noteId',
      );
      if (list.files?.isEmpty ?? true) {
        debugPrint('Note $noteId not found on Drive');
        return;
      }
      fileId = list.files!.first.id!;
    }

    final response = await _retry(
          () => api.files
          .get(fileId!, downloadOptions: drive.DownloadOptions.fullMedia),
      name: 'downloadNote:$noteId',
    );
    if (response is! drive.Media) throw Exception('Unexpected response type');

    final bytes = await response.stream.expand((c) => c).toList();
    final remoteNote =
    Note.fromJson(jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>);

    final localNote = _notesBox!.get(noteId) as Note?;
    final ns = _syncState.notes[noteId];

    final localDirty = ns?.pendingUpload == true;
    final remoteNewer = ns?.remoteVersion == null ||
        remoteNote.updatedAt.isAfter(ns!.remoteVersion!);

    if (localNote != null &&
        localDirty &&
        remoteNewer &&
        ns?.lastSyncedAt != null) {
      debugPrint('Conflict detected on note $noteId');
      _syncState.notes[noteId] = (ns ?? NoteSync(noteId: noteId)).copyWith(
        driveFileId: fileId,
        remoteVersion: remoteNote.updatedAt,
        conflict:
        SyncConflict(remoteVersion: remoteNote, detectedAt: DateTime.now()),
      );
      _persistSyncState();
      return;
    }

    for (final imgId in remoteNote.imageIds) {
      if (_imagesBox?.get(imgId) == null) {
        final existing = _syncState.images[imgId];
        _syncState.images[imgId] = ImageSync(
          imageId: imgId,
          driveFileId: existing?.driveFileId,
          pendingUpload: false,
          existsOnDrive: true,
        );
      }
    }

    if (metadata?['deleted'] == true) {
      remoteNote.deleted = true;
    }

    await _notesBox!.put(noteId, remoteNote);
    _updateSearchIndex(remoteNote);

    _syncState.notes[noteId] = NoteSync(
      noteId: noteId,
      driveFileId: fileId,
      lastSyncedAt: DateTime.now(),
      remoteVersion: remoteNote.updatedAt,
      pendingUpload: false,
    );
    _persistSyncState();
  }

  Future<void> _reconcileDeletedNotes(DriveManifest manifest) async {
    final localNoteIds = (_notesBox?.keys.cast<dynamic>().toList() ?? [])
        .whereType<String>()
        .toList();

    for (final noteId in localNoteIds) {
      if (!manifest.noteMetadata.containsKey(noteId)) {
        final ns = _syncState.notes[noteId];
        if (ns?.pendingUpload == false) {
          await hardDelete(noteId);
        }
      }
    }
  }

  Future<void> _downloadMissingImages(
      drive.DriveApi api, DriveManifest manifest) async {
    for (final imageId in manifest.imageIds) {
      if (_imagesBox?.get(imageId) != null) continue;

      final imgSync = _syncState.images[imageId];
      String? fileId = imgSync?.driveFileId;

      if (fileId == null) {
        final list = await _retry(
              () => api.files.list(
            q: "name = '$imageId.bin' and '${_syncState.imagesFolderId}' in parents and trashed = false",
            $fields: 'files(id)',
            pageSize: 1,
          ),
          name: 'findImage:$imageId',
        );
        if (list.files?.isEmpty ?? true) {
          debugPrint('Image $imageId not found on Drive');
          continue;
        }
        fileId = list.files!.first.id!;
      }

      try {
        final response = await _retry(
              () => api.files
              .get(fileId!, downloadOptions: drive.DownloadOptions.fullMedia),
          name: 'downloadImage:$imageId',
        );
        if (response is! drive.Media) continue;

        final buffer = <int>[];
        const chunkSize = 64 * 1024;

        await for (final chunk in response.stream) {
          buffer.addAll(chunk);
          if (buffer.length > chunkSize) {
            await Future.delayed(Duration.zero);
          }
        }

        await _imagesBox?.put(
            imageId, _encodeImage(Uint8List.fromList(buffer)));

        _syncState.images[imageId] = ImageSync(
          imageId: imageId,
          driveFileId: fileId,
          pendingUpload: false,
          existsOnDrive: true,
        );
        _persistSyncState();
      } catch (e) {
        debugPrint('Failed to download image $imageId: $e');
      }
    }
  }

  // ── Local JSON backup / restore ─────────────────────────────────────────────

  /// Exports all non-deleted notes plus the current encryption salt into a
  /// single JSON bundle and returns the UTF-8 encoded bytes.
  ///
  /// Bundle schema:
  /// ```json
  /// {
  ///   "schemaVersion": 1,
  ///   "exportedAt": "<ISO-8601>",
  ///   "salt": "<base64url PBKDF2 salt, or null>",
  ///   "notes": [ ...note.toJson()... ]
  /// }
  /// ```
  ///
  /// The salt is included so that after a full reinstall the user can supply
  /// both this file and their master password, and [importNotesJson] will
  /// restore the salt so EncryptionService can re-derive the same key and
  /// decrypt every note in the bundle.
  ///
  /// Throws if the notes box is not open.
  Future<Uint8List> exportNotesJson() async {
    if (_notesBox == null) throw StateError('Notes box not open');

    final notesJson = _notesBox!.values
        .cast<Note>()
        .where((n) => !n.deleted)
        .map((n) => n.toJson())
        .toList();

    final salt = await EncryptionService.instance.exportSalt();

    final bundle = <String, dynamic>{
      'schemaVersion': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'salt': salt,
      'notes': notesJson,
    };

    return Uint8List.fromList(utf8.encode(jsonEncode(bundle)));
  }

  /// Imports notes from a JSON bundle produced by [exportNotesJson].
  ///
  /// Merge strategy — for each note in the bundle:
  /// - If the note does not exist locally → insert it.
  /// - If it exists and the bundle copy is newer (`updatedAt`) → overwrite.
  /// - If it exists and the local copy is newer → keep local (skip).
  ///
  /// Salt handling: if the bundle contains a salt and the device currently has
  /// NO local salt (e.g. fresh reinstall before any password is set), the
  /// bundle salt is supplied to [EncryptionService] so the user can re-derive
  /// the original key with their master password on the next unlock.
  ///
  /// Returns the number of notes actually written (inserted or updated).
  ///
  /// Throws [FormatException] for malformed JSON or wrong schema version.
  Future<int> importNotesJson(Uint8List bytes) async {
    if (_notesBox == null) throw StateError('Notes box not open');

    final Map<String, dynamic> bundle;
    try {
      bundle = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      throw const FormatException('File is not valid JSON.');
    }

    final version = bundle['schemaVersion'] as int? ?? 0;
    if (version != 1) {
      throw FormatException(
          'Unsupported backup version $version. '
              'Please use a backup created by this app.');
    }

    // ── Salt restoration ────────────────────────────────────────────────────
    // If the bundle carries a salt and the device has no local salt yet
    // (fresh reinstall / first use), supply it so the user's master password
    // will re-derive the same key on next unlock.
    final bundleSalt = bundle['salt'] as String?;
    if (bundleSalt != null) {
      final localSalt = await EncryptionService.instance.exportSalt();
      if (localSalt == null) {
        await EncryptionService.instance.supplyDriveSalt(bundleSalt);
        debugPrint('[Import] Restored salt from backup bundle.');
      }
    }

    final rawNotes = bundle['notes'] as List? ?? [];
    int imported = 0;

    for (final raw in rawNotes) {
      try {
        final note =
        Note.fromJson(Map<String, dynamic>.from(raw as Map));
        if (note.deleted) continue;

        final existing = _notesBox!.get(note.id) as Note?;
        if (existing == null ||
            note.updatedAt.isAfter(existing.updatedAt)) {
          await _notesBox!.put(note.id, note);
          _updateSearchIndex(note);
          // Mark as pending upload so the next Drive sync pushes it.
          _syncState.markNoteDirty(note.id);
          imported++;
        }
      } catch (e) {
        debugPrint('[Import] Skipped malformed note entry: $e');
      }
    }

    _persistSyncState();
    notifyListeners();
    return imported;
  }

  // ── Misc ────────────────────────────────────────────────────────────────────

  void refreshNotes() {
    _rebuildSearchIndex();
    notifyListeners();
  }

  /// Force-reloads all notes from Hive and notifies listeners.
  ///
  /// Call this after [onEncryptionReady] on web, where the keyReady listener
  /// may have fired before the Hive box was open, leaving the note list empty.
  /// Safe to call on native too — it is a no-op if the box or key isn't ready.
  Future<void> reloadNotes() async {
    if (!_encryptionReady || _notesBox == null) return;
    _rebuildSearchIndex();
    notifyListeners();
  }
}