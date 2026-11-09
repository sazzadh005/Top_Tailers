import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../models/measurements.dart';
import '../repositories/repositories.dart';

/// Holds the signed-in user. Methods throw [AppException] on failure so the
/// calling screen can show the message and manage its own busy state.
///
/// Role-based screens are a convenience. The BACKEND enforces who may do what.
class AuthProvider extends ChangeNotifier {
  AuthProvider(this._repo, {Duration splash = const Duration(milliseconds: 1200)}) {
    _recoverySub = _repo.passwordRecoveryEvents.listen((_) {
      _recovering = true;
      _safeNotify();
    });
    _endedSub = _repo.sessionEndedEvents.listen((_) {
      if (_user != null) {
        _user = null;
        _safeNotify();
      }
    });
    _init(splash);
  }

  final AuthRepository _repo;
  StreamSubscription<void>? _recoverySub;
  StreamSubscription<void>? _endedSub;

  AppUser? _user;
  bool _initializing = true;
  bool _recovering = false;
  bool _disposed = false;

  AppUser? get user => _user;
  bool get isInitializing => _initializing;
  bool get isAdmin => _user?.isAdmin ?? false;

  /// True after the app was opened from a password-reset email link.
  bool get isRecovering => _recovering;

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _init(Duration splash) async {
    if (splash != Duration.zero) await Future<void>.delayed(splash);
    try {
      final restored = await _repo.restoreSession();
      // A login that happened while restoring wins.
      if (restored != null && _user == null) _user = restored;
    } catch (_) {
      // No usable session: start signed out.
    }
    _initializing = false;
    _safeNotify();
  }

  Future<void> login(String email, String password) async {
    _user = await _repo.login(email, password);
    notifyListeners();
  }

  Future<void> register({
    required String name,
    required String email,
    required String phone,
    required String address,
    required String password,
    BodyMeasurements measurements = BodyMeasurements.empty,
  }) async {
    _user = await _repo.register(
      name: name,
      email: email,
      phone: phone,
      address: address,
      password: password,
      measurements: measurements,
    );
    notifyListeners();
  }

  Future<void> sendPasswordReset(String email) => _repo.sendPasswordReset(email);

  /// Completes a password reset started from the emailed link.
  Future<void> setNewPassword(String newPassword) async {
    await _repo.updatePassword(newPassword);
    _recovering = false;
    notifyListeners();
  }

  void dismissRecovery() {
    _recovering = false;
    notifyListeners();
  }

  Future<void> updateProfile({
    required String name,
    required String phone,
    required String address,
    String? profileImage,
    String? profileImagePublicId,
    bool clearProfileImage = false,
  }) async {
    final current = _user;
    if (current == null) return;
    _user = await _repo.updateProfile(
      current.copyWith(
        name: name.trim(),
        phone: phone.trim(),
        address: address.trim(),
        profileImage: profileImage,
        profileImagePublicId: profileImagePublicId,
        clearProfileImage: clearProfileImage,
      ),
    );
    notifyListeners();
  }

  /// Saves the signed-in customer's own measurements to their profile.
  Future<void> updateMyMeasurements(BodyMeasurements measurements) async {
    final current = _user;
    if (current == null) return;
    _user = await _repo.updateMeasurements(current.id, measurements, actor: current);
    notifyListeners();
  }

  void logout() {
    _user = null;
    notifyListeners();
    _repo.logout().ignore();
  }

  @override
  void dispose() {
    _disposed = true;
    _recoverySub?.cancel();
    _endedSub?.cancel();
    super.dispose();
  }
}
