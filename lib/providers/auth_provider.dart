import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../services/mock_backend.dart';

/// Holds the signed-in user. Methods throw [AppException] on failure so the
/// calling screen can show the message and manage its own busy state.
class AuthProvider extends ChangeNotifier {
  AuthProvider() {
    _init();
  }

  final MockBackend _backend = MockBackend.instance;

  AppUser? _user;
  bool _initializing = true;

  AppUser? get user => _user;
  bool get isInitializing => _initializing;
  bool get isAdmin => _user?.isAdmin ?? false;

  Future<void> _init() async {
    // Short splash; with Firebase this is where the persisted session is restored.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    _initializing = false;
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    _user = await _backend.login(email, password);
    notifyListeners();
  }

  Future<void> register({
    required String name,
    required String email,
    required String phone,
    required String address,
    required String password,
  }) async {
    _user = await _backend.register(
      name: name,
      email: email,
      phone: phone,
      address: address,
      password: password,
    );
    notifyListeners();
  }

  Future<void> sendPasswordReset(String email) => _backend.sendPasswordReset(email);

  Future<void> updateProfile({
    required String name,
    required String phone,
    required String address,
    String? profileImage,
    bool clearProfileImage = false,
  }) async {
    final current = _user;
    if (current == null) return;
    _user = await _backend.updateProfile(
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

  void logout() {
    _user = null;
    notifyListeners();
  }
}
