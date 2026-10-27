import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import * as M from '../src/throttle/morph-push.mjs';
import { searchOf, searchesOf, MORPH_ARMS } from '../src/throttle/push-cycle.mjs';
import { EXTRA_START_JS } from '../src/throttle/push-cycle-page.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const golden = readFileSync(join(HERE, '../../contracts/golden/measure/push-cycle.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const ops = (op) => golden.filter((g) => g.op === op);
const vms = (xs) => xs.map((v) => ({ vm: v.vm, wins: v.wins }));

test('constants match the Lean module', () => {
  const [c] = ops('pushConstants');
  assert.equal(M.PUSH_MS, c.pushMs);
  assert.equal(M.LEAD_MS, c.leadMs);
  assert.equal(M.TAIL_MS, c.tailMs);
  assert.equal(M.SLOW_MS, c.slowMs);
  assert.equal(M.MIN_WINS, c.minWins);
  assert.equal(M.MIN_VMS, c.minVms);
});

test('window membership equals the Lean golden', () => {
  assert.ok(ops('pushInWin').length >= 2);
  for (const g of ops('pushInWin')) assert.deepEqual(g.ts.map((t) => M.inWin(g.t0, t)), g.in);
});

test('windows of a pass equal the Lean golden', () => {
  assert.ok(ops('pushWindows').length >= 5);
  for (const g of ops('pushWindows')) {
    const r = { rows: g.rows, rafs: g.rafs, frames: g.frames, endMs: g.endMs };
    assert.deepEqual(M.windows(r, g.starts), g.windows, g.case);
  }
});

test('the arm verdict equals the Lean golden', () => {
  assert.ok(ops('pushVerdict').length >= 7);
  for (const g of ops('pushVerdict')) {
    const b = vms(g.base), a = vms(g.arm);
    assert.equal(M.vmCount(b), g.baseVms, g.case);
    assert.equal(M.vmCount(a), g.armVms, g.case);
    assert.deepEqual(M.armCmps(b, a), g.cmps, g.case);
    assert.equal(M.armVerdict(b, a), g.verdict, g.case);
  }
});

test('the quiet checks equal the Lean golden', () => {
  assert.ok(ops('pushQuiet').length >= 5);
  for (const g of ops('pushQuiet')) {
    assert.equal(M.quietVerdict(M.quiet, vms(g.vms)), g.quiet, g.case);
    assert.equal(M.quietVerdict(M.rafFree, vms(g.vms)), g.rafFree, g.case);
  }
});

test('timeline seconds map to page ms through the sync mark', () => {
  assert.equal(M.pageMs(12.5, { p: 4000, s: 10 }), 6500);
});

test('buildPush keeps only rows and rAF requests inside a push window, in page ms', () => {
  const rec = { o: [0, 1, 1, 0], t: [100, 1000, 1016, 1032] };
  const rows = [['TimeStamp', 1, null, 'fwpc:sync'], ['Layout', 1.5, null, null], ['Paint', 2.1, null, null], ['Composite', 2.2, null, null], ['Layout', 9, null, null]];
  const p = M.buildPush({ rows, sync: { p: 500, s: 1 }, sync2: { p: 8500, s: 9 }, rafs: [900, 1100.4, 2000], rec, endP: 5000 });
  assert.deepEqual(p.starts, [1000]);
  assert.deepEqual(p.rows, [['Layout', 1000], ['Paint', 1600]]);
  assert.deepEqual(p.rafs, [1100]);
  assert.equal(p.drift, 0);
});

test('buildPushSegs maps every segment through its own marks and reports the largest drift', () => {
  const rec = { o: [0, 1, 1, 0], t: [100, 1000, 1016, 1032] };
  const g1 = { rows: [['Layout', 1.5, null, null]], sync: { p: 500, s: 1 }, sync2: { p: 700, s: 1.2 } };
  const g2 = { rows: [['Paint', 5.1, null, null], ['Layout', 9, null, null]], sync: { p: 0, s: 5 }, sync2: { p: 4000, s: 9.01 } };
  const p = M.buildPushSegs({ segs: [g1, g2], rafs: [1100.4], rec, endP: 5000 });
  assert.deepEqual(p.rows, [['Layout', 1000]]);
  assert.equal(p.drift, -10);
  assert.equal(p.segs, 2);
});

test('stampSync takes the first and last page-side stamp of a segment', () => {
  const rows = [['TimeStamp', 1, null, 'fwpc:100.5'], ['Layout', 1.2, null, null], ['TimeStamp', 1.5, null, 'fwpc:600.2'], ['TimeStamp', 2, null, 'other'], ['TimeStamp', 9.25, null, 'fwpc:8300']];
  assert.deepEqual(M.stampSync(rows), { sync: { p: 100.5, s: 1 }, sync2: { p: 8300, s: 9.25 } });
  assert.equal(M.stampSync(rows.slice(0, 2)), null);
});

test('the morph arms have their own pages and the base page is the default one', () => {
  assert.equal(searchOf('morph-base'), '');
  assert.equal(searchOf('morph-geom'), '?fw=morph.geom:on');
  assert.equal(searchOf('morph-timed'), '?fw=morph.geom:on,morph.tween:geom-timed');
  assert.deepEqual(searchesOf(Object.keys(MORPH_ARMS)), ['?fw=morph.geom:on', '?fw=morph.geom:on,morph.tween:geom-timed']);
});

test('the recorder wraps requestAnimationFrame and still calls the native one', () => {
  assert.match(EXTRA_START_JS, /native\(cb\)/);
  assert.match(EXTRA_START_JS, /cb !== st\.cb/);
});
