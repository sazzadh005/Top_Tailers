import test, { before } from 'node:test';
import assert from 'node:assert/strict';
import { freshDb, seed, rejects, line } from './harness.mjs';

let api, S;
before(async () => {
  api = await freshDb(); S = await seed(api);
  await api.rpc(S.adminId, 'public.admin_save_customer_discount', [S.nusrat, 'percent', 8, true, 'regular']);
});
const quote = (uid, items, voucher = null) => api.rpc(uid, 'public.quote_pricing', [items, voucher]);

test('plain total, integer paisa', async () => {
  const q = await quote(S.rahim, [line(S.buttons, 3)]);
  assert.equal(q.subtotalMinor, 75000);
  assert.equal(q.totalMinor, 75000);
  assert.equal(q.deliveryMinor, 0, 'the SRS defines no delivery charge');
  assert.equal(q.source, 'none');
});

test('product discount lowers the line and is reported separately', async () => {
  const q = await quote(S.rahim, [line(S.cotton, 3, { colorName: 'White' })]);
  assert.equal(q.subtotalMinor, 135000);
  assert.equal(q.productDiscountMinor, 13500);
  assert.equal(q.totalMinor, 121500);
});

test('percent discounts round down to the paisa', async () => {
  const p = await api.rpc(S.adminId, 'public.admin_save_product', [{ code: 'RND-001', productName: 'Odd', description: 'x', category: 'Accessories',
    priceMinor: 12345, discount: { enabled: true, kind: 'percent', value: 10 } }]);
  const q = await quote(S.rahim, [line(p)]);
  assert.equal(q.productDiscountMinor, 1234);
  assert.equal(q.totalMinor, 11111);
});

test('voucher: percent, fixed and category restricted', async () => {
  const pct = await quote(S.rahim, [line(S.buttons, 2)], 'DEMO10');
  assert.equal(pct.voucherDiscountMinor, 5000);
  assert.equal(pct.voucherCode, 'DEMO10');
  assert.equal(pct.totalMinor, 45000);
  assert.equal((await quote(S.rahim, [line(S.buttons, 2)], 'demoflat100')).voucherDiscountMinor, 10000);
  assert.equal((await quote(S.rahim, [line(S.silk), line(S.buttons)], 'DEMOFAB15')).voucherDiscountMinor, 18000);
});

test('a fixed voucher never exceeds the eligible amount', async () => {
  assert.equal((await quote(S.rahim, [line(S.buttons)], 'DEMOFLAT100')).voucherDiscountMinor, 10000);
  const tiny = await api.rpc(S.adminId, 'public.admin_save_product', [{ code: 'TNY-001', productName: 'Tiny', description: 'x', category: 'Accessories', priceMinor: 5000 }]);
  const q2 = await quote(S.rahim, [line(tiny)], 'DEMOFLAT100');
  assert.equal(q2.voucherDiscountMinor, 5000, 'capped at the basket');
  assert.equal(q2.totalMinor, 0);
});

test('voucher problems return the app\'s messages', async () => {
  assert.equal((await quote(S.rahim, [line(S.buttons)], 'NOPE')).voucherNote, 'This voucher code is not valid.');
  assert.equal((await quote(S.rahim, [line(S.buttons)], 'DEMOEXPIRED')).voucherNote, 'This voucher has expired.');
  assert.equal((await quote(S.rahim, [line(S.buttons)], 'DEMOOFF')).voucherNote, 'This voucher is not active.');
  assert.equal((await quote(S.rahim, [line(S.buttons)], 'DEMOFAB15')).voucherNote,
    'No eligible items in Fabrics. Vouchers do not apply to items that already have a discount.');
  const bad = await quote(S.rahim, [line(S.buttons)], 'NOPE');
  assert.equal(bad.voucherDiscountMinor, 0);
  assert.equal(bad.totalMinor, 25000, 'an invalid voucher changes nothing');
});

test('vouchers ignore lines that already carry a product discount', async () => {
  const onlyDiscounted = await quote(S.rahim, [line(S.cotton, 1, { colorName: 'White' })], 'DEMO10');
  assert.equal(onlyDiscounted.voucherDiscountMinor, 0);
  assert.match(onlyDiscounted.voucherNote, /already have a discount/);
  const mixed = await quote(S.rahim, [line(S.cotton, 1, { colorName: 'White' }), line(S.buttons, 4)], 'DEMO10');
  assert.equal(mixed.voucherDiscountMinor, 10000, '10% of the 1000.00 non-discounted line only');
  assert.equal(mixed.productDiscountMinor, 4500);
});

test('customer discount applies only to its owner', async () => {
  const mine = await quote(S.nusrat, [line(S.buttons, 4)]);
  assert.equal(mine.customerDiscountMinor, 8000);
  assert.equal(mine.source, 'customer');
  assert.equal((await quote(S.rahim, [line(S.buttons, 4)])).customerDiscountMinor, 0);
});

