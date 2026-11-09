import test from 'node:test';
import assert from 'node:assert/strict';
import { signParams, destroyAsset } from '../../supabase/functions/_shared/cloudinary.ts';
import { makeCloudinarySignHandler, makeCleanupHandler } from '../../supabase/functions/_shared/handlers.ts';
import { loadAamarPayConfig, loadCloudinaryConfig } from '../../supabase/functions/_shared/env.ts';
import type { MediaDb, WhoAmI } from '../../supabase/functions/_shared/types.ts';

const SECRET = 'cld-secret-DO-NOT-LEAK-123';
const cfg = { cloudName: 'hmpqmney', apiKey: 'key123', apiSecret: SECRET };
const ADMIN: WhoAmI = { id: '11111111-1111-1111-1111-111111111111', role: 'admin' };
const CUSTOMER: WhoAmI = { id: '22222222-2222-2222-2222-222222222222', role: 'customer' };

function media(users: Record<string, WhoAmI>, queue: string[] = []): MediaDb & { completed: string[]; failed: string[]; tickets: string[]; orphanRuns: number } {
  const m = {
    completed: [] as string[], failed: [] as string[], tickets: [] as string[], orphanRuns: 0,
    recordTicket: async (id: string) => { m.tickets.push(id); },
    queueOrphans: async () => { m.orphanRuns++; return 0; },
    whoAmI: async (t: string) => { const u = users[t]; if (!u) throw Object.assign(new Error('Please sign in.'), { status: 401 }); return u; },
    claimCleanup: async () => queue,
    completeCleanup: async (ids: string[]) => { m.completed.push(...ids); },
    failCleanup: async (id: string) => { m.failed.push(id); },
  };
  return m;
}
const req = (body: unknown, token?: string, method = 'POST') =>
  new Request('https://fn.example/cloudinary-sign', {
    method, headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: method === 'GET' ? undefined : JSON.stringify(body),
  });

test('signature matches Cloudinary\'s documented example vector', async () => {
  // Example from Cloudinary's "Generating authentication signatures" documentation.
  const sig = await signParams({ eager: 'w_400,h_300,c_pad|w_260,h_200,c_crop', public_id: 'sample_image', timestamp: 1315060510 }, 'abcd');
  assert.equal(sig, 'bfd09f95f331f558cbd1320e67aa8d488770583e');
});

test('file, api_key, cloud_name and resource_type are never signed, and order does not matter', async () => {
  const a = await signParams({ public_id: 'x', timestamp: 1 }, 's');
  const b = await signParams({ timestamp: 1, file: 'BIGDATA', api_key: 'k', cloud_name: 'c', resource_type: 'image', public_id: 'x' }, 's');
  assert.equal(a, b);
});

test('product tickets: admin only, server-chosen random public id, never overwrite', async () => {
  const db = media({ adm: ADMIN, cus: CUSTOMER });
  let n = 0;
  const h = makeCloudinarySignHandler({ cfg, db, now: () => 1_700_000_000_000, newId: () => `id-${++n}` });
  assert.equal((await h(req({ scope: 'product' }, 'cus'))).status, 403);
  assert.equal((await h(req({ scope: 'product' }))).status, 401);
  assert.equal((await h(req({ scope: 'product' }, 'bogus'))).status, 401);

  const ok = await h(req({ scope: 'product', publicId: 'toptailers/products/overwrite-me' }, 'adm'));   // client choice ignored
  assert.equal(ok.status, 200);
  assert.deepEqual(db.tickets, ['toptailers/products/id-1'], 'every issued ticket is tracked for orphan cleanup');
  const t = await ok.json();
  assert.equal(t.publicId, 'toptailers/products/id-1');
  assert.equal(t.overwrite, false);
  assert.equal(t.cloudName, 'hmpqmney');
  assert.equal(t.uploadUrl, 'https://api.cloudinary.com/v1_1/hmpqmney/image/upload');
  assert.equal(t.timestamp, 1_700_000_000);
  const expected = await signParams({ allowed_formats: 'jpg,jpeg,png,webp', overwrite: false, public_id: 'toptailers/products/id-1', timestamp: 1_700_000_000 }, SECRET);
  assert.equal(t.signature, expected);
  const second = await (await h(req({ scope: 'product' }, 'adm'))).json();
  assert.notEqual(second.publicId, t.publicId, 'each upload gets a fresh id, so existing images cannot be replaced');
});

test('avatar tickets: any signed-in user, but only for their OWN avatar', async () => {
  const h = makeCloudinarySignHandler({ cfg, db: media({ adm: ADMIN, cus: CUSTOMER }) });
  const t = await (await h(req({ scope: 'avatar', publicId: `toptailers/avatars/${ADMIN.id}` }, 'cus'))).json();
  assert.equal(t.publicId, `toptailers/avatars/${CUSTOMER.id}`, 'cannot target another user');
  assert.equal(t.overwrite, true);
  assert.equal((await h(req({ scope: 'avatar' }))).status, 401);
});

