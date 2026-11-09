import test, { before } from 'node:test';
import assert from 'node:assert/strict';
import { freshDb, seed, rejects, line, placeOrder, VALID_META } from './harness.mjs';

let api, S, order;
before(async () => {
  api = await freshDb();
  S = await seed(api);
  order = await placeOrder(api, S.rahim, [line(S.buttons, 2)]);
});

test('anonymous users can read and call nothing', async () => {
  for (const t of ['profiles', 'products', 'orders', 'payments', 'vouchers', 'notifications', 'app_settings']) {
    await rejects(api.anon(`select * from public.${t}`), 'permission denied');
  }
  await rejects(api.anon(`select public.search_products('')`), 'permission denied');
  await rejects(api.anon(`select public.place_order('{}'::jsonb)`), 'permission denied');
});

test('signed-in users cannot touch internal tables', async () => {
  for (const t of ['app_settings', 'idempotency_keys', 'rate_limits', 'image_cleanup_queue', 'image_upload_tickets']) {
    await rejects(api.user(S.rahim)(`select * from public.${t}`), 'permission denied');
  }
});

test('a customer sees only their own profile, orders, measurements and notifications', async () => {
  const u = api.user(S.nusrat);
  assert.deepEqual((await u(`select id from public.profiles`)).rows.map((r) => r.id), [S.nusrat]);
  assert.equal((await u(`select * from public.orders`)).rows.length, 0);
  assert.equal((await u(`select * from public.payments`)).rows.length, 0);
  assert.equal((await u(`select * from public.order_items`)).rows.length, 0);
  assert.equal((await u(`select * from public.notifications where user_id = $1`, [S.rahim])).rows.length, 0);
  assert.equal((await api.user(S.rahim)(`select * from public.orders`)).rows.length, 1);
  await rejects(api.rpc(S.nusrat, 'public.get_order', [order.id]), 'Order not found');
});

test('customers cannot write business tables directly', async () => {
  const u = api.user(S.rahim);
  await rejects(u(`update public.orders set total_minor = 1`), 'permission denied');
  await rejects(u(`delete from public.orders`), 'permission denied');
  await rejects(u(`insert into public.products(code, product_name, price_minor, category) values ('HAX-001','x',1,'Fabrics')`), 'permission denied');
  await rejects(u(`update public.products set price_minor = 1`), 'permission denied');
  await rejects(u(`insert into public.vouchers(code,title,kind,value) values ('FREE100','x','percent',99)`), 'permission denied');
  await rejects(u(`insert into public.customer_discounts(customer_id,kind,value) values ($1,'percent',99)`, [S.rahim]), 'permission denied');
  await rejects(u(`update public.payments set status = 'successful'`), 'permission denied');
  await rejects(u(`insert into public.notifications(user_id,title) values ($1,'x')`, [S.rahim]), 'permission denied');
});

test('role escalation is impossible', async () => {
  await rejects(api.user(S.rahim)(`update public.profiles set role = 'admin' where id = $1`, [S.rahim]), 'permission denied');
  const id = await api.signUp('sneaky@example.com', { ...VALID_META, role: 'admin' });
  const r = await api.admin(`select role from public.profiles where id = $1`, [id]);
  assert.equal(r.rows[0].role, 'customer', 'client metadata must never grant admin');
  await rejects(api.db.exec(`set role authenticated; update public.profiles set role='admin' where id='${id}'`), 'permission denied');
  await api.db.exec('reset role');
  assert.equal((await api.rpc(S.rahim, 'public.is_admin')), false);
  assert.equal((await api.rpc(S.adminId, 'public.is_admin')), true);
});

test('only the trusted service tooling can provision admins and call internal functions', async () => {
  await rejects(api.rpc(S.rahim, 'public.provision_admin', ['rahim@example.com']), 'permission denied');
  await rejects(api.rpc(S.rahim, 'public.record_payment_result', ['X', {}]), 'permission denied');
  await rejects(api.rpc(S.rahim, 'public.purge_old_notifications'), 'permission denied');
  await rejects(api.rpc(S.rahim, 'public.compute_pricing', [[line(S.buttons)], null, S.nusrat]), 'permission denied');
  await rejects(api.rpc(S.rahim, 'public.claim_cloudinary_cleanup'), 'permission denied');
  await api.service(`select public.purge_old_notifications()`);
});

