import test, { before } from 'node:test';
import assert from 'node:assert/strict';
import { freshDb, seed, rejects, line, placeOrder } from './harness.mjs';

let api, S;
before(async () => {
  api = await freshDb(); S = await seed(api);
  await api.rpc(S.adminId, 'public.admin_save_customer_discount', [S.nusrat, 'percent', 8, true, 'regular']);
  await api.rpc(S.rahim, 'public.set_measurements', [S.rahim, { chest: 98, waist: 86, neck: 38 }]);
});
const place = (uid, items, extra) => placeOrder(api, uid, items, extra);
const admin = (fn, args) => api.rpc(S.adminId, `public.${fn}`, args);
const status = (id, st) => admin('update_order_status', [id, st]);
const advance = async (id, to) => {
  const path = ['confirmed', 'processing', 'completed'];
  for (const st of path.slice(0, path.indexOf(to) + 1)) await status(id, st);
};

test('placing an order stores a full snapshot and a pending cash-on-delivery payment', async () => {
  const o = await place(S.rahim, [line(S.cotton, 2, { colorName: 'White' }), line(S.buttons, 1)], { note: 'Call first' });
  assert.match(o.reference, /^TTF-\d{6}-[A-HJ-NP-Z2-9]{4}$/);
  assert.notEqual(o.reference, o.id, 'reference is for display; id is the stable key');
  assert.equal(o.status, 'pending');
  assert.equal(o.customerName, 'Rahim Uddin');
  assert.equal(o.note, 'Call first');
  assert.equal(o.payment.method, 'cod');
  assert.equal(o.payment.status, 'pending');
  assert.equal(o.payment.provider, 'none');
  assert.equal(o.payment.amountMinor, o.totalMinor);
  assert.equal(o.history.length, 1);
  assert.equal(o.history[0].status, 'pending');
  const cotton = o.items.find((i) => i.productCode === 'FAB-COT-001');
  assert.equal(cotton.listUnitMinor, 45000);
  assert.equal(cotton.unitMinor, 40500, 'discounted price actually charged');
  assert.equal(cotton.colorName, 'White');
  assert.equal(o.subtotalMinor, 90000 + 25000);
  assert.equal(o.productDiscountMinor, 9000);
  assert.equal(o.totalMinor, 115000 - 9000);
  assert.ok((await api.rpc(S.rahim, 'public.visible_notifications')).map((n) => n.title).includes('Order placed'));
});

test('each order keeps its own contact number; the profile is never read back', async () => {
  const a = await place(S.rahim, [line(S.buttons)], { contactPhone: '01912345678' });
  const b = await place(S.rahim, [line(S.buttons)], { contactPhone: '+880 1812-345678' });
  assert.equal(a.contactPhone, '01912345678');
  assert.equal(b.contactPhone, '01812345678', 'canonical form');
  await api.rpc(S.rahim, 'public.update_my_profile', ['Rahim Uddin', '01611112222', 'New address, Gazipur']);
  const again = await api.rpc(S.rahim, 'public.get_order', [a.id]);
  assert.equal(again.contactPhone, '01912345678');
  assert.equal(again.shippingAddress, 'House 12, Road 4, Gazipur', 'address snapshot is unaffected too');
  assert.equal((await api.rpc(S.rahim, 'public.my_profile')).phone, '01611112222');
  await api.rpc(S.rahim, 'public.update_my_profile', ['Rahim Uddin', '01712345678', 'House 12, Road 4, Gazipur Sadar']);
});

test('invalid contact numbers and addresses are rejected', async () => {
  await rejects(place(S.rahim, [line(S.buttons)], { contactPhone: '12345' }), 'valid mobile number');
  await rejects(place(S.rahim, [line(S.buttons)], { contactPhone: '02712345678' }), 'valid mobile number');
  await rejects(place(S.rahim, [line(S.buttons)], { shippingAddress: 'abc' }), 'more complete address');
  await rejects(place(S.rahim, [line(S.buttons)], { shippingAddress: '  ' }), 'address is required');
  await rejects(place(S.rahim, [line(S.buttons)], { note: 'x'.repeat(301) }), '300 characters');
  await rejects(place(S.rahim, [line(S.buttons)], { paymentMethod: 'cheque' }), 'Cash on Delivery or Online');
});

