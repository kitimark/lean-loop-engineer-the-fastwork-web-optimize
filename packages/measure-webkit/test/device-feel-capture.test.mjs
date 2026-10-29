import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { CAP_START_JS, inputsOf, visitCapture } from '../src/device-feel-capture.mjs';
import { captureOf } from '../src/device-feel-cap.mjs';
import { normalize } from '../src/device-session.mjs';

const mk = (n, f) => Array.from({ length: n }, (_, i) => f(i));
// 6 frames at 16.7 ms; the page scrolls 100 px per frame; frame 5 is idle (last scroll move 1.5 s ago).
const raw = () => ({
  zoom: { frames: 0, min: 1, max: 1 }, maxY: 5000, viewport: { w: 390, h: 844, dpr: 3 }, cardCount: 2,
  frames: {
    t: mk(6, (i) => 100 + i * 16.7), y: [0, 100, 200, 700, 800, 800], vh: mk(6, () => 844), vt: mk(6, () => 0),
    p: { hero: mk(6, () => 0), people: mk(6, () => 0), fade: mk(6, () => 0) },
    o: mk(6, (i) => [1000, i === 2 ? 400 : 1000]), a: [1, 1, 1, 1, 1, 0],
  },
  touches: [[100, 's', 10, 400, 1], [110, 'm', 10, 380, 1], [200, 'e', 10, 300, 1]],
  pins: [[117, 100, 90]], starts: [[100, 0, 1000], [110, 400, 1000]],
});
const row = (type, start, msg = null) => [type, start, start + 0.1, msg];
const rows = () => [
  ...mk(6, (i) => row('TimeStamp', 1 + i * 0.0167, `cap:${i}`)), row('TimeStamp', 1.2, 'cap:end'),
  row('RecalculateStyles', 1.0), row('Layout', 1.02), row('Paint', 1.05), row('Paint', 1.19),
  row('RecalculateStyles', 1.06), row('RecalculateStyles', 1.1),
];

test('inputsOf converts page units to Lean units and joins Timeline rows to zones', () => {
  const r = raw();
  const x = inputsOf(r, rows());
  assert.deepEqual(x.ts.slice(0, 2), [10000, 11670]);
  assert.deepEqual(x.ys, [0, 1000, 2000, 7000, 8000, 8000]);
  assert.deepEqual(x.pins, [[11700, 1000, 900]]);
  assert.deepEqual(x.starts, [[0, 1000], [400, 1000]]);
  assert.equal(x.cards.length, 2);
  assert.deepEqual(x.cards[1], [1000, 1000, 400, 1000, 1000, 1000]);
  assert.equal(x.zoneNote, null);
  // zone 0: style (frame 0), layout (frame 1), paint (frame 2); zone 1: the style in frame 3; the idle step takes the rest
  assert.deepEqual(x.zones.map((c) => c[0] + c[1] + c[2]), [3, 1]);
  const cap = captureOf(x);
  assert.equal(cap.pins, 1);
  assert.equal(cap.blinks, 1);
  assert.equal(cap.retargets, 1);
  assert.equal(cap.fights, 1);
});

test('inputsOf offsets overscroll, drops idle steps from the zones and survives missing Timeline marks', () => {
  const r = raw();
  r.frames.y = [-50, -20, 0, 700, 800, 800];
  const x = inputsOf(r, rows());
  assert.equal(x.ys[0], 0);
  assert.equal(x.ys[2], 500);
  const idleOnly = inputsOf(r, []);
  assert.deepEqual(idleOnly.zones, []);
  assert.match(idleOnly.zoneNote, /no frame marks/);
  const noEnd = inputsOf(r, rows().filter((q) => q[3] !== 'cap:end'));
  assert.match(noEnd.zoneNote, /no end mark/);
});

test('the idle frame work is not counted in a zone', () => {
  const x = inputsOf(raw(), rows());
  // the final Paint at 1.19 belongs to the idle step 5 (mark at 1.0835 .. end 1.2): not in any zone
  const total = x.zones.flat().reduce((a, b) => a + b, 0);
  const all = rows().filter((q) => ['RecalculateStyles', 'Layout', 'Paint'].includes(q[0])).length;
  assert.ok(total < all);
});

test('the page recorder installs the pin, trace and touch hooks and carries the Lean idle limit', () => {
  assert.match(CAP_START_JS, /window\.scrollTo = /);
  assert.match(CAP_START_JS, /__fwTakeTrace/);
  assert.match(CAP_START_JS, /IDLE = 1500/);
  assert.match(CAP_START_JS, /hero\.orbit_card/);
});

test('the saved raw record normalizes for the replay lanes', () => {
  const dir = mkdtempSync(join(tmpdir(), 'cap-test-'));
  try {
    const st = { n: 6, zoom: { frames: 0, min: 1, max: 1 }, maxY: 5000, viewport: { w: 390, h: 844, dpr: 3 }, touches: raw().touches, pins: raw().pins, starts: raw().starts, cards: 2 };
    const frames = raw().frames;
    const calls = [];
    const c = {
      evaluate: async (expr) => {
        calls.push(expr);
        if (expr.includes('__fwCap.stop()')) return JSON.stringify(st);
        const m = expr.match(/slice\("([^"]+)", (\d+), (\d+)\)/);
        if (m) { const v = m[1].startsWith('p.') ? frames.p[m[1].slice(2)] : frames[m[1]]; return JSON.stringify(v.slice(Number(m[2]), Number(m[3]))); }
        return 'on';
      },
    };
    const logs = [];
    const vc = visitCapture({ ctx: { c }, visit: { id: 'base', label: 'A', index: 0 }, dir, log: (l) => logs.push(l), startTl: async () => ({ stop: async () => rows() }) });
    return vc.start().then(async (ok) => {
      assert.equal(ok, true);
      assert.equal(vc.open, true);
      const r = await vc.finish();
      assert.equal(vc.open, false);
      assert.equal(r.capture.pins, 1);
      assert.equal(r.file, join('visits', '01-A.json'));
      assert.ok(existsSync(join(dir, r.file)));
      const rec = JSON.parse(readFileSync(join(dir, r.file), 'utf8'));
      assert.equal(rec.schema, 'fw.phone.record/1');
      const n = normalize(rec);
      assert.equal(n.t.length, 6);
      assert.equal(n.touches.length, 3);
      assert.equal(rec.feel.active.length, 6);
      assert.deepEqual((await vc.finish()).error, 'no capture was running');
    });
  } finally {
    // removed after the promise settles in the next test turn
    setTimeout(() => rmSync(dir, { recursive: true, force: true }), 500);
  }
});

test('a failing start leaves the visit unmeasured and the session alive', async () => {
  const logs = [];
  const vc = visitCapture({ ctx: { c: { evaluate: async () => { throw new Error('boom'); } } }, visit: { id: 'base', label: 'B', index: 1 }, dir: tmpdir(), log: (l) => logs.push(l), startTl: async () => ({ stop: async () => [] }) });
  assert.equal(await vc.start(), false);
  assert.equal(vc.open, false);
  assert.match(logs.join('\n'), /capture start failed/);
});
