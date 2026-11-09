# Backend

* `supabase/migrations/` - schema, integrity triggers, pricing, orders, payments, RLS and grants (apply with `supabase db push`)
* `supabase/functions/` - Edge Functions: `payments-initiate`, `payments-callback`, `cloudinary-sign`, `cloudinary-cleanup`
* `supabase/seed.sql` - development/demo data only
* `supabase/config.toml` - auth and function settings
* `tests/` - SQL tests (PostgreSQL via PGlite) and Edge Function tests; `tools/contract_check.py` checks the app against the backend

```bash
npm install && npm test && npm run typecheck
```
Setup and deployment: `../docs/BACKEND_SETUP.md`. Never commit real secrets: use Edge Function secrets
(`supabase/functions/.env.example` lists the names).
