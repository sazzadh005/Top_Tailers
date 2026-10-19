import '../../models/app_notification.dart';
import '../../models/app_user.dart';
import '../../models/customer_discount.dart';
import '../../models/feedback.dart';
import '../../models/order.dart';
import '../../models/product.dart';
import '../../models/requests.dart';
import '../../models/voucher.dart';
import 'mock_seed.dart';

/// In-memory data shared by the mock repositories. This stands in for the
/// future database and is DEMONSTRATION DATA ONLY: nothing here is a real
/// order, payment, inventory or spending record.
class MockStore {
  MockStore({
    DateTime Function()? clock,
    this.latency = const Duration(milliseconds: 350),
    bool seed = true,
  }) : _clock = clock ?? DateTime.now {
    if (seed) seedMockData(this);
  }

  final DateTime Function() _clock;
  final Duration latency;

  DateTime now() => _clock();

  int _sequence = 2000;
  String newId(String prefix) => '$prefix${_sequence++}';

  /// Simulated network delay. [factor] scales the base latency.
  Future<void> wait([int factor = 1]) {
    if (latency == Duration.zero) return Future<void>.value();
    return Future<void>.delayed(latency * factor);
  }

  /// Demo order reference such as TTF-261014-K7Q2. Generated locally for the
  /// frontend demo; a backend will issue real references.
  String mockReference(String id, DateTime date) {
    final yy = (date.year % 100).toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    final dd = date.day.toString().padLeft(2, '0');
    var hash = 7;
    for (final unit in id.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final suffix = StringBuffer();
    var h = hash;
    for (var i = 0; i < 4; i++) {
      suffix.write(alphabet[h % alphabet.length]);
      h ~/= alphabet.length;
    }
    return 'TTF-$yy$mm$dd-$suffix';
  }

  final Map<String, String> passwords = {};
  final List<AppUser> users = [];
  final List<Product> products = [];
  final List<AppOrder> orders = [];
  final List<AppNotification> notifications = [];
  final List<ProductFeedback> feedback = [];
  final List<ProductSuggestion> suggestions = [];
  final List<RestockRequest> restocks = [];
  final List<Voucher> vouchers = [];
  final Map<String, CustomerDiscount> customerDiscounts = {};
  final Map<String, Set<String>> wishlists = {};

  Product? productById(String id) {
    for (final p in products) {
      if (p.id == id) return p;
    }
    return null;
  }

  int orderIndex(String id) => orders.indexWhere((o) => o.id == id);

  void notify(String userId, String title, String body) {
    notifications.insert(
      0,
      AppNotification(
        id: newId('n'),
        userId: userId,
        title: title,
        body: body,
        createdAt: now(),
      ),
    );
  }
}
