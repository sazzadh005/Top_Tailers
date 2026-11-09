import test, { before } from 'node:test';
import assert from 'node:assert/strict';
import { freshDb, seed, rejects, line, placeOrder } from './harness.mjs';

let api, S;
before(async () => { api = await freshDb(); S = await seed(api); });

const onlineOrder = (uid = S.rahim, qty = 2, extra = {}) => placeOrder(api, uid, [line(S.buttons, qty)], { paymentMethod: 'online', ...extra });
const startRaw = (uid, orderId, key = null) => api.rpc(uid, 'public.start_payment_attempt', [orderId, key]);
// Most tests are not about throttling, so clear the limiter between calls.
const start = async (uid, orderId, key = null) => { await api.admin('delete from public.rate_limits'); return startRaw(uid, orderId, key); };
const record = async (tranId, verified, store = null) =>
  (await api.service(`select public.record_payment_result($1, $2::jsonb, $3) as r`, [tranId, JSON.stringify(verified), store])).rows[0].r;
const ok = (a, o = {}) => ({ statusCode: '2', merTxnId: a.tranId, amount: a.amountDecimal, currency: 'BDT', pgTxnId: `PG-${a.tranId}`, storeId: 'aamarpaytest', payStatus: 'Successful', ...o });
const order = (uid, id) => api.rpc(uid, 'public.get_order', [id]);

test('only the owner can start a payment, only for online orders, and the amount comes from the order', async () => {
  const o = await onlineOrder();
  await rejects(start(S.nusrat, o.id), 'Order not found');
  await rejects(start(S.adminId, o.id), 'Order not found');
  const cod = await placeOrder(api, S.rahim, [line(S.buttons)]);
  await rejects(start(S.rahim, cod.id), 'Cash on Delivery');
  const a = await start(S.rahim, o.id);
  assert.equal(a.amountMinor, 50000);
  assert.equal(a.amountDecimal, '500.00');
  assert.equal(a.currency, 'BDT');
  assert.ok(a.tranId.length <= 32 && a.tranId.length >= 8, 'AamarPay tran_id is limited to 32 characters');
  assert.match(a.tranId, /^TTF[0-9a-f]+$/);
  assert.equal(a.orderReference, o.reference);
  assert.equal(a.customerEmail, 'rahim@example.com');
  assert.equal(a.customerAddress, 'House 12, Road 4, Gazipur');
  assert.equal((await order(S.rahim, o.id)).payment.status, 'pending', 'starting a payment is not a payment');
});

test('the decimal amount string is exact for awkward values', async () => {
  const p = await api.rpc(S.adminId, 'public.admin_save_product', [{ code: 'AMT-001', productName: 'Odd', description: 'x', category: 'Accessories', priceMinor: 100005 }]);
  const o = await placeOrder(api, S.rahim, [line(p)], { paymentMethod: 'online' });
  assert.equal((await start(S.rahim, o.id)).amountDecimal, '1000.05');
  const p2 = await api.rpc(S.adminId, 'public.admin_save_product', [{ code: 'AMT-002', productName: 'Round', description: 'x', category: 'Accessories', priceMinor: 100000 }]);
  const o2 = await placeOrder(api, S.rahim, [line(p2)], { paymentMethod: 'online' });
  assert.equal((await start(S.rahim, o2.id)).amountDecimal, '1000.00');
});

test('payment start is idempotent per key and each attempt has a unique transaction id', async () => {
  const o = await onlineOrder();
  const a1 = await start(S.rahim, o.id, 'pay-key-0001');
  const a2 = await start(S.rahim, o.id, 'pay-key-0001');
  const b = await start(S.rahim, o.id, 'pay-key-0002');
  assert.equal(a1.tranId, a2.tranId, 'a retry reuses the attempt');
  assert.notEqual(a1.tranId, b.tranId);
  assert.equal((await api.admin(`select count(*)::int n from public.payment_attempts where order_id = $1`, [o.id])).rows[0].n, 2);
  await api.service(`select public.attach_payment_url($1, 'https://sandbox.aamarpay.com/paynow.php?track=T1')`, [a1.tranId]);
  assert.equal((await start(S.rahim, o.id, 'pay-key-0001')).paymentUrl, 'https://sandbox.aamarpay.com/paynow.php?track=T1');
});

test('a verified success marks the PAYMENT paid; the order status is untouched', async () => {
  const o = await onlineOrder();
  const a = await start(S.rahim, o.id);
  assert.equal((await record(a.tranId, ok(a), 'aamarpaytest')).outcome, 'paid');
  const after = await order(S.rahim, o.id);
  assert.equal(after.payment.status, 'successful');
  assert.equal(after.payment.provider, 'aamarpay');
  assert.equal(after.payment.transactionRef, `PG-${a.tranId}`);
  assert.equal(after.status, 'pending', 'order placement and payment are separate facts');
  assert.ok((await api.rpc(S.rahim, 'public.visible_notifications')).some((n) => n.title === 'Payment received'));
});

