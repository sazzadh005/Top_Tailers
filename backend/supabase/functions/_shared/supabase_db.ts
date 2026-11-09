// Deno-only wiring to Supabase. Not imported by tests (they use fakes or PGlite).
import { createClient } from 'npm:@supabase/supabase-js@2';
import { mapDbError } from './errors.ts';
import { AttemptInfo, AttemptStart, MediaDb, PaymentOutcome, PaymentsDb, VerifiedTransaction, WhoAmI } from './types.ts';

export interface SupabaseEnv { url: string; anonKey: string; serviceKey: string }

export function loadSupabaseEnv(get: (n: string) => string | undefined): SupabaseEnv {
  const need = (n: string) => {
    const v = get(n)?.trim();
    if (!v) throw new Error(`Missing ${n}`);
    return v;
  };
  return { url: need('SUPABASE_URL'), anonKey: need('SUPABASE_ANON_KEY'), serviceKey: need('SUPABASE_SERVICE_ROLE_KEY') };
}

const opts = { auth: { persistSession: false, autoRefreshToken: false } };

export function makeDbs(env: SupabaseEnv): { payments: PaymentsDb; media: MediaDb } {
  const service = createClient(env.url, env.serviceKey, opts);
  const asUser = (token: string) =>
    createClient(env.url, env.anonKey, { ...opts, global: { headers: { Authorization: `Bearer ${token}` } } });

  async function call<T>(client: ReturnType<typeof createClient>, fn: string, args: Record<string, unknown> = {}): Promise<T> {
    const { data, error } = await client.rpc(fn, args);
    if (error) throw mapDbError(error);
    return data as T;
  }

  const payments: PaymentsDb = {
    startAttempt: (token, orderId, key) =>
      call<AttemptStart>(asUser(token), 'start_payment_attempt', { p_order_id: orderId, p_idempotency_key: key ?? null }),
    attachUrl: async (tranId, url) => { await call(service, 'attach_payment_url', { p_tran_id: tranId, p_url: url }); },
    attemptInfo: (tranId) => call<AttemptInfo | null>(service, 'payment_attempt_info', { p_tran_id: tranId }),
    recordResult: (tranId, verified: VerifiedTransaction, store) =>
      call<PaymentOutcome>(service, 'record_payment_result', { p_tran_id: tranId, p_verified: verified, p_expected_store: store }),
    recordCancel: (tranId) => call<PaymentOutcome>(service, 'record_payment_cancel', { p_tran_id: tranId }),
  };

  const media: MediaDb = {
    whoAmI: async (token) => {
      const p = await call<{ id: string; role: string }>(asUser(token), 'my_profile');
      return { id: p.id, role: p.role === 'admin' ? 'admin' : 'customer' } as WhoAmI;
    },
    recordTicket: async (publicId, userId) => { await call(service, 'record_upload_ticket', { p_public_id: publicId, p_user: userId }); },
    queueOrphans: () => call<number>(service, 'queue_orphaned_uploads'),
    claimCleanup: (limit) => call<string[]>(service, 'claim_cloudinary_cleanup', { p_limit: limit }),
    completeCleanup: async (ids) => { await call(service, 'complete_cloudinary_cleanup', { p_ids: ids }); },
    failCleanup: async (id, error) => { await call(service, 'fail_cloudinary_cleanup', { p_id: id, p_error: error }); },
  };
  return { payments, media };
}
