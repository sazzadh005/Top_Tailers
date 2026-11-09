// Captures REAL output of the SQL functions as JSON fixtures for the Dart mapper tests.
// Run: node tests/export_fixtures.mjs <output dir>
import { writeFileSync, mkdirSync } from 'node:fs';
import { freshDb, seed, line, placeOrder, IMG } from './harness.mjs';

const out = process.argv[2] ?? '../test/fixtures';
mkdirSync(out, { recursive: true });
const save = (name, value) => writeFileSync(`${out}/${name}.json`, JSON.stringify(value, null, 2));

const api = await freshDb();
const S = await seed(api);
const admin = (fn, args = []) => api.rpc(S.adminId, `public.${fn}`, args);

// a product with images, variants, specs and a discount
const img = IMG('fixture-1');
const rich = await admin('admin_save_product', [{ code: 'FIX-001', productName: 'Fixture Fabric', description: 'Rich fixture', category: 'Fabrics',
  priceMinor: 45000, unit: 'yard', isFeatured: true, popularity: 50, specs: { Material: 'Cotton', Width: '44 in' },
  imagePaths: [img.url], imagePublicIds: [img.publicId], colors: [{ name: 'Sand', argb: 0xFFD8C3A0 }], sizes: ['M', 'L'],
  discount: { enabled: true, kind: 'fixed', value: 5000 } }]);
save('product', rich);
save('product_page', await api.rpc(S.rahim, 'public.search_products', ['', null, 'featured', false, 1, 3]));
await api.admin(`insert into public.promo_banners(id, title, subtitle, color_argb, category, voucher_code, position) values
  ('b1', 'Festive Fabrics', 'Up to 15% off with a voucher', 4287103018, 'Fabrics', 'DEMOFAB15', 0),
  ('b2', 'Tailoring', 'Made to your measurements', 4281545523, 'Tailoring', null, 1)`);
save('home', await api.rpc(S.rahim, 'public.get_home'));
save('voucher', await api.rpc(S.rahim, 'public.get_voucher', ['DEMOFAB15']));

await api.rpc(S.rahim, 'public.set_measurements', [S.rahim, { chest: 98.5, waist: 86, neck: 38 }]);
await api.rpc(S.adminId, 'public.admin_save_customer_discount', [S.rahim, 'percent', 8, true, 'regular customer']);
save('user', await api.rpc(S.rahim, 'public.my_profile'));
save('customer_discount', await api.rpc(S.rahim, 'public.my_customer_discount'));

// a completed COD tailoring order with a profile measurement snapshot
const tailoring = await placeOrder(api, S.rahim, [line(S.stitching), line(S.buttons, 2)],
  { measurements: { source: 'profile' }, note: 'Fixture order' });
for (const st of ['confirmed', 'processing', 'completed']) await admin('update_order_status', [tailoring.id, st]);
save('order_completed', await api.rpc(S.rahim, 'public.get_order', [tailoring.id]));

// a cancelled order with a reason
const cancelled = await placeOrder(api, S.rahim, [line(S.cotton, 1, { colorName: 'White' })], { voucherCode: null });
await api.rpc(S.rahim, 'public.cancel_order', [cancelled.id, 'Ordered by mistake', 'Fixture note']);
save('order_cancelled', await api.rpc(S.rahim, 'public.get_order', [cancelled.id]));

// an online order paid through the verified-result path
const online = await placeOrder(api, S.rahim, [line(S.buttons, 2)], { paymentMethod: 'online' });
const a = await api.rpc(S.rahim, 'public.start_payment_attempt', [online.id]);
await api.service(`select public.record_payment_result($1, $2::jsonb)`, [a.tranId,
  JSON.stringify({ statusCode: '2', merTxnId: a.tranId, amount: a.amountDecimal, currency: 'BDT', pgTxnId: 'PG-FIXTURE' })]);
save('order_online_paid', await api.rpc(S.rahim, 'public.get_order', [online.id]));
save('order_list', await api.rpc(S.rahim, 'public.search_orders'));
save('customers', await admin('admin_list_customers'));

await api.rpc(S.rahim, 'public.submit_feedback', [tailoring.id, S.stitching.id, 5, 'Fixture feedback comment']);
save('feedback_list', await api.rpc(S.rahim, 'public.my_feedback'));
await api.rpc(S.rahim, 'public.submit_suggestion', ['Muslin fabric', 'Light and soft']);
save('suggestions', await api.rpc(S.rahim, 'public.my_suggestions'));
await api.rpc(S.rahim, 'public.submit_restock', [S.velvet.id, 'Wedding outfit']);
save('restocks', await api.rpc(S.rahim, 'public.my_restocks'));
save('notifications', await api.rpc(S.rahim, 'public.visible_notifications'));
console.log('fixtures written to', out);
