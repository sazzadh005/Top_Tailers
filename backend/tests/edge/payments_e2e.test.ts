// End-to-end payment lifecycle: real Edge Function handlers + the real SQL functions
// (PostgreSQL via PGlite) + a FAKE AamarPay gateway. No network, no real money.
import test, { before } from 'node:test';
import assert from 'node:assert/strict';
// @ts-ignore: plain JS test harness
import { freshDb, seed, line, placeOrder } from '../harness.mjs';
import { makeInitiateHandler, makeCallbackHandler } from '../../supabase/functions/_shared/handlers.ts';
import { mapDbError } from '../../supabase/functions/_shared/errors.ts';
import type { PaymentsDb, AamarPayConfig } from '../../supabase/functions/_shared/types.ts';

const SECRET = 'aamar-sig-key-DO-NOT-LEAK-9f2c';
const cfg: AamarPayConfig = { baseUrl: 'https://sandbox.aamarpay.com', storeId: 'aamarpaytest', signatureKey: SECRET, functionsBase: 'https://proj.supabase.co/functions/v1' };

let api: any, S: any, tokens: Record<string, string>;
const logs: string[] = [];
const captured: string[] = [];   // every response body/header we hand out

// ---- fake AamarPay -----------------------------------------------------------
const gw = {
  initiates: [] as Record<string, unknown>[],
  verifyCalls: 0,
  down: false,
  scenario: new Map<string, Record<string, unknown>>(),
  fetch: async (url: string, init?: RequestInit): Promise<Response> => {
    const u = new URL(url);
    if (u.pathname === '/jsonpost.php') {
      const body = JSON.parse(String(init?.body));
      gw.initiates.push(body);
      if (body.signature_key !== SECRET || body.store_id !== 'aamarpaytest') return new Response(JSON.stringify({ result: 'false', error: 'Invalid signature' }));
      return new Response(JSON.stringify({ result: 'true', payment_url: `https://sandbox.aamarpay.com/paynow.php?track=${body.tran_id}` }));
    }
    if (u.pathname === '/api/v1/trxcheck/request.php') {
      gw.verifyCalls++;
      if (gw.down) throw new Error('network down');
      if (u.searchParams.get('signature_key') !== SECRET) return new Response(JSON.stringify({ status: 'error' }));
      const id = u.searchParams.get('request_id')!;
      return new Response(JSON.stringify(gw.scenario.get(id) ?? { mer_txnid: id, status_code: '0', pay_status: 'Pending' }));
    }
    return new Response('not found', { status: 404 });
  },
};
const paid = (a: { tranId: string; amountDecimal: string }, o: Record<string, unknown> = {}) =>
  ({ mer_txnid: a.tranId, pg_txnid: `PG-${a.tranId}`, status_code: '2', pay_status: 'Successful', amount: a.amountDecimal, currency: 'BDT', store_id: 'aamarpaytest', payment_type: 'bKash', ...o });

// ---- database adapter (the same RPCs supabase_db.ts calls) -----------------------
const mapErr = (e: any) => mapDbError({ message: e.message, hint: e.hint, code: e.code });
const db: PaymentsDb = {
  async startAttempt(token, orderId, key) {
    const uid = tokens[token];
    if (!uid) throw mapDbError({ message: 'Please sign in.', hint: 'UNAUTHENTICATED' });
    await api.admin('delete from public.rate_limits');
    try { return await api.rpc(uid, 'public.start_payment_attempt', [orderId, key ?? null]); } catch (e) { throw mapErr(e); }
  },
  async attachUrl(t, u) { await api.service(`select public.attach_payment_url($1,$2)`, [t, u]); },
  async attemptInfo(t) { return (await api.service(`select public.payment_attempt_info($1) as r`, [t])).rows[0].r; },
  async recordResult(t, v, s) {
    try { return (await api.service(`select public.record_payment_result($1,$2::jsonb,$3) as r`, [t, JSON.stringify(v), s])).rows[0].r; } catch (e) { throw mapErr(e); }
  },
  async recordCancel(t) {
    try { return (await api.service(`select public.record_payment_cancel($1) as r`, [t])).rows[0].r; } catch (e) { throw mapErr(e); }
  },
};
const initiate = makeInitiateHandler({ cfg, db, fetch: gw.fetch });
const callback = makeCallbackHandler({ cfg, db, fetch: gw.fetch });

