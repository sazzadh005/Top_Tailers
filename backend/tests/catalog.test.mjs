import test, { before } from 'node:test';
import assert from 'node:assert/strict';
import { freshDb, seed, rejects, line, placeOrder, IMG } from './harness.mjs';

let api, S;
before(async () => { api = await freshDb(); S = await seed(api); });
const save = (o) => api.rpc(S.adminId, 'public.admin_save_product', [o]);
const base = { description: 'Nice', category: 'Fabrics' };
const search = (o = {}) => api.rpc(S.rahim, 'public.search_products', [o.p_text ?? '', o.p_category ?? null, o.p_sort ?? 'featured', o.p_in_stock ?? false, o.p_page ?? 1, o.p_page_size ?? 8]);

test('product codes are unique, case-insensitive and normalised to upper case', async () => {
  const p = await save({ ...base, code: ' fab-new-900 ', productName: 'New', priceMinor: 10000 });
  assert.equal(p.code, 'FAB-NEW-900');
  await rejects(save({ ...base, code: 'FAB-NEW-900', productName: 'Dup', priceMinor: 10000 }), 'already used by another product');
  await rejects(save({ ...base, code: 'fab-new-900', productName: 'Dup', priceMinor: 10000 }), 'already used by another product');
  const again = await save({ ...base, id: p.id, code: 'FAB-NEW-900', productName: 'Renamed', priceMinor: 12000 });
  assert.equal(again.productName, 'Renamed');
  await rejects(save({ ...base, id: p.id, code: 'FAB-COT-001', productName: 'x', priceMinor: 1000 }), 'already used by another product');
  assert.equal(await api.rpc(S.adminId, 'public.admin_is_code_taken', ['FAB-COT-001']), true);
  assert.equal(await api.rpc(S.adminId, 'public.admin_is_code_taken', ['FAB-COT-001', S.cotton.id]), false);
});

test('the database itself enforces code uniqueness, not just the function', async () => {
  await rejects(api.admin(`insert into public.products(code, product_name, price_minor, category) values ('FAB-COT-001','x',100,'Fabrics')`), 'duplicate key');
  await rejects(api.admin(`insert into public.products(code, product_name, price_minor, category) values ('bad code','x',100,'Fabrics')`), 'products_code_format');
});

test('product input validation', async () => {
  const bad = async (o, msg) => rejects(save({ ...base, code: 'VAL-001', productName: 'V', priceMinor: 1000, ...o }), msg);
  await bad({ code: '' }, 'Product code is required');
  await bad({ code: 'AB' }, '3-24 characters');
  await bad({ code: 'AB--CD' }, 'single hyphens');
  await bad({ productName: ' ' }, 'Product name is required');
  await bad({ description: '' }, 'Description is required');
  await bad({ priceMinor: 0 }, 'Price must be greater than 0');
  await bad({ priceMinor: -5 }, 'Price must be greater than 0');
  await bad({ priceMinor: 2000000000 }, 'Price is too large');
  await bad({ category: 'Shoes' }, 'Unknown category');
});

test('product discounts are validated: percent 1-99, fixed below the price', async () => {
  const d = (discount) => save({ ...base, code: 'DIS-001', productName: 'D', priceMinor: 10000, discount });
  await rejects(d({ enabled: true, kind: 'percent', value: 0 }), 'greater than 0');
  await rejects(d({ enabled: true, kind: 'percent', value: 100 }), 'between 1 and 99');
  await rejects(d({ enabled: true, kind: 'fixed', value: 10000 }), 'less than the price');
  await rejects(d({ enabled: true, kind: 'fixed', value: -1 }), 'greater than 0');
  await rejects(d({ enabled: true, kind: 'weird', value: 5 }), 'percentage or a fixed');
  const p = await d({ enabled: true, kind: 'fixed', value: 9999 });
  assert.deepEqual(p.discount, { enabled: true, kind: 'fixed', value: 9999 });
  const off = await save({ ...base, id: p.id, code: 'DIS-001', productName: 'D', priceMinor: 10000, discount: { enabled: false, kind: 'percent', value: 15 } });
  assert.deepEqual(off.discount, { enabled: false, kind: 'percent', value: 15 }, 'a disabled discount keeps its settings');
  await rejects(api.admin(`update public.products set discount_enabled=true, discount_kind='percent', discount_value=100 where id=$1`, [p.id]), 'products_discount_valid');
  await rejects(save({ ...base, id: p.id, code: 'DIS-001', productName: 'D', priceMinor: 5000, discount: { enabled: true, kind: 'fixed', value: 9999 } }), 'less than the price');
});

