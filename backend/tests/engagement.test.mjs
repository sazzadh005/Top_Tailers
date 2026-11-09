import test, { before } from 'node:test';
import assert from 'node:assert/strict';
import { freshDb, seed, rejects, line, placeOrder, VALID_META } from './harness.mjs';

let api, S, done, pending;
before(async () => {
  api = await freshDb(); S = await seed(api);
  done = await placeOrder(api, S.rahim, [line(S.silk, 1, { colorName: 'Maroon' }), line(S.buttons)]);
  for (const st of ['confirmed', 'processing', 'completed']) await api.rpc(S.adminId, 'public.update_order_status', [done.id, st]);
  pending = await placeOrder(api, S.rahim, [line(S.buttons)]);
});
const fb = (uid, o = {}) => api.rpc(uid, 'public.submit_feedback', [o.order ?? done.id, o.product ?? S.silk.id, o.rating ?? 5, o.comment ?? 'Lovely fabric and fast delivery']);

test('feedback is allowed only for a product in your own Completed order, once', async () => {
  const f = await fb(S.rahim);
  assert.equal(f.rating, 5);
  assert.equal(f.productName, 'Silk Blend Fabric');
  await rejects(fb(S.rahim), 'already reviewed this item');
  assert.equal((await fb(S.rahim, { product: S.buttons.id, rating: 3, comment: 'Fine buttons' })).rating, 3);
});

test('feedback is refused for non-completed orders, other users, wrong products and bad input', async () => {
  await rejects(fb(S.rahim, { order: pending.id, product: S.buttons.id }), 'after the order is Completed');
  await rejects(fb(S.nusrat), 'not your order');
  await rejects(fb(S.rahim, { product: S.cotton.id }), 'not part of that order');
  await rejects(fb(S.rahim, { rating: 0 }), 'rating from 1 to 5');
  await rejects(fb(S.rahim, { rating: 6 }), 'rating from 1 to 5');
  await rejects(fb(S.rahim, { comment: 'ok' }), 'at least a few words');
  await rejects(fb(S.rahim, { order: '00000000-0000-0000-0000-000000000000' }), 'Order not found');
  await rejects(api.user(S.rahim)(`insert into public.feedback(order_id, product_id, product_name, user_id, rating, comment) values ($1,$2,'x',$3,5,'forged review')`, [done.id, S.silk.id, S.rahim]), 'permission denied');
});

test('other shoppers see first names only; owners and admins see more', async () => {
  const seen = await api.rpc(S.nusrat, 'public.feedback_for_product', [S.silk.id]);
  assert.equal(seen.length, 1);
  assert.equal(seen[0].userName, 'Rahim');
  assert.equal(seen[0].userId, '', 'reviewer identity is not exposed');
  assert.equal((await api.rpc(S.rahim, 'public.feedback_for_product', [S.silk.id]))[0].userId, S.rahim);
  assert.equal((await api.rpc(S.rahim, 'public.my_feedback')).length, 2);
  assert.equal((await api.rpc(S.nusrat, 'public.my_feedback')).length, 0);
  const all = await api.rpc(S.adminId, 'public.admin_all_feedback');
  assert.equal(all.length, 2);
  assert.equal(all[0].userName, 'Rahim Uddin');
});

test('suggestions and restock requests: submit, validate, deduplicate, review', async () => {
  await rejects(api.rpc(S.rahim, 'public.submit_suggestion', ['ab', 'x']), 'what you would like us to stock');
  const s = await api.rpc(S.rahim, 'public.submit_suggestion', ['Muslin fabric', 'Light and soft']);
  assert.equal(s.status, 'received');
  assert.equal(s.userName, 'Rahim Uddin');
  const r = await api.rpc(S.rahim, 'public.submit_restock', [S.velvet.id, 'Wedding outfit']);
  assert.equal(r.status, 'received');
  assert.equal(r.productCode, 'FAB-VEL-005');
  await rejects(api.rpc(S.rahim, 'public.submit_restock', [S.velvet.id, 'again']), 'open restock request');
  await rejects(api.rpc(S.rahim, 'public.submit_restock', ['00000000-0000-0000-0000-000000000000', '']), 'Product not found');
  assert.notEqual((await api.rpc(S.nusrat, 'public.submit_restock', [S.velvet.id, 'Me too'])).id, r.id);
  assert.equal((await api.rpc(S.rahim, 'public.my_suggestions')).length, 1);
  assert.equal((await api.rpc(S.rahim, 'public.my_restocks')).length, 1);
  assert.equal((await api.rpc(S.nusrat, 'public.my_suggestions')).length, 0);
  await rejects(api.rpc(S.rahim, 'public.set_suggestion_status', [s.id, 'planned']), 'Only the shop admin');
  await rejects(api.rpc(S.rahim, 'public.set_restock_status', [r.id, 'planned']), 'Only the shop admin');
  await api.rpc(S.adminId, 'public.set_suggestion_status', [s.id, 'underReview']);
  await api.rpc(S.adminId, 'public.set_restock_status', [r.id, 'declined']);
  assert.equal((await api.rpc(S.rahim, 'public.my_suggestions'))[0].status, 'underReview');
  assert.equal((await api.rpc(S.rahim, 'public.my_restocks'))[0].status, 'declined');
  await rejects(api.rpc(S.adminId, 'public.set_suggestion_status', [s.id, 'bogus']), 'Unknown status');
  await rejects(api.rpc(S.adminId, 'public.set_restock_status', ['00000000-0000-0000-0000-000000000000', 'planned']), 'Request not found');
  assert.equal((await api.rpc(S.rahim, 'public.submit_restock', [S.velvet.id, 'Still need it'])).status, 'received', 'once declined, a fresh request is allowed');
  assert.equal((await api.rpc(S.adminId, 'public.admin_all_restocks')).length, 3);
  assert.equal((await api.rpc(S.adminId, 'public.admin_all_suggestions')).length, 1);
  await rejects(api.rpc(S.rahim, 'public.admin_all_restocks'), 'Only the shop admin');
});

