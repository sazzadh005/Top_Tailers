import { initiatePayment, verifyTransaction } from './aamarpay.ts';
import { createUploadTicket, destroyAsset } from './cloudinary.ts';
import {
  AamarPayConfig, CloudinaryConfig, FetchFn, HttpError, MediaDb, PaymentOutcome, PaymentsDb,
} from './types.ts';

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-supabase-api-version',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const JSON_HEADERS = {
  ...CORS_HEADERS,
  'Content-Type': 'application/json; charset=utf-8',
  'Cache-Control': 'no-store',
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

export function errorResponse(e: unknown, log: (m: string) => void = console.error): Response {
  if (e instanceof HttpError) return json({ error: { code: e.code, message: e.message } }, e.status);
  // Log the type only: unexpected errors could carry request details we must not persist.
  log(`unexpected error: ${e instanceof Error ? e.name : typeof e}`);
  return json({ error: { code: 'INTERNAL', message: 'Something went wrong. Please try again.' } }, 500);
}

export function bearer(req: Request): string {
  const h = req.headers.get('authorization') ?? '';
  const m = /^Bearer\s+(.+)$/i.exec(h);
  if (!m) throw new HttpError(401, 'UNAUTHENTICATED', 'Please sign in.');
  return m[1].trim();
}

/** Any failure to identify the caller is a 401, never a 500. */
async function authenticate(db: MediaDb, token: string) {
  try {
    return await db.whoAmI(token);
  } catch (e) {
    if (e instanceof HttpError && e.status !== 500) throw e;
    throw new HttpError(401, 'UNAUTHENTICATED', 'Please sign in.');
  }
}

