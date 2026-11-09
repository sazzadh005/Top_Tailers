# Top Tailers & Fabrics

Flutter (Android) app for a tailoring and fabrics shop: customer shopping and a Shop Admin area.
The app runs against a real **Supabase** backend (Postgres + Auth + Edge Functions) with **AamarPay** payments
and **Cloudinary** images. An opt-in in-memory demo mode remains for offline demonstrations.

## Run it

```bash
# real backend (after following docs/BACKEND_SETUP.md)
flutter pub get
flutter run --dart-define=SUPABASE_URL=https://<ref>.supabase.co --dart-define=SUPABASE_ANON_KEY=<anon key>

# offline demo with sample data (shows a DEMO DATA banner)
flutter run --dart-define=USE_MOCK_DATA=true
```
With neither, the app shows a "Backend not configured" screen rather than pretending to have data.
`flutter analyze` and `flutter test` have **not** been run by the author (no Flutter SDK was available); see `docs/TEST_REPORT.md`.

- Requirement-to-screen checklist and discount stacking rules: `docs/REQUIREMENTS_CHECKLIST.md`
- How the app talks to the backend: `docs/BACKEND_INTEGRATION.md`; setup: `docs/BACKEND_SETUP.md`; feature map: `docs/FEATURE_BACKEND_MAP.md`; security and blockers: `docs/BLOCKERS_AND_SECURITY.md`; verification: `docs/TEST_REPORT.md`

## Demo accounts (demo mode only: `USE_MOCK_DATA=true`; not real authentication)

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
- Online payment uses **AamarPay** through the backend (`AamarPayGateway`): the server starts and verifies every payment. In demo mode (`USE_MOCK_DATA=true`) payment is a labelled demonstration.
- The real backend is **Supabase** (see `docs/BACKEND_SETUP.md`, `docs/FEATURE_BACKEND_MAP.md`, `docs/BLOCKERS_AND_SECURITY.md`, `docs/TEST_REPORT.md`). Run with `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`.
- Role-based screens are a convenience; real authorization belongs to the backend.
