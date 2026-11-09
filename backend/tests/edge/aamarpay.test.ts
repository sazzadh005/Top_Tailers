import test from 'node:test';
import assert from 'node:assert/strict';
import { buildInitiateBody, callbackUrls, normalizeVerification, parseInitiateResponse, verifyTransaction, initiatePayment } from '../../supabase/functions/_shared/aamarpay.ts';
import { mapDbError } from '../../supabase/functions/_shared/errors.ts';
import type { AamarPayConfig, AttemptStart } from '../../supabase/functions/_shared/types.ts';

const cfg: AamarPayConfig = {
  baseUrl: 'https://sandbox.aamarpay.com', storeId: 'aamarpaytest', signatureKey: 'SIG-KEY-DO-NOT-LEAK',
  functionsBase: 'https://proj.supabase.co/functions/v1',
};
const info: AttemptStart = {
  tranId: 'TTFabcdef0123456789abcdef01', amountMinor: 50000, amountDecimal: '500.00', currency: 'BDT',
  orderId: '33333333-3333-3333-3333-333333333333', orderReference: 'TTF-261020-ABCD', customerName: 'Rahim Uddin',
  customerEmail: 'rahim@example.com', customerPhone: '01712345678', customerAddress: 'House 12, Road 4, Gazipur',
  description: 'Order TTF-261020-ABCD', paymentUrl: null, status: 'initiated',
};

test('initiate body carries every field AamarPay documents as required', () => {
  const b = buildInitiateBody(cfg, info, info.customerAddress);
  for (const k of ['store_id', 'signature_key', 'tran_id', 'amount', 'currency', 'desc', 'cus_name', 'cus_email', 'cus_phone', 'success_url', 'fail_url', 'cancel_url', 'type']) {
    assert.ok(k in b && (b as Record<string, unknown>)[k] !== '', `missing ${k}`);
  }
  assert.equal(b.type, 'json');
  assert.equal(b.amount, '500.00');
  assert.equal(b.currency, 'BDT');
  assert.ok(b.tran_id.length <= 32, 'tran_id is limited to 32 characters');
  assert.equal(b.store_id, 'aamarpaytest');
});

test('callback URLs point at our function and identify the attempt', () => {
  const u = callbackUrls(cfg, info.tranId);
  assert.equal(u.success, `https://proj.supabase.co/functions/v1/payments-callback?tran=${info.tranId}&r=success`);
  assert.ok(u.fail.endsWith('&r=fail') && u.cancel.endsWith('&r=cancel'));
});

test('over-long transaction ids are refused before anything is sent', () => {
  assert.throws(() => buildInitiateBody(cfg, { ...info, tranId: 'x'.repeat(33) }, 'a'), /too long/);
});

test('only an https aamarpay.com payment page is accepted from the gateway', () => {
  assert.equal(parseInitiateResponse({ result: 'true', payment_url: 'https://sandbox.aamarpay.com/paynow.php?track=X' }), 'https://sandbox.aamarpay.com/paynow.php?track=X');
  assert.equal(parseInitiateResponse({ result: true, payment_url: 'https://secure.aamarpay.com/paynow.php?track=Y' }), 'https://secure.aamarpay.com/paynow.php?track=Y');
  for (const bad of [
    null, {}, { result: 'false' }, { result: 'true' },
    { result: 'true', payment_url: 'http://sandbox.aamarpay.com/x' },
    { result: 'true', payment_url: 'https://evil.example/paynow.php' },
    { result: 'true', payment_url: 'https://aamarpay.com.evil.example/x' },
    { result: 'true', payment_url: 'javascript:alert(1)' },
    { result: 'true', payment_url: 'not a url' },
  ]) assert.throws(() => parseInitiateResponse(bad), /payment gateway/, JSON.stringify(bad));
});