async function readJson(req: Request): Promise<Record<string, unknown>> {
  const len = Number(req.headers.get('content-length') ?? '0');
  if (len > 65536) throw new HttpError(413, 'TOO_LARGE', 'Request is too large.');
  try {
    const v = await req.json();
    if (v && typeof v === 'object' && !Array.isArray(v)) return v as Record<string, unknown>;
  } catch { /* fall through */ }
  throw new HttpError(400, 'BAD_REQUEST', 'Send a JSON object.');
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const IDEM = /^[A-Za-z0-9_-]{8,64}$/;
const TRAN = /^[A-Za-z0-9]{8,32}$/;

// ------------------------------------------------------- payments-initiate
export interface InitiateDeps { cfg: AamarPayConfig; db: PaymentsDb; fetch: FetchFn }

/**
 * Authenticated customer starts an online payment for THEIR order. The amount,
 * name and phone come from the stored order; nothing about money is read from
 * the request.
 */
export function makeInitiateHandler(deps: InitiateDeps) {
  return async (req: Request): Promise<Response> => {
    try {
      if (req.method !== 'POST') throw new HttpError(405, 'METHOD', 'Use POST.');
      const token = bearer(req);
      const body = await readJson(req);
      const orderId = String(body.orderId ?? '');
      if (!UUID.test(orderId)) throw new HttpError(400, 'ORDER_INVALID', 'Invalid order.');
      const key = body.idempotencyKey === undefined ? undefined : String(body.idempotencyKey);
      if (key !== undefined && !IDEM.test(key)) throw new HttpError(400, 'IDEMPOTENCY_INVALID', 'Invalid idempotency key.');

      const info = await deps.db.startAttempt(token, orderId, key);
      if (info.paymentUrl && info.status === 'initiated') {
        return json({ paymentUrl: info.paymentUrl, tranId: info.tranId, amountMinor: info.amountMinor, currency: info.currency });
      }
      const url = await initiatePayment(deps.fetch, deps.cfg, info, info.customerAddress);
      await deps.db.attachUrl(info.tranId, url);
      return json({ paymentUrl: url, tranId: info.tranId, amountMinor: info.amountMinor, currency: info.currency });
    } catch (e) {
      return errorResponse(e);
    }
  };
}

// ------------------------------------------------------- payments-callback
export interface CallbackDeps { cfg: AamarPayConfig; db: PaymentsDb; fetch: FetchFn }

const MESSAGES: Record<string, string> = {
  paid: 'Payment received. You can close this page and return to the Top Tailers app.',
  already_processed: 'This payment was already recorded. You can close this page and return to the app.',
  duplicate_success: 'This order was already paid. The shop will review the extra payment. Please return to the app.',
  mismatch: 'We could not match this payment to your order. Please contact the shop and do not pay again.',
  failed: 'The payment did not complete. Return to the app and try again.',
  expired: 'The payment session expired. Return to the app and try again.',
  cancelled: 'Payment cancelled. Return to the app and try again whenever you are ready.',
  pending: 'We are still waiting for confirmation from the payment gateway. Return to the app and check your order in a moment.',
  ignored: 'This payment reference was already handled. Return to the app to see your order.',
};

async function readBodyTran(req: Request): Promise<string | undefined> {
  if (req.method !== 'POST') return undefined;
  const len = Number(req.headers.get('content-length') ?? '0');
  if (len > 65536) return undefined;
  const ct = req.headers.get('content-type') ?? '';
  try {
    if (ct.includes('application/x-www-form-urlencoded')) return new URLSearchParams(await req.text()).get('mer_txnid') ?? undefined;
    if (ct.includes('application/json')) {
      const j = await req.json() as Record<string, unknown>;
      return typeof j.mer_txnid === 'string' ? j.mer_txnid : undefined;
    }
  } catch { /* ignore malformed bodies */ }
  return undefined;
}

function reply(cfg: AamarPayConfig, out: PaymentOutcome, status = 200): Response {
  if (cfg.returnUrl && status === 200) {
    const sep = cfg.returnUrl.includes('?') ? '&' : '?';
    const loc = `${cfg.returnUrl}${sep}order=${encodeURIComponent(out.orderId ?? '')}&result=${encodeURIComponent(out.outcome)}`;
    return new Response(null, { status: 303, headers: { Location: loc } });
  }
  return new Response(MESSAGES[out.outcome] ?? MESSAGES.pending, {
    status, headers: { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store' },
  });
}

/**
 * Public endpoint for AamarPay's success/fail redirects, cancel redirect and IPN.
 * NOTHING in the request is trusted except the transaction reference. The
 * outcome always comes from AamarPay's Search Transaction API, and the database
 * re-checks amount, currency, store and transaction id before marking a payment paid.
 */
export function makeCallbackHandler(deps: CallbackDeps) {
  return async (req: Request): Promise<Response> => {
    try {
      if (req.method !== 'GET' && req.method !== 'POST') throw new HttpError(405, 'METHOD', 'Use GET or POST.');
      const url = new URL(req.url);
      const tranId = url.searchParams.get('tran') ?? (await readBodyTran(req)) ?? '';
      if (!TRAN.test(tranId)) throw new HttpError(400, 'BAD_REF', 'Invalid payment reference.');
      const kind = url.searchParams.get('r');

      const info = await deps.db.attemptInfo(tranId);
      if (!info) throw new HttpError(404, 'PAYMENT_UNKNOWN', 'Unknown payment reference.');

      let outcome: PaymentOutcome;
      try {
        const verified = await verifyTransaction(deps.fetch, deps.cfg, tranId);
        if (kind === 'cancel' && verified.statusCode !== '2') {
          outcome = await deps.db.recordCancel(tranId);
        } else {
          outcome = await deps.db.recordResult(tranId, verified, deps.cfg.storeId);
        }
      } catch (e) {
        if (e instanceof HttpError && e.status === 502) {
          // Could not confirm with the provider: change nothing, tell the customer to check later.
          return reply(deps.cfg, { outcome: 'pending', orderId: info.orderId }, 503);
        }
        throw e;
      }
      return reply(deps.cfg, { ...outcome, orderId: outcome.orderId ?? info.orderId });
    } catch (e) {
      if (e instanceof HttpError) {
        return new Response(e.message, { status: e.status, headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
      }
      return errorResponse(e);
    }
  };
}

// ------------------------------------------------------- cloudinary-sign
export interface SignDeps { cfg: CloudinaryConfig; db: MediaDb; now?: () => number; newId?: () => string }

/** Returns a signed upload ticket. The server picks the public id, so clients cannot overwrite other assets. */
export function makeCloudinarySignHandler(deps: SignDeps) {
  return async (req: Request): Promise<Response> => {
    if (req.method === 'OPTIONS') {
      return new Response('ok', { headers: CORS_HEADERS });
    }

    try {
      if (req.method !== 'POST') throw new HttpError(405, 'METHOD', 'Use POST.');
      const who = await authenticate(deps.db, bearer(req));
      const body = await readJson(req);
      const scope = String(body.scope ?? '');
      let publicId: string;
      let overwrite = false;
      if (scope === 'product') {
        if (who.role !== 'admin') throw new HttpError(403, 'FORBIDDEN', 'Only the shop admin can upload product images.');
        publicId = `toptailers/products/${(deps.newId ?? (() => crypto.randomUUID()))()}`;
      } else if (scope === 'avatar') {
        publicId = `toptailers/avatars/${who.id}`;   // each user can only ever touch their own avatar
        overwrite = true;
      } else {
        throw new HttpError(400, 'SCOPE_INVALID', 'Unknown upload type.');
      }
      const ticket = await createUploadTicket(deps.cfg, publicId, { overwrite, now: deps.now });
      await deps.db.recordTicket(publicId, who.id);   // lets the cleanup job find uploads that never get used
      return json(ticket);
    } catch (e) {
      return errorResponse(e);
    }
  };
}

// ------------------------------------------------------- cloudinary-cleanup
export interface CleanupDeps { cfg: CloudinaryConfig; db: MediaDb; fetch: FetchFn; cronSecret?: string }

function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}

/** Destroys queued Cloudinary assets. Callable by the admin or a scheduler holding the cron secret. */
export function makeCleanupHandler(deps: CleanupDeps) {
  return async (req: Request): Promise<Response> => {
    try {
      if (req.method !== 'POST') throw new HttpError(405, 'METHOD', 'Use POST.');
      const cron = req.headers.get('x-cron-secret');
      const cronOk = !!deps.cronSecret && !!cron && safeEqual(cron, deps.cronSecret);
      if (!cronOk) {
        const who = await authenticate(deps.db, bearer(req));
        if (who.role !== 'admin') throw new HttpError(403, 'FORBIDDEN', 'Only the shop admin can do this.');
      }
      await deps.db.queueOrphans();
      const ids = await deps.db.claimCleanup(20);
      const done: string[] = [];
      let failed = 0;
      for (const id of ids) {
        try { await destroyAsset(deps.fetch, deps.cfg, id); done.push(id); }
        catch (e) { failed++; await deps.db.failCleanup(id, e instanceof Error ? e.message : 'failed'); }
      }
      if (done.length) await deps.db.completeCleanup(done);
      return json({ processed: done.length, failed });
    } catch (e) {
      return errorResponse(e);
    }
  };
}