test('measurement snapshots belong to the order and survive profile edits', async () => {
  const item = [line(S.stitching)];
  const custom = await place(S.rahim, item, { measurements: { source: 'enteredForOrder', values: { chest: 101, neck: 39 } } });
  assert.equal(custom.measurements.source, 'enteredForOrder');
  assert.equal(custom.measurements.values.chest, 101);
  const fromProfile = await place(S.rahim, item, { measurements: { source: 'profile', values: { chest: 999 } } });
  assert.equal(fromProfile.measurements.values.chest, 98, 'profile source uses the SERVER copy, not client values');
  const other = await place(S.rahim, item, { measurements: { source: 'otherPerson', forPerson: 'Karim', values: { chest: 110 } } });
  assert.equal(other.measurements.forPerson, 'Karim');
  await api.rpc(S.rahim, 'public.set_measurements', [S.rahim, { chest: 120 }]);
  assert.equal((await api.rpc(S.rahim, 'public.get_order', [fromProfile.id])).measurements.values.chest, 98);
  assert.equal((await api.rpc(S.rahim, 'public.get_order', [custom.id])).measurements.values.chest, 101);
  assert.equal((await api.rpc(S.rahim, 'public.my_profile')).measurements.chest, 120);
  await api.rpc(S.rahim, 'public.set_measurements', [S.rahim, { chest: 98, waist: 86, neck: 38 }]);
});

test('tailoring orders need valid measurements; other orders do not', async () => {
  const item = [line(S.stitching)];
  await rejects(place(S.rahim, item), 'Measurements are required');
  await rejects(place(S.rahim, item, { measurements: { source: 'enteredForOrder', values: {} } }), 'at least one measurement');
  await rejects(place(S.rahim, item, { measurements: { source: 'enteredForOrder', values: { chest: 5 } } }), 'between 60 and 160');
  await rejects(place(S.rahim, item, { measurements: { source: 'enteredForOrder', values: { biceps: 30 } } }), 'Unknown measurement field');
  await rejects(place(S.rahim, item, { measurements: { source: 'otherPerson', values: { chest: 100 } } }), 'name of the person');
  await rejects(place(S.nusrat, item, { measurements: { source: 'profile' } }), 'no saved measurements');
  assert.equal((await place(S.rahim, [line(S.buttons)])).measurements, null);
});

test('prices are recomputed on the server: a stale or forged total is rejected', async () => {
  const req = (total) => ({ contactPhone: '01712345678', shippingAddress: 'House 12, Road 4, Gazipur', paymentMethod: 'cod',
    items: [line(S.buttons, 2)], expectedTotalMinor: total });
  await rejects(api.rpc(S.rahim, 'public.place_order', [req(1)]), 'Prices or discounts changed');
  await rejects(api.rpc(S.rahim, 'public.place_order', [req(0)]), 'Prices or discounts changed');
  assert.equal((await api.rpc(S.rahim, 'public.place_order', [req(50000)])).totalMinor, 50000);
  const forged = await api.rpc(S.rahim, 'public.place_order', [{ ...req(50000), items: [{ ...line(S.buttons, 2), unitMinor: 1, priceMinor: 1 }] }]);
  assert.equal(forged.items[0].unitMinor, 25000);
});

test('a price change between quote and checkout is detected', async () => {
  const p = await admin('admin_save_product', [{ code: 'CHG-001', productName: 'Changing', description: 'x', category: 'Accessories', priceMinor: 10000 }]);
  const quote = await api.rpc(S.rahim, 'public.quote_pricing', [[line(p)]]);
  await admin('admin_save_product', [{ id: p.id, code: 'CHG-001', productName: 'Changing', description: 'x', category: 'Accessories', priceMinor: 12000 }]);
  await rejects(api.rpc(S.rahim, 'public.place_order', [{ contactPhone: '01712345678', shippingAddress: 'House 12, Road 4, Gazipur',
    paymentMethod: 'cod', items: [line(p)], expectedTotalMinor: quote.totalMinor }]), 'Prices or discounts changed');
});

