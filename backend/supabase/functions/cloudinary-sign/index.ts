import { loadCloudinaryConfig } from '../_shared/env.ts';
import { makeCloudinarySignHandler } from '../_shared/handlers.ts';
import { loadSupabaseEnv, makeDbs } from '../_shared/supabase_db.ts';

// deno-lint-ignore no-explicit-any
declare const Deno: any;
const get = (n: string) => Deno.env.get(n);
const { media } = makeDbs(loadSupabaseEnv(get));

Deno.serve(makeCloudinarySignHandler({ cfg: loadCloudinaryConfig(get), db: media }));
