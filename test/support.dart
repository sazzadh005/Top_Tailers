import 'package:top_tailers_/app/app_services.dart';
import 'package:top_tailers_/models/app_user.dart';
import 'package:top_tailers_/models/cancellation.dart';
import 'package:top_tailers_/models/measurements.dart';
import 'package:top_tailers_/models/order.dart';
import 'package:top_tailers_/models/payment.dart';

/// Fixed "now" so seed data ages are deterministic.
final DateTime kNow = DateTime(2026, 10, 18, 12);

AppServices testServices() =>
    AppServices.mock(latency: Duration.zero, clock: () => kNow);

Future<AppUser> loginAs(AppServices s, String email) {
  final password = email == 'admin@toptailers.com' ? 'Admin@123' : 'Customer@123';
  return s.auth.login(email, password);
}

const String kRahim = 'customer@example.com';
const String kNusrat = 'nusrat@example.com';
const String kTanvir = 'tanvir@example.com';
const String kAdmin = 'admin@toptailers.com';

/// Builds an order directly for pure-logic tests.
AppOrder makeOrder({
  String id = 'O1',
  String userId = 'u2',
  String customerName = 'Rahim Uddin',
  String phone = '01712345678',
  String reference = 'TTF-261018-AAAA',
  List<OrderItem>? items,
  int total = 100000,
  OrderStatus status = OrderStatus.pending,
  PaymentMethod method = PaymentMethod.cod,
  PaymentStatus payment = PaymentStatus.pending,
  DateTime? date,
  CancellationRecord? cancellation,
  OrderMeasurementSnapshot? measurements,
}) {
  final when = date ?? DateTime(2026, 10, 10, 9);
  return AppOrder(
    id: id,
    reference: reference,
    userId: userId,
    customerName: customerName,
    contactPhone: phone,
    shippingAddress: 'Somewhere in Gazipur',
    measurements: measurements,
    items: items ??
        const [
          OrderItem(
            productId: 'p1',
            productCode: 'FAB-COT-001',
            productName: 'Premium Cotton Fabric',
            listUnitMinor: 45000,
            unitMinor: 45000,
            quantity: 1,
            category: 'Fabrics',
          ),
        ],
    subtotalMinor: total,
    productDiscountMinor: 0,
    customerDiscountMinor: 0,
    voucherDiscountMinor: 0,
    deliveryMinor: 0,
    totalMinor: total,
    payment: PaymentRecord(
      id: 'PAY-$id',
      method: method,
      status: payment,
      amountMinor: total,
      provider: method == PaymentMethod.cod ? PaymentProvider.none : PaymentProvider.demo,
      updatedAt: when,
    ),
    status: status,
    orderDate: when,
    history: [OrderEvent(status: OrderStatus.pending, at: when)],
    cancellation: cancellation,
  );
}
