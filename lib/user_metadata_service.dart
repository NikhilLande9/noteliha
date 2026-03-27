// lib/services/user_metadata_service.dart
//
// Writes a minimal support-only document to Firestore whenever a user signs in.
// Document path: users/{googleId}
//
// Fields stored (static / near-static only — no behavioural data):
//   email        – account email address
//   deviceModel  – e.g. "Pixel 8 Pro"
//   androidVersion – e.g. "14"
//   appVersion   – e.g. "1.0.0+5"
//   createdAt    – server timestamp, written once on first sign-in
//   lastActive   – server timestamp, refreshed at most once per 24 hours
//
// Write rules:
//   • New user  → SetOptions(merge: false) to create the document with
//                 both createdAt and lastActive set to FieldValue.serverTimestamp().
//   • Existing  → update() only when appVersion changed OR lastActive is
//                 older than 24 hours — avoids wasteful writes on every launch.
//
// No real-time listeners, background tracking, or analytics of any kind.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

class UserMetadataService {
  UserMetadataService._();

  static final UserMetadataService instance = UserMetadataService._();

  // Reuse resolved info within a single app session — they never change at
  // runtime, so there is no need to re-fetch on every sign-in.
  PackageInfo? _packageInfo;
  String? _deviceModel;
  String? _androidVersion;

  // ── Public entry point ─────────────────────────────────────────────────────

  /// Call this inside `onCurrentUserChanged` when [account] is non-null.
  /// All Firestore I/O is fire-and-forget: errors are logged but never rethrown
  /// so they cannot interfere with the sign-in or Drive sync flows.
  Future<void> upsertOnSignIn({
    required String googleId,
    required String email,
  }) async {
    try {
      await _ensureDeviceInfo();

      // Use email as the document ID — dots replaced so it reads cleanly in the
      // Firestore console. e.g. "nikhillande9@gmail.com" → "nikhillande9@gmail_com"
      final docId = email.replaceAll('.', '_');
      final docRef = FirebaseFirestore.instance.collection('users').doc(docId);

      final snapshot = await docRef.get();

      if (!snapshot.exists) {
        // ── First sign-in: create document ────────────────────────────────
        await docRef.set({
          'email': email,
          'deviceModel': _deviceModel ?? 'unknown',
          'androidVersion': _androidVersion ?? 'unknown',
          'appVersion': _packageInfo != null
              ? '${_packageInfo!.version}+${_packageInfo!.buildNumber}'
              : 'unknown',
          'createdAt': FieldValue.serverTimestamp(),
          'lastActive': FieldValue.serverTimestamp(),
        });
        debugPrint('[UserMetadata] Created document for $googleId');
        return;
      }

      // ── Returning user: update only when necessary ────────────────────────
      final data = snapshot.data()!;
      final storedVersion = data['appVersion'] as String?;
      final currentVersion = _packageInfo?.version ?? 'unknown';

      final lastActiveRaw = data['lastActive'];
      DateTime? lastActiveTs;
      if (lastActiveRaw is Timestamp) {
        lastActiveTs = lastActiveRaw.toDate();
      }

      final versionChanged = storedVersion != currentVersion;
      final stale = lastActiveTs == null ||
          DateTime.now().difference(lastActiveTs) > const Duration(hours: 24);

      if (!versionChanged && !stale) {
        debugPrint('[UserMetadata] No update needed for $googleId');
        return;
      }

      final updates = <String, dynamic>{
        'lastActive': FieldValue.serverTimestamp(),
      };
      if (versionChanged) {
        updates['appVersion'] = currentVersion;
        debugPrint('[UserMetadata] App version changed → updating to $currentVersion');
      }
      // Keep email current in case the user changes their Google account address.
      updates['email'] = email;

      await docRef.update(updates);
      debugPrint('[UserMetadata] Updated document for $googleId');
    } catch (e, st) {
      // Never let metadata errors bubble up to the caller.
      debugPrint('[UserMetadata] upsertOnSignIn failed: $e\n$st');
    }
  }

  // ── Device / package info helpers ──────────────────────────────────────────

  Future<void> _ensureDeviceInfo() async {
    // Resolve package and device info once per session.
    _packageInfo ??= await PackageInfo.fromPlatform();

    if (_deviceModel != null) return; // already resolved

    if (kIsWeb) {
      _deviceModel = 'web';
      _androidVersion = 'n/a';
      return;
    }

    try {
      final plugin = DeviceInfoPlugin();
      final android = await plugin.androidInfo;
      _deviceModel = '${android.manufacturer} ${android.model}'.trim();
      _androidVersion = android.version.release;
    } catch (e) {
      debugPrint('[UserMetadata] DeviceInfo unavailable: $e');
      _deviceModel = 'unknown';
      _androidVersion = 'unknown';
    }
  }
}