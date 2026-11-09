import { loadAamarPayConfig } from '../_shared/env.ts';
import { makeCallbackHandler } from '../_shared/handlers.ts';
import { loadSupabaseEnv, makeDbs } from '../_shared/supabase_db.ts';

// deno-lint-ignore no-explicit-any
declare const Deno: any;
const get = (n: string) => Deno.env.get(n);
const { payments } = makeDbs(loadSupabaseEnv(get));

// verify_jwt = false (see config.toml): AamarPay and the customer's browser call this
// without a Supabase JWT. Safety comes from server-side verification, not from the caller.
Deno.serve(makeCallbackHandler({ cfg: loadAamarPayConfig(get), db: payments, fetch: (u, i) => fetch(u, i) }));
