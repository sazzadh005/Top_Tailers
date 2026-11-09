# Requirement-to-screen checklist

Sources: SRS deck (v1.0), your enhancement brief, the existing v1 app. The SRS lists online payment,
measurements, reviews, coupons and delivery tracking as **out of scope for v1.0** and names them under
"Future enhancements". They are built here because the enhancement brief asks for them explicitly.
Every other SRS rule (5 order statuses, cancellation rules, no delivery charge, two roles) is kept.

Status key: DONE = implemented in the frontend with mock data; BACKEND = needs the future backend to be real.

## Preserved from v1 (regression list)

| Existing feature | Where | Notes |
|---|---|---|
| Login / register / forgot password | `screens/auth/*` | Same flow; register gained optional measurements |
| Role-based home (customer / admin) | `main.dart` `AuthGate` | Demo convenience; not security |
| Product search (name, description, category) + category filter + clear | `CatalogProvider`, `shop_screen.dart` | Same matching; product code added; now debounced and paged |
| Cart add / quantity / remove | `CartProvider`, `cart_screen.dart` | Lines are now per variant |
| Checkout with address, place order, cart kept on failure | `checkout_screen.dart` | Extended |
| Customer cancel only while Pending; admin Pending/Confirmed | `AppOrder`, `MockOrderRepository` | Reason now required |
| Admin status flow Pending > Confirmed > Processing > Completed | `OrderDetailScreen` | Unchanged |
| Notifications with unread badge | `notifications_screen.dart` | 30-day retention added |
| Profile edit incl. photo | `edit_profile_screen.dart` | Unchanged |
| Admin product CRUD + image | `admin_products_screen.dart`, `product_form_screen.dart` | Extended |
| Admin customer list | `admin_customers_screen.dart` | Extended |

## Enhancement brief

| # | Requirement | Screen / code | Status |
|---|---|---|---|
| 4 | Home: banner, categories, featured fabrics, tailoring services, popular, discounted, offers, search, recently viewed | `home_screen.dart` | DONE |
| 4 | Product cards: image, name, code, original+discounted price, badge, variants, availability, wishlist, cart action | `widgets/product_widgets.dart` | DONE (no photos exist, so generated fabric swatches are shown until images are uploaded) |
| 4 | Product details: gallery, code, specs, colours, length/quantity, availability, feedback, add to cart | `product_detail_screen.dart` | DONE |
| 4 | Cart and checkout visuals, breakdown, clear cart, recommendations | `cart_screen.dart`, `checkout_screen.dart` | DONE |
| 5 | Lazy loading / pagination | `CatalogProvider.loadMore`, `ProductQuery.page` | DONE (mock pages; API-shaped) |
| 6 | Separate customer and admin interfaces | `customer_shell.dart`, `admin_shell.dart` | DONE; BACKEND enforces authorization |
| 7 | Registration/profile with name, mobile, address, measurements | `register_screen.dart`, `edit_profile_screen.dart`, `measurements_screen.dart` | DONE |
| 8 | Measurements: registration, profile, admin, checkout; order snapshot; saved vs order vs other person | `measurement_form.dart`, `checkout_screen.dart`, `admin_customer_detail_screen.dart` | DONE |
| 9 | Unique product codes, admin search by code, duplicate rejection | `product_form_screen.dart`, `MockCatalogRepository` | DONE; BACKEND enforces uniqueness |
| 10 | Product discounts (fixed/percent), preview, validation, badges everywhere | `discount_editor.dart`, `discounts_screen.dart`, `DiscountMath` | DONE |
| 11 | Customer-specific discounts | `customer_discount_sheet.dart`, `CustomerDiscountRules` | DONE; BACKEND validates eligibility |
| 12 | Customer detail: ID, contacts, orders, measurements, discount, Lifetime Spending | `admin_customer_detail_screen.dart`, `SpendingCalculator` | DONE (mock figure) |
| 13 | Order search for customers and admins with filters | `orders_screen.dart`, `OrderSearch` | DONE; BACKEND enforces scope |
| 14 | Cart | `cart_screen.dart` | DONE |
| 15 | Vouchers apply/remove, messages, separate discount line | `voucher_panel.dart`, `VoucherRules` | DONE (mock vouchers) |
| 16 | Per-order contact number | `checkout_screen.dart`, `AppOrder.contactPhone` | DONE |
| 17 | COD + Online payment, payment states | `online_payment_screen.dart`, `AamarPayGateway`, EF `payments-*` (demo: `payment_demo_screen.dart`) | DONE in code and tests; live sandbox run still to do (see TEST_REPORT) |
| 18 | Customer and admin order screens | `orders_screen.dart`, `order_detail_screen.dart` | DONE |
| 19 | Cancellation with reason, actor, timestamp; permanent record | `cancel_order_sheet.dart`, `CancellationRecord` | DONE |
| 20 | Status timeline separate from payment status | `order_detail_screen.dart` | DONE, SRS statuses only |
| 21 | Feedback after receiving an order, restricted and de-duplicated | `feedback_sheet.dart`, `MockFeedbackRepository` | DONE |
| 22 | Suggestions and restock requests + admin review | `requests_screen.dart`, `admin_inbox_screen.dart` | DONE |
| 23 | Notifications, 30-day retention | `NotificationRetention`, `notifications_screen.dart` | DONE (hiding, not deletion) |
| 24 | Wishlist, recently viewed, sort/filter, order notes | `wishlist_screen.dart`, `shop_screen.dart`, `checkout_screen.dart` | DONE |
| 25 | One pricing structure everywhere, integer money | `domain/pricing.dart`, `core/money.dart` | DONE |
| 26 | Backend-ready architecture | `repositories/`, `data/mock/`, `app/app_services.dart` | DONE |

Not built (with reasons)
- Tailoring-service pricing beyond the single seeded price per service: the SRS gives no price list.
- Delivery charge: the SRS defines none, so the policy exists (`DeliveryPolicy`) but charges nothing.
- Refunds and partial refunds: the SRS defines no refund rules; Lifetime Spending subtracts nothing.
- Cancellation-approval workflow: the SRS cancels directly; no approval step was added.
- Extra order statuses (ready for dispatch, shipped): not in the SRS; the 5 SRS statuses are used.
- "Verified purchase" label: not shown; production verification belongs to the backend.
- Review moderation: not required by the SRS; reviews publish immediately in the mock.

## Stacking rules (defined here because the SRS has none)

1. A product discount lowers that line's own price.
2. Vouchers and customer discounts ignore any line that already has a product discount.
3. A customer discount and a voucher never stack: only the larger applies (tie goes to the customer discount); the cart explains why a voucher was not used.
4. Percent discounts are whole percents 1-99, rounded down to the paisa. Fixed discounts must be below the price. A discount never exceeds the amount it applies to.