test('customer discount and voucher never stack: the larger wins, ties go to the customer', async () => {
  const items = [line(S.buttons, 4)];
  const voucherWins = await quote(S.nusrat, items, 'DEMO10');
  assert.equal(voucherWins.source, 'voucher');
  assert.equal(voucherWins.voucherDiscountMinor, 10000);
  assert.equal(voucherWins.customerDiscountMinor, 0);
  assert.equal(voucherWins.totalMinor, 90000);
  assert.equal((await quote(S.nusrat, [line(S.buttons, 1)], 'DEMOFLAT100')).source, 'voucher');

  await api.rpc(S.adminId, 'public.admin_save_customer_discount', [S.nusrat, 'percent', 20, true, 'vip']);
  const customer = await quote(S.nusrat, items, 'DEMO10');
  assert.equal(customer.source, 'customer');
  assert.equal(customer.customerDiscountMinor, 20000);
  assert.equal(customer.voucherDiscountMinor, 0);
  assert.match(customer.voucherNote, /not applied: your customer discount is larger/);

  await api.rpc(S.adminId, 'public.admin_save_customer_discount', [S.nusrat, 'percent', 10, true, 'tie']);
  const tie = await quote(S.nusrat, items, 'DEMO10');
  assert.equal(tie.source, 'customer', 'a tie goes to the customer discount');
  assert.equal(tie.totalMinor, 90000);
  assert.equal(tie.customerDiscountMinor + tie.voucherDiscountMinor, 10000, 'only one order-level discount');

  await api.rpc(S.adminId, 'public.admin_save_customer_discount', [S.nusrat, 'percent', 8, false, 'off']);
  assert.equal((await quote(S.nusrat, items)).customerDiscountMinor, 0, 'inactive discounts do not apply');
  await api.rpc(S.adminId, 'public.admin_save_customer_discount', [S.nusrat, 'percent', 8, true, 'regular']);
});

test('customer discount ignores items that already have a product discount', async () => {
  const q = await quote(S.nusrat, [line(S.cotton, 1, { colorName: 'White' })]);
  assert.equal(q.customerDiscountMinor, 0);
  assert.equal(q.productDiscountMinor, 4500);
});

test('removing the voucher restores the total', async () => {
  const items = [line(S.buttons, 2)];
  assert.equal((await quote(S.rahim, items, 'DEMO10')).totalMinor, 45000);
  assert.equal((await quote(S.rahim, items)).totalMinor, 50000);
});

test('admin discount settings are validated', async () => {
  const cd = (kind, v) => api.rpc(S.adminId, 'public.admin_save_customer_discount', [S.rahim, kind, v, true, '']);
  await rejects(cd('percent', 0), 'greater than 0');
  await rejects(cd('percent', 100), 'between 1 and 99');
  await rejects(cd('fixed', -5), 'greater than 0');
  await rejects(cd('weird', 5), 'percentage or a fixed');
  await rejects(api.rpc(S.adminId, 'public.admin_save_customer_discount', [S.adminId, 'percent', 5, true, '']), 'Customer not found');
  assert.equal((await cd('fixed', 5000)).value, 5000);
  assert.equal((await api.rpc(S.rahim, 'public.my_customer_discount')).kind, 'fixed');
  await api.rpc(S.adminId, 'public.admin_remove_customer_discount', [S.rahim]);
  assert.equal(await api.rpc(S.rahim, 'public.my_customer_discount'), null);
});

test('delivery charge is configurable but off by default', async () => {
  await api.admin(`update public.app_settings set value='6000' where key='delivery_flat_minor'`);
  const flat = await quote(S.rahim, [line(S.buttons)]);
  assert.equal(flat.deliveryMinor, 6000);
  assert.equal(flat.totalMinor, 31000);
  await api.admin(`update public.app_settings set value='30000' where key='delivery_free_above_minor'`);
  assert.equal((await quote(S.rahim, [line(S.buttons)])).deliveryMinor, 6000);
  assert.equal((await quote(S.rahim, [line(S.buttons, 10)])).deliveryMinor, 0);
  await api.admin(`update public.app_settings set value='0' where key='delivery_flat_minor'`);
  await api.admin(`update public.app_settings set value=null where key='delivery_free_above_minor'`);
});

test('unknown or deleted products cannot be quoted', async () => {
  await rejects(quote(S.rahim, [{ productId: '00000000-0000-0000-0000-000000000000', quantity: 1 }]), 'no longer available');
  await rejects(api.rpc(S.rahim, 'public.quote_pricing', ['"not-an-array"']), 'Your cart is empty');
});
