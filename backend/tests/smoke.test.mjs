import test from 'node:test';
import assert from 'node:assert/strict';
import { freshDb, seed } from './harness.mjs';

test('migrations apply cleanly and the fixture seeds through the real RPCs', async () => {
  const api = await freshDb();
  const r = await api.admin(`select count(*)::int as n from pg_tables where schemaname='public'`);
  assert.ok(r.rows[0].n >= 25, `expected the schema tables, got ${r.rows[0].n}`);
  const S = await seed(api);
  assert.equal(S.cotton.code, 'FAB-COT-001');
});