test('initiatePayment posts JSON to /jsonpost.php and surfaces gateway failures safely', async () => {
  let seen: { url: string; body: Record<string, unknown> } | null = null;
  const good = async (url: string, init?: RequestInit) => {
    seen = { url, body: JSON.parse(String(init?.body)) };
    return new Response(JSON.stringify({ result: 'true', payment_url: 'https://sandbox.aamarpay.com/paynow.php?track=Z' }));
  };
  assert.equal(await initiatePayment(good, cfg, info, 'addr'), 'https://sandbox.aamarpay.com/paynow.php?track=Z');
  assert.equal(seen!.url, 'https://sandbox.aamarpay.com/jsonpost.php');
  await assert.rejects(initiatePayment(async () => { throw new Error('boom'); }, cfg, info, 'a'), /not reachable/);
  await assert.rejects(initiatePayment(async () => new Response('<html>nope</html>'), cfg, info, 'a'), /did not accept/);
  await assert.rejects(initiatePayment(async () => new Response(JSON.stringify({ result: 'false', error: 'Invalid signature' })), cfg, info, 'a'), (e: Error) => !e.message.includes('SIG-KEY'));
});

test('verification maps the documented Search Transaction fields', async () => {
  let url = '';
  const f = async (u: string) => {
    url = u;
    return new Response(JSON.stringify({ pg_txnid: 'PG1', mer_txnid: info.tranId, status_code: 2, pay_status: 'Successful', amount: '500.00', currency: 'BDT', store_id: 'aamarpaytest', payment_type: 'bKash', card_number: '01XXXXXXXXX' }));
  };
  const v = await verifyTransaction(f, cfg, info.tranId);
  assert.deepEqual(v, { statusCode: '2', payStatus: 'Successful', merTxnId: info.tranId, pgTxnId: 'PG1', amount: '500.00', currency: 'BDT', storeId: 'aamarpaytest', paymentType: 'bKash' });
  assert.ok(!('card_number' in v), 'card data is dropped');
  const q = new URL(url);
  assert.equal(q.pathname, '/api/v1/trxcheck/request.php');
  assert.equal(q.searchParams.get('request_id'), info.tranId);
  assert.equal(q.searchParams.get('store_id'), 'aamarpaytest');
  assert.equal(q.searchParams.get('type'), 'json');
  assert.equal(q.searchParams.get('signature_key'), cfg.signatureKey);
});

test('verification failures never pretend success and never expose the key', async () => {
  await assert.rejects(verifyTransaction(async () => { throw new Error(`GET with SIG-KEY-DO-NOT-LEAK failed`); }, cfg, 'T'), (e: Error) => /not reach/.test(e.message) && !e.message.includes('SIG-KEY'));
  await assert.rejects(verifyTransaction(async () => new Response('x', { status: 500 }), cfg, 'T'), /could not confirm/);
  await assert.rejects(verifyTransaction(async () => new Response('<html>'), cfg, 'T'), /unreadable/);
  assert.equal((await verifyTransaction(async () => new Response('{}'), cfg, 'T')).statusCode, '', 'an empty answer is not a success');
  assert.equal(normalizeVerification(null).statusCode, '');
});

test('database errors map to safe HTTP statuses without leaking internals', () => {
  assert.equal(mapDbError({ message: 'Order not found.', hint: 'ORDER_NOT_FOUND', code: 'P0001' }).status, 404);
  assert.equal(mapDbError({ message: 'Please sign in.', hint: 'UNAUTHENTICATED', code: '28000' }).status, 401);
  assert.equal(mapDbError({ message: 'Only the shop admin can do this.', hint: 'FORBIDDEN', code: '42501' }).status, 403);
  assert.equal(mapDbError({ message: 'Too many attempts.', hint: 'RATE_LIMITED', code: 'P0001' }).status, 429);
  assert.equal(mapDbError({ message: 'This order is Cash on Delivery.', hint: 'PAYMENT_NOT_ONLINE', code: 'P0001' }).status, 400);
  assert.equal(mapDbError({ message: 'JWT expired', code: 'PGRST301' }).status, 401);
  const internal = mapDbError({ message: 'relation "secret_table" does not exist', code: '42P01' });
  assert.equal(internal.status, 500);
  assert.ok(!internal.message.includes('secret_table'));
});