async function capture(res: Response): Promise<Response> {
  const copy = res.clone();
  captured.push(await copy.text(), ...copy.headers.values());
  return res;
}
const startReq = (token: string | null, body: unknown) =>
  new Request('https://fn/payments-initiate', { method: 'POST', headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) }, body: JSON.stringify(body) });
const cb = (tran: string, r: string | null, form?: Record<string, string>, method = 'POST') =>
  new Request(`https://fn/payments-callback${tran ? `?tran=${tran}` : ''}${r ? `${tran ? '&' : '?'}r=${r}` : ''}`, {
    method, headers: form ? { 'content-type': 'application/x-www-form-urlencoded' } : {}, body: form && method === 'POST' ? new URLSearchParams(form).toString() : undefined,
  });
const onlineOrder = (uid = S.rahim, qty = 2) => placeOrder(api, uid, [line(S.buttons, qty)], { paymentMethod: 'online' });
const getOrder = (uid: string, id: string) => api.rpc(uid, 'public.get_order', [id]);
async function begin(uid = S.rahim, token = 'rahim') {
  const o = await onlineOrder(uid);
  const res = await capture(await initiate(startReq(token, { orderId: o.id })));
  assert.equal(res.status, 200);
  const j = await res.json();
  return { o, tranId: j.tranId as string, j, amountDecimal: '500.00' };
}

before(async () => {
  api = await freshDb(); S = await seed(api);
  tokens = { rahim: S.rahim, nusrat: S.nusrat, admin: S.adminId };
  for (const k of ['log', 'error', 'warn'] as const) {
    const orig = console[k]; console[k] = (...a: unknown[]) => { logs.push(a.map(String).join(' ')); orig.apply(console, [] as never); };
  }
});

test('initiate: amount and customer details come from the stored order; client money is ignored', async () => {
  const o = await onlineOrder();
  const res = await capture(await initiate(startReq('rahim', { orderId: o.id, amount: 1, amountMinor: 1, currency: 'USD' })));
  assert.equal(res.status, 200);
  const j = await res.json();
  assert.match(j.paymentUrl, /^https:\/\/sandbox\.aamarpay\.com\/paynow\.php\?track=TTF/);
  assert.equal(j.amountMinor, 50000);
  const sent = gw.initiates.at(-1)!;
  assert.equal(sent.amount, '500.00');
  assert.equal(sent.currency, 'BDT');
  assert.equal(sent.cus_name, 'Rahim Uddin');
  assert.equal(sent.cus_email, 'rahim@example.com');
  assert.equal(sent.cus_phone, o.contactPhone);
  assert.equal(sent.store_id, 'aamarpaytest');
  assert.ok(String(sent.tran_id).length <= 32);
  assert.match(String(sent.success_url), /payments-callback\?tran=TTF\w+&r=success$/);
  assert.equal((await getOrder(S.rahim, o.id)).payment.status, 'pending', 'starting is not paying');
});

test('initiate is idempotent: a retry reuses the attempt and does not call the gateway again', async () => {
  const o = await onlineOrder();
  const call = () => initiate(startReq('rahim', { orderId: o.id, idempotencyKey: 'retry-key-0001' }));
  const before = gw.initiates.length;
  const a = await (await capture(await call())).json();
  const b = await (await capture(await call())).json();
  assert.equal(a.tranId, b.tranId);
  assert.equal(a.paymentUrl, b.paymentUrl);
  assert.equal(gw.initiates.length, before + 1, 'only one gateway call');
});

test('initiate authorization and validation', async () => {
  const o = await onlineOrder();
  const cod = await placeOrder(api, S.rahim, [line(S.buttons)]);
  const expect = async (token: string | null, body: unknown, status: number) => {
    const r = await capture(await initiate(startReq(token, body)));
    assert.equal(r.status, status, JSON.stringify(body));
    return r;
  };
  await expect(null, { orderId: o.id }, 401);
  await expect('forged-token', { orderId: o.id }, 401);
  await expect('nusrat', { orderId: o.id }, 404);
  await expect('admin', { orderId: o.id }, 404);
  await expect('rahim', { orderId: cod.id }, 400);
  await expect('rahim', { orderId: 'not-a-uuid' }, 400);
  await expect('rahim', { orderId: o.id, idempotencyKey: 'x' }, 400);
  await expect('rahim', {}, 400);
  assert.equal((await initiate(new Request('https://fn/payments-initiate', { method: 'GET' }))).status, 405);
  const c = await onlineOrder();
  await api.rpc(S.rahim, 'public.cancel_order', [c.id, 'Ordered by mistake']);
  await expect('rahim', { orderId: c.id }, 400);
});

