import '../../core/app_exception.dart';
import '../../domain/discount.dart';
import '../../models/customer_discount.dart';
import '../../models/voucher.dart';
import '../../repositories/repositories.dart';
import 'mock_store.dart';

class MockDiscountRepository implements DiscountRepository {
  MockDiscountRepository(this._store);

  final MockStore _store;

  @override
  Future<CustomerDiscount?> getCustomerDiscount(String customerId) async {
    await _store.wait();
    return _store.customerDiscounts[customerId];
  }

  @override
  Future<List<CustomerDiscount>> listCustomerDiscounts() async {
    await _store.wait();
    return _store.customerDiscounts.values.toList();
  }

  @override
  Future<CustomerDiscount> saveCustomerDiscount(CustomerDiscount discount) async {
    await _store.wait();
    final error = DiscountMath.validateGeneral(discount.kind, discount.value);
    if (error != null) throw AppException(error);
    final saved = CustomerDiscount(
      customerId: discount.customerId,
      kind: discount.kind,
      value: discount.value,
      active: discount.active,
      note: discount.note,
      updatedAt: _store.now(),
    );
    _store.customerDiscounts[discount.customerId] = saved;
    return saved;
  }

  @override
  Future<void> removeCustomerDiscount(String customerId) async {
    await _store.wait();
    _store.customerDiscounts.remove(customerId);
  }
}

class MockVoucherRepository implements VoucherRepository {
  MockVoucherRepository(this._store);

  final MockStore _store;

  @override
  Future<Voucher?> findByCode(String code) async {
    await _store.wait();
    final key = code.trim().toUpperCase();
    for (final v in _store.vouchers) {
      if (v.code == key) return v;
    }
    return null;
  }
}
