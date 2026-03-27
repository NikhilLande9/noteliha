// lib/services/user_metadata_service.dart
//
// Writes a minimal support-only document to Firestore whenever a user signs in.
// Document path: users/{emailDocId}
//
// Top-level fields:
//   uid          – auto-incremented integer, assigned once on first sign-in
//   email        – account email address
//   createdAt    – server timestamp, written once on first sign-in
//   devices      – map of per-device entries (see below)
//
// Per-device entry (nested under devices/{deviceKey}):
//   deviceModel    – e.g. "motorola edge 60 fusion" or "web"
//   androidVersion – e.g. "16" or "n/a"
//   appVersion     – e.g. "1.0.0.6"
//   lastActive     – server timestamp, refreshed at most once per 24 hours
//   firstSeen      – server timestamp, written once per device
//
// Device key format:
//   Android → "android_{manufacturer}_{model}" (lowercased, spaces → underscores)
//   Web     → "web"
//
// Write rules:
//   • New user     → transaction: atomically increment counter + create document
//   • New device   → update() to add the device entry with firstSeen + lastActive
//   • Known device → update() only when appVersion changed OR lastActive > 24 hrs
//   • No change    → skip entirely — zero Firestore writes
//
// Reads per sign-in: 2 (user doc + counter doc on first sign-in only, else 1)
// Writes per sign-in: 0–1 depending on staleness
//
// No real-time listeners, background tracking, or analytics of any kind.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

class UserMetadataService {
  UserMetadataService._();

  static final UserMetadataService instance = UserMetadataService._();

  // Resolved once per app session — never changes at runtime.
  PackageInfo? _packageInfo;
  String? _deviceModel;
  String? _androidVersion;
  String? _deviceKey;

  // Firestore refs
  static final _db = FirebaseFirestore.instance;
  static final _usersCol = _db.collection('users');
  static final _counterDoc = _db.collection('meta').doc('counter');

  // ── Public entry point ─────────────────────────────────────────────────────

  Future<void> upsertOnSignIn({
    required String googleId,
    required String email,
  }) async {
    try {
      await _ensureDeviceInfo();

      final docId = _emailToDocId(email);
      final docRef = _usersCol.doc(docId);
      final currentVersion = _currentVersion();

      final snapshot = await docRef.get();

      if (!snapshot.exists) {
        await _createUser(
            docRef: docRef, email: email, version: currentVersion);
        debugPrint('[UserMetadata] Created document for $googleId');
        return;
      }

      await _upsertDevice(
        docRef: docRef,
        data: snapshot.data()!,
        email: email,
        version: currentVersion,
        googleId: googleId,
      );
    } catch (e, st) {
      debugPrint('[UserMetadata] upsertOnSignIn failed: $e\n$st');
    }
  }

  // ── New user ───────────────────────────────────────────────────────────────

  Future<void> _createUser({
    required DocumentReference docRef,
    required String email,
    required String version,
  }) async {
    // Atomically increment counter and assign uid in a single transaction.
    // This ensures no two users ever get the same uid even under concurrent
    // sign-ins (unlikely but handled correctly).
    await _db.runTransaction((tx) async {
      final counterSnap = await tx.get(_counterDoc);
      final nextUid = ((counterSnap.data()?['userCount'] as int?) ?? 0) + 1;

      tx.set(docRef, {
        'uid': nextUid,
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
        'devices': {
          _deviceKey!: _deviceEntry(version, isNew: true),
        },
      });

      tx.set(
        _counterDoc,
        {'userCount': nextUid},
        SetOptions(merge: true),
      );
    });
  }

  // ── Returning user ─────────────────────────────────────────────────────────

  Future<void> _upsertDevice({
    required DocumentReference docRef,
    required Map<String, dynamic> data,
    required String email,
    required String version,
    required String googleId,
  }) async {
    final devices = Map<String, dynamic>.from(data['devices'] as Map? ?? {});
    final existing = devices[_deviceKey!] != null
        ? Map<String, dynamic>.from(devices[_deviceKey!] as Map)
        : null;

    // ── New device on existing account ────────────────────────────────────
    if (existing == null) {
      await docRef.update({
        'email': email,
        'devices.$_deviceKey': _deviceEntry(version, isNew: true),
      });
      debugPrint('[UserMetadata] New device added for $googleId: $_deviceKey');
      return;
    }

    // ── Known device — check if update is needed ──────────────────────────
    final storedVersion = existing['appVersion'] as String?;
    final lastActiveRaw = existing['lastActive'];
    DateTime? lastActiveTs;
    if (lastActiveRaw is Timestamp) {
      lastActiveTs = lastActiveRaw.toDate();
    }

    final versionChanged = storedVersion != version;
    final stale = lastActiveTs == null ||
        DateTime.now().difference(lastActiveTs) > const Duration(hours: 24);

    if (!versionChanged && !stale) {
      debugPrint(
          '[UserMetadata] No update needed for $googleId on $_deviceKey');
      return;
    }

    // Only write the fields that actually changed — dot-notation targets
    // just this device's sub-fields, leaving all other devices untouched.
    final updates = <String, dynamic>{
      'email': email,
      'devices.$_deviceKey.lastActive': FieldValue.serverTimestamp(),
    };
    if (versionChanged) {
      updates['devices.$_deviceKey.appVersion'] = version;
      debugPrint('[UserMetadata] Version changed → $version for $_deviceKey');
    }

    await docRef.update(updates);
    debugPrint('[UserMetadata] Updated $_deviceKey for $googleId');
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Builds a fresh device entry map.
  /// [isNew] = true adds firstSeen (written only once per device).
  Map<String, dynamic> _deviceEntry(String version, {required bool isNew}) => {
        'deviceModel': _deviceModel ?? 'unknown',
        'androidVersion': _androidVersion ?? 'unknown',
        'appVersion': version,
        'lastActive': FieldValue.serverTimestamp(),
        if (isNew) 'firstSeen': FieldValue.serverTimestamp(),
      };

  /// Resolves the current version string e.g. "1.0.0.6"
  String _currentVersion() => _packageInfo != null
      ? '${_packageInfo!.version}.${_packageInfo!.buildNumber}'
      : 'unknown';

  /// Converts email to a Firestore-safe document ID.
  /// e.g. "nikhillande9@gmail.com" → "nikhillande9@gmail_com"
  static String _emailToDocId(String email) => email.replaceAll('.', '_');

  /// Converts a raw string to a safe Firestore map key.
  /// e.g. "Motorola Edge 60 Fusion" → "motorola_edge_60_fusion"
  static String _toKey(String raw) =>
      raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').trim();

  // ── Device / package info ──────────────────────────────────────────────────

  Future<void> _ensureDeviceInfo() async {
    _packageInfo ??= await PackageInfo.fromPlatform();
    if (_deviceKey != null) return; // already resolved this session

    if (kIsWeb) {
      _deviceModel = 'web';
      _androidVersion = 'n/a';
      _deviceKey = 'web';
      return;
    }

    try {
      final plugin = DeviceInfoPlugin();
      final android = await plugin.androidInfo;
      final manufacturer = android.manufacturer.trim();
      final model = android.model.trim();
      _deviceModel = '$manufacturer $model';
      _androidVersion = android.version.release;
      _deviceKey = 'android_${_toKey('$manufacturer $model')}';
    } catch (e) {
      debugPrint('[UserMetadata] DeviceInfo unavailable: $e');
      _deviceModel = 'unknown';
      _androidVersion = 'unknown';
      _deviceKey = 'android_unknown';
    }
  }
}