test('customers are refused every admin operation', async () => {
  const deny = 'Only the shop admin';
  await rejects(api.rpc(S.rahim, 'public.admin_save_product', [{ code: 'NEW-001', productName: 'x', description: 'y', priceMinor: 100, category: 'Fabrics' }]), deny);
  await rejects(api.rpc(S.rahim, 'public.admin_delete_product', [S.cotton.id]), deny);
  await rejects(api.rpc(S.rahim, 'public.admin_list_customers'), deny);
  await rejects(api.rpc(S.rahim, 'public.admin_save_customer_discount', [S.rahim, 'percent', 50, true, '']), deny);
  await rejects(api.rpc(S.rahim, 'public.admin_save_voucher', [{ code: 'FREE', kind: 'percent', value: 50 }]), deny);
  await rejects(api.rpc(S.rahim, 'public.admin_all_feedback'), deny);
  await rejects(api.rpc(S.rahim, 'public.update_order_status', [order.id, 'confirmed']), deny);
  await rejects(api.rpc(S.rahim, 'public.admin_is_code_taken', ['X']), deny);
});

test('payment attempts and voucher definitions are not readable by customers', async () => {
  assert.equal((await api.user(S.rahim)(`select * from public.vouchers`)).rows.length, 0);
  assert.equal((await api.user(S.rahim)(`select * from public.payment_attempts`)).rows.length, 0);
  assert.ok((await api.user(S.adminId)(`select * from public.vouchers`)).rows.length >= 5);
});

test('measurements are private to the owner and the admin', async () => {
  await api.rpc(S.rahim, 'public.set_measurements', [S.rahim, { chest: 98, waist: 86 }]);
  assert.equal((await api.user(S.nusrat)(`select * from public.customer_measurements`)).rows.length, 0);
  await rejects(api.rpc(S.nusrat, 'public.set_measurements', [S.rahim, { chest: 120 }]), 'You can only change your own measurements.');
  const asAdmin = await api.rpc(S.adminId, 'public.set_measurements', [S.rahim, { chest: 99 }]);
  assert.equal(asAdmin.measurements.chest, 99);
  assert.equal((await api.user(S.adminId)(`select * from public.customer_measurements`)).rows.length, 1);
});

test('profile edits are validated and cannot change identity', async () => {
  await rejects(api.rpc(S.rahim, 'public.update_my_profile', ['R', '01712345678', 'House 12, Road 4']), 'Name must be at least 2 characters');
  await rejects(api.rpc(S.rahim, 'public.update_my_profile', ['Rahim', '12345', 'House 12, Road 4']), 'valid mobile number');
  await rejects(api.rpc(S.rahim, 'public.update_my_profile', ['Rahim', '01712345678', 'short']), 'complete address');
  const ok = await api.rpc(S.rahim, 'public.update_my_profile', ['Rahim U.', '+8801712345699', 'House 12, Road 4, Gazipur']);
  assert.equal(ok.phone, '01712345699');
  assert.equal(ok.role, 'customer');
  await rejects(api.admin(`update public.profiles set email = 'other@example.com' where id = $1`, [S.rahim]), 'cannot be changed');
});

test('profile images must be our own Cloudinary assets in the user\'s own folder', async () => {
  const good = `https://res.cloudinary.com/hmpqmney/image/upload/v1/toptailers/avatars/${S.rahim}.jpg`;
  const args = (url, pid) => ['Rahim U.', '01712345699', 'House 12, Road 4, Gazipur', url, pid];
  await rejects(api.rpc(S.rahim, 'public.update_my_profile', args('https://evil.example/x.jpg', `toptailers/avatars/${S.rahim}`)), 'Invalid profile image');
  await rejects(api.rpc(S.rahim, 'public.update_my_profile', args(good, `toptailers/avatars/${S.nusrat}`)), 'Invalid profile image');
  await rejects(api.rpc(S.rahim, 'public.update_my_profile', args(good.replace('hmpqmney', 'otherCloud'), `toptailers/avatars/${S.rahim}`)), 'Invalid profile image');
  const ok = await api.rpc(S.rahim, 'public.update_my_profile', args(good, `toptailers/avatars/${S.rahim}`));
  assert.equal(ok.profileImage, good);
});

test('wishlist rows belong to their owner', async () => {
  await api.user(S.rahim)(`insert into public.wishlist_items(user_id, product_id) values ($1, $2)`, [S.rahim, S.cotton.id]);
  await rejects(api.user(S.rahim)(`insert into public.wishlist_items(user_id, product_id) values ($1, $2)`, [S.nusrat, S.cotton.id]), 'row-level security');
  assert.equal((await api.user(S.nusrat)(`select * from public.wishlist_items`)).rows.length, 0);
  assert.equal((await api.user(S.rahim)(`select * from public.wishlist_items`)).rows.length, 1);
});

test('voucher guessing is rate limited', async () => {
  const id = await api.signUp('guesser@example.com', VALID_META);
  let blocked = false;
  for (let i = 0; i < 40; i++) {
    try { await api.rpc(id, 'public.get_voucher', [`GUESS${i}X`]); } catch (e) { blocked = String(e.message).includes('Too many attempts'); if (blocked) break; }
  }
  assert.ok(blocked, 'expected throttling after 30 attempts a minute');
});
