// Pure JSON <-> model mapping for the backend's RPC responses. No package
// dependencies, so it can be unit tested against fixtures captured from the
// real SQL functions (test/fixtures).
import '../../domain/discount.dart';
import '../../models/app_notification.dart';
import '../../models/app_user.dart';
import '../../models/cancellation.dart';
import '../../models/catalog_query.dart';
import '../../models/customer_discount.dart';
import '../../models/customer_summary.dart';
import '../../models/feedback.dart';
import '../../models/measurements.dart';
import '../../models/order.dart';
import '../../models/payment.dart';
import '../../models/product.dart';
import '../../models/requests.dart';
import '../../models/voucher.dart';

typedef Json = Map<String, dynamic>;

Json asJson(Object? v) => Map<String, dynamic>.from(v as Map);

List<Json> asJsonList(Object? v) =>
    [for (final e in (v as List? ?? const <Object?>[])) Map<String, dynamic>.from(e as Map)];

DateTime _dt(Object? v) => DateTime.parse(v as String).toLocal();
int _int(Object? v) => (v as num).toInt();
String? _str(Object? v) => v == null ? null : v as String;

DiscountKind _kind(Object? v) => DiscountKind.values.byName(v as String);

BodyMeasurements measurementsFromJson(Object? v) {
  if (v is! Map) return BodyMeasurements.empty;
  final out = <MeasurementField, double>{};
  for (final f in MeasurementField.values) {
    final raw = v[f.name];
    if (raw is num) out[f] = raw.toDouble();
  }
  return BodyMeasurements(out);
}

Json measurementsToJson(BodyMeasurements m) => {
      for (final e in m.values.entries) e.key.name: e.value,
    };

AppUser userFromJson(Json j) => AppUser(
      id: j['id'] as String,
      name: j['name'] as String,
      email: j['email'] as String,
      phone: (j['phone'] as String?) ?? '',
      address: (j['address'] as String?) ?? '',
      role: (j['role'] as String) == 'admin' ? UserRole.admin : UserRole.customer,
      createdAt: _dt(j['createdAt']),
      profileImage: _str(j['profileImage']),
      profileImagePublicId: _str(j['profileImagePublicId']),
      measurements: measurementsFromJson(j['measurements']),
    );

CustomerSummary customerSummaryFromJson(Json j) => CustomerSummary(
      user: userFromJson(j),
      orderCount: _int(j['orderCount']),
      lifetimeSpendingMinor: _int(j['lifetimeSpendingMinor']),
    );

