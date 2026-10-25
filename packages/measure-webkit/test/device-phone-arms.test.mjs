import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import * as P from '../src/device-phone-arms.mjs';
import { resolveFlags } from '../src/device-arms.mjs';
import { spread } from '../src/device-session.mjs';
import { COUNT_TYPES } from '../src/reduce.mjs';

const lines = readFileSync(new URL('../../contracts/golden/device/phone-arms.jsonl', import.meta.url), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);
const byId = new Map(P.ARMS.map((a) => [a.id, a]));
const ids = (xs) => xs.map((a) => a.id);

test('every golden kind has lines', () => {
  for (const k of ['consts', 'arm', 'dedup', 'visits', 'session', 'blocks', 'start', 'zones', 'cell', 'label', 'table']) assert.ok(of(k).length > 0, k);
});

test('dedup matches Lean', () => {
  for (const c of of('dedup')) {
    assert.deepEqual(ids(P.dedup(c.in)), c.kept, c.name);
    assert.deepEqual(P.dropped(c.in), c.dropped, c.name);
  }
});

test('the session: no arm is dropped, the base opens, closes and sits mid-way, every other arm once', () => {
  assert.equal(P.KEPT.length, P.ARMS.length);
  assert.equal(P.KEPT.length, 14);
  assert.equal(P.SESSION.length, 16);
  const l = ids(P.SESSION);
  assert.equal(l.filter((x) => x === 'base').length, 3);
  assert.equal(l[0], 'base');
  assert.equal(l[l.length - 1], 'base');
  for (const a of P.OTHERS) assert.equal(l.filter((x) => x === a.id).length, 1, a.id);
});

test('visits, blocks and the session plan match Lean', () => {
  for (const c of of('visits')) {
    const os = c.others.map((i) => byId.get(i));
    assert.deepEqual(ids(P.visits(P.BASE, os)), c.visits, c.name);
  }
  const [s] = of('session');
  assert.deepEqual(ids(P.SESSION), s.visits);
  assert.deepEqual(P.blocks(P.PA.perBlock, ids(P.SESSION)), s.blocks);
  assert.equal(P.wallMin(P.SESSION.length), s.wallMin);
  for (const c of of('wallmin')) assert.equal(P.wallMin(c.n), c.wallMin, `n=${c.n}`);
  for (const c of of('blocks')) {
    const l = Array.from({ length: c.n }, (_, i) => i);
    const b = P.blocks(c.per, l);
    assert.deepEqual(b.map((x) => x.length), c.blocks);
    assert.deepEqual(b.flat(), c.flat);
  }
});

test('when a visit may start matches Lean', () => {
  for (const c of of('start')) {
    assert.equal(P.mayStart(c.elapsedS, c.longestS), c.mayStart, JSON.stringify(c));
    assert.equal(P.coolOk(c.elapsedS), c.coolOk, JSON.stringify(c));
  }
});

test('bin zones and zone sums match Lean', () => {
  for (const c of of('zones')) {
    assert.deepEqual(c.bins.map((b) => P.binZone(c.vh10, c.maxY10, b[0])), c.zones);
    for (const z of ['hero', 'finish', 'rest']) assert.equal(P.zoneSum(c.vh10, c.maxY10, z, c.bins), c[z], z);
  }
});

test('cell verdicts, labels and tables match Lean', () => {
  for (const c of of('cell')) {
    assert.equal(P.cells([c.base], [c.arm])[0], c.verdict, JSON.stringify(c));
    assert.equal(spread(c.base), c.spread);
  }
  for (const c of of('label')) assert.equal(P.labelOf(c.cells), c.label, JSON.stringify(c.cells));
  for (const c of of('table')) {
    assert.deepEqual(c.arms.map((a) => P.cells(c.base, a)), c.cells);
    assert.deepEqual(P.table(c.base, c.arms), c.labels);
  }
});

test('the constants are the ones the CLI runs', () => {
  const [c] = of('consts');
  assert.deepEqual(P.PA, c);
  assert.equal(c.perBlock, Math.floor(c.capMin / c.visitMin));
  for (const m of P.METRICS.filter((x) => !['over34', 'over50', 'paintArea'].includes(x))) assert.ok(COUNT_TYPES.includes(m), m);
  assert.ok(P.METRICS.includes('paintArea'));
});

test('each flag arm loads exactly its flags, and the arm ids are the flags it adds', () => {
  for (const a of P.ARMS) {
    if (a.target === 'original') continue;
    assert.deepEqual(resolveFlags(P.searchOf(a)), [...a.flags].sort(), a.id);
  }
});

