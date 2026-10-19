import '../../domain/discount.dart';
import '../../domain/pricing.dart';
import '../../models/app_notification.dart';
import '../../models/app_user.dart';
import '../../models/cancellation.dart';
import '../../models/customer_discount.dart';
import '../../models/feedback.dart';
import '../../models/measurements.dart';
import '../../models/order.dart';
import '../../models/payment.dart';
import '../../models/product.dart';
import '../../models/requests.dart';
import '../../models/voucher.dart';
import 'mock_store.dart';

// Demo credentials (frontend demonstration only, NOT secure authentication):
//   admin@toptailers.com  / Admin@123
//   customer@example.com  / Customer@123   (Rahim)
//   nusrat@example.com    / Customer@123   (has a customer discount)
//   tanvir@example.com    / Customer@123

const _white = FabricColor(name: 'White', argb: 0xFFF4F1EA);
const _skyBlue = FabricColor(name: 'Sky Blue', argb: 0xFF9CC3E4);
const _sand = FabricColor(name: 'Sand', argb: 0xFFD8C3A0);
const _maroon = FabricColor(name: 'Maroon', argb: 0xFF7B1E3A);
const _emerald = FabricColor(name: 'Emerald', argb: 0xFF1F7A5C);
const _gold = FabricColor(name: 'Gold', argb: 0xFFC9A24B);
const _charcoal = FabricColor(name: 'Charcoal', argb: 0xFF3D3F44);
const _navy = FabricColor(name: 'Navy', argb: 0xFF1E2D52);
const _ivory = FabricColor(name: 'Ivory', argb: 0xFFEFE6D2);
const _olive = FabricColor(name: 'Olive', argb: 0xFF6B6F3A);
const _wine = FabricColor(name: 'Wine', argb: 0xFF5B1730);
const _midnight = FabricColor(name: 'Midnight', argb: 0xFF14182B);
const _check = FabricColor(name: 'Blue Check', argb: 0xFF6E8FB5);
const _cream = FabricColor(name: 'Cream', argb: 0xFFF1E7CF);
const _black = FabricColor(name: 'Black', argb: 0xFF1E1E1E);
const _grey = FabricColor(name: 'Grey', argb: 0xFF8A8D91);
const _lightBlue = FabricColor(name: 'Light Blue', argb: 0xFFB9D3EA);

const _sizes = ['S', 'M', 'L', 'XL'];