Product productFromJson(Json j) {
  final d = j['discount'];
  return Product(
    id: j['id'] as String,
    code: j['code'] as String,
    productName: j['productName'] as String,
    description: (j['description'] as String?) ?? '',
    priceMinor: _int(j['priceMinor']),
    category: j['category'] as String,
    availability: j['availability'] as bool,
    imagePaths: [for (final u in (j['imagePaths'] as List? ?? const [])) u as String],
    imagePublicIds: [for (final u in (j['imagePublicIds'] as List? ?? const [])) u as String],
    colors: [
      for (final c in asJsonList(j['colors'])) FabricColor(name: c['name'] as String, argb: _int(c['argb'])),
    ],
    sizes: [for (final s in (j['sizes'] as List? ?? const [])) s as String],
    specs: {
      for (final e in ((j['specs'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}',
    },
    isFeatured: j['isFeatured'] as bool,
    popularity: _int(j['popularity']),
    unit: j['unit'] as String,
    requiresMeasurements: j['requiresMeasurements'] as bool,
    discount: d is Map
        ? ProductDiscount(
            enabled: d['enabled'] as bool,
            kind: _kind(d['kind']),
            value: _int(d['value']),
          )
        : null,
    createdAt: _dt(j['createdAt']),
  );
}

/// Body for admin_save_product. The server validates and normalises everything.
Json productToJson(Product p) => {
      if (p.id.isNotEmpty) 'id': p.id,
      'code': p.code,
      'productName': p.productName,
      'description': p.description,
      'priceMinor': p.priceMinor,
      'category': p.category,
      'availability': p.availability,
      'unit': p.unit,
      'requiresMeasurements': p.requiresMeasurements,
      'isFeatured': p.isFeatured,
      'popularity': p.popularity,
      'specs': p.specs,
      'discount': p.discount == null
          ? null
          : {'enabled': p.discount!.enabled, 'kind': p.discount!.kind.name, 'value': p.discount!.value},
      'imagePaths': p.imagePaths,
      'imagePublicIds': p.imagePublicIds,
      'colors': [
        for (final c in p.colors) {'name': c.name, 'argb': c.argb},
      ],
      'sizes': p.sizes,
    };

PageResult<Product> productPageFromJson(Json j) => PageResult<Product>(
      items: [for (final p in asJsonList(j['items'])) productFromJson(p)],
      page: _int(j['page']),
      hasMore: j['hasMore'] as bool,
      total: _int(j['total']),
    );

Voucher voucherFromJson(Json j) => Voucher(
      code: j['code'] as String,
      title: (j['title'] as String?) ?? j['code'] as String,
      kind: _kind(j['kind']),
      value: _int(j['value']),
      expiresAt: j['expiresAt'] == null ? null : _dt(j['expiresAt']),
      categories: {for (final c in (j['categories'] as List? ?? const [])) c as String},
      isActive: j['isActive'] as bool,
      isPublic: j['isPublic'] as bool,
    );

HomeContent homeFromJson(Json j) => HomeContent(
      banners: [
        for (final b in asJsonList(j['banners']))
          PromoBanner(
            id: b['id'] as String,
            title: b['title'] as String,
            subtitle: b['subtitle'] as String,
            colorArgb: _int(b['colorArgb']),
            category: _str(b['category']),
            voucherCode: _str(b['voucherCode']),
          ),
      ],
      featured: [for (final p in asJsonList(j['featured'])) productFromJson(p)],
      services: [for (final p in asJsonList(j['services'])) productFromJson(p)],
      popular: [for (final p in asJsonList(j['popular'])) productFromJson(p)],
      discounted: [for (final p in asJsonList(j['discounted'])) productFromJson(p)],
      offers: [for (final v in asJsonList(j['offers'])) voucherFromJson(v)],
    );

CustomerDiscount customerDiscountFromJson(Json j) => CustomerDiscount(
      customerId: j['customerId'] as String,
      kind: _kind(j['kind']),
      value: _int(j['value']),
      active: j['active'] as bool,
      note: (j['note'] as String?) ?? '',
      updatedAt: _dt(j['updatedAt']),
    );

AppOrder orderFromJson(Json j) {
  final pay = asJson(j['payment']);
  final m = j['measurements'];
  final c = j['cancellation'];
  return AppOrder(
    id: j['id'] as String,
    reference: j['reference'] as String,
    userId: j['userId'] as String,
    customerName: j['customerName'] as String,
    contactPhone: j['contactPhone'] as String,
    shippingAddress: j['shippingAddress'] as String,
    note: (j['note'] as String?) ?? '',
    measurements: m is Map
        ? OrderMeasurementSnapshot(
            measurements: measurementsFromJson(m['values']),
            source: MeasurementSource.values.byName(m['source'] as String),
            forPerson: _str(m['forPerson']),
            capturedAt: _dt(m['capturedAt']),
          )
        : null,
    items: [
      for (final i in asJsonList(j['items']))
        OrderItem(
          productId: _str(i['productId']) ?? '',
          productCode: i['productCode'] as String,
          productName: i['productName'] as String,
          listUnitMinor: _int(i['listUnitMinor']),
          unitMinor: _int(i['unitMinor']),
          quantity: _int(i['quantity']),
          imagePath: _str(i['imagePath']),
          category: (i['category'] as String?) ?? '',
          unit: (i['unit'] as String?) ?? 'piece',
          colorName: _str(i['colorName']),
          size: _str(i['size']),
        ),
    ],
    subtotalMinor: _int(j['subtotalMinor']),
    productDiscountMinor: _int(j['productDiscountMinor']),
    customerDiscountMinor: _int(j['customerDiscountMinor']),
    voucherDiscountMinor: _int(j['voucherDiscountMinor']),
    deliveryMinor: _int(j['deliveryMinor']),
    totalMinor: _int(j['totalMinor']),
    voucherCode: _str(j['voucherCode']),
    payment: PaymentRecord(
      id: pay['id'] as String,
      method: PaymentMethod.values.byName(pay['method'] as String),
      status: PaymentStatus.values.byName(pay['status'] as String),
      amountMinor: _int(pay['amountMinor']),
      provider: PaymentProvider.values.byName(pay['provider'] as String),
      transactionRef: _str(pay['transactionRef']),
      updatedAt: _dt(pay['updatedAt']),
    ),
    status: OrderStatus.values.byName(j['status'] as String),
    orderDate: _dt(j['orderDate']),
    history: [
      for (final e in asJsonList(j['history']))
        OrderEvent(status: OrderStatus.values.byName(e['status'] as String), at: _dt(e['at'])),
    ],
    cancellation: c is Map
        ? CancellationRecord(
            cancelledBy: CancelActor.values.byName(c['cancelledBy'] as String),
            cancelledByName: c['cancelledByName'] as String,
            reason: c['reason'] as String,
            note: (c['note'] as String?) ?? '',
            cancelledAt: _dt(c['cancelledAt']),
          )
        : null,
  );
}

/// Body for place_order. Prices are deliberately absent: the server recomputes
/// them and only compares against [PlaceOrderRequest.expectedTotalMinor].
Json orderRequestToJson(PlaceOrderRequest r) => {
      'contactPhone': r.contactPhone,
      'shippingAddress': r.shippingAddress,
      'note': r.note,
      'voucherCode': r.voucherCode,
      'paymentMethod': r.paymentMethod.name,
      'expectedTotalMinor': r.expectedTotalMinor,
      'items': [
        for (final i in r.items)
          {
            'productId': i.productId,
            'quantity': i.quantity,
            if (i.colorName != null) 'colorName': i.colorName,
            if (i.size != null) 'size': i.size,
          },
      ],
      'measurements': r.measurements == null
          ? null
          : {
              'source': r.measurements!.source.name,
              if (r.measurements!.forPerson != null) 'forPerson': r.measurements!.forPerson,
              'values': measurementsToJson(r.measurements!.measurements),
            },
    };

ProductFeedback feedbackFromJson(Json j) => ProductFeedback(
      id: j['id'] as String,
      orderId: j['orderId'] as String,
      productId: j['productId'] as String,
      productName: j['productName'] as String,
      userId: (j['userId'] as String?) ?? '',
      userName: (j['userName'] as String?) ?? '',
      rating: _int(j['rating']),
      comment: j['comment'] as String,
      createdAt: _dt(j['createdAt']),
    );

ProductSuggestion suggestionFromJson(Json j) => ProductSuggestion(
      id: j['id'] as String,
      userId: j['userId'] as String,
      userName: (j['userName'] as String?) ?? '',
      title: j['title'] as String,
      details: (j['details'] as String?) ?? '',
      status: RequestStatus.values.byName(j['status'] as String),
      createdAt: _dt(j['createdAt']),
    );

RestockRequest restockFromJson(Json j) => RestockRequest(
      id: j['id'] as String,
      userId: j['userId'] as String,
      userName: (j['userName'] as String?) ?? '',
      productId: j['productId'] as String,
      productCode: (j['productCode'] as String?) ?? '',
      productName: (j['productName'] as String?) ?? '',
      reason: (j['reason'] as String?) ?? '',
      status: RequestStatus.values.byName(j['status'] as String),
      createdAt: _dt(j['createdAt']),
    );

AppNotification notificationFromJson(Json j) => AppNotification(
      id: j['id'] as String,
      userId: j['userId'] as String,
      title: j['title'] as String,
      body: (j['body'] as String?) ?? '',
      createdAt: j['createdAt'] == null ? null : _dt(j['createdAt']),
      read: j['read'] == true,
    );

/// Date-only text (YYYY-MM-DD) for the server's order-search date filters.
String? dateOnly(DateTime? d) => d == null
    ? null
    : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
