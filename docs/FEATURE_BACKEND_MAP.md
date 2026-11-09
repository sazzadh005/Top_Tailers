# Feature -> backend map

Every row is implemented in the backend and covered by an automated test unless marked.
SQL = `backend/supabase/migrations`, EF = `backend/supabase/functions`, tests in `backend/tests`.

| Feature | Backend piece | Verified by |
|---|---|---|
| Register / login / logout, session restore | Supabase Auth + trigger `handle_new_user` (role is always `customer`) | `security`, `orders` suites; Dart repo unverified on device |
| Admins only by provisioning | `provision_admin` (service role only) | `security` |
| Role escalation impossible | `profiles_guard`, no UPDATE grant, RLS | `security` |
| Profile + photo | `update_my_profile`, image URL/folder checks | `security` |
| Saved measurements (private) | `set_measurements`, ranges validated | `security`, `orders` |
| Product catalogue, search, sort, paging, home shelves | `search_products`, `get_products_by_ids`, `get_home` | `catalog` |
| Unique product codes (case-insensitive, reserved after delete) | unique index + `admin_save_product` | `catalog` |
| Product CRUD (admin), soft delete | `admin_save_product`, `admin_delete_product` | `catalog`, `security` |
| Product discounts (percent 1-99, fixed < price) | check constraint + function | `catalog`, `pricing` |
| Customer discounts | `admin_save_customer_discount`, `my_customer_discount` | `pricing` |
| Vouchers (rate-limited lookup) | `get_voucher`, `admin_save_voucher` | `pricing`, `security` |
| One shared pricing function (quote = charge) | `compute_pricing` <- `quote_pricing`, `place_order` | `pricing`, `orders` |
| Atomic checkout, server recalculation, price-change detection | `place_order` | `orders` |
| Idempotent order placement (retry-safe) | `idempotency_keys`, advisory lock | `orders`, Dart provider test |
| Contact/address/measurement snapshots, immutable history | order tables + triggers | `orders` |
| Status machine (Pending>Confirmed>Processing>Completed) | `update_order_status`, `orders_guard` | `orders` |
| Cancellation (reason, who/when, rules) | `cancel_order`, `cancellations` | `orders`, `payments` |
| Order search (scope by caller) | `search_orders` | `orders` |
| Lifetime spending (Completed + paid, once) | `admin_list_customers` | `orders`, Dart contract test |
| AamarPay start (amount from DB) | `start_payment_attempt` + EF `payments-initiate` | `payments`, `payments_e2e` |
| AamarPay verify + record (idempotent, mismatch-safe) | EF `payments-callback` + `record_payment_result` | `payments`, `payments_e2e` |
| Cancel/fail/expire handling, duplicate/late payments flagged | `record_payment_*`, `needs_review` | `payments`, `payments_e2e` |
| Signed Cloudinary uploads (admin products / own avatar) | EF `cloudinary-sign` | `cloudinary.test.ts` |
| Orphaned/replaced image cleanup | tickets, queue, EF `cloudinary-cleanup` | `uploads`, `cloudinary.test.ts` |
| Feedback (Completed order, once per item, first names) | `submit_feedback`, `feedback_for_product` | `engagement` |
| Suggestions and restock requests (+ admin status) | `submit_*`, `set_*_status` | `engagement` |
| Notifications, 30-day window (exactly 30 days visible) | `visible_notifications`, `purge_old_notifications`, RLS | `engagement` |
| Wishlist | table + RLS | `security` |
| Dev seed | `supabase/seed.sql` | `seed` |
| App <-> backend field/parameter agreement | `tools/contract_check.py`, `test/fixtures` | contract check, Dart mapper tests (Dart unrun) |

Not covered by an automated test: push notifications (not built), email delivery, refunds (undefined in the SRS; flagged for manual handling).