void seedMockData(MockStore s) {
  final now = s.now();
  DateTime ago(int days, [int hours = 0]) =>
      now.subtract(Duration(days: days, hours: hours));

  // ------------------------------------------------------------------ users
  const adminId = 'u1';
  const rahimId = 'u2';
  const nusratId = 'u3';
  const tanvirId = 'u4';

  s.users.addAll([
    AppUser(
      id: adminId,
      name: 'Shop Administrator',
      email: 'admin@toptailers.com',
      phone: '01800000000',
      address: 'Top Tailers & Fabrics, Main Road, Gazipur',
      role: UserRole.admin,
      createdAt: ago(120),
    ),
    AppUser(
      id: rahimId,
      name: 'Rahim Uddin',
      email: 'customer@example.com',
      phone: '01712345678',
      address: 'House 12, Road 4, Gazipur Sadar, Gazipur',
      role: UserRole.customer,
      createdAt: ago(90),
      measurements: const BodyMeasurements({
        MeasurementField.neck: 38,
        MeasurementField.chest: 98,
        MeasurementField.shoulder: 44,
        MeasurementField.sleeveLength: 62,
        MeasurementField.waist: 86,
        MeasurementField.shirtLength: 74,
      }),
    ),
    AppUser(
      id: nusratId,
      name: 'Nusrat Jahan',
      email: 'nusrat@example.com',
      phone: '01911223344',
      address: 'Flat 3B, Sunrise Tower, Tongi, Gazipur',
      role: UserRole.customer,
      createdAt: ago(60),
      measurements: const BodyMeasurements({
        MeasurementField.chest: 88,
        MeasurementField.waist: 72,
        MeasurementField.hip: 96,
      }),
    ),
    AppUser(
      id: tanvirId,
      name: 'Tanvir Ahmed',
      email: 'tanvir@example.com',
      phone: '01611998877',
      address: 'Block C, House 7, Konabari, Gazipur',
      role: UserRole.customer,
      createdAt: ago(25),
    ),
  ]);
  s.passwords[adminId] = 'Admin@123';
  for (final id in [rahimId, nusratId, tanvirId]) {
    s.passwords[id] = 'Customer@123';
  }

  // --------------------------------------------------------------- products
  Product p(
    String id,
    String code,
    String name,
    String desc,
    int takaPrice,
    String category, {
    bool available = true,
    List<FabricColor> colors = const [],
    List<String> sizes = const [],
    Map<String, String> specs = const {},
    bool featured = false,
    int popularity = 0,
    String unit = 'piece',
    bool measure = false,
    ProductDiscount? discount,
    int createdDaysAgo = 30,
  }) {
    return Product(
      id: id,
      code: code,
      productName: name,
      description: desc,
      priceMinor: takaPrice * 100,
      category: category,
      availability: available,
      colors: colors,
      sizes: sizes,
      specs: specs,
      isFeatured: featured,
      popularity: popularity,
      unit: unit,
      requiresMeasurements: measure,
      discount: discount,
      createdAt: ago(createdDaysAgo),
    );
  }

  s.products.addAll([
    p('p1', 'FAB-COT-001', 'Premium Cotton Fabric',
        'Soft, breathable cotton for shirts, panjabis and everyday wear. Easy to stitch and comfortable in warm weather.',
        450, 'Fabrics',
        colors: const [_white, _skyBlue, _sand],
        specs: const {'Material': '100% cotton', 'Width': '44 in', 'Care': 'Machine wash cold'},
        featured: true, popularity: 90, unit: 'yard',
        discount: const ProductDiscount(enabled: true, kind: DiscountKind.percent, value: 10),
        createdDaysAgo: 40),
    p('p2', 'FAB-SLK-002', 'Silk Blend Fabric',
        'A smooth silk blend with a gentle sheen, ideal for festive wear and formal occasions.',
        1200, 'Fabrics',
        colors: const [_maroon, _emerald, _gold],
        specs: const {'Material': 'Silk blend', 'Width': '45 in', 'Care': 'Dry clean'},
        featured: true, popularity: 70, unit: 'yard', createdDaysAgo: 20),
    p('p3', 'FAB-WOL-003', 'Wool Suiting Fabric',
        'Fine wool suiting with a crisp drape for blazers, trousers and waistcoats.',
        1800, 'Fabrics',
        colors: const [_charcoal, _navy],
        specs: const {'Material': 'Wool blend', 'Width': '58 in', 'Care': 'Dry clean'},
        featured: true, popularity: 60, unit: 'yard',
        discount: const ProductDiscount(enabled: true, kind: DiscountKind.fixed, value: 20000),
        createdDaysAgo: 15),
    p('p4', 'FAB-LIN-004', 'Linen Shirt Fabric',
        'Lightweight linen that stays cool in warm weather, with a relaxed natural texture.',
        650, 'Fabrics',
        colors: const [_ivory, _olive],
        specs: const {'Material': 'Linen', 'Width': '54 in', 'Care': 'Machine wash cold'},
        featured: true, popularity: 85, unit: 'yard', createdDaysAgo: 10),
    p('p5', 'FAB-VEL-005', 'Velvet Fabric',
        'Deep-pile velvet for winter and wedding wear. Currently out of stock.',
        1500, 'Fabrics',
        available: false,
        colors: const [_wine, _midnight],
        specs: const {'Material': 'Polyester velvet', 'Width': '46 in'},
        popularity: 30, unit: 'yard', createdDaysAgo: 80),
    p('p6', 'FAB-CHK-006', 'Checked Shirting Fabric',
        'Classic checked shirting for casual and office shirts.',
        520, 'Fabrics',
        colors: const [_check],
        specs: const {'Material': 'Cotton blend', 'Width': '44 in'},
        popularity: 40, unit: 'yard',
        discount: const ProductDiscount(enabled: false, kind: DiscountKind.percent, value: 15),
        createdDaysAgo: 5),
    p('p7', 'RDY-SHT-101', "Men's Formal Shirt",
        'Ready-made formal shirt in a tailored fit with reinforced stitching.',
        1450, 'Readymade',
        colors: const [_white, _lightBlue], sizes: _sizes,
        specs: const {'Fit': 'Tailored', 'Material': 'Cotton blend'},
        popularity: 80,
        discount: const ProductDiscount(enabled: true, kind: DiscountKind.percent, value: 15),
        createdDaysAgo: 35),
    p('p8', 'RDY-PNJ-102', 'Cotton Panjabi',
        'Classic cotton panjabi with hand-finished collar detail, comfortable for daily and festive wear.',
        1800, 'Readymade',
        colors: const [_cream, _navy], sizes: _sizes,
        specs: const {'Material': 'Cotton', 'Care': 'Machine wash cold'},
        featured: true, popularity: 95, createdDaysAgo: 28),
    p('p9', 'RDY-TRS-103', 'Formal Trousers',
        'Straight-cut formal trousers with a clean finish.',
        1650, 'Readymade',
        colors: const [_black, _grey], sizes: _sizes,
        specs: const {'Fit': 'Straight', 'Material': 'Poly-viscose'},
        popularity: 55, createdDaysAgo: 18),
    p('p10', 'TLR-SHT-201', 'Shirt Stitching Service',
        'Professional stitching of your fabric into a shirt by our tailors. Body measurements are required.',
        800, 'Tailoring',
        specs: const {'Service': 'Shirt stitching', 'Fabric': 'Your own or bought here'},
        popularity: 75, unit: 'service', measure: true, featured: true, createdDaysAgo: 50),
    p('p11', 'TLR-PNJ-202', 'Panjabi Stitching Service',
        'Custom panjabi stitching to your measurements.',
        1200, 'Tailoring',
        specs: const {'Service': 'Panjabi stitching', 'Fabric': 'Your own or bought here'},
        popularity: 65, unit: 'service', measure: true, createdDaysAgo: 50),
    p('p12', 'TLR-TRS-203', 'Trouser Stitching Service',
        'Custom trouser stitching to your measurements.',
        900, 'Tailoring',
        specs: const {'Service': 'Trouser stitching', 'Fabric': 'Your own or bought here'},
        popularity: 50, unit: 'service', measure: true, createdDaysAgo: 50),
    p('p13', 'TLR-ALT-204', 'Alteration Service',
        'Resizing and fit adjustments for an existing garment.',
        300, 'Tailoring',
        specs: const {'Service': 'Alteration'},
        popularity: 45, unit: 'service', measure: true, createdDaysAgo: 50),
    p('p14', 'ACC-BTN-301', 'Button & Thread Set',
        'Assorted buttons and matching threads for repairs and finishing touches.',
        250, 'Accessories', popularity: 35, createdDaysAgo: 60),
    p('p15', 'ACC-TAP-302', 'Measuring Tape',
        'Soft 150 cm tailor measuring tape, handy for taking your own measurements.',
        180, 'Accessories', popularity: 25, createdDaysAgo: 60),
  ]);

  // ---------------------------------------------------------------- vouchers
  s.vouchers.addAll([
    Voucher(
      code: 'DEMO10',
      title: 'Demo: 10% off eligible items',
      kind: DiscountKind.percent,
      value: 10,
      expiresAt: now.add(const Duration(days: 60)),
      isPublic: true,
    ),
    Voucher(
      code: 'DEMOFAB15',
      title: 'Demo: 15% off fabrics',
      kind: DiscountKind.percent,
      value: 15,
      categories: const {'Fabrics'},
      expiresAt: now.add(const Duration(days: 60)),
      isPublic: true,
    ),
    Voucher(
      code: 'DEMOFLAT100',
      title: 'Demo: BDT 100 off',
      kind: DiscountKind.fixed,
      value: 10000,
      expiresAt: now.add(const Duration(days: 60)),
    ),
    Voucher(
      code: 'DEMOEXPIRED',
      title: 'Demo: expired voucher',
      kind: DiscountKind.percent,
      value: 20,
      expiresAt: now.subtract(const Duration(days: 1)),
    ),
    const Voucher(
      code: 'DEMOOFF',
      title: 'Demo: inactive voucher',
      kind: DiscountKind.percent,
      value: 5,
      isActive: false,
    ),
  ]);

  // ------------------------------------------------- customer-specific discounts
  s.customerDiscounts[nusratId] = CustomerDiscount(
    customerId: nusratId,
    kind: DiscountKind.percent,
    value: 8,
    active: true,
    note: 'Demo: regular customer',
    updatedAt: ago(20),
  );
  s.customerDiscounts[tanvirId] = CustomerDiscount(
    customerId: tanvirId,
    kind: DiscountKind.fixed,
    value: 5000,
    active: false,
    note: 'Demo: inactive',
    updatedAt: ago(10),
  );

  // ------------------------------------------------------------------ orders
  AppOrder order({
    required String id,
    required AppUser user,
    required String phone,
    required List<List<Object?>> lines, // [productId, qty, color?, size?]
    required int daysAgo,
    required OrderStatus status,
    required PaymentMethod method,
    required PaymentStatus payStatus,
    String? voucherCode,
    String? address,
    String note = '',
    OrderMeasurementSnapshot? measurements,
    CancellationRecord? cancellation,
  }) {
    final items = <OrderItem>[];
    final priced = <PricedLine>[];
    for (final l in lines) {
      final prod = s.productById(l[0]! as String)!;
      final qty = l[1]! as int;
      items.add(OrderItem(
        productId: prod.id,
        productCode: prod.code,
        productName: prod.productName,
        listUnitMinor: prod.priceMinor,
        unitMinor: prod.effectivePriceMinor,
        quantity: qty,
        category: prod.category,
        unit: prod.unit,
        colorName: l.length > 2 ? l[2] as String? : null,
        size: l.length > 3 ? l[3] as String? : null,
      ));
      priced.add(PricedLine(
        category: prod.category,
        listUnitMinor: prod.priceMinor,
        unitMinor: prod.effectivePriceMinor,
        quantity: qty,
      ));
    }
    Voucher? voucher;
    for (final v in s.vouchers) {
      if (v.code == voucherCode) voucher = v;
    }
    final custDiscount = s.customerDiscounts[user.id];
    final b = PricingService.compute(
      priced,
      voucher: voucher,
      customerDiscount: custDiscount,
      now: ago(daysAgo),
    );

    final placed = ago(daysAgo);
    final history = <OrderEvent>[OrderEvent(status: OrderStatus.pending, at: placed)];
    final flow = [
      OrderStatus.confirmed,
      OrderStatus.processing,
      OrderStatus.completed,
    ];
    if (status == OrderStatus.cancelled) {
      history.add(OrderEvent(
        status: OrderStatus.cancelled,
        at: cancellation?.cancelledAt ?? placed.add(const Duration(hours: 3)),
      ));
    } else {
      var step = 1;
      for (final st in flow) {
        if (status.index >= st.index) {
          history.add(OrderEvent(status: st, at: placed.add(Duration(hours: 6 * step))));
          step++;
        }
      }
    }

    return AppOrder(
      id: id,
      reference: s.mockReference(id, placed),
      userId: user.id,
      customerName: user.name,
      contactPhone: phone,
      shippingAddress: address ?? user.address,
      note: note,
      measurements: measurements,
      items: items,
      subtotalMinor: b.subtotalMinor,
      productDiscountMinor: b.productDiscountMinor,
      customerDiscountMinor: b.customerDiscountMinor,
      voucherDiscountMinor: b.voucherDiscountMinor,
      deliveryMinor: b.deliveryMinor,
      totalMinor: b.totalMinor,
      voucherCode: b.voucherCode,
      payment: PaymentRecord(
        id: 'PAY-$id',
        method: method,
        status: payStatus,
        amountMinor: b.totalMinor,
        provider: method == PaymentMethod.cod ? PaymentProvider.none : PaymentProvider.demo,
        updatedAt: placed.add(const Duration(hours: 1)),
      ),
      status: status,
      orderDate: placed,
      history: history,
      cancellation: cancellation,
    );
  }

  final rahim = s.users[1];
  final nusrat = s.users[2];
  final tanvir = s.users[3];

  s.orders.addAll([
    order(
      id: 'ORD-1001', user: rahim, phone: '01712345678', daysAgo: 12,
      lines: [['p1', 3, 'White', null]],
      status: OrderStatus.completed, method: PaymentMethod.cod,
      payStatus: PaymentStatus.successful,
    ),
    order(
      id: 'ORD-1002', user: rahim, phone: '01898765432', daysAgo: 1,
      lines: [['p8', 1, 'Cream', 'M'], ['p14', 2, null, null]],
      status: OrderStatus.pending, method: PaymentMethod.online,
      payStatus: PaymentStatus.pending,
      note: 'Please call before delivery.',
    ),
    order(
      id: 'ORD-1003', user: rahim, phone: '01712345678', daysAgo: 3,
      lines: [['p10', 1, null, null]],
      status: OrderStatus.processing, method: PaymentMethod.online,
      payStatus: PaymentStatus.successful,
      measurements: OrderMeasurementSnapshot(
        measurements: const BodyMeasurements({
          MeasurementField.neck: 40,
          MeasurementField.chest: 104,
          MeasurementField.shoulder: 46,
          MeasurementField.sleeveLength: 64,
          MeasurementField.shirtLength: 76,
        }),
        source: MeasurementSource.otherPerson,
        forPerson: 'Karim (brother)',
        capturedAt: ago(3),
      ),
    ),
    order(
      id: 'ORD-1009', user: rahim, phone: '01712345678', daysAgo: 30,
      lines: [['p3', 2, 'Navy', null]],
      status: OrderStatus.completed, method: PaymentMethod.online,
      payStatus: PaymentStatus.successful,
    ),
    order(
      id: 'ORD-1004', user: nusrat, phone: '01911223344', daysAgo: 20,
      lines: [['p2', 2, 'Maroon', null]],
      status: OrderStatus.completed, method: PaymentMethod.cod,
      payStatus: PaymentStatus.successful,
    ),
    order(
      id: 'ORD-1005', user: nusrat, phone: '01955667788', daysAgo: 2,
      lines: [['p4', 4, 'Ivory', null]],
      status: OrderStatus.pending, method: PaymentMethod.online,
      payStatus: PaymentStatus.failed, voucherCode: 'DEMOFAB15',
    ),
    order(
      id: 'ORD-1006', user: tanvir, phone: '01611998877', daysAgo: 5,
      lines: [['p9', 1, 'Black', 'L']],
      status: OrderStatus.cancelled, method: PaymentMethod.cod,
      payStatus: PaymentStatus.pending,
      cancellation: CancellationRecord(
        cancelledBy: CancelActor.customer,
        cancelledByName: tanvir.name,
        reason: 'Ordered by mistake',
        cancelledAt: ago(5).add(const Duration(hours: 2)),
      ),
    ),
    order(
      id: 'ORD-1007', user: tanvir, phone: '01611998877', daysAgo: 8,
      lines: [['p7', 1, 'White', 'L']],
      status: OrderStatus.cancelled, method: PaymentMethod.cod,
      payStatus: PaymentStatus.pending,
      cancellation: CancellationRecord(
        cancelledBy: CancelActor.shopAdmin,
        cancelledByName: 'Shop Administrator',
        reason: 'Item out of stock',
        note: 'Size L sold out; customer informed by phone.',
        cancelledAt: ago(8).add(const Duration(hours: 9)),
      ),
    ),
    order(
      id: 'ORD-1008', user: tanvir, phone: '01744556677', daysAgo: 1,
      lines: [['p11', 1, null, null]],
      status: OrderStatus.confirmed, method: PaymentMethod.cod,
      payStatus: PaymentStatus.pending,
      address: 'Shop pickup arranged by phone',
      measurements: OrderMeasurementSnapshot(
        measurements: const BodyMeasurements({
          MeasurementField.chest: 96,
          MeasurementField.shoulder: 43,
          MeasurementField.sleeveLength: 60,
          MeasurementField.shirtLength: 100,
        }),
        source: MeasurementSource.enteredForOrder,
        capturedAt: ago(1),
      ),
    ),
  ]);

  // ---------------------------------------------------------------- feedback
  s.feedback.addAll([
    ProductFeedback(
      id: 'f1', orderId: 'ORD-1001', productId: 'p1',
      productName: 'Premium Cotton Fabric', userId: rahimId, userName: 'Rahim Uddin',
      rating: 5, comment: 'Soft fabric and true to the colour shown.',
      createdAt: ago(10),
    ),
    ProductFeedback(
      id: 'f2', orderId: 'ORD-1004', productId: 'p2',
      productName: 'Silk Blend Fabric', userId: nusratId, userName: 'Nusrat Jahan',
      rating: 4, comment: 'Lovely sheen. Slightly narrower than expected.',
      createdAt: ago(17),
    ),
  ]);

  // ---------------------------------------------- suggestions & restock requests
  s.suggestions.add(ProductSuggestion(
    id: 's1', userId: rahimId, userName: 'Rahim Uddin',
    title: 'Khadi cotton fabric',
    details: 'Please stock khadi cotton in natural shades for summer panjabis.',
    status: RequestStatus.underReview, createdAt: ago(6),
  ));
  s.restocks.add(RestockRequest(
    id: 'r1', userId: nusratId, userName: 'Nusrat Jahan',
    productId: 'p5', productCode: 'FAB-VEL-005', productName: 'Velvet Fabric',
    reason: 'Needed for a wedding outfit next month.',
    status: RequestStatus.received, createdAt: ago(2),
  ));

  // ----------------------------------------------------------- notifications
  void note(String id, String user, String title, String body, DateTime? at) {
    s.notifications.add(AppNotification(
      id: id, userId: user, title: title, body: body, createdAt: at,
    ));
  }

  note('n1', rahimId, 'Order placed', 'Your order ORD-1002 was received and is waiting for confirmation.', ago(1));
  note('n2', rahimId, 'Order Processing', 'Your order ORD-1003 is now Processing.', ago(2));
  note('n3', rahimId, 'Order Completed', 'Your order ORD-1001 is Completed. Share your feedback from the order page.', ago(10));
  note('n4', rahimId, 'New season fabrics', 'Linen and cotton arrivals are now in the shop.', ago(29));
  note('n5', rahimId, 'Older announcement (31 days)', 'This is older than 30 days and is hidden.', ago(31));
  note('n6', rahimId, 'Very old announcement (60 days)', 'This is hidden by the 30-day rule.', ago(60));
  s.notifications.add(const AppNotification(
    id: 'n7', userId: rahimId, title: 'Missing timestamp',
    body: 'A record without a usable timestamp is never shown.', createdAt: null,
  ));
  note('n8', nusratId, 'Order Completed', 'Your order ORD-1004 is Completed.', ago(19));
  note('n9', tanvirId, 'Order Confirmed', 'Your order ORD-1008 is now Confirmed.', ago(1));
}
