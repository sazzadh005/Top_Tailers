import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../models/measurements.dart';
import '../repositories/repositories.dart';

/// Holds the signed-in user. Methods throw [AppException] on failure so the
/// calling screen can show the message and manage its own busy state.
///
/// Role-based screens are a CONVENIENCE for demonstration. Real authentication
/// and authorization must be enforced by the backend.
class AuthProvider extends ChangeNotifier {
  AuthProvider(this._repo, {Duration splash = const Duration(milliseconds: 1200)}) {
    _init(splash);
  }

  final AuthRepository _repo;

  AppUser? _user;
  bool _initializing = true;

  AppUser? get user => _user;
  bool get isInitializing => _initializing;
  bool get isAdmin => _user?.isAdmin ?? false;

  Future<void> _init(Duration splash) async {
    if (splash != Duration.zero) await Future<void>.delayed(splash);
    _initializing = false;
    notifyListeners();
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

  Future<void> updateProfile({
    required String name,
    required String phone,
    required String address,
    String? profileImage,
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
  }
}
