// Loads the real migrations into PGlite (PostgreSQL 18 in WASM) behind a thin
// Supabase shim (roles, auth schema, auth.uid()) so RLS and functions are
// tested against an actual SQL engine.
import { PGlite } from '@electric-sql/pglite';
import { pg_trgm } from '@electric-sql/pglite/contrib/pg_trgm';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const migDir = join(here, '..', 'supabase', 'migrations');

const SHIM = `
create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls;
create schema extensions; create schema auth;
create table auth.users (id uuid primary key default gen_random_uuid(), email text, raw_user_meta_data jsonb default '{}'::jsonb);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(coalesce(current_setting('request.jwt.claim.sub', true), ''), '')::uuid $$;
grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;
grant usage on schema extensions to anon, authenticated, service_role;
`;

export async function freshDb() {
  const db = new PGlite({ extensions: { pg_trgm } });
  await db.exec(SHIM);
  for (const f of readdirSync(migDir).filter((n) => n.endsWith('.sql')).sort()) {
    try {
      await db.exec(readFileSync(join(migDir, f), 'utf8'));
    } catch (e) {
      throw new Error(`migration ${f} failed: ${e.message}`);
    }
  }
  return new Api(db);
}

export class Api {
  constructor(db) { this.db = db; }
  /** Run SQL as the postgres owner (like the dashboard / service tooling). */
  async admin(sql, params) { await this.db.exec('reset role'); return this.db.query(sql, params); }
  /** Run SQL as a given Supabase role, optionally impersonating a user id. */
  async as(role, uid, sql, params) {
    await this.db.exec('reset role');
    await this.db.query(`select set_config('request.jwt.claim.sub', $1, false)`, [uid ?? '']);
    await this.db.exec(`set role ${role}`);
    try { return await this.db.query(sql, params); }
    finally { await this.db.exec('reset role'); await this.db.query(`select set_config('request.jwt.claim.sub','',false)`); }
  }
  user(uid) { return (sql, params) => this.as('authenticated', uid, sql, params); }
  service(sql, params) { return this.as('service_role', null, sql, params); }
  anon(sql, params) { return this.as('anon', null, sql, params); }
  /** Sign up through auth.users so the profile trigger runs (as GoTrue would). */
  async signUp(email, meta = {}) {
    const r = await this.admin(`insert into auth.users(email, raw_user_meta_data) values ($1,$2) returning id`, [email, JSON.stringify(meta)]);
    return r.rows[0].id;
  }
  async rpc(uid, fn, args = []) {
    const ph = args.map((_, i) => `$${i + 1}`).join(',');
    const r = await this.user(uid)(`select ${fn}(${ph}) as r`, args.map((a) => (a !== null && typeof a === 'object' ? JSON.stringify(a) : a)));
    return r.rows[0].r;
  }
}

/** Expect a rejection whose message contains `text`. */
export async function rejects(promise, text) {
  try { await promise; } catch (e) {
    if (text && !String(e.message).includes(text)) throw new Error(`expected error containing "${text}", got "${e.message}"`);
    return e;
  }
  throw new Error(`expected rejection${text ? ` containing "${text}"` : ''}, but it succeeded`);
}

export const VALID_META = { name: 'Rahim Uddin', phone: '01712345678', address: 'House 12, Road 4, Gazipur Sadar' };

const IMG = (n) => ({
  url: `https://res.cloudinary.com/hmpqmney/image/upload/v1/toptailers/products/${n}.jpg`,
  publicId: `toptailers/products/${n}`,
});
export { IMG };

/** Standard fixture: an admin, two customers, products and vouchers. */
export async function seed(api) {
  const adminId = await api.signUp('admin@toptailers.test', { name: 'Shop Admin', phone: '01800000000', address: 'Main Road, Gazipur' });
  await api.admin(`select public.provision_admin('admin@toptailers.test')`);
  const rahim = await api.signUp('rahim@example.com', VALID_META);
  const nusrat = await api.signUp('nusrat@example.com', { ...VALID_META, name: 'Nusrat Jahan', phone: '01911223344' });

  const mk = (o) => api.rpc(adminId, 'public.admin_save_product', [{
    availability: true, description: 'A good product', ...o }]);
  const cotton = await mk({ code: 'FAB-COT-001', productName: 'Premium Cotton Fabric', description: 'Soft breathable cotton',
    priceMinor: 45000, category: 'Fabrics', unit: 'yard', isFeatured: true, popularity: 90,
    colors: [{ name: 'White', argb: 0xFFF4F1EA }, { name: 'Sand', argb: 0xFFD8C3A0 }],
    discount: { enabled: true, kind: 'percent', value: 10 } });
  const silk = await mk({ code: 'FAB-SLK-002', productName: 'Silk Blend Fabric', priceMinor: 120000, category: 'Fabrics',
    isFeatured: true, popularity: 70, colors: [{ name: 'Maroon', argb: 0xFF7B1E3A }] });
  const shirt = await mk({ code: 'RDY-SHT-101', productName: "Men's Formal Shirt", priceMinor: 145000, category: 'Readymade',
    popularity: 80, colors: [{ name: 'White', argb: 0xFFF4F1EA }], sizes: ['S', 'M', 'L'] });
  const stitching = await mk({ code: 'TLR-SHT-201', productName: 'Shirt Stitching Service', priceMinor: 80000, category: 'Tailoring',
    requiresMeasurements: true, popularity: 75 });
  const buttons = await mk({ code: 'ACC-BTN-301', productName: 'Button & Thread Set', priceMinor: 25000, category: 'Accessories', popularity: 35 });
  const velvet = await mk({ code: 'FAB-VEL-005', productName: 'Velvet Fabric', priceMinor: 150000, category: 'Fabrics',
    availability: false, popularity: 30, colors: [{ name: 'Wine', argb: 0xFF5B1730 }] });

  const v = (o) => api.rpc(adminId, 'public.admin_save_voucher', [o]);
  await v({ code: 'DEMO10', title: 'Demo 10%', kind: 'percent', value: 10, isPublic: true });
  await v({ code: 'DEMOFAB15', title: 'Demo fabrics 15%', kind: 'percent', value: 15, categories: ['Fabrics'], isPublic: true });
  await v({ code: 'DEMOFLAT100', title: 'Demo flat', kind: 'fixed', value: 10000 });
  await v({ code: 'DEMOEXPIRED', title: 'Expired', kind: 'percent', value: 20, expiresAt: '2020-01-01T00:00:00Z' });
  await v({ code: 'DEMOOFF', title: 'Inactive', kind: 'percent', value: 5, isActive: false });

  return { adminId, rahim, nusrat, cotton, silk, shirt, stitching, buttons, velvet };
}

export const line = (p, qty = 1, extra = {}) => ({ productId: p.id, quantity: qty, ...extra });

/** Places an order as `uid` with the correct expected total from the server quote. */
export async function placeOrder(api, uid, items, extra = {}) {
  const quote = await api.rpc(uid, 'public.quote_pricing', [items, extra.voucherCode ?? null]);
  const req = { contactPhone: '01712345678', shippingAddress: 'House 12, Road 4, Gazipur', paymentMethod: 'cod',
    items, expectedTotalMinor: quote.totalMinor, ...extra };
  return api.rpc(uid, 'public.place_order', [req, extra.__key ?? null]);
}
