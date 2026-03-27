// lib/update_state.dart
//
// Singleton ChangeNotifier that holds the in-app update availability state.
// Shared between NoteListScreen (auto-check on startup) and
// _UpdateChecker in SettingsScreen (manual check) so both always reflect
// the same state without duplicating Play Core calls.

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

enum UpdateAvailableState { idle, checking, available, upToDate, downloading, error }

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

  Future<void> checkForUpdate({bool silent = false}) async {
    if (_state == UpdateAvailableState.checking ||
        _state == UpdateAvailableState.downloading) return;

    _state = UpdateAvailableState.checking;
    _errorMessage = null;
    notifyListeners();

    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability == UpdateAvailability.updateAvailable) {
        _state = UpdateAvailableState.available;
        _updateInfo = info;
      } else {
        _state = UpdateAvailableState.upToDate;
        // Reset to idle after 3s for the manual-check UI only
        if (!silent) {
          await Future.delayed(const Duration(seconds: 3));
          if (_state == UpdateAvailableState.upToDate) {
            _state = UpdateAvailableState.idle;
          }
        } else {
          _state = UpdateAvailableState.idle;
        }
      }
    } catch (e) {
      if (silent) {
        // Silent startup check — swallow the error, reset to idle
        _state = UpdateAvailableState.idle;
      } else {
        _errorMessage = 'Could not check for updates. Try again later.';
        _state = UpdateAvailableState.error;
        await Future.delayed(const Duration(seconds: 3));
        if (_state == UpdateAvailableState.error) {
          _state = UpdateAvailableState.idle;
        }
      }
    }

    notifyListeners();
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
}