test('availability, variants, quantity and voucher rules are enforced at checkout', async () => {
  await rejects(place(S.rahim, [line(S.velvet, 1, { colorName: 'Wine' })]), 'no longer available');
  await rejects(place(S.rahim, [line(S.cotton)]), 'choose a colour');
  await rejects(place(S.rahim, [line(S.cotton, 1, { colorName: 'Purple' })]), 'colour is no longer offered');
  await rejects(place(S.rahim, [line(S.shirt, 1, { colorName: 'White' })]), 'choose a size');
  await rejects(place(S.rahim, [line(S.shirt, 1, { colorName: 'White', size: 'XXL' })]), 'size is no longer offered');
  await rejects(place(S.rahim, [line(S.buttons, 1, { size: 'M' })]), 'size is no longer offered');
  await rejects(place(S.rahim, [line(S.buttons, 21)]), 'Invalid quantity');
  await rejects(place(S.rahim, [line(S.buttons, 0)]), 'Invalid quantity');
  await rejects(place(S.rahim, []), 'cart is empty');
  await rejects(place(S.rahim, [line(S.buttons)], { voucherCode: 'DEMOEXPIRED', expectedTotalMinor: 25000 }), 'expired');
  await rejects(place(S.rahim, [line(S.buttons)], { voucherCode: 'NOPE', expectedTotalMinor: 25000 }), 'not valid');
});

test('a voucher is recorded on the order; the larger discount wins and is recorded', async () => {
  const v = await place(S.rahim, [line(S.buttons, 2)], { voucherCode: 'DEMO10' });
  assert.equal(v.voucherCode, 'DEMO10');
  assert.equal(v.voucherDiscountMinor, 5000);
  assert.equal(v.customerDiscountMinor, 0);
  assert.equal((await place(S.nusrat, [line(S.buttons, 2)], { voucherCode: 'DEMOFLAT100' })).voucherDiscountMinor, 10000);
  const c = await place(S.nusrat, [line(S.buttons, 2)]);
  assert.equal(c.customerDiscountMinor, 4000);
  assert.equal(c.voucherCode, null);
  assert.equal((await place(S.nusrat, [line(S.buttons, 2)], { voucherCode: 'DEMO10', expectedTotalMinor: 45000 })).voucherDiscountMinor, 5000, '10% beats 8%');
});

test('admins cannot place orders; anonymous callers cannot either', async () => {
  await rejects(api.rpc(S.adminId, 'public.place_order', [{ items: [line(S.buttons)], expectedTotalMinor: 25000, contactPhone: '01712345678', shippingAddress: 'House 12, Road 4', paymentMethod: 'cod' }]), 'Only customers');
  await rejects(api.anon(`select public.place_order('{}'::jsonb)`), 'permission denied');
});

test('idempotency keys prevent duplicate orders', async () => {
  const items = [line(S.buttons)];
  const before = (await api.rpc(S.rahim, 'public.search_orders')).length;
  const a = await place(S.rahim, items, { __key: 'key-abcdef-001' });
  const b = await place(S.rahim, items, { __key: 'key-abcdef-001' });
  assert.equal(a.id, b.id, 'a retried request returns the original order');
  assert.equal((await api.rpc(S.rahim, 'public.search_orders')).length, before + 1, 'only one order was created');
  await rejects(place(S.rahim, [line(S.buttons, 2)], { __key: 'key-abcdef-001' }), 'already used for a different order');
  assert.notEqual((await place(S.rahim, items, { __key: 'key-abcdef-002' })).id, a.id);
  await rejects(place(S.rahim, items, { __key: 'short' }), 'Invalid idempotency key');
  assert.notEqual((await place(S.nusrat, items, { __key: 'key-abcdef-001' })).id, a.id, 'keys are per user');
});

test('order snapshots cannot be changed or deleted, by anyone', async () => {
  const o = await place(S.rahim, [line(S.buttons)]);
  await rejects(api.admin(`update public.orders set contact_phone = '01999999999' where id = $1`, [o.id]), 'snapshot');
  await rejects(api.admin(`update public.orders set total_minor = 1, subtotal_minor = 1 where id = $1`, [o.id]), 'snapshot');
  await rejects(api.admin(`delete from public.orders where id = $1`, [o.id]), 'append-only');
  await rejects(api.admin(`update public.order_items set unit_minor = 1 where order_id = $1`, [o.id]), 'append-only');
  await rejects(api.admin(`delete from public.order_items where order_id = $1`, [o.id]), 'append-only');
  await rejects(api.admin(`delete from public.order_events where order_id = $1`, [o.id]), 'append-only');
  await rejects(api.admin(`delete from public.payments where order_id = $1`, [o.id]), 'append-only');
  await rejects(api.admin(`delete from public.profiles where id = $1`, [S.rahim]), 'violates RESTRICT');
  await admin('admin_save_product', [{ id: S.buttons.id, code: 'ACC-BTN-301', productName: 'Renamed', description: 'x', category: 'Accessories', priceMinor: 99999 }]);
  const stored = await api.rpc(S.rahim, 'public.get_order', [o.id]);
  assert.equal(stored.items[0].productName, 'Button & Thread Set');
  assert.equal(stored.items[0].unitMinor, 25000);
  await admin('admin_save_product', [{ id: S.buttons.id, code: 'ACC-BTN-301', productName: 'Button & Thread Set', description: 'x', category: 'Accessories', priceMinor: 25000 }]);
});