test('bad scope, bad method and secret hygiene', async () => {
  const h = makeCloudinarySignHandler({ cfg, db: media({ adm: ADMIN }) });
  assert.equal((await h(req({ scope: 'logo' }, 'adm'))).status, 400);
  assert.equal((await h(req({}, 'adm', 'GET'))).status, 405);
  const res = await h(req({ scope: 'product' }, 'adm'));
  const text = await res.text();
  assert.ok(!text.includes(SECRET), 'the API secret must never appear in a response');
  assert.ok(![...res.headers.values()].some((v) => v.includes(SECRET)));
});

test('destroy signs the request and treats "not found" as success', async () => {
  const calls: { url: string; body: string }[] = [];
  const f = (result: string) => async (url: string, init?: RequestInit) => {
    calls.push({ url, body: String(init?.body) });
    return new Response(JSON.stringify({ result }), { status: 200 });
  };
  await destroyAsset(f('ok'), cfg, 'toptailers/products/old', () => 1_700_000_000_000);
  const form = new URLSearchParams(calls[0].body);
  assert.equal(calls[0].url, 'https://api.cloudinary.com/v1_1/hmpqmney/image/destroy');
  assert.equal(form.get('public_id'), 'toptailers/products/old');
  assert.equal(form.get('api_key'), 'key123');
  assert.equal(form.get('signature'), await signParams({ invalidate: true, public_id: 'toptailers/products/old', timestamp: 1_700_000_000 }, SECRET));
  assert.ok(!calls[0].body.includes(SECRET), 'the secret is used to sign, never sent');
  await destroyAsset(f('not found'), cfg, 'toptailers/products/gone');
  await assert.rejects(destroyAsset(f('error'), cfg, 'toptailers/products/x'), /refused/);
  await assert.rejects(destroyAsset(async () => { throw new Error('net'); }, cfg, 'x'), /not reachable/);
});

test('cleanup job: admin or cron secret only; failures are recorded, successes completed', async () => {
  const db = media({ adm: ADMIN, cus: CUSTOMER }, ['toptailers/products/a', 'toptailers/products/b']);
  let calls = 0;
  const fetchFn = async (_u: string, init?: RequestInit) => {
    calls++;
    const pid = new URLSearchParams(String(init?.body)).get('public_id');
    return new Response(JSON.stringify({ result: pid?.endsWith('b') ? 'error' : 'ok' }), { status: 200 });
  };
  const h = makeCleanupHandler({ cfg, db, fetch: fetchFn, cronSecret: 'cron-secret-xyz' });
  const call = (headers: Record<string, string>) => h(new Request('https://fn.example/cleanup', { method: 'POST', headers }));
  assert.equal((await call({})).status, 401);
  assert.equal((await call({ authorization: 'Bearer cus' })).status, 403);
  assert.equal((await call({ 'x-cron-secret': 'wrong', authorization: 'Bearer nope' })).status, 401);
  assert.equal(calls, 0, 'nothing is destroyed before authorization passes');
  const ok = await call({ 'x-cron-secret': 'cron-secret-xyz' });
  assert.equal(ok.status, 200);
  assert.equal(db.orphanRuns, 1, 'unused uploads are queued before each cleanup run');
  assert.deepEqual(await ok.json(), { processed: 1, failed: 1 });
  assert.deepEqual(db.completed, ['toptailers/products/a']);
  assert.deepEqual(db.failed, ['toptailers/products/b']);
  assert.equal((await call({ authorization: 'Bearer adm' })).status, 200);
});

test('configuration loading names the missing variable but never prints secrets', () => {
  const get = (m: Record<string, string>) => (n: string) => m[n];
  assert.throws(() => loadCloudinaryConfig(get({ CLOUDINARY_CLOUD_NAME: 'x', CLOUDINARY_API_KEY: 'k' })), /CLOUDINARY_API_SECRET/);
  assert.throws(() => loadAamarPayConfig(get({ SUPABASE_URL: 'https://p.supabase.co', AAMARPAY_STORE_ID: 's' })), /AAMARPAY_SIGNATURE_KEY/);
  assert.throws(() => loadAamarPayConfig(get({ SUPABASE_URL: 'https://p.supabase.co', AAMARPAY_STORE_ID: 's', AAMARPAY_SIGNATURE_KEY: 'k', AAMARPAY_BASE_URL: 'https://evil.example' })), /must be/);
  assert.throws(() => loadAamarPayConfig(get({ SUPABASE_URL: 'https://p.supabase.co', AAMARPAY_STORE_ID: 's', AAMARPAY_SIGNATURE_KEY: 'k', PAYMENT_RETURN_URL: 'javascript:alert(1)' })), /deep link/);
  const ok = loadAamarPayConfig(get({ SUPABASE_URL: 'https://p.supabase.co/', AAMARPAY_STORE_ID: 's', AAMARPAY_SIGNATURE_KEY: 'k' }));
  assert.equal(ok.baseUrl, 'https://sandbox.aamarpay.com', 'defaults to the sandbox');
  assert.equal(ok.functionsBase, 'https://p.supabase.co/functions/v1');
});