test('repeated callbacks are idempotent', async () => {
  const o = await onlineOrder();
  const a = await start(S.rahim, o.id);
  assert.equal((await record(a.tranId, ok(a))).outcome, 'paid');
  const count = async () => (await api.rpc(S.rahim, 'public.visible_notifications')).filter((n) => n.title === 'Payment received').length;
  const before = await count();
  for (let i = 0; i < 3; i++) assert.equal((await record(a.tranId, ok(a))).outcome, 'already_processed');
  assert.equal(await count(), before, 'no duplicate side effects');
  assert.equal((await order(S.rahim, o.id)).payment.status, 'successful');
  assert.equal((await record(a.tranId, { ...ok(a), statusCode: '7' })).outcome, 'already_processed');
  assert.equal((await order(S.rahim, o.id)).payment.status, 'successful');
});

test('mismatched amount, currency, transaction id or store are never accepted as paid', async () => {
  const cases = [
    ['amount', (a) => ok(a, { amount: '1.00' })],
    ['amount', (a) => ok(a, { amount: '999999.00' })],
    ['amount', (a) => ok(a, { amount: 'abc' })],
    ['amount', (a) => ok(a, { amount: undefined })],
    ['Currency', (a) => ok(a, { currency: 'USD' })],
    ['Transaction id', (a) => ok(a, { merTxnId: 'SOMEONE-ELSES' })],
  ];
  for (const [needle, make] of cases) {
    const o = await onlineOrder();
    const a = await start(S.rahim, o.id);
    const r = await record(a.tranId, make(a), 'aamarpaytest');
    assert.equal(r.outcome, 'mismatch', needle);
    assert.match(r.reason, new RegExp(needle, 'i'));
    assert.notEqual((await order(S.rahim, o.id)).payment.status, 'successful');
    assert.equal((await api.admin(`select needs_review from public.payments where order_id = $1`, [o.id])).rows[0].needs_review, true, 'flagged for a human');
  }
  const o = await onlineOrder();
  const a = await start(S.rahim, o.id);
  assert.equal((await record(a.tranId, ok(a, { storeId: 'other-store' }), 'aamarpaytest')).outcome, 'mismatch');
});

test('a gateway transaction id cannot be reused on another order', async () => {
  const o1 = await onlineOrder(); const a1 = await start(S.rahim, o1.id);
  const o2 = await onlineOrder(); const a2 = await start(S.rahim, o2.id);
  assert.equal((await record(a1.tranId, ok(a1, { pgTxnId: 'SHARED-1' }))).outcome, 'paid');
  assert.equal((await record(a2.tranId, ok(a2, { pgTxnId: 'SHARED-1' }))).outcome, 'mismatch');
  assert.notEqual((await order(S.rahim, o2.id)).payment.status, 'successful');
});

test('failed, expired and still-initiated results', async () => {
  const f = await onlineOrder(); const af = await start(S.rahim, f.id);
  assert.equal((await record(af.tranId, { statusCode: '7', merTxnId: af.tranId })).outcome, 'failed');
  assert.equal((await order(S.rahim, f.id)).payment.status, 'failed');
  const e = await onlineOrder(); const ae = await start(S.rahim, e.id);
  assert.equal((await record(ae.tranId, { statusCode: '3', merTxnId: ae.tranId })).outcome, 'expired');
  assert.equal((await order(S.rahim, e.id)).payment.status, 'failed');
  const p = await onlineOrder(); const ap = await start(S.rahim, p.id);
  assert.equal((await record(ap.tranId, { statusCode: '0', merTxnId: ap.tranId })).outcome, 'pending');
  assert.equal((await order(S.rahim, p.id)).payment.status, 'pending');
  assert.equal((await record(ap.tranId, { statusCode: 'garbage' })).outcome, 'pending');
  const retry = await start(S.rahim, f.id);
  assert.notEqual(retry.tranId, af.tranId);
  assert.equal((await record(retry.tranId, ok(retry))).outcome, 'paid');
  assert.equal((await order(S.rahim, f.id)).payment.status, 'successful');
});

test('cancelling the hosted page: only an unpaid attempt can be cancelled', async () => {
  const o = await onlineOrder(); const a = await start(S.rahim, o.id);
  const c = (await api.service(`select public.record_payment_cancel($1) as r`, [a.tranId])).rows[0].r;
  assert.equal(c.outcome, 'cancelled');
  assert.equal((await order(S.rahim, o.id)).payment.status, 'cancelled');
  assert.equal((await api.service(`select public.record_payment_cancel($1) as r`, [a.tranId])).rows[0].r.outcome, 'ignored');
  assert.equal((await record(a.tranId, ok(a))).outcome, 'paid');
  assert.equal((await order(S.rahim, o.id)).payment.status, 'successful');
  assert.equal((await api.service(`select public.record_payment_cancel($1) as r`, [a.tranId])).rows[0].r.outcome, 'ignored');
  await rejects(api.service(`select public.record_payment_cancel('NO-SUCH-TRAN')`), 'Unknown transaction');
});