test('the status machine only moves forward, one step at a time, by the admin', async () => {
  const o = await place(S.rahim, [line(S.buttons)]);
  await rejects(status(o.id, 'completed'), 'cannot move from Pending to Completed');
  await rejects(status(o.id, 'processing'), 'cannot move from Pending to Processing');
  await rejects(status(o.id, 'cancelled'), 'cancel action');
  await rejects(status(o.id, 'bogus'), 'cannot move');
  assert.equal((await status(o.id, 'confirmed')).status, 'confirmed');
  await rejects(status(o.id, 'pending'), 'cannot move');
  await rejects(status(o.id, 'confirmed'), 'cannot move');
  await status(o.id, 'processing');
  await status(o.id, 'completed');
  const done = await api.rpc(S.rahim, 'public.get_order', [o.id]);
  assert.deepEqual(done.history.map((h) => h.status), ['pending', 'confirmed', 'processing', 'completed']);
  await rejects(status(o.id, 'confirmed'), 'cannot move');
  const o2 = await place(S.rahim, [line(S.buttons)]);
  await rejects(api.admin(`update public.orders set status = 'completed' where id = $1`, [o2.id]), 'cannot move from Pending to Completed');
  await rejects(api.admin(`update public.orders set status = 'cancelled' where id = $1`, [o2.id]), 'cancellation record is required');
});

test('completing a cash-on-delivery order confirms its payment; the customer is notified', async () => {
  const o = await place(S.rahim, [line(S.buttons)]);
  await advance(o.id, 'completed');
  const done = await api.rpc(S.rahim, 'public.get_order', [o.id]);
  assert.equal(done.payment.status, 'successful');
  assert.equal(done.payment.provider, 'none');
  assert.ok((await api.rpc(S.rahim, 'public.visible_notifications')).some((n) => n.title === 'Order Completed' && n.body.includes(o.reference)));
});

test('customer cancellation: reason required, recorded with who/when, only while Pending', async () => {
  const o = await place(S.rahim, [line(S.buttons)]);
  await rejects(api.rpc(S.rahim, 'public.cancel_order', [o.id, '  ']), 'cancellation reason');
  await rejects(api.rpc(S.rahim, 'public.cancel_order', [o.id, 'Other', 'no']), 'describe the reason');
  const c = await api.rpc(S.rahim, 'public.cancel_order', [o.id, 'Ordered by mistake', 'Sorry']);
  assert.equal(c.status, 'cancelled');
  assert.equal(c.cancellation.cancelledBy, 'customer');
  assert.equal(c.cancellation.cancelledByName, 'Rahim Uddin');
  assert.equal(c.cancellation.reason, 'Ordered by mistake');
  assert.equal(c.cancellation.note, 'Sorry');
  assert.ok(c.cancellation.cancelledAt);
  assert.deepEqual(c.history.map((h) => h.status), ['pending', 'cancelled'], 'history is preserved');
  assert.equal(c.items.length, 1, 'cancelled orders are never deleted');
  await rejects(api.rpc(S.rahim, 'public.cancel_order', [o.id, 'again']), 'already been cancelled');
  await rejects(admin('cancel_order', [o.id, 'again']), 'already been cancelled');
  assert.ok((await api.rpc(S.rahim, 'public.visible_notifications')).some((n) => n.title === 'Order cancelled'));
});

test('cancellation rules: customers Pending only, admins Pending or Confirmed, owners only', async () => {
  const o = await place(S.rahim, [line(S.buttons)]);
  await status(o.id, 'confirmed');
  await rejects(api.rpc(S.rahim, 'public.cancel_order', [o.id, 'No longer needed']), 'only while it is Pending');
  const byAdmin = await admin('cancel_order', [o.id, 'Item out of stock', 'Size sold out']);
  assert.equal(byAdmin.cancellation.cancelledBy, 'shopAdmin');
  assert.equal(byAdmin.cancellation.reason, 'Item out of stock');
  assert.equal(byAdmin.cancellation.cancelledByName, 'Shop Admin');
  assert.ok((await api.rpc(S.rahim, 'public.visible_notifications')).some((n) => n.title === 'Order cancelled' && n.body.includes('cancelled by the shop')));
  const p = await place(S.rahim, [line(S.buttons)]);
  await advance(p.id, 'processing');
  await rejects(admin('cancel_order', [p.id, 'Pricing or listing error']), 'Only Pending or Confirmed');
  await rejects(api.rpc(S.rahim, 'public.cancel_order', [p.id, 'x']), 'only while it is Pending');
  const theirs = await place(S.rahim, [line(S.buttons)]);
  await rejects(api.rpc(S.nusrat, 'public.cancel_order', [theirs.id, 'not mine']), 'only cancel your own');
  assert.equal((await admin('get_order', [theirs.id])).status, 'pending');
  await rejects(api.rpc(S.rahim, 'public.cancel_order', ['00000000-0000-0000-0000-000000000000', 'x']), 'Order not found');
});

