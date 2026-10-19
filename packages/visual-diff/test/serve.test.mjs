import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { startOverlayServer } from '../src/serve.mjs';

test('overlay server: the rewrite build is served with the types a browser accepts; media falls back, documents never do', async () => {
  const root = mkdtempSync(join(tmpdir(), 'vd-root-'));
  const snap = mkdtempSync(join(tmpdir(), 'vd-snap-'));
  mkdirSync(join(root, 'assets'));
  writeFileSync(join(root, 'index.html'), '<!doctype html>');
  writeFileSync(join(root, 'assets', 'a.css'), '@layer x{}');
  writeFileSync(join(root, 'assets', 'a.js'), 'export {}');
  writeFileSync(join(snap, 'only-in-snapshot.png'), 'png');
  writeFileSync(join(snap, 'only-in-snapshot.css'), 'a{}');
  const s = await startOverlayServer(root, snap);
  try {
    const get = async (p) => { const r = await fetch(s.origin + p); return [r.status, r.headers.get('content-type')]; };
    assert.deepEqual(await get('/'), [200, 'text/html; charset=utf-8']);
    assert.deepEqual(await get('/assets/a.css'), [200, 'text/css; charset=utf-8']);
    assert.deepEqual(await get('/assets/a.js'), [200, 'text/javascript; charset=utf-8']);
    assert.deepEqual(await get('/only-in-snapshot.png'), [200, 'image/png']);
    assert.equal((await get('/only-in-snapshot.css'))[0], 404);
  } finally {
    await s.close();
  }
});