test('product images: only our Cloudinary assets, max 4, no sharing between products', async () => {
  const mk = (code, imgs) => save({ ...base, code, productName: code, priceMinor: 1000,
    imagePaths: imgs.map((i) => i.url), imagePublicIds: imgs.map((i) => i.publicId) });
  await rejects(save({ ...base, code: 'IMG-000', productName: 'x', priceMinor: 1000, imagePaths: ['https://evil.example/a.jpg'], imagePublicIds: ['toptailers/products/a'] }), 'Invalid product image');
  await rejects(save({ ...base, code: 'IMG-000', productName: 'x', priceMinor: 1000,
    imagePaths: ['https://res.cloudinary.com/otherCloud/image/upload/toptailers/products/a.jpg'], imagePublicIds: ['toptailers/products/a'] }), 'Invalid product image');
  await rejects(save({ ...base, code: 'IMG-000', productName: 'x', priceMinor: 1000,
    imagePaths: [IMG('a').url], imagePublicIds: ['toptailers/avatars/a'] }), 'Invalid product image');
  await rejects(mk('IMG-000', [1, 2, 3, 4, 5].map((n) => IMG('five' + n))), 'up to 4 images');
  await rejects(save({ ...base, code: 'IMG-000', productName: 'x', priceMinor: 1000, imagePaths: [IMG('a').url], imagePublicIds: [] }), 'Invalid images');
  const p = await mk('IMG-001', [IMG('one'), IMG('two')]);
  assert.deepEqual(p.imagePaths, [IMG('one').url, IMG('two').url]);
  await rejects(mk('IMG-002', [IMG('one')]), 'already used by another product');
});

test('replacing or removing an image queues the old Cloudinary asset for cleanup', async () => {
  const p = await save({ ...base, code: 'IMG-010', productName: 'x', priceMinor: 1000, imagePaths: [IMG('old').url], imagePublicIds: [IMG('old').publicId] });
  await save({ ...base, id: p.id, code: 'IMG-010', productName: 'x', priceMinor: 1000, imagePaths: [IMG('new').url], imagePublicIds: [IMG('new').publicId] });
  const q = await api.admin(`select public_id from public.image_cleanup_queue`);
  assert.ok(q.rows.some((r) => r.public_id === IMG('old').publicId));
  assert.ok(!q.rows.some((r) => r.public_id === IMG('new').publicId), 'the live image must never be queued');
  const claimed = (await api.service(`select public.claim_cloudinary_cleanup(10) as ids`)).rows[0].ids;
  assert.ok(claimed.includes(IMG('old').publicId));
  await api.service(`select public.complete_cloudinary_cleanup($1::text[])`, [`{${claimed.join(',')}}`]);
  assert.equal((await api.admin(`select * from public.image_cleanup_queue`)).rows.length, 0);
});

test('an image still referenced by an order snapshot is never destroyed', async () => {
  const p = await save({ ...base, code: 'IMG-020', productName: 'Pic', priceMinor: 5000, imagePaths: [IMG('kept').url], imagePublicIds: [IMG('kept').publicId] });
  await placeOrder(api, S.rahim, [line(p)]);
  await save({ ...base, id: p.id, code: 'IMG-020', productName: 'Pic', priceMinor: 5000, imagePaths: [], imagePublicIds: [] });
  const claimed = (await api.service(`select public.claim_cloudinary_cleanup(50) as ids`)).rows[0].ids;
  assert.ok(!claimed.includes(IMG('kept').publicId));
});

test('soft delete hides a product but keeps its code reserved and old orders intact', async () => {
  const p = await save({ ...base, code: 'DEL-001', productName: 'Gone', priceMinor: 5000 });
  const o = await placeOrder(api, S.rahim, [line(p)]);
  await api.rpc(S.adminId, 'public.admin_delete_product', [p.id]);
  assert.equal((await search({ p_text: 'DEL-001' })).total, 0);
  await rejects(save({ ...base, code: 'DEL-001', productName: 'Reuse', priceMinor: 5000 }), 'already used by another product');
  assert.equal((await api.rpc(S.rahim, 'public.get_order', [o.id])).items[0].productName, 'Gone');
  await rejects(api.rpc(S.rahim, 'public.quote_pricing', [[line(p)]]), 'no longer available');
});

test('search matches name, description, category and code, case-insensitively', async () => {
  const ids = async (args) => (await search(args)).items.map((i) => i.code).sort();
  assert.deepEqual(await ids({ p_text: 'cotton' }), ['FAB-COT-001']);
  assert.deepEqual(await ids({ p_text: 'COTTON' }), ['FAB-COT-001']);
  assert.deepEqual(await ids({ p_text: 'breathable' }), ['FAB-COT-001']);
  assert.deepEqual(await ids({ p_text: 'tailoring' }), ['TLR-SHT-201']);
  assert.deepEqual(await ids({ p_text: 'tlr-' }), ['TLR-SHT-201']);
  assert.deepEqual(await ids({ p_text: 'fab-vel-005' }), ['FAB-VEL-005']);
  assert.deepEqual(await ids({ p_text: 'no such thing' }), []);
});

