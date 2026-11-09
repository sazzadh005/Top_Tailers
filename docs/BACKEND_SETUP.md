# Backend setup (Supabase + AamarPay + Cloudinary)

This is the order to do things in. Nothing here has been run against your cloud account: the
code is verified locally (see `TEST_REPORT.md`), and these steps are what you do to deploy it.

## 0. Decision in one paragraph
The backend is **Supabase** (Postgres + Auth + Edge Functions). Reasons: the backend SRS is
relational (unique product codes, one cancellation per order, transactional order placement,
substring search, row-level security), and Supabase runs the secure server-side parts (pricing,
payment verification, signed uploads) on its **free plan**, while Firebase Cloud Functions and
Secret Manager need a billing account (Blaze). The Firebase packages were configured but never used by
any screen, so nothing needed migrating. The Firebase project, `google-services.json`, `.firebaserc`
and `firebase.json` are untouched, so nothing was deleted; the Dart packages and the unsigned
Cloudinary upload test screen were removed from the app. Cloudinary stays for images.

## 1. Create the project
1. supabase.com -> new project (note the **project ref** and the database password).
2. Free plan caveats: projects pause after 7 days of inactivity, there are no backups, 500 MB database.
   Fine for a demo/exam; move to Pro (about $25/month) before real customers.

## 2. Apply the database
Run every Supabase CLI command **from the `backend/` folder** (that is where `supabase/` lives).
The CLI cannot be installed with `npm i -g`; use `npx` (no install) or Scoop/Homebrew.
```bash
cd backend
npx supabase@latest login                      # opens a browser; or set SUPABASE_ACCESS_TOKEN
npx supabase@latest link --project-ref <ref>   # asks for the database password from step 1
npx supabase@latest db push                    # applies supabase/migrations/*.sql in order
```
(Windows alternative: `scoop bucket add supabase https://github.com/supabase/scoop-bucket.git && scoop install supabase`, then drop `npx supabase@latest` and type `supabase`.)

To add your own migration later: `npx supabase@latest migration new add_something` creates
`supabase/migrations/<timestamp>_add_something.sql`; write SQL in it and run `db push`. Never edit a migration that was already pushed - add a new one.
Optional demo catalogue (NOT for a real shop): paste `backend/supabase/seed.sql` into the SQL editor.

## 3. Auth settings (Dashboard -> Authentication)
* Email confirmations: **off** (the app signs people in right after registration) - or on, if you
  want verified emails (then registration shows "check your email").
* Minimum password length: **8**. (`backend/supabase/config.toml` holds these; `npx supabase@latest config push`, run from `backend/`, applies it - not exercised here, so check the dashboard afterwards.)
* URL configuration: Site URL and a redirect URL `io.supabase.toptailers://login-callback/`
  (the app's password-reset deep link).

## 4. Create the admin (admins are never self-registered)
Register the admin email in the app, then in **SQL editor** (service role only; customers cannot call this):
```sql
select public.provision_admin('admin@yourshop.com');
```

## 5. Secrets (Edge Function secrets; never in the app or in git)
Copy `backend/supabase/functions/.env.example` to `backend/supabase/functions/.env` (git-ignored), fill it in, then (from `backend/`):
```bash
npx supabase@latest secrets set --env-file supabase/functions/.env
```
* **Cloudinary**: the API secret was pasted into a chat during development - treat it as leaked.
  Console -> Settings -> API Keys: create a new key, put it in the secrets, revoke the old one.
  Also disable the unsigned preset `toptailers_products` (Settings -> Upload -> Upload presets):
  signed uploads replace it.
* **AamarPay**: store id and signature key. The sandbox values are published in AamarPay's sandbox docs;
  production values come from your approved merchant account.

## 6. Deploy the functions
From `backend/`:
```bash
npx supabase@latest functions deploy payments-initiate
npx supabase@latest functions deploy payments-callback
npx supabase@latest functions deploy cloudinary-sign
npx supabase@latest functions deploy cloudinary-cleanup
```
`config.toml` sets `verify_jwt`: on for `payments-initiate` and `cloudinary-sign`; **off** for
`payments-callback` (AamarPay and the customer's browser call it) and `cloudinary-cleanup` (it checks an
admin login or the `x-cron-secret` header itself).

## 7. AamarPay
* Each payment attempt sends AamarPay these URLs automatically (nothing to register for them):
  `https://<ref>.supabase.co/functions/v1/payments-callback?tran=<id>&r=success|fail|cancel`
* **IPN** (server-to-server notice): AamarPay documents that the IPN listener URL is given to them during
  onboarding. Ask AamarPay support to register
  `https://<ref>.supabase.co/functions/v1/payments-callback`. The app works without it (the success redirect
  and the app's status check verify with AamarPay), but IPN makes payments settle even if the customer closes
  the browser before the redirect.
* Sandbox supports only bKash. For production set `AAMARPAY_BASE_URL=https://secure.aamarpay.com` and the live credentials.
* The function verifies every payment with AamarPay's Search Transaction API and checks amount, currency,
  store and transaction id before marking anything paid. Redirect bodies are never trusted.

## 8. Cloudinary cleanup job
Uploads that are replaced, or issued but never attached, are queued and destroyed by `cloudinary-cleanup`.
Run it on a schedule (hourly/daily) with the cron secret, e.g. from any scheduler:
```bash
curl -X POST https://<ref>.supabase.co/functions/v1/cloudinary-cleanup -H "x-cron-secret: <CRON_SECRET>"
```
The admin can also call it signed in. (Which scheduler you use - Supabase schedules, pg_cron + pg_net, GitHub Actions - is your choice; none was exercised here.)
Notification purging (older than 30 days) is scheduled by migration 4 **if** the `pg_cron` extension is
enabled (Dashboard -> Database -> Extensions); hiding old notifications does not depend on it.

## 9. Run the app
```bash
flutter pub get
flutter run --dart-define=SUPABASE_URL=https://<ref>.supabase.co --dart-define=SUPABASE_ANON_KEY=<anon key>
flutter build apk --release --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
```
The anon key is public by design (data is protected by row-level security). With neither value the app shows
a "Backend not configured" screen instead of fake data. Offline demo: `--dart-define=USE_MOCK_DATA=true`
(shows a DEMO DATA banner).

## 10. Local development (needs Docker; not exercised here)
From `backend/`: `npx supabase@latest start`, then `npx supabase@latest db reset` (migrations + `seed.sql`), `npx supabase@latest functions serve`.

## 11. Tests
```bash
cd backend && npm install
npm test            # SQL suites (PostgreSQL via PGlite) + Edge Function tests
npm run typecheck
npm run fixtures && npm run contract    # regenerate real-output fixtures; check app<->backend contract
flutter test        # on your machine (could not be run in the build environment)
```
