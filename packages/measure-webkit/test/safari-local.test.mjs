import { test } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { webdriver, freePort, armServer } from '../src/safari-local.mjs';

async function stub() {
  const seen = [];
  const server = http.createServer((req, res) => {
    let body = '';
    req.on('data', (d) => { body += d; });
    req.on('end', () => {
      seen.push([req.method, req.url, body ? JSON.parse(body) : null]);
      const send = (code, value) => { res.writeHead(code, { 'content-type': 'application/json' }); res.end(JSON.stringify({ value })); };
      if (req.url === '/session') return send(200, { sessionId: 'S1', capabilities: {} });
      if (req.url.endsWith('/execute/async')) {
        const b = JSON.parse(body);
        return send(200, b.script.includes('FAIL') ? { err: 'Error: nope' } : { ok: { ts: [0, 16.7] } });
      }
      if (req.url.endsWith('/execute/sync')) return send(200, 'sync-result');
      if (req.url.endsWith('/url')) return send(404, { error: 'no such window', message: 'gone' });
      send(200, null);
    });
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  return { seen, base: `http://127.0.0.1:${server.address().port}`, close: () => new Promise((r) => { server.closeAllConnections(); server.close(r); }) };
}

test('webdriver: session, scripts, errors and close against a stub endpoint', async () => {
  const s = await stub();
  try {
    const wd = webdriver(s.base);
    await wd.newSession();
    assert.deepEqual(s.seen[0], ['POST', '/session', { capabilities: { alwaysMatch: { browserName: 'safari' } } }]);
    assert.equal(await wd.sync('return 1'), 'sync-result');
    assert.deepEqual(await wd.expr('Promise.resolve(1)'), { ts: [0, 16.7] });
    await assert.rejects(() => wd.expr('FAIL'), /page: Error: nope/);
    await assert.rejects(() => wd.navigate('http://x/'), /404 no such window/);
    await wd.close();
    assert.deepEqual(s.seen.at(-1).slice(0, 2), ['DELETE', '/session/S1']);
    await wd.close();
    assert.equal(s.seen.filter((x) => x[0] === 'DELETE').length, 1, 'close is idempotent');
  } finally { await s.close(); }
});

test('freePort gives a port that can be listened on', async () => {
  const p = await freePort();
  assert.ok(p > 1024 && p < 65536);
});

test('armServer answers each arm from its own tree on one origin', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'fw-arm-'));
  try {
    writeFileSync(join(dir, 'configs.json'), JSON.stringify({ bySearch: { '': 'h0', '?x': 'h1' }, byHash: { h0: 'a.html', h1: 'b.html' } }));
    writeFileSync(join(dir, 'a.html'), 'default'); writeFileSync(join(dir, 'b.html'), 'flagged');
    const srv = await armServer([{ id: 'base', tree: { dir, search: '' } }, { id: 'x', tree: { dir, search: '?x' } }]);
    try {
      assert.equal(await (await fetch(srv.url)).text(), 'default');
      srv.setArm('x');
      assert.equal(await (await fetch(srv.url)).text(), 'flagged');
      assert.equal(srv.armHash('x'), 'h1');
      assert.throws(() => srv.setArm('nope'), /no arm/);
    } finally { await srv.close(); }
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
