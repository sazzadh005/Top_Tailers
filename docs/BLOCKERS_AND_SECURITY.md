# Security notes and remaining blockers

## Do these before using it for real
1. **Rotate the Cloudinary API secret.** It was pasted in a chat during development. Create a new key,
   store it only as an Edge Function secret, revoke the old one. It is not in any file in this project.
2. **Disable the unsigned Cloudinary preset** `toptailers_products`; uploads are now server-signed.
3. **Ask AamarPay to register the IPN URL** (`.../functions/v1/payments-callback`). They document that this
   is done by their support/onboarding. Until then payments still verify through the redirect and the app's status check.
4. **Production AamarPay credentials** require an approved merchant account; the sandbox accepts only bKash.
5. **Supabase plan:** the free plan pauses after 7 days idle and has no backups. Use Pro for real customers.
6. Decide the **refund policy**: the requirements don't define refunds. A payment that arrives for a cancelled
   order, a cancellation after payment, or a duplicate payment is stored and flagged `needs_review` for a human.
   Nothing refunds automatically.

## What protects the system
* Prices, discounts, vouchers and totals are recomputed in the database; the app only sends ids and quantities.
* Clients cannot write business tables at all; every write is an audited SQL function that checks the caller.
* Orders, items, measurements, history, cancellations are append-only (database triggers).
* Payments are marked paid only after the **server** verifies with AamarPay, and amount, currency, store and
  transaction id must match. Redirect/IPN bodies are never trusted. Repeated callbacks are harmless.
* AamarPay signature key and Cloudinary secret exist only in Edge Function secrets; tests assert they never
  appear in a response, header or log.
* Voucher guessing and payment starts are rate limited per user.
* Cloudinary: the server chooses the public id (no overwriting others), product uploads are admin-only,
  and the database only accepts image URLs from the shop's own Cloudinary folders.

## Known limitations
* Android's Gradle still applies the Firebase `google-services` plugin and `google-services.json` remains
  (harmless, unused). Remove them when you are sure you will not use Firebase.
* Order lists load the newest 100 orders (server supports paging; the app does not page yet).
* Registration with email confirmation ON is only a message ("check your email"), not a full verification flow.
* Cloudinary's per-file size limit is enforced by the app (5 MB), not by the server signature.
* Free-text fields (notes, feedback) are stored and returned as text; the app renders them as text only.
* Delivery charge is 0 because the SRS defines none (configurable in `app_settings` if that changes).
