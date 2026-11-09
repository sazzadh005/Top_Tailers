import test, { before } from 'node:test';
import assert from 'node:assert/strict';
import { freshDb, seed, rejects, IMG } from './harness.mjs';

let api, S;
before(async () => { api = await freshDb(); S = await seed(api); });
const save = (o) => api.rpc(S.adminId, 'public.admin_save_product', [{ description: 'x', category: 'Accessories', priceMinor: 1000, ...o }]);
const ticket = (id, hoursAgo) => api.service(`select public.record_upload_ticket($1, $2)`, [id, S.adminId])
  .then(() => api.admin(`update public.image_upload_tickets set issued_at = now() - ($2 || ' hours')::interval where public_id = $1`, [id, String(hoursAgo)]));
const queued = async () => (await api.admin(`select public_id from public.image_cleanup_queue`)).rows.map((r) => r.public_id);

test('only the service role can record tickets or queue orphans', async () => {
  await rejects(api.rpc(S.adminId, 'public.record_upload_ticket', ['toptailers/products/x', S.adminId]), 'permission denied');
  await rejects(api.rpc(S.rahim, 'public.queue_orphaned_uploads'), 'permission denied');
  await rejects(api.user(S.adminId)(`select * from public.image_upload_tickets`), 'permission denied');
});

test('an old upload that was never attached is queued for destruction', async () => {
  await ticket('toptailers/products/never-used', 3);
  assert.equal((await api.service(`select public.queue_orphaned_uploads() as n`)).rows[0].n, 1);
  assert.ok((await queued()).includes('toptailers/products/never-used'));
  assert.equal((await api.admin(`select * from public.image_upload_tickets where public_id = 'toptailers/products/never-used'`)).rows.length, 0, 'ticket is consumed');
});

test('recent uploads are left alone (the admin may still be filling in the form)', async () => {
  await ticket('toptailers/products/in-progress', 0);
  await api.service(`select public.queue_orphaned_uploads()`);
  assert.ok(!(await queued()).includes('toptailers/products/in-progress'));
  assert.equal((await api.admin(`select * from public.image_upload_tickets where public_id = 'toptailers/products/in-progress'`)).rows.length, 1);
});

test('an upload that WAS attached to a product is never queued', async () => {
  const img = IMG('attached');
  await ticket(img.publicId, 5);
  await save({ code: 'UPL-001', productName: 'With image', imagePaths: [img.url], imagePublicIds: [img.publicId] });
  await api.service(`select public.queue_orphaned_uploads()`);
  assert.ok(!(await queued()).includes(img.publicId));
});

test('an avatar attached to a profile is never queued', async () => {
  const pid = `toptailers/avatars/${S.rahim}`;
  const url = `https://res.cloudinary.com/hmpqmney/image/upload/v1/${pid}.jpg`;
  await api.rpc(S.rahim, 'public.update_my_profile', ['Rahim Uddin', '01712345678', 'House 12, Road 4, Gazipur', url, pid]);
  await ticket(pid, 5);
  await api.service(`select public.queue_orphaned_uploads()`);
  assert.ok(!(await queued()).includes(pid));
  const claimed = (await api.service(`select public.claim_cloudinary_cleanup(50) as ids`)).rows[0].ids;
  assert.ok(!claimed.includes(pid), 'and the claim step also refuses live assets');
});

test('the full cleanup path: orphan -> queue -> claim -> destroyed -> removed from the queue', async () => {
  await ticket('toptailers/products/abandoned', 9);
  await api.service(`select public.queue_orphaned_uploads()`);
  const claimed = (await api.service(`select public.claim_cloudinary_cleanup(50) as ids`)).rows[0].ids;
  assert.ok(claimed.includes('toptailers/products/abandoned'));
  await api.service(`select public.complete_cloudinary_cleanup($1::text[])`, [`{${claimed.join(',')}}`]);
  assert.ok(!(await queued()).includes('toptailers/products/abandoned'));
});
