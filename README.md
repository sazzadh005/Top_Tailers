# Top Tailers & Fabrics

Flutter (Android) app for a tailoring and fabrics shop: customer shopping and a Shop Admin area.
Frontend phase: everything runs on **in-memory mock data**; no backend, database or live payment exists yet.

- Requirement-to-screen checklist and discount stacking rules: `docs/REQUIREMENTS_CHECKLIST.md`
- What the backend must still do: `docs/BACKEND_INTEGRATION.md`

## Demo accounts (frontend demonstration only, not secure authentication)

| Role | Email | Password | Notes |
|---|---|---|---|
| Customer | customer@example.com | Customer@123 | Rahim: measurements, orders in most states |
| Customer | nusrat@example.com | Customer@123 | Has an active 8% customer discount |
| Customer | tanvir@example.com | Customer@123 | Cancelled orders (by customer and by admin) |
| Shop Admin | admin@toptailers.com | Admin@123 | |

Demonstration vouchers: `DEMO10` (10%), `DEMOFAB15` (15%, fabrics only), `DEMOFLAT100` (fixed),
`DEMOEXPIRED` (expired), `DEMOOFF` (inactive). They exist only in mock data.

## Run

```bash
flutter pub get
flutter analyze
flutter test
flutter run            # emulator running or device connected
```

No new packages were added in this phase (`provider` and `image_picker` as before).

## Architecture

```
lib/
  core/          theme, money (integer paisa), formatting, validators
  models/        Product, CartItem, AppOrder (+snapshots), PaymentRecord, CancellationRecord, ...
  domain/        pure rules: pricing + stacking, discounts, spending, notification retention, order search
  repositories/  interfaces the UI depends on (the backend seam)
  data/mock/     in-memory store, seed data, mock repositories, demo payment gateway
  app/           AppServices: the one place data sources are chosen
  providers/     state (provider package); no business rules inside widgets
  widgets/       shared UI (product cards, price breakdown, voucher panel, measurement form, ...)
  screens/       auth, customer, admin, shared
test/            pricing, vouchers, discounts, retention, search, spending, snapshots, cancellation, payments, providers
```

Key decisions
- Money is an integer number of paisa everywhere; there is no floating-point money.
- Orders own snapshots of contact number, address, note, measurements, prices and voucher; editing a profile never changes them.
- Online payment is a labelled demonstration. `PaymentGateway` is the seam for a future SSLCommerz integration via the backend.
- Role-based screens are a convenience; real authorization belongs to the backend.
