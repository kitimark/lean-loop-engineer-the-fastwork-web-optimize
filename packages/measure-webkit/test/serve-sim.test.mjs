import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { safeJoin, serveTree } from '../src/serve.mjs';
import { ports, iwdpConfigText } from '../src/sim.mjs';
import { schedule } from '../src/scrollrun.mjs';
import { bootstrapSource } from '../src/page.mjs';

test('safeJoin keeps requests inside the root', () => {
  const root = '/srv/site';
  assert.equal(safeJoin(root, '/a/b.css?x=1'), '/srv/site/a/b.css');
  assert.equal(safeJoin(root, '/'), '/srv/site');
  assert.equal(safeJoin(root, '/../etc/passwd'), null);
  assert.equal(safeJoin(root, '/%2e%2e/etc/passwd'), null);
  assert.equal(safeJoin(root, '/a%00b'), null);
});

test('serveTree serves files, mounts and the analytics stub, no-store, read-only', async () => {
  const root = mkdtempSync(join(tmpdir(), 'fw-wk-t-'));
  const fx = mkdtempSync(join(tmpdir(), 'fw-wk-f-'));
  writeFileSync(join(root, 'index.html'), '<p>hi</p>');
  writeFileSync(join(root, 'analytics.js'), 'REAL');
  mkdirSync(join(root, 'd'));
  writeFileSync(join(fx, 'seek.html'), 'FIX');
  const s = await serveTree(root, { mounts: { '/__fixtures': fx } });
  try {
    const get = (p, init) => fetch(`http://127.0.0.1:${s.port}${p}`, init);
    const r = await get('/');
    assert.equal(r.status, 200);
    assert.equal(r.headers.get('cache-control'), 'no-store');
    assert.equal(await r.text(), '<p>hi</p>');
    assert.equal(await (await get('/__fixtures/seek.html')).text(), 'FIX');
    assert.match(await (await get('/analytics.js')).text(), /replaced by an empty script/);
    assert.equal((await get('/nope')).status, 404);
    assert.equal((await get('/', { method: 'POST' })).status, 405);
    assert.equal((await get('/', { headers: { range: 'bytes=0-2' } })).status, 206);
  } finally { await s.close(); }
  const live = await serveTree(root, { vendors: 'live' });
  try { assert.equal(await (await fetch(`http://127.0.0.1:${live.port}/analytics.js`)).text(), 'REAL'); } finally { await live.close(); }
});

test('ports refuse the phone proxy and duplicates', () => {
  assert.deepEqual(ports({}), { list: 9341, tabs: 9342 });
  assert.throws(() => ports({ FW_WK_LIST_PORT: '9222' }), /phone/);
  assert.throws(() => ports({ FW_WK_LIST_PORT: '9350', FW_WK_TABS_PORT: '9350' }), /differ/);
});

test('proxy config ignores phones (-1) and ends with the simulator port', () => {
  const id = 'a'.repeat(25);
  assert.equal(iwdpConfigText([id, id], { list: 1, tabs: 2 }), `null:1\n${id}:-1\n:2\n`);
  assert.equal(iwdpConfigText([], { list: 1, tabs: 2 }), 'null:1\n:2\n');
});

test('schedule ends exactly at maxY', () => {
  assert.deepEqual(schedule(120, 50), [0, 50, 100, 120]);
  assert.deepEqual(schedule(100, 50), [0, 50, 100]);
});

test('bootstrap source parses and pins only when asked', () => {
  assert.doesNotThrow(() => new Function(bootstrapSource({ clock: 'pinned' })));
  assert.match(bootstrapSource({ clock: 'pinned' }), /static now\(\)/);
  assert.doesNotMatch(bootstrapSource({ clock: 'live' }), /static now\(\)/);
});
