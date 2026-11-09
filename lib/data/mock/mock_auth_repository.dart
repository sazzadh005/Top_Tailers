import '../../core/app_exception.dart';
import '../../domain/spending.dart';
import '../../models/app_user.dart';
import '../../models/customer_summary.dart';
import '../../models/measurements.dart';
import '../../repositories/repositories.dart';
import 'mock_store.dart';

class MockAuthRepository implements AuthRepository {
  MockAuthRepository(this._store);

  final MockStore _store;

  @override
  Future<AppUser> login(String email, String password) async {
    await _store.wait();
    final key = email.trim().toLowerCase();
    for (final user in _store.users) {
      if (user.email.toLowerCase() == key && _store.passwords[user.id] == password) {
        return user;
      }
    }
    throw AppException('Invalid email or password.');
  }

  @override
  Future<AppUser> register({
    required String name,
    required String email,
    required String phone,
    required String address,
    required String password,
    BodyMeasurements measurements = BodyMeasurements.empty,
  }) async {
    await _store.wait();
    final key = email.trim().toLowerCase();
    if (_store.users.any((u) => u.email.toLowerCase() == key)) {
      throw AppException('An account with this email already exists.');
    }
    final user = AppUser(
      id: _store.newId('u'),
      name: name.trim(),
      email: key,
      phone: phone.trim(),
      address: address.trim(),
      role: UserRole.customer,
      createdAt: _store.now(),
      measurements: measurements,
    );
    _store.users.add(user);
    _store.passwords[user.id] = password;
    _store.notify(user.id, 'Welcome to Top Tailers & Fabrics',
        'Your account is ready. Start browsing our collection.');
    return user;
  }

  /// Succeeds regardless of whether the email exists, so responses do not
  /// reveal which emails are registered.
  @override
  Future<void> sendPasswordReset(String email) => _store.wait();

  int _indexOf(String id) => _store.users.indexWhere((u) => u.id == id);

  @override
  Future<AppUser> updateProfile(AppUser updated) async {
    await _store.wait();
    final index = _indexOf(updated.id);
    if (index < 0) throw AppException('Account not found.');
    _store.users[index] = updated;
    return updated;
  }

  @override
  Future<AppUser> updateMeasurements(
    String customerId,
    BodyMeasurements measurements, {
    required AppUser actor,
  }) async {
    await _store.wait();
    if (!actor.isAdmin && actor.id != customerId) {
      throw AppException('You can only change your own measurements.');
    }
    final index = _indexOf(customerId);
    if (index < 0) throw AppException('Customer not found.');
    final updated = _store.users[index].copyWith(measurements: measurements);
    _store.users[index] = updated;
    return updated;
  }

  @override
  Future<List<CustomerSummary>> getCustomerSummaries({required AppUser actor}) async {
    await _store.wait();
    if (!actor.isAdmin) throw AppException('Only the shop admin can view customers.');
    final list = _store.users.where((u) => u.role == UserRole.customer).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return [
      for (final u in list)
        CustomerSummary(
          user: u,
          orderCount: SpendingCalculator.orderCount(_store.orders.where((o) => o.userId == u.id)),
          lifetimeSpendingMinor:
              SpendingCalculator.lifetimeSpendingMinor(_store.orders.where((o) => o.userId == u.id)),
        ),
    ];
  }

  // The mock keeps no session; a real backend restores one here.
  @override
  Future<AppUser?> restoreSession() async => null;

  @override
  Future<void> logout() async {}

  @override
  Future<void> updatePassword(String newPassword) async {}

  @override
  Stream<void> get passwordRecoveryEvents => const Stream<void>.empty();

  @override
  Stream<void> get sessionEndedEvents => const Stream<void>.empty();
}
