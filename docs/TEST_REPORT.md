# Test report

Honest account of what was run, what was only checked statically, and what could not be run.
Build environment: Linux sandbox, Node 22. **No Flutter/Dart SDK, no Docker, no access to Supabase, AamarPay or Cloudinary.**

## 1. Executed and passing

| What | How it was run | Result |
|---|---|---|
| Database schema, RLS, grants, triggers, pricing, orders, payments, notifications, uploads, seed | `cd backend && npm run test:sql` - the real migrations loaded into **PostgreSQL 18 (PGlite)** behind a small Supabase shim (roles, `auth.uid()`), tests run as `anon` / `authenticated` / `service_role` | **96 / 96** (security 13, catalog 15, pricing 14, orders 23, payments 15, engagement 8, uploads 6, seed 1, smoke 1) |
| Edge Functions (AamarPay initiate/callback, Cloudinary sign/cleanup, config, error mapping) | `npm run test:edge` (tsx). `payments_e2e` wires the **real handlers to the real SQL functions** with a **fake AamarPay** | **32 / 32** |
| Edge Function types | `npm run typecheck` (`tsc --strict`) | clean |
| App <-> backend contract | `npm run contract` | **245** keys / RPC parameters / measurement ranges verified |

Highlights actually exercised: a customer cannot read others' orders or write any business table; role escalation fails;
forged or stale totals are rejected; retried orders and payment starts are idempotent; a forged "success" redirect
does not mark anything paid; amount/currency/store/transaction-id mismatches are flagged, not accepted; repeated
callbacks do nothing twice; late or duplicate payments are flagged; orders/items/cancellations cannot be edited or
deleted; notifications exactly 30 days old are visible and older ones hidden/purged; date filters use Dhaka days;
the AamarPay signature key and Cloudinary secret never appear in any response, header or log; Cloudinary's
documented signature example reproduces exactly.

One thing the suite found in my own work: a date-filter test failed late in the session because it used the UTC date while
the server correctly uses Dhaka days (it was already Nov 7 in Dhaka). The test was wrong, not the server; it is fixed and a midnight-boundary test was added.

## 2. Checked statically only (Dart)

* A syntax parse (tree-sitter) of all 105 Dart files, import resolution, cross-file symbol visibility, and constructor
  named/required argument checks: **0 problems**. This is **not** type checking: `flutter analyze` has not been run.
* `test/supabase_mappers_test.dart` (15 cases) parses **real server output** captured in `test/fixtures` through the Dart mappers;
  the contract check above verifies the same keys without Dart. The new provider/repository tests (backend-style auth,
  idempotency, refresh, summaries) are written but unrun. In total about **137 Dart test cases** exist; **none has been executed here**.
  Run `flutter test` on your machine; failures there are expected to be small (typos, API signatures) rather than design problems, but that is an expectation, not a result.

## 3. Not run (and why)

| Not run | Why | What it means |
|---|---|---|
| `flutter pub get/analyze/test`, emulator, release APK | no Flutter SDK | the app may have compile errors I could not see; `supabase_flutter`/`url_launcher` call signatures are from memory of the 2.x API |
| Deploy to your Supabase project | no network to Supabase; also needs your consent and your secrets | migrations/functions are untested on real Supabase (PGlite is real PostgreSQL but not GoTrue/PostgREST/Edge runtime) |
| Edge Functions under Deno | Deno not available | handlers are runtime-neutral and tested under Node; Deno-specific wiring (`index.ts`, `supabase_db.ts`) is not executed |
| Live AamarPay sandbox payment | no network | request/response fields follow AamarPay's official docs, but a real sandbox transaction has not been made; city/country fields and the IPN signature behaviour are unverified |
| Live Cloudinary upload/destroy | no network | signing matches the documented example; a real upload has not been made |
| `pg_cron` schedule, password-reset deep link, device behaviour | not available | configured but unexercised |
| `supabase start` local stack | no Docker | not exercised |

## 4. Environment incident
The build sandbox's working directory was reset twice during this session. Everything not already saved to `outputs/` was lost the second time,
so the backend and the Flutter integration were **rebuilt from the session record and re-verified from scratch**; the results above are from the rebuilt code.