test('cancellation records are permanent and unique per order', async () => {
  const o = await place(S.rahim, [line(S.buttons)]);
  await api.rpc(S.rahim, 'public.cancel_order', [o.id, 'Ordered by mistake']);
  await rejects(api.admin(`delete from public.cancellations where order_id = $1`, [o.id]), 'append-only');
  await rejects(api.admin(`update public.cancellations set reason = 'edited' where order_id = $1`, [o.id]), 'append-only');
  await rejects(api.admin(`insert into public.cancellations(order_id, cancelled_by, cancelled_by_user, cancelled_by_name, reason) values ($1,'customer',$2,'x','y')`, [o.id, S.rahim]), 'duplicate key');
  await rejects(api.admin(`update public.orders set status = 'pending' where id = $1`, [o.id]), 'cannot move from Cancelled');
});

test('order search: scope, fields and filters', async () => {
  const mine = await api.rpc(S.rahim, 'public.search_orders');
  assert.ok(mine.length > 5 && mine.every((o) => o.userId === S.rahim), 'customers only ever see their own orders');
  assert.equal((await api.rpc(S.rahim, 'public.search_orders', ['Nusrat'])).length, 0, 'customers cannot find other people by name');
  const nusratOrders = await api.rpc(S.nusrat, 'public.search_orders');
  assert.ok(nusratOrders.length > 0 && nusratOrders.every((o) => o.userId === S.nusrat));
  const all = await api.rpc(S.adminId, 'public.search_orders');
  assert.ok(all.length > mine.length);
  const byName = await api.rpc(S.adminId, 'public.search_orders', ['nusrat']);
  assert.ok(byName.length > 0 && byName.every((o) => o.customerName === 'Nusrat Jahan'));
  assert.equal((await api.rpc(S.rahim, 'public.search_orders', [mine[0].reference.toLowerCase()])).length, 1, 'by reference');
  assert.equal((await api.rpc(S.rahim, 'public.search_orders', [mine[0].id])).length, 1, 'by order id');
  const byCode = await api.rpc(S.adminId, 'public.search_orders', ['TLR-SHT-201']);
  assert.ok(byCode.length > 0 && byCode.every((o) => o.items.some((i) => i.productCode === 'TLR-SHT-201')));
  assert.ok((await api.rpc(S.adminId, 'public.search_orders', ['shirt stitching'])).length > 0, 'by product name');
  const byPhone = await api.rpc(S.adminId, 'public.search_orders', ['01912345678']);
  assert.ok(byPhone.length > 0 && byPhone.every((o) => o.contactPhone === '01912345678'));
  const cancelled = await api.rpc(S.adminId, 'public.search_orders', ['', 'cancelled']);
  assert.ok(cancelled.length > 0 && cancelled.every((o) => o.status === 'cancelled'));
  assert.ok((await api.rpc(S.adminId, 'public.search_orders', ['cancelled'])).some((o) => o.status === 'cancelled'), 'status as a keyword');
  const completedPaid = await api.rpc(S.adminId, 'public.search_orders', ['', 'completed', 'successful']);
  assert.ok(completedPaid.every((o) => o.status === 'completed' && o.payment.status === 'successful'));
  assert.ok((await api.rpc(S.adminId, 'public.search_orders', ['', null, 'pending'])).every((o) => o.payment.status === 'pending'));
  // The shop's calendar is Asia/Dhaka, so "today" must be the Dhaka date, not the UTC date.
  const today = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Dhaka' }).format(new Date());
  assert.ok((await api.rpc(S.adminId, 'public.search_orders', ['', null, null, today, today])).length > 0, 'orders placed today fall in today\'s range');
  assert.equal((await api.rpc(S.adminId, 'public.search_orders', ['', null, null, '2020-01-01', '2020-01-02'])).length, 0);
  assert.equal((await api.rpc(S.adminId, 'public.search_orders', ['no-such-thing-xyz'])).length, 0);
});

