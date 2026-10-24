import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { client } from '../src/trajectory/transitions-safari.mjs';

function fake(handler) {
  const seen = [];
  const srv = createServer((req, res) => {
    let b = '';
    req.on('data', (d) => { b += d; });
    req.on('end', () => {
      seen.push([req.method, req.url, b ? JSON.parse(b) : null]);
      const [code, value] = handler(req.method, req.url);
      res.writeHead(code, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ value }));
    });
  });
  return new Promise((r) => srv.listen(0, '127.0.0.1', () => r({ srv, seen, base: `http://127.0.0.1:${srv.address().port}` })));
}

test('client: opens a session, runs scripts under it and deletes it', async () => {
  const f = await fake((m, u) => (u === '/session' ? [200, { sessionId: 's1', capabilities: { browserName: 'Safari', browserVersion: '26' } }] : [200, 7]));
  try {
    const c = client(f.base);
    const caps = await c.open();
    assert.equal(caps.browserName, 'Safari');
    assert.equal(await c.sync('return 7'), 7);
    await c.async('cb(1)', [2]);
    await c.close();
    assert.deepEqual(f.seen.map((s) => `${s[0]} ${s[1]}`), ['POST /session', 'POST /session/s1/execute/sync', 'POST /session/s1/execute/async', 'DELETE /session/s1']);
    assert.deepEqual(f.seen[2][2], { script: 'cb(1)', args: [2] });
  } finally { f.srv.close(); }
});

test('client: a driver error is thrown with its name', async () => {
  const f = await fake(() => [500, { error: 'session not created', message: 'Allow Remote Automation is off' }]);
  try {
    await assert.rejects(client(f.base).open(), /session not created/);
  } finally { f.srv.close(); }
});
