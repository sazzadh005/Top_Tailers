import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { freshDb, VALID_META, line } from './harness.mjs';

test('the dev seed loads and produces a shop a customer can actually order from', async () => {
  const api = await freshDb();
  await api.admin(readFileSync(new URL('../supabase/seed.sql', import.meta.url), 'utf8').replace(/\r/g, '')).catch(async () => {
    await api.db.exec(readFileSync(new URL('../supabase/seed.sql', import.meta.url), 'utf8'));
  });
  const me = await api.signUp('seedcheck@example.com', VALID_META);
  const home = await api.rpc(me, 'public.get_home');
  assert.equal(home.banners.length, 3);
  assert.ok(home.featured.length >= 2);
  const page = await api.rpc(me, 'public.search_products', ['', null, 'featured', false, 1, 50]);
  assert.equal(page.total, 5);
  const shirt = page.items.find((p) => p.code === 'RDY-SHT-101');
  const order = await (async () => {
    const items = [line(shirt, 1, { colorName: 'White', size: 'M' })];
    const q = await api.rpc(me, 'public.quote_pricing', [items, 'DEMO10']);
    return api.rpc(me, 'public.place_order', [{ contactPhone: '01712345678', shippingAddress: 'House 12, Road 4, Gazipur',
      paymentMethod: 'cod', items, voucherCode: 'DEMO10', expectedTotalMinor: q.totalMinor }]);
  })();
  assert.equal(order.totalMinor, 130500, '10% voucher off 1450.00');
});
