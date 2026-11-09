# Backend integration (status: implemented)

The app talks to the backend only through the interfaces in `lib/repositories/repositories.dart`.
`AppServices` chooses the implementation:

* `buildSupabaseServices(client)` (`lib/app/supabase_services.dart`) - the real backend (default when `SUPABASE_URL` and `SUPABASE_ANON_KEY` are supplied).
* `AppServices.mock()` - in-memory demo data, only with `--dart-define=USE_MOCK_DATA=true` (bannered "DEMO DATA"); also what the unit tests use.

Implementations live in `lib/data/supabase/`: `supabase_repositories.dart` (every call is an audited SQL function),
`json_mappers.dart` (pure, contract-tested), `aamarpay_gateway.dart`, `cloudinary_uploader.dart`, `error_mapper.dart`.

Payment flow: place order (COD or online) -> for online, `payments-initiate` returns AamarPay's hosted page ->
app opens it in the browser -> the server verifies with AamarPay -> the app reads the verified status.
The app never marks a payment paid. Setup: `BACKEND_SETUP.md`.