test('a second successful payment for the same order is flagged, not applied twice', async () => {
  const o = await onlineOrder();
  const a = await start(S.rahim, o.id); const b = await start(S.rahim, o.id);
  assert.equal((await record(a.tranId, ok(a))).outcome, 'paid');
  assert.equal((await record(b.tranId, ok(b))).outcome, 'duplicate_success');
  const row = await api.admin(`select needs_review, review_reason, transaction_ref from public.payments where order_id = $1`, [o.id]);
  assert.equal(row.rows[0].needs_review, true);
  assert.equal(row.rows[0].transaction_ref, `PG-${a.tranId}`, 'the first payment stays authoritative');
  await rejects(start(S.rahim, o.id), 'already paid');
});

test('cancelled orders: attempts are closed, and late money is flagged for manual handling', async () => {
  const o = await onlineOrder(); const a = await start(S.rahim, o.id);
  await api.rpc(S.rahim, 'public.cancel_order', [o.id, 'Ordered by mistake']);
  assert.equal((await order(S.rahim, o.id)).payment.status, 'cancelled');
  await rejects(start(S.rahim, o.id), 'cancelled');
  assert.equal((await record(a.tranId, ok(a))).outcome, 'paid');
  const row = await api.admin(`select status, needs_review, review_reason from public.payments where order_id = $1`, [o.id]);
  assert.equal(row.rows[0].needs_review, true);
  assert.match(row.rows[0].review_reason, /cancelled order/);

  const paid = await onlineOrder(); const pa = await start(S.rahim, paid.id);
  await record(pa.tranId, ok(pa));
  const c = await api.rpc(S.rahim, 'public.cancel_order', [paid.id, 'No longer needed']);
  assert.equal(c.payment.status, 'successful', 'a paid payment is never silently reverted');
  const flag = await api.admin(`select needs_review, review_reason from public.payments where order_id = $1`, [paid.id]);
  assert.equal(flag.rows[0].needs_review, true);
  assert.match(flag.rows[0].review_reason, /refund handling is not defined/);
  assert.equal((await api.admin(`select paid_at_cancellation from public.cancellations where order_id = $1`, [paid.id])).rows[0].paid_at_cancellation, true);
});

test('only whitelisted gateway fields are stored; card data can never leak in', async () => {
  const o = await onlineOrder(); const a = await start(S.rahim, o.id);
  await record(a.tranId, ok(a, { cardNumber: '4111111111111111', card_holder: 'X', signatureKey: 'SECRET', paymentType: 'bKash' }));
  const v = (await api.admin(`select verification from public.payment_attempts where tran_id = $1`, [a.tranId])).rows[0].verification;
  assert.deepEqual(Object.keys(v).sort(), ['amount', 'currency', 'merTxnId', 'payStatus', 'paymentType', 'pgTxnId', 'statusCode', 'storeId']);
  assert.ok(!JSON.stringify(v).includes('4111'));
});

test('clients can never record payment results or touch payment rows', async () => {
  const o = await onlineOrder(); const a = await start(S.rahim, o.id);
  await rejects(api.rpc(S.rahim, 'public.record_payment_result', [a.tranId, ok(a)]), 'permission denied');
  await rejects(api.rpc(S.rahim, 'public.record_payment_cancel', [a.tranId]), 'permission denied');
  await rejects(api.rpc(S.rahim, 'public.attach_payment_url', [a.tranId, 'https://evil.example']), 'permission denied');
  await rejects(api.user(S.rahim)(`update public.payments set status='successful' where order_id=$1`, [o.id]), 'permission denied');
  await rejects(api.user(S.adminId)(`update public.payments set status='successful' where order_id=$1`, [o.id]), 'permission denied');
  await rejects(api.service(`select public.record_payment_result('UNKNOWN-TRAN', '{}'::jsonb)`), 'Unknown transaction');
});

test('the database blocks reverting or altering a payment', async () => {
  const o = await onlineOrder(); const a = await start(S.rahim, o.id);
  await record(a.tranId, ok(a));
  await rejects(api.admin(`update public.payments set status='pending' where order_id=$1`, [o.id]), 'cannot be reverted');
  await rejects(api.admin(`update public.payments set amount_minor=1 where order_id=$1`, [o.id]), 'cannot be changed');
});

test('payment start is rate limited', async () => {
  const id = await api.signUp('payer@example.com', { name: 'Pat Payer', phone: '01733334444', address: 'Road 5, Gazipur Sadar' });
  const o = await placeOrder(api, id, [line(S.buttons)], { paymentMethod: 'online' });
  let blocked = false;
  for (let i = 0; i < 15 && !blocked; i++) {
    try { await startRaw(id, o.id, `rate-key-${String(i).padStart(4, '0')}`); } catch (e) { blocked = String(e.message).includes('Too many attempts'); }
  }
  assert.ok(blocked);
});
