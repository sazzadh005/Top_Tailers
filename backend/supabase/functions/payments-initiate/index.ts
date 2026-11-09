import { loadAamarPayConfig } from '../_shared/env.ts';
import { makeInitiateHandler } from '../_shared/handlers.ts';
import { loadSupabaseEnv, makeDbs } from '../_shared/supabase_db.ts';

// deno-lint-ignore no-explicit-any
declare const Deno: any;
const get = (n: string) => Deno.env.get(n);
const { payments } = makeDbs(loadSupabaseEnv(get));

// JWT verification is ON for this function (see config.toml): only signed-in users get here.
Deno.serve(makeInitiateHandler({ cfg: loadAamarPayConfig(get), db: payments, fetch: (u, i) => fetch(u, i) }));