test('order search validation and safe wildcard handling', async () => {
  await rejects(api.rpc(S.rahim, 'public.search_orders', ['x'.repeat(61)]), 'too long');
  await rejects(api.rpc(S.rahim, 'public.search_orders', ['', null, null, '2026-10-10', '2026-10-01']), 'start date must be before');
  await rejects(api.rpc(S.rahim, 'public.search_orders', ['', 'bogus']), 'Unknown order status');
  await rejects(api.rpc(S.rahim, 'public.search_orders', ['', null, 'bogus']), 'Unknown payment status');
  assert.equal((await api.rpc(S.rahim, 'public.search_orders', ['%'])).length, 0);
  assert.equal((await api.rpc(S.rahim, 'public.search_orders', ["' or 1=1 --"])).length, 0);
  await rejects(api.anon(`select public.search_orders()`), 'permission denied');
});

test('get_order is visible to the owner and the admin only', async () => {
  const o = await place(S.rahim, [line(S.buttons)]);
  assert.equal((await api.rpc(S.rahim, 'public.get_order', [o.id])).id, o.id);
  assert.equal((await api.rpc(S.adminId, 'public.get_order', [o.id])).id, o.id);
  await rejects(api.rpc(S.nusrat, 'public.get_order', [o.id]), 'Order not found');
});

test('lifetime spending counts Completed + paid orders once, excluding everything else', async () => {
  const id = await api.signUp('spender@example.com', { name: 'Sam Spender', phone: '01655556666', address: 'Sunrise Tower, Tongi' });
  const mk = (n) => place(id, [line(S.buttons, n)]);
  const completedCod = await mk(1);   await advance(completedCod.id, 'completed');
  const cancelled = await mk(2);      await api.rpc(id, 'public.cancel_order', [cancelled.id, 'Ordered by mistake']);
  await mk(3);
  const onlinePending = await place(id, [line(S.buttons, 4)], { paymentMethod: 'online' });
  await advance(onlinePending.id, 'completed');
  const onlinePaid = await place(id, [line(S.buttons, 5)], { paymentMethod: 'online' });
  await advance(onlinePaid.id, 'completed');
  const tran = await api.rpc(id, 'public.start_payment_attempt', [onlinePaid.id]);
  await api.service(`select public.record_payment_result($1, $2::jsonb)`, [tran.tranId, JSON.stringify({ statusCode: '2', merTxnId: tran.tranId, amount: tran.amountDecimal, currency: 'BDT', pgTxnId: 'PG1' })]);
  const me = (await admin('admin_list_customers', [])).find((c) => c.id === id);
  assert.equal(me.orderCount, 5);
  assert.equal(me.lifetimeSpendingMinor, 25000 + 125000, 'only completed + paid orders');
});

test('the customer list is admin-only and never exposes password data', async () => {
  const list = await admin('admin_list_customers', []);
  assert.ok(list.every((c) => c.role === 'customer'));
  assert.ok(list.every((c) => !('passwordHash' in c) && !('password' in c)));
  await rejects(api.rpc(S.rahim, 'public.admin_list_customers'), 'Only the shop admin');
});

test('order date filters use Dhaka calendar days (midnight boundary, inclusive end date)', async () => {
  const o = await place(S.rahim, [line(S.buttons)]);
  // 18:30 UTC on 1 March is 00:30 on 2 March in Dhaka. Orders are immutable, so move the
  // timestamp the way a migration or restore would: as the table owner with the guard paused.
  await api.admin(`alter table public.orders disable trigger orders_guard_trg`);
  await api.admin(`update public.orders set order_date = '2026-03-01T18:30:00Z' where id = $1`, [o.id]);
  await api.admin(`alter table public.orders enable trigger orders_guard_trg`);
  const on = async (from, to) => (await api.rpc(S.rahim, 'public.search_orders', ['', null, null, from, to])).some((x) => x.id === o.id);
  assert.equal(await on('2026-03-02', '2026-03-02'), true, 'it is 2 March in Dhaka');
  assert.equal(await on('2026-03-01', '2026-03-01'), false, 'it is not 1 March in Dhaka');
  assert.equal(await on('2026-03-01', '2026-03-02'), true, 'the end date is inclusive');
  assert.equal(await on('2026-03-03', '2026-03-04'), false);
});
