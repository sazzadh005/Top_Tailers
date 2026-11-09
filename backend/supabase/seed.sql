-- DEVELOPMENT / DEMO SEED ONLY. Do not run against a production shop.
-- Gives a fresh project a small catalogue, banners and sample vouchers so the app
-- has something to show. Real products are created by the admin in the app.
-- Run in the Supabase SQL editor, or automatically by `supabase db reset` locally.

insert into public.promo_banners(id, title, subtitle, color_argb, category, voucher_code, position) values
  ('b1', 'Festive Fabrics', 'Up to 15% off fabrics with a voucher', 4287103018, 'Fabrics', 'DEMOFAB15', 0),
  ('b2', 'Made to Measure', 'Professional tailoring for every occasion', 4281545523, 'Tailoring', null, 1),
  ('b3', 'Ready to Wear', 'Formal shirts and more', 4278232446, 'Readymade', null, 2)
on conflict (id) do nothing;

insert into public.vouchers(code, title, kind, value, categories, is_public) values
  ('DEMO10', 'Demo 10% off', 'percent', 10, '{}', true),
  ('DEMOFAB15', 'Demo 15% off fabrics', 'percent', 15, '{Fabrics}', true),
  ('DEMOFLAT100', 'Demo 100 BDT off', 'fixed', 10000, '{}', false)
on conflict (code) do nothing;

insert into public.products(code, product_name, description, price_minor, category, unit, requires_measurements, is_featured, popularity, specs) values
  ('FAB-COT-001', 'Premium Cotton Fabric', 'Soft, breathable cotton for shirts and kurtas.', 45000, 'Fabrics', 'yard', false, true, 90, '{"Material":"100% cotton","Width":"44 in"}'),
  ('FAB-SLK-002', 'Silk Blend Fabric', 'Smooth silk blend with a subtle sheen.', 120000, 'Fabrics', 'yard', false, true, 70, '{"Material":"Silk blend"}'),
  ('RDY-SHT-101', 'Men''s Formal Shirt', 'Classic fit formal shirt.', 145000, 'Readymade', 'piece', false, false, 80, '{}'),
  ('TLR-SHT-201', 'Shirt Stitching Service', 'Custom shirt stitched to your measurements.', 80000, 'Tailoring', 'service', true, false, 75, '{}'),
  ('ACC-BTN-301', 'Button & Thread Set', 'Matching buttons and thread.', 25000, 'Accessories', 'piece', false, false, 35, '{}')
on conflict (code) do nothing;

insert into public.product_variants(product_id, type, name, argb, position)
select id, 'color', c.name, c.argb, c.pos from public.products p
join (values ('FAB-COT-001','White',4294045930,0),('FAB-COT-001','Sand',4292232096,1),('FAB-SLK-002','Maroon',4286455354,0),('RDY-SHT-101','White',4294045930,0)) as c(code,name,argb,pos) on c.code = p.code
on conflict do nothing;

insert into public.product_variants(product_id, type, name, position)
select p.id, 'size', s.name, s.pos from public.products p
join (values ('RDY-SHT-101','S',0),('RDY-SHT-101','M',1),('RDY-SHT-101','L',2)) as s(code,name,pos) on s.code = p.code
on conflict do nothing;