test('initiate reports gateway problems without exposing details', async () => {
  const o = await onlineOrder();
  const bad = makeInitiateHandler({ cfg: { ...cfg, signatureKey: 'wrong-key' }, db, fetch: gw.fetch });
  const r = await capture(await bad(startReq('rahim', { orderId: o.id })));
  assert.equal(r.status, 502);
  assert.ok(!(await r.clone().text()).includes('Invalid signature'));
  const down = makeInitiateHandler({ cfg, db, fetch: async () => { throw new Error('dns'); } });
  assert.equal((await capture(await down(startReq('rahim', { orderId: o.id })))).status, 502);
  assert.equal((await getOrder(S.rahim, o.id)).payment.status, 'pending');
});

test('a verified success marks the payment paid; the browser redirect alone proves nothing', async () => {
  const { o, tranId, amountDecimal } = await begin();
  const forged = await capture(await callback(cb(tranId, 'success', { mer_txnid: tranId, pay_status: 'Successful', status_code: '2', amount: amountDecimal })));
  assert.equal(forged.status, 200);
  assert.match(await forged.text(), /still waiting/);
  assert.equal((await getOrder(S.rahim, o.id)).payment.status, 'pending');
  gw.scenario.set(tranId, paid({ tranId, amountDecimal }));
  const real = await capture(await callback(cb(tranId, 'success', { mer_txnid: tranId })));
  assert.equal(real.status, 200);
  assert.match(await real.text(), /Payment received/);
  const after = await getOrder(S.rahim, o.id);
  assert.equal(after.payment.status, 'successful');
  assert.equal(after.payment.provider, 'aamarpay');
  assert.equal(after.payment.transactionRef, `PG-${tranId}`);
  assert.equal(after.status, 'pending', 'paying does not confirm the order; order status is separate');
});

test('a failure redirect cannot be "upgraded" and a failed payment can be retried', async () => {
  const { o, tranId } = await begin();
  gw.scenario.set(tranId, { mer_txnid: tranId, status_code: '7', pay_status: 'Failed' });
  const r = await capture(await callback(cb(tranId, 'fail', { mer_txnid: tranId, pay_status: 'Successful' })));
  assert.match(await r.text(), /did not complete/);
  assert.equal((await getOrder(S.rahim, o.id)).payment.status, 'failed');
  const retry = await (await capture(await initiate(startReq('rahim', { orderId: o.id })))).json();
  assert.notEqual(retry.tranId, tranId);
  gw.scenario.set(retry.tranId, paid({ tranId: retry.tranId, amountDecimal: '500.00' }));
  await capture(await callback(cb(retry.tranId, 'success')));
  assert.equal((await getOrder(S.rahim, o.id)).payment.status, 'successful');
});

test('mismatched amount, currency or store reported by the gateway is never accepted', async () => {
  for (const bad of [{ amount: '1.00' }, { currency: 'USD' }, { mer_txnid: 'TTFsomeoneelse000000000000' }, { store_id: 'another-store' }]) {
    const { o, tranId, amountDecimal } = await begin();
    gw.scenario.set(tranId, paid({ tranId, amountDecimal }, bad));
    const r = await capture(await callback(cb(tranId, 'success')));
    assert.match(await r.text(), /could not match/, JSON.stringify(bad));
    assert.notEqual((await getOrder(S.rahim, o.id)).payment.status, 'successful');
    assert.equal((await api.admin(`select needs_review from public.payments where order_id = $1`, [o.id])).rows[0].needs_review, true);
  }
});

test('repeated callbacks (redirect + IPN + refresh) are idempotent', async () => {
  const { o, tranId, amountDecimal } = await begin();
  gw.scenario.set(tranId, paid({ tranId, amountDecimal }));
  const results: string[] = [];
  for (const req of [cb(tranId, 'success', { mer_txnid: tranId }), cb(tranId, 'success', { mer_txnid: tranId }), cb('', null, { mer_txnid: tranId }), cb(tranId, 'success', undefined, 'GET')]) {
    results.push(await (await capture(await callback(req))).text());
  }
  assert.match(results[0], /Payment received/);
  for (const later of results.slice(1)) assert.match(later, /already recorded/);
  const notes = (await api.rpc(S.rahim, 'public.visible_notifications')).filter((n: any) => n.body.includes(o.reference) && n.title === 'Payment received');
  assert.equal(notes.length, 1, 'one payment, one notification');
  assert.equal((await getOrder(S.rahim, o.id)).payment.status, 'successful');
});

