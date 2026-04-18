// lib/update_state.dart
//
// Singleton ChangeNotifier that holds the in-app update availability state.
// Shared between NoteListScreen (auto-check on startup) and
// _UpdateChecker in SettingsScreen (manual check) so both always reflect
// the same state without duplicating Play Core calls.

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

enum UpdateAvailableState {
  idle,
  checking,
  available,
  upToDate,
  downloading,
  error
}

class UpdateStateNotifier extends ChangeNotifier {
  UpdateStateNotifier._();
  static final UpdateStateNotifier instance = UpdateStateNotifier._();

  UpdateAvailableState _state = UpdateAvailableState.idle;
  AppUpdateInfo? _updateInfo;
  String? _errorMessage;

  UpdateAvailableState get state => _state;
  AppUpdateInfo? get updateInfo => _updateInfo;
  String? get errorMessage => _errorMessage;

  bool get isUpdateAvailable => _state == UpdateAvailableState.available;

  // ── Check ──────────────────────────────────────────────────────────────────

  // Returns the resolved UpdateAvailableState *before* any delayed reset,
  // so callers (e.g. a SnackBar in SettingsScreen) can act on the result
  // without racing the 3-second auto-reset.
  Future<UpdateAvailableState> checkForUpdate({bool silent = false}) async {
    if (_state == UpdateAvailableState.checking ||
        _state == UpdateAvailableState.downloading) {
      return _state;
    }

    // In-app updates are only supported on Android via Google Play.
    // On web, iOS, or non-Play Android builds the API always throws, so we
    // short-circuit here and report "up-to-date" instead of surfacing a
    // confusing error banner.
    if (kIsWeb || !_isAndroid()) {
      _state = UpdateAvailableState.upToDate;
      notifyListeners();
      if (!silent) {
        Future.delayed(const Duration(seconds: 3), () {
          if (_state == UpdateAvailableState.upToDate) {
            _state = UpdateAvailableState.idle;
            notifyListeners();
          }
        });
      } else {
        _state = UpdateAvailableState.idle;
        notifyListeners();
      }
      return UpdateAvailableState.upToDate;
    }

    _state = UpdateAvailableState.checking;
    _errorMessage = null;
    notifyListeners();

    UpdateAvailableState resolved;

    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        resolved = UpdateAvailableState.available;
        _state = resolved;
        _updateInfo = info;
        notifyListeners();
      } else {
        resolved = UpdateAvailableState.upToDate;
        _state = resolved;
        notifyListeners(); // render "All Up-to-date" in the tile immediately

        if (silent) {
          _state = UpdateAvailableState.idle;
          notifyListeners();
        } else {
          // Hold the upToDate state so the tile shows it, then quietly reset.
          Future.delayed(const Duration(seconds: 3), () {
            if (_state == UpdateAvailableState.upToDate) {
              _state = UpdateAvailableState.idle;
              notifyListeners();
            }
          });
        }
      }
    } catch (e) {
      // Play Core can throw PlatformException on sideloaded APKs, emulators,
      // and devices without Google Play Services. Treat these as "up-to-date"
      // rather than surfacing a scary red error tile to the user.
      final isPlayCoreUnsupported = e.toString().contains('in_app_update') ||
          e.toString().contains('INSTALL_UNAVAILABLE') ||
          e.toString().contains('PlatformException') ||
          e.toString().contains('not available');

      if (silent || isPlayCoreUnsupported) {
        resolved = UpdateAvailableState.upToDate;
        _state = resolved;
        notifyListeners();
        if (!silent) {
          Future.delayed(const Duration(seconds: 3), () {
            if (_state == UpdateAvailableState.upToDate) {
              _state = UpdateAvailableState.idle;
              notifyListeners();
            }
          });
        } else {
          _state = UpdateAvailableState.idle;
          notifyListeners();
        }
      } else {
        resolved = UpdateAvailableState.error;
        _errorMessage = 'Could not check for updates. Try again later.';
        _state = resolved;
        notifyListeners();
        Future.delayed(const Duration(seconds: 3), () {
          if (_state == UpdateAvailableState.error) {
            _state = UpdateAvailableState.idle;
            notifyListeners();
          }
        });
      }
    }

    return resolved;
  }

  // ── Download ───────────────────────────────────────────────────────────────

  Future<bool> startUpdate() async {
    if (_state != UpdateAvailableState.available) return false;
    _state = UpdateAvailableState.downloading;
    notifyListeners();

    try {
      await InAppUpdate.startFlexibleUpdate();
      _state = UpdateAvailableState.idle;
      notifyListeners();
      return true;
    } catch (_) {
      _state = UpdateAvailableState.available; // revert so user can retry
      notifyListeners();
      return false;
    }
  }

  static Future<void> completeUpdate() => InAppUpdate.completeFlexibleUpdate();

  // ── Helpers ────────────────────────────────────────────────────────────────

  static bool _isAndroid() {
    try {
      // defaultTargetPlatform is available without dart:io
      return defaultTargetPlatform == TargetPlatform.android;
    } catch (_) {
      return false;
    }
  }
}