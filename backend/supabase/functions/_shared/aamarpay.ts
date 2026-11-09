import { AamarPayConfig, AttemptStart, FetchFn, HttpError, VerifiedTransaction } from './types.ts';

// Endpoints and fields follow AamarPay's official documentation:
//   Initiate Payment (JSON): POST {base}/jsonpost.php
//   Search Transaction:      GET  {base}/api/v1/trxcheck/request.php
// Docs: https://aamarpay.readme.io/reference/initiate-payment-json
//       https://aamarpay.readme.io/reference/search-transaction

export const MAX_TRAN_ID = 32;

export function callbackUrls(cfg: AamarPayConfig, tranId: string) {
  const base = `${cfg.functionsBase.replace(/\/$/, '')}/payments-callback?tran=${encodeURIComponent(tranId)}`;
  return { success: `${base}&r=success`, fail: `${base}&r=fail`, cancel: `${base}&r=cancel` };
}

/** Body for POST /jsonpost.php. Amount, name and phone come from the stored order. */
export function buildInitiateBody(cfg: AamarPayConfig, info: AttemptStart, address: string) {
  if (info.tranId.length > MAX_TRAN_ID) throw new HttpError(500, 'PAYMENT_CONFIG', 'Transaction id is too long.');
  const urls = callbackUrls(cfg, info.tranId);
  return {
    store_id: cfg.storeId,
    signature_key: cfg.signatureKey,
    tran_id: info.tranId,
    amount: info.amountDecimal,           // "500.00": decimal string, no symbols or commas
    currency: info.currency,
    desc: info.description.slice(0, 200),
    cus_name: info.customerName,
    cus_email: info.customerEmail,
    cus_phone: info.customerPhone,
    cus_add1: address.slice(0, 100),
    cus_country: 'Bangladesh',
    success_url: urls.success,
    fail_url: urls.fail,
    cancel_url: urls.cancel,
    type: 'json',
  };
}

/** Accepts only an https AamarPay payment page, so a tampered response cannot redirect elsewhere. */
export function parseInitiateResponse(json: unknown): string {
  const j = json as { result?: unknown; payment_url?: unknown } | null;
  if (!j || String(j.result) !== 'true' || typeof j.payment_url !== 'string') {
    throw new HttpError(502, 'GATEWAY_REJECTED', 'The payment gateway did not accept the request. Please try again.');
  }
  let url: URL;
  try { url = new URL(j.payment_url); } catch { url = new URL('http://invalid.invalid'); }
  if (url.protocol !== 'https:' || !(url.hostname === 'aamarpay.com' || url.hostname.endsWith('.aamarpay.com'))) {
    throw new HttpError(502, 'GATEWAY_REJECTED', 'The payment gateway returned an unexpected address.');
  }
  return url.toString();
}

export async function initiatePayment(fetchFn: FetchFn, cfg: AamarPayConfig, info: AttemptStart, address: string): Promise<string> {
  let res: Response;
  try {
    res = await fetchFn(`${cfg.baseUrl}/jsonpost.php`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(buildInitiateBody(cfg, info, address)),   // never logged: contains the signature key
      signal: AbortSignal.timeout(15000),
    });
  } catch {
    throw new HttpError(502, 'GATEWAY_UNREACHABLE', 'The payment gateway is not reachable right now. Please try again.');
  }
  let json: unknown = null;
  try { json = await res.json(); } catch { /* handled below */ }
  return parseInitiateResponse(json);
}

/** Maps AamarPay's response to the fields the database checks. */
export function normalizeVerification(json: unknown): VerifiedTransaction {
  const j = (json ?? {}) as Record<string, unknown>;
  const s = (v: unknown) => (v === undefined || v === null ? undefined : String(v));
  return {
    statusCode: s(j.status_code) ?? '',
    payStatus: s(j.pay_status),
    merTxnId: s(j.mer_txnid),
    pgTxnId: s(j.pg_txnid),
    amount: s(j.amount),
    currency: s(j.currency),
    storeId: s(j.store_id) ?? s(j.merchant_id),
    paymentType: s(j.payment_type) ?? s(j.card_type),
  };
}

/**
 * Server-side verification via the Search Transaction API. This is the ONLY
 * source of truth for a payment: redirects, callback bodies and anything the
 * app says are ignored. The signature key travels in the query string as the
 * provider documents, so this URL must never be logged.
 */
export async function verifyTransaction(fetchFn: FetchFn, cfg: AamarPayConfig, tranId: string): Promise<VerifiedTransaction> {
  const q = new URLSearchParams({ request_id: tranId, store_id: cfg.storeId, signature_key: cfg.signatureKey, type: 'json' });
  let res: Response;
  try {
    res = await fetchFn(`${cfg.baseUrl}/api/v1/trxcheck/request.php?${q.toString()}`, { method: 'GET', signal: AbortSignal.timeout(15000) });
  } catch {
    throw new HttpError(502, 'VERIFY_UNREACHABLE', 'Could not reach the payment gateway to confirm the payment.');
  }
  if (!res.ok) throw new HttpError(502, 'VERIFY_FAILED', 'The payment gateway could not confirm the payment.');
  let json: unknown;
  try { json = await res.json(); } catch { throw new HttpError(502, 'VERIFY_FAILED', 'The payment gateway returned an unreadable answer.'); }
  return normalizeVerification(json);
}