test('search treats LIKE wildcards literally', async () => {
  assert.equal((await search({ p_text: '%' })).total, 0);
  assert.equal((await search({ p_text: '_' })).total, 0);
  assert.equal((await search({ p_text: "x' or 1=1 --" })).total, 0);
});

test('search filters, sorting and paging', async () => {
  const fabricsInStock = await search({ p_category: 'Fabrics', p_in_stock: true, p_page_size: 50 });
  assert.ok(fabricsInStock.items.every((i) => i.category === 'Fabrics' && i.availability));
  assert.ok(!fabricsInStock.items.some((i) => i.code === 'FAB-VEL-005'));
  const eff = (i) => i.priceMinor - (i.discount?.enabled ? (i.discount.kind === 'percent' ? Math.floor(i.priceMinor * i.discount.value / 100) : i.discount.value) : 0);
  const cheap = (await search({ p_sort: 'priceLow', p_page_size: 50 })).items;
  for (let i = 1; i < cheap.length; i++) assert.ok(eff(cheap[i - 1]) <= eff(cheap[i]), 'priceLow must sort by effective price');
  const dear = (await search({ p_sort: 'priceHigh', p_page_size: 50 })).items;
  for (let i = 1; i < dear.length; i++) assert.ok(eff(dear[i - 1]) >= eff(dear[i]));
  const az = (await search({ p_sort: 'nameAZ', p_page_size: 50 })).items.map((i) => i.productName.toLowerCase());
  assert.deepEqual(az, [...az].sort());
  assert.equal((await search({ p_sort: 'featured', p_page_size: 50 })).items[0].isFeatured, true);

  const total = (await search({ p_page_size: 50 })).total;
  const p1 = await search({ p_page: 1, p_page_size: 3 });
  const p2 = await search({ p_page: 2, p_page_size: 3 });
  assert.equal(p1.items.length, 3);
  assert.equal(p1.hasMore, total > 3);
  assert.equal(p1.total, total);
  assert.equal(new Set([...p1.items, ...p2.items].map((i) => i.id)).size, 6, 'pages must not overlap');
  assert.equal((await search({ p_page: Math.ceil(total / 3), p_page_size: 3 })).hasMore, false);
  assert.equal((await search({ p_page_size: 5000 })).items.length <= 50, true, 'page size is capped at 50');
});

test('search rejects unknown sort or category and requires sign-in', async () => {
  await rejects(search({ p_sort: 'cheapest' }), 'Unknown sort');
  await rejects(search({ p_category: 'Shoes' }), 'Unknown category');
  await rejects(api.anon(`select public.search_products('')`), 'permission denied');
});

test('product json carries images, colours, sizes, specs and discount in the app shape', async () => {
  const [shirt] = (await search({ p_text: 'RDY-SHT-101' })).items;
  assert.deepEqual(shirt.sizes, ['S', 'M', 'L']);
  assert.equal(shirt.colors[0].name, 'White');
  assert.equal(typeof shirt.colors[0].argb, 'number');
  for (const k of ['id','code','productName','description','priceMinor','category','availability','imagePaths','imagePublicIds','colors','sizes','specs','isFeatured','popularity','unit','requiresMeasurements','discount','createdAt']) {
    assert.ok(k in shirt, `missing ${k}`);
  }
  assert.equal(shirt.unit, 'piece');
});

test('home shelves follow the app rules', async () => {
  const h = await api.rpc(S.rahim, 'public.get_home');
  assert.ok(h.featured.every((p) => p.category === 'Fabrics' && p.isFeatured && p.availability));
  assert.ok(h.services.every((p) => p.category === 'Tailoring'));
  assert.ok(h.discounted.every((p) => p.discount?.enabled));
  assert.ok(h.popular.length <= 8 && h.popular.every((p) => p.availability));
  assert.deepEqual(h.offers.map((o) => o.code).sort(), ['DEMO10', 'DEMOFAB15'], 'only public, active, unexpired vouchers');
  assert.ok(!h.popular.some((p) => p.code === 'FAB-VEL-005'), 'unavailable products are not promoted');
});

test('get_products_by_ids omits unknown ids', async () => {
  const r = await api.rpc(S.rahim, 'public.get_products_by_ids', [`{${S.cotton.id},00000000-0000-0000-0000-000000000000}`]);
  assert.equal(r.length, 1);
});