// now() is fixed within one transaction, so inserting "exactly 30 days ago" and
// reading in the SAME transaction tests the true boundary.
async function inTx(uid, insertSql) {
  const res = await api.db.exec(`
    begin;
    select set_config('request.jwt.claim.sub', '${uid}', true);
    ${insertSql}
    set local role authenticated;
    select public.visible_notifications() as r;
    commit;`);
  await api.db.exec('reset role');
  return res.find((r) => r.fields?.some((f) => f.name === 'r')).rows[0].r;
}

test('notifications: less than 30 days and exactly 30 days are visible, older are hidden', async () => {
  const id = await api.signUp('notes@example.com', VALID_META);
  await api.admin(`delete from public.notifications where user_id = $1`, [id]);
  const rows = await inTx(id, `
    insert into public.notifications(user_id, title, created_at) values
      ('${id}', 'fresh',        now() - interval '1 hour'),
      ('${id}', 'twentynine',   now() - interval '29 days'),
      ('${id}', 'exactly30',    now() - interval '30 days'),
      ('${id}', 'just-over',    now() - interval '30 days 1 second'),
      ('${id}', 'thirtyone',    now() - interval '31 days'),
      ('${id}', 'ancient',      now() - interval '400 days');`);
  assert.deepEqual(rows.map((n) => n.title), ['fresh', 'twentynine', 'exactly30'], 'newest first; 30 days exactly stays visible');
  assert.equal((await api.admin(`select count(*)::int n from public.notifications where user_id = $1`, [id])).rows[0].n, 6, 'hiding is not deleting');
});

test('notifications always have a timestamp', async () => {
  await rejects(api.admin(`insert into public.notifications(user_id, title, created_at) values ($1, 'x', null)`, [S.rahim]), 'not-null');
});

test('purging deletes only notifications older than 30 days, and only via the service role', async () => {
  const id = await api.signUp('purge@example.com', VALID_META);
  await api.admin(`delete from public.notifications where user_id = $1`, [id]);
  await api.admin(`insert into public.notifications(user_id, title, created_at) values
      ($1, 'keep-new', now() - interval '2 days'), ($1, 'keep-29', now() - interval '29 days'),
      ($1, 'drop-31', now() - interval '31 days'), ($1, 'drop-100', now() - interval '100 days')`, [id]);
  await rejects(api.rpc(id, 'public.purge_old_notifications'), 'permission denied');
  assert.ok((await api.service(`select public.purge_old_notifications() as n`)).rows[0].n >= 2);
  const left = (await api.admin(`select title from public.notifications where user_id = $1 order by title`, [id])).rows.map((r) => r.title);
  assert.deepEqual(left, ['keep-29', 'keep-new']);
});

test('notifications are private, mark-read works, and direct reads also respect the window', async () => {
  const mine = await api.rpc(S.rahim, 'public.visible_notifications');
  assert.ok(mine.length > 0 && mine.every((n) => n.userId === S.rahim));
  assert.ok(mine.every((n) => n.createdAt));
  const sorted = [...mine].sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
  assert.deepEqual(mine.map((n) => n.id), sorted.map((n) => n.id));
  assert.equal((await api.rpc(S.nusrat, 'public.visible_notifications')).every((n) => n.userId === S.nusrat), true);
  assert.ok(mine.some((n) => !n.read));
  await api.rpc(S.rahim, 'public.mark_notifications_read');
  assert.ok((await api.rpc(S.rahim, 'public.visible_notifications')).every((n) => n.read));
  await api.admin(`insert into public.notifications(user_id, title, created_at) values ($1, 'old-direct', now() - interval '40 days')`, [S.rahim]);
  assert.ok(!(await api.user(S.rahim)(`select title from public.notifications`)).rows.some((r) => r.title === 'old-direct'), 'RLS hides old rows from direct reads too');
});
