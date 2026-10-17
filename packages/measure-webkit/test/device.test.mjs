// Pure parts of the phone support (no phone, no proxy): config text, redaction, ports, frame statistics.
import test from 'node:test';
import assert from 'node:assert/strict';
import { phoneConfigText, redact, PHONE_PORTS } from '../src/device.mjs';
import { frameStats, summarizeFrames } from '../src/device-runs.mjs';
import { serveTree } from '../src/serve.mjs';

const UD = '00001111-0000111122223333';
const OTHER = '00009999-0000999988887777';

test('proxy config: the phone on the tabs port, every other phone ignored, never the Simulator or 9221/9222 ports', () => {
  const t = phoneConfigText(UD, [UD, OTHER], PHONE_PORTS);
  assert.deepEqual(t.trim().split('\n'), [`null:${PHONE_PORTS.list}`, `${UD}:${PHONE_PORTS.tabs}`, `${OTHER}:-1`]);
  for (const p of Object.values(PHONE_PORTS)) assert.ok(![9221, 9222, 9341, 9342].includes(p));
});

test('redact removes the LAN address, device ids and other IPv4 addresses', () => {
  const ip = (...p) => p.join('.'); // built from parts so no address literal sits in the file
  const lan = ip(192, 168, 1, 20); const other = ip(10, 0, 0, 5);
  const s = redact(`GET http://${lan}:8000/ for ${UD} via ${other} and 127.0.0.1`, lan, UD);
  assert.ok(!s.includes(lan) && !s.includes(UD) && !s.includes(other));
  assert.ok(s.includes('127.0.0.1'));
  assert.ok(!redact(`id ${OTHER}`).includes(OTHER));
});

test('frame statistics: moving frames only, intervals > 34 and > 50 ms per 100, per 500 px zone', () => {
  // intervals 17,17,60,17,40,17 ; the 5th frame (index 4) does not move (same y as the one before)
  const ts = [0, 17, 34, 94, 111, 151, 168];
  const ys = [0, 10, 20, 30, 30, 50, 600];
  const rows = frameStats({ ts, ys });
  assert.equal(rows.length, 5);
  const s = summarizeFrames([{ ts, ys }]);
  assert.equal(s.total.moving, 5);
  assert.equal(s.total.over34, 2);
  assert.equal(s.total.over50, 1);
  assert.equal(s.total.per100Over50, 20);
  assert.equal(s.total.longestMs, 60);
  assert.equal(s.zones.length, 2);
  assert.equal(s.zones[1].moving, 1);
});

test('compareArms tabulates mean/min/max per zone and in total, per arm', async () => {
  const { compareArms, compareMarkdown } = await import('../src/device-compare.mjs');
  const { COUNT_TYPES } = await import('../src/reduce.mjs');
  const mk = (layout) => {
    const counts = COUNT_TYPES.map(() => 0); counts[COUNT_TYPES.indexOf('Layout')] = layout;
    const total = Object.fromEntries(COUNT_TYPES.map((t) => [t, t === 'Layout' ? layout : 0]));
    return { total, zones: [{ counts, paintArea: 10 }], census: [{ requestedY: 0, layerCount: 3, memoryBytes: 100 }] };
  };
  const cmp = compareArms({ a: [mk(2), mk(4)], b: [mk(10)] });
  assert.equal(cmp.types.Layout.total.a.mean, 3);
  assert.equal(cmp.types.Layout.total.a.min, 2);
  assert.equal(cmp.types.Layout.zones[0].b.max, 10);
  assert.deepEqual(cmp.arms, { a: 2, b: 1 });
  assert.match(compareMarkdown(cmp), /\| \*\*total\*\* \| 3 \[2-4\] \| 10 \[10-10\] \|/);
});

test('serveTree binds the host it is given and reports it in url', async () => {
  const s = await serveTree('.', { host: '127.0.0.1' });
  try { assert.match(s.url, /^http:\/\/127\.0\.0\.1:\d+\/$/); } finally { await s.close(); }
});
