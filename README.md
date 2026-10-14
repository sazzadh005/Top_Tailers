# Top Tailers & Fabrics

Flutter (Android) frontend for the **Top Tailors & Fabrics Management System** SRS (v1.0).
Customers browse, order and track purchases; administrators manage products, customers and orders.

> **Backend status:** the SRS specifies Firebase (Auth, Firestore, Storage, FCM). No Firebase project or
> `google-services.json` was supplied, so this build runs on an **in-memory mock backend**
> (`lib/services/mock_backend.dart`). All screens, validation, cart logic and the order workflow are real;
> data resets when the app restarts. See "Connecting Firebase" below.

## Demo accounts

| Role      | Email                  | Password      |
|-----------|------------------------|---------------|
| Customer  | customer@example.com   | Customer@123  |
| Admin     | admin@toptailers.com   | Admin@123     |

The login screen has "Customer" / "Admin" chips that fill these in. Remove them before a production release.

## Run

```bash
flutter pub get
flutter analyze
flutter test
flutter run            # with an Android emulator running or a device connected
```

## SRS feature areas -> screens

| SRS area (slide 5)   | Implemented in |
|----------------------|----------------|
| 1. Account: register, log in, reset password, edit profile | `screens/auth/*`, `screens/shared/edit_profile_screen.dart`, `screens/shared/profile_screen.dart` |
| 2. Catalog: browse by category, search, details | `screens/customer/shop_screen.dart`, `product_detail_screen.dart` |
| 3. Cart & Orders: quantities, totals, checkout, status | `cart_screen.dart`, `checkout_screen.dart`, `order_success_screen.dart`, `screens/shared/orders_screen.dart`, `order_detail_screen.dart` |
| 4. Administration: products, images, customers, orders | `screens/admin/*` (products CRUD + image upload, customers list, orders with status updates) |
| 5. Notifications: order updates | `screens/shared/notifications_screen.dart` (in-app list + unread badge) |
| 6. Access control: rules by role | Role-based UI routing in `AuthGate` (`main.dart`); Firestore/Storage **rules are backend work** |

Order status flow (slide 9): Pending -> Confirmed -> Processing -> Completed, plus Cancelled.
Customers may cancel while Pending; admins may cancel Pending or Confirmed; every change creates a
notification for the customer.

Place-order use case (slide 10): cart review, total, Checkout, confirm address, Place Order, saved as
Pending, cart cleared, confirmation shown. On failure an error is shown and the cart is kept.

Out of scope per SRS (not built): online payment, delivery tracking, tailoring measurements, reviews,
coupons, invoices, sales dashboard.

## Structure

```
lib/
  core/        theme, validators, formatting, strings, error helper
  models/      AppUser, Product, CartItem, AppOrder/OrderStatus, AppNotification
  services/    mock_backend.dart  (swap for Firebase)
  providers/   auth, catalog, cart, orders (provider package)
  widgets/     shared UI pieces
  screens/     auth, customer, admin, shared
test/          validators, cart, order-status rules, app smoke test
```

## Connecting Firebase (remaining backend work)

Replace the method bodies in `MockBackend` with Firebase calls; providers and screens stay unchanged.

- `login/register/sendPasswordReset` -> Firebase Authentication
- `getProducts/addProduct/updateProduct/deleteProduct` -> Firestore `products`; `Product.imagePath` becomes a Storage URL
- `placeOrder/getOrders/cancelOrder/updateOrderStatus` -> Firestore `orders`
- `getCustomers/updateProfile` -> Firestore `users` (with `role`)
- notifications -> Cloud Messaging (`fcmToken` on `users`) plus a Cloud Function or admin client trigger
- Firestore and Storage security rules by role (customers see only their own data; only admins edit products and statuses)