test('pagesOf names the prerendered page of each arm and the arm that would duplicate it', () => {
  const dir = mkdtempSync(join(tmpdir(), 'pa-'));
  try {
    const bySearch = { '': 'h0' };
    P.ARMS.filter((a) => a.flags.length > 0).forEach((a, i) => { bySearch[P.searchOf(a)] = `h${i + 1}`; });
    writeFileSync(join(dir, 'configs.json'), JSON.stringify({ bySearch, byHash: {} }));
    const r = P.pagesOf(dir);
    assert.equal(r.distinct, true);
    assert.equal(r.rows.length, 14);
    bySearch[P.searchOf(P.ARMS[3])] = 'h0';
    writeFileSync(join(dir, 'configs.json'), JSON.stringify({ bySearch, byHash: {} }));
    assert.deepEqual(P.pagesOf(dir).dup, [{ id: P.ARMS[3].id, sameAs: 'base' }]);
    delete bySearch[P.searchOf(P.ARMS[4])];
    writeFileSync(join(dir, 'configs.json'), JSON.stringify({ bySearch, byHash: {} }));
    assert.throws(() => P.pagesOf(dir), /not prerendered/);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

const countsFile = (layout, vh = 775, maxY = 5267, area = 0, layers = 100) => ({
  reduced: Array.from({ length: 3 }, () => ({
    info: { vh, maxY },
    zones: Array.from({ length: 11 }, (_, i) => ({ zone: i, y0: i * 500, steps: 10, counts: COUNT_TYPES.map((t) => (t === 'Layout' ? layout : 1)), paintArea: area })),
    census: [0, 1500, 'max'].map((y) => ({ requestedY: y, layerCount: layers, memoryBytes: layers * 1048576 })),
  })),
});
const framesFile = (slow, maxY = 5267) => ({
  runs: Array.from({ length: 5 }, () => {
    const ts = [], ys = [];
    let t = 0;
    for (let k = 0; k * 13 <= maxY; k++) { t += k === 380 ? 60 : 16.67; ts.push(Math.round(t * 100) / 100); ys.push(Math.min(maxY, k * 13)); }
    if (!slow) ts.forEach((_, i) => { ts[i] = Math.round(i * 16.67 * 100) / 100; });
    return { maxY, ts, ys };
  }),
});

test('a visit reduces to Layout sums per zone and slow-frame rates per zone', () => {
  const v = P.visitValues(countsFile(2), framesFile(true));
  assert.equal(v.vh, 775);
  assert.equal(v.counts.length, 3);
  assert.equal(v.counts[0].hero.Layout, 2 * 3);
  assert.equal(v.counts[0].finish.Layout + v.counts[0].rest.Layout + v.counts[0].hero.Layout, 2 * 11);
  assert.equal(v.frames.length, 5);
  assert.ok(v.frames[0].finish.over34 > 0 || v.frames[0].rest.over34 > 0);
  const flat = P.visitValues(countsFile(2), framesFile(false));
  assert.deepEqual(['hero', 'finish', 'rest'].map((z) => flat.frames[0][z].over34), [0, 0, 0]);
});

test('the session table: a lower Layout beyond the base spread is better, equal is same, a missing arm is unresolved', () => {
  const mk = (arm, layout, slow) => ({ arm, values: P.visitValues(countsFile(layout), framesFile(slow)) });
  const second = P.OTHERS[1].id, third = P.OTHERS[2].id;
  const done = [mk('base', 4, true), mk('base', 4, true), mk('base', 4, true), mk(P.OTHERS[0].id, 1, true), mk(second, 4, true)];
  const t = P.reduceSession(done);
  assert.equal(t.base.visits, 3);
  const first = t.arms.find((a) => a.id === P.OTHERS[0].id);
  assert.equal(first.cells.find((c) => c.zone === 'hero' && c.metric === 'Layout').verdict, 'beats');
  assert.equal(first.labels.counts.hero, 'better');
  assert.equal(first.cells.find((c) => c.zone === 'hero' && c.metric === 'over34').verdict, 'same');
  assert.equal(t.arms.find((a) => a.id === second).labels.counts.all, 'same');
  const none = t.arms.find((a) => a.id === third);
  assert.equal(none.visits, 0);
  assert.equal(none.labels.counts.all, 'unresolved');
  assert.deepEqual(P.anomalies(done), []);
  assert.ok(P.anomalies([{ arm: 'base', values: P.visitValues(countsFile(4), framesFile(true)) }, { arm: 'x', values: P.visitValues(countsFile(4, 700), framesFile(true)) }])[0].includes('viewport'));
});

test('paintArea sums per zone and the census layers and bytes reduce against the base', () => {
  const v = P.visitValues(countsFile(2, 775, 5267, 10, 100), framesFile(false));
  assert.equal(v.counts[0].hero.paintArea + v.counts[0].finish.paintArea + v.counts[0].rest.paintArea, 110);
  assert.equal(v.census[0].length, 3);
  const mk = (arm, area, layers) => ({ arm, values: P.visitValues(countsFile(2, 775, 5267, area, layers), framesFile(false)) });
  const a = P.OTHERS[0].id, b = P.OTHERS[1].id;
  const t = P.reduceSession([mk('base', 10, 100), mk('base', 10, 100), mk('base', 10, 100), mk(a, 5, 60), mk(b, 10, 100)]);
  const ra = t.arms.find((x) => x.id === a), rb = t.arms.find((x) => x.id === b);
  assert.equal(ra.cells.find((c) => c.zone === 'hero' && c.metric === 'paintArea').verdict, 'beats');
  assert.equal(rb.cells.find((c) => c.zone === 'hero' && c.metric === 'paintArea').verdict, 'same');
  assert.equal(ra.census[0].layers.verdict, 'beats');
  assert.equal(ra.census[0].bytes.verdict, 'beats');
  assert.equal(rb.census[2].layers.verdict, 'same');
  assert.equal(t.base.census.length, 3);
  assert.equal(t.base.census[2].y, 'max');
  assert.equal(t.arms.find((x) => x.id === P.OTHERS[2].id).census[0].layers.verdict, 'unresolved');
});