test('IPN style call (no query, tran id only in the body) is handled the same way', async () => {
  const { o, tranId, amountDecimal } = await begin();
  gw.scenario.set(tranId, paid({ tranId, amountDecimal }));
  assert.equal((await capture(await callback(cb('', null, { mer_txnid: tranId, pay_status: 'Successful' })))).status, 200);
  assert.equal((await getOrder(S.rahim, o.id)).payment.status, 'successful');
  const json = await callback(new Request(`https://fn/payments-callback`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ mer_txnid: tranId }) }));
  assert.match(await json.text(), /already recorded/);
});

test('if the gateway cannot be reached, nothing changes and the customer is told to check later', async () => {
  const { o, tranId, amountDecimal } = await begin();
  gw.down = true;
  const r = await capture(await callback(cb(tranId, 'success', { mer_txnid: tranId })));
  assert.equal(r.status, 503);
  assert.match(await r.text(), /still waiting/);
  assert.equal((await getOrder(S.rahim, o.id)).payment.status, 'pending');
  gw.down = false;
  gw.scenario.set(tranId, paid({ tranId, amountDecimal }));
  await capture(await callback(cb('', null, { mer_txnid: tranId })));
  assert.equal((await getOrder(S.rahim, o.id)).payment.status, 'successful');
});

test('cancel redirect cancels only when the gateway confirms nothing was paid', async () => {
  const a = await begin();
  assert.match(await (await capture(await callback(cb(a.tranId, 'cancel')))).text(), /cancelled/);
  assert.equal((await getOrder(S.rahim, a.o.id)).payment.status, 'cancelled');
  const b = await begin();
  gw.scenario.set(b.tranId, paid({ tranId: b.tranId, amountDecimal: b.amountDecimal }));
  assert.match(await (await capture(await callback(cb(b.tranId, 'cancel')))).text(), /Payment received/);
  assert.equal((await getOrder(S.rahim, b.o.id)).payment.status, 'successful');
});

test('unknown or malformed references are rejected', async () => {
  assert.equal((await capture(await callback(cb('TTFdoesnotexist0000000000000', 'success')))).status, 404);
  assert.equal((await capture(await callback(cb('bad ref!', 'success')))).status, 400);
  assert.equal((await capture(await callback(cb('', null)))).status, 400);
  assert.equal((await capture(await callback(new Request('https://fn/payments-callback?tran=TTFabc', { method: 'DELETE' })))).status, 405);
});

test('a paid order stays paid even if a later report says failed', async () => {
  const { o, tranId, amountDecimal } = await begin();
  gw.scenario.set(tranId, paid({ tranId, amountDecimal }));
  await capture(await callback(cb(tranId, 'success')));
  gw.scenario.set(tranId, { mer_txnid: tranId, status_code: '7' });
  await capture(await callback(cb(tranId, 'fail')));
  assert.equal((await getOrder(S.rahim, o.id)).payment.status, 'successful');
});

test('optional return URL redirects the browser with the verified result', async () => {
  const withReturn = makeCallbackHandler({ cfg: { ...cfg, returnUrl: 'io.supabase.toptailers://payment-result' }, db, fetch: gw.fetch });
  const { o, tranId, amountDecimal } = await begin();
  gw.scenario.set(tranId, paid({ tranId, amountDecimal }));
  const r = await withReturn(cb(tranId, 'success'));
  assert.equal(r.status, 303);
  assert.equal(r.headers.get('location'), `io.supabase.toptailers://payment-result?order=${o.id}&result=paid`);
});

test('the signature key never appears in a response, header or log', () => {
  assert.ok(captured.length > 20, 'sanity: responses were captured');
  for (const text of [...captured, ...logs]) assert.ok(!text.includes(SECRET), 'secret leaked');
  assert.ok(gw.initiates.every((b) => b.signature_key === SECRET || b.signature_key === 'wrong-key'));   // 'wrong-key' = the deliberate misconfiguration test
});

test('admins can see attempts and review flags; customers cannot', async () => {
  assert.ok((await api.user(S.adminId)(`select * from public.payment_attempts`)).rows.length > 5);
  assert.equal((await api.user(S.rahim)(`select * from public.payment_attempts`)).rows.length, 0);
});
