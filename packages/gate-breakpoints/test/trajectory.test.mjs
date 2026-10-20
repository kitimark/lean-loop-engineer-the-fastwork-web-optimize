// The trajectory reducer against the vectors Lean generates (lean/Fw/Gate/Trajectory.lean, scripts/TrajectoryGolden.lean), and the
// loop around it (reduceWidth) on small synthetic readings whose answers are worked out by hand.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { armCheck, byM, byStep, bucket, judgeAgainst, pickWidths, quantile, readsDominate, reduceRaw, reduceWidth, rel, runCheck, verdictLines, window as windowOf } from '../src/trajectory/reduce.mjs';
import { HERO_NODES, MORPH_NODES, PAGE_PROPS, HERO_STEPS, WIDTHS, MOTION_PROPS } from '../src/trajectory/registry.mjs';

const golden = readFileSync(fileURLToPath(new URL('../../contracts/golden/gate/trajectory.jsonl', import.meta.url)), 'utf8')
  .split('\n').filter(Boolean).map((l) => JSON.parse(l));

test('the golden file holds every operation', () => {
  assert.deepEqual([...new Set(golden.map((g) => g.op))].sort(), ['against', 'window', 'bucket', 'byM', 'byStep', 'widths', 'rel', 'arm', 'run', 'quantile', 'dominate'].sort());
  assert.ok(golden.length >= 100);
});

for (const g of golden) {
  test(`golden ${g.op}: ${g.name}`, () => {
    if (g.op === 'against') assert.equal(judgeAgainst(g.kind, g.win, g.r), g.verdict);
    else if (g.op === 'window') assert.deepEqual(windowOf(g.ms, g.m), g.idx);
    else if (g.op === 'bucket') assert.equal(bucket(g.m), g.bucket);
    else if (g.op === 'byM') assert.deepEqual(byM(g.phase, g.kind, g.orig, g.rew).map((x) => x[1]), g.verdicts);
    else if (g.op === 'rel') assert.equal(rel(g.cand, g.base), g.rel);
    else if (g.op === 'arm') assert.equal(armCheck(g.arm), g.verdict);
    else if (g.op === 'run') assert.equal(runCheck(g.arms), g.verdict);
    else if (g.op === 'quantile') assert.equal(quantile(g.xs, g.p), g.q);
    else if (g.op === 'dominate') assert.equal(readsDominate(g.read, g.gap), g.dominates);
    else if (g.op === 'byStep') {
      const side = (xs) => xs.map((x) => [x.step, x.s]);
      assert.deepEqual(byStep(g.kind, side(g.orig), side(g.rew)).map(([step, verdict]) => ({ step, verdict })), g.verdicts);
    } else if (g.op === 'widths') {
      const got = pickWidths(g.input);
      assert.deepEqual(got === null ? { ok: false } : { ok: true, widths: got }, g.pick);
    } else assert.fail(`unknown op ${g.op}`);
  });
}

// ---- the loop around the reducer ------------------------------------------------------------------------------------------

const registries = { hero: HERO_NODES, morph: MORPH_NODES, page: PAGE_PROPS };
const propIdx = (nodes, id, prop) => nodes.find((n) => n.id === id).props.findIndex((p) => p.id === prop);

/** A row whose every node has one element and every property the value `fill(kind)`, except `over`. */
function row(nodes, extra, fill, over = {}) {
  const out = {};
  for (const n of nodes) {
    out[n.id] = [n.props.map((p) => {
      const key = `${n.id}.${p.id}`;
      return key in over ? over[key] : fill(p);
    })];
  }
  return { nodes: out, page: [[[5947000]]], y: 0, m: null, since: null, ...extra };
}
const fill = (p) => (p.kind === 'discrete' ? 'off' : p.kind === 'colour' ? [43000, 49000, 59000, 255000] : [0]);

const OK_REWRITE = { config: 'h1', mode: 'hydrate' };
const NO_FW = { config: null, mode: null };

/** One raw run of the hero path; the morph path is empty. */
function heroRun(role, copy, arm) {
  const rows = HERO_STEPS.map((s) => row(HERO_NODES, { step: s.id, frame: 'rest', tag: `${s.id}/rest`, settled: true }, fill, { 'hero.copy.opacity': copy(s.id) }));
  return { width: 390, site: role === 'orig' ? 'orig' : 'rewrite', role, want: role === 'orig' ? null : 'h1', hero: { ready: { ready: true }, arm, rows }, morph: undefined };
}

function raw({ origCopy, baseCopy, candCopy, candArm = OK_REWRITE }) {
  return { engine: 'x', runs: [heroRun('orig', origCopy, NO_FW), heroRun('base', baseCopy ?? origCopy, OK_REWRITE), heroRun('cand', candCopy, candArm)] };
}

test('reduceRaw: equal arms are clean, nothing is new', () => {
  const red = reduceRaw(raw({ origCopy: () => [750], candCopy: () => [750] }), registries);
  assert.equal(red.refused, false);
  assert.equal(red.red, false);
  assert.equal(red.totals.fail, 0);
  assert.ok(red.totals.pass > 0);
});

test('reduceRaw: one stale step is the only new unit (bug A shape)', () => {
  const red = reduceRaw(raw({ origCopy: (s) => (s === 's25' ? [750] : [1000]), candCopy: () => [1000] }), registries);
  const failed = red.units.filter((u) => u.verdict.startsWith('fail:'));
  assert.deepEqual(failed.map((u) => `${u.node}.${u.prop}@${u.step}`), ['hero.copy.opacity@s25']);
  assert.equal(red.red, true);
  assert.match(verdictLines('chromium', '', red).join('\n'), /VERDICT trajectory chromium w=390 hero hero.copy.opacity NEW 1\/10 units: s25=apart/);
});

test('reduceRaw: a failure the faithful arm has too is baseline red, not new', () => {
  const o = (s) => (s === 's25' ? [750] : [1000]);
  const red = reduceRaw(raw({ origCopy: o, baseCopy: () => [1000], candCopy: () => [1000] }), registries);
  assert.equal(red.rels.both, 1);
  assert.equal(red.rels.new, 0);
  assert.equal(red.red, false);
  assert.equal(red.fails, true);
});

test('reduceRaw: a candidate that fixes what the faithful arm fails is cleared', () => {
  const o = (s) => (s === 's25' ? [750] : [1000]);
  const red = reduceRaw(raw({ origCopy: o, baseCopy: () => [1000], candCopy: o }), registries);
  assert.equal(red.rels.cleared, 1);
  assert.equal(red.red, false);
});

test('reduceRaw: a missing faithful arm makes every failure new', () => {
  const r = raw({ origCopy: (s) => (s === 's25' ? [750] : [1000]), candCopy: () => [1000] });
  r.runs = r.runs.filter((x) => x.role !== 'base');
  const red = reduceRaw(r, registries);
  assert.equal(red.rels.new, 1);
  assert.ok(red.notes.some((n) => /no faithful arm/.test(n)));
});

test('reduceRaw: a rewrite that client-rendered the default config is refused, not judged (inc-variant-gate-flags-off)', () => {
  const red = reduceRaw(raw({ origCopy: () => [750], candCopy: () => [750], candArm: { config: 'h0', mode: 'client-render' } }), registries);
  assert.equal(red.refused, true);
  assert.equal(red.units.length, 0);
  assert.equal(red.red, false);
  assert.match(verdictLines('webkit', '?fw=x', red).join('\n'), /REFUSED config: cand w=390 hero: config h0 mode client-render want h1/);
});

test('reduceRaw: no arm is refused', () => {
  assert.equal(reduceRaw({ engine: 'x', runs: [] }, registries).refused, true);
});

test('reduceRaw: the original page with a window.__fw is refused', () => {
  const r = raw({ origCopy: () => [750], candCopy: () => [750] });
  r.runs[0].hero.arm = OK_REWRITE;
  assert.equal(reduceRaw(r, registries).refused, true);
});

/** A morph phase of the nav class `is-expanded`: one sample per morph value, with `cls(m)` as the class. */
function phaseRows(ms, cls, extra = {}) {
  const ci = propIdx(MORPH_NODES, 'nav', 'cls.is-expanded');
  return ms.map((m, i) => {
    const r = row(MORPH_NODES, { m, since: 1000, t0: i * 20, t1: i * 20 + 4, ...extra }, fill);
    r.nodes.nav[0][ci] = cls(m);
    return r;
  });
}
const morphOf = (open, arm, reads) => ({ watched: true, ready: { ready: true }, arm, approach: [], phases: { open }, phaseReads: reads ?? { open: 'full' } });
const runOf = (role, morph) => ({ width: 390, site: role === 'orig' ? 'orig' : 'rewrite', role, want: role === 'orig' ? null : 'h1', morph });
const EVERY = [0, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000, 10000];

test('reduceWidth: a morph class that stays off fails at the buckets where the original has it on (bug B shape)', () => {
  const fine = [...EVERY.slice(0, 10), 9300, 9600, 9900, 10000];
  const orig = { morph: morphOf(phaseRows(fine, (m) => (m >= 9300 ? 'on' : 'off')), NO_FW) };
  const rewrite = { morph: morphOf(phaseRows(fine, () => 'off'), OK_REWRITE) };
  const units = reduceWidth({ width: 390, orig, rewrite, registries }).filter((u) => u.node === 'nav' && u.prop === 'cls.is-expanded' && u.phase === 'open');
  assert.deepEqual(units.filter((u) => u.verdict.startsWith('fail:')).map((u) => u.step), ['open@10']);
  assert.equal(units.find((u) => u.step === 'open@5').verdict, 'pass');
});

test('reduceWidth: an empty bucket 1..9 in a push is fail:coverage, in a hold a skip, outside 1..9 a skip', () => {
  const sparse = [0, 1000, 2000, 8000, 9000, 10000];
  const orig = { morph: morphOf(phaseRows(EVERY, () => 'off'), NO_FW) };
  const rewrite = { morph: morphOf(phaseRows(sparse, () => 'off'), OK_REWRITE) };
  const u = reduceWidth({ width: 390, orig, rewrite, registries }).filter((x) => x.node === 'nav' && x.prop === 'cls.is-expanded' && x.phase === 'open');
  const by = Object.fromEntries(u.map((x) => [x.step, x.verdict]));
  assert.deepEqual([by['open@3'], by['open@4'], by['open@5'], by['open@6'], by['open@7']], Array(5).fill('fail:coverage'));
  assert.equal(by['open@1'], 'pass');
  assert.equal(by['open@11'], 'skip:noSample');
});

test('reduceWidth: a push sample without a morph value is fail:coverage', () => {
  const orig = { morph: morphOf(phaseRows(EVERY, () => 'off'), NO_FW) };
  const rows = phaseRows(EVERY, () => 'off');
  rows[4].m = null;
  const rewrite = { morph: morphOf(rows, OK_REWRITE) };
  const u = reduceWidth({ width: 390, orig, rewrite, registries }).find((x) => x.node === 'nav' && x.prop === 'cls.is-expanded' && x.step === 'open@11');
  assert.equal(u.verdict, 'fail:coverage');
});

test('reduceWidth: a rewrite sample beyond the original range is fail:coverage', () => {
  const orig = { morph: morphOf(phaseRows([0, 500, 1000, 1500], () => 'off'), NO_FW) };
  const rewrite = { morph: morphOf(phaseRows(EVERY, () => 'off'), OK_REWRITE) };
  const u = reduceWidth({ width: 390, orig, rewrite, registries }).find((x) => x.node === 'nav' && x.prop === 'cls.is-expanded' && x.step === 'open@10');
  assert.equal(u.verdict, 'fail:coverage');
});

test('reduceWidth: with the lean read set only the lean properties are units in a push', () => {
  const orig = { morph: morphOf(phaseRows(EVERY, () => 'off'), NO_FW, { open: 'lean' }) };
  const rewrite = { morph: morphOf(phaseRows(EVERY, () => 'off'), OK_REWRITE, { open: 'lean' }) };
  const props = new Set(reduceWidth({ width: 390, orig, rewrite, registries }).filter((u) => u.phase === 'open').map((u) => `${u.node}.${u.prop}`));
  assert.ok(props.has('nav.cls.is-on-dark') && props.has('logo.rect-in-nav'));
  assert.ok(!props.has('nav.background-color') && !props.has('logo.color') && !props.has('nav.rect'));
});

test('reduceRaw: the timing rows split the read cost from the gap between samples', () => {
  const morph = (arm, ms) => morphOf(phaseRows(ms, () => 'off'), arm);
  const r = { engine: 'x', runs: ['orig', 'base', 'cand'].map((role) => runOf(role, morph(role === 'orig' ? NO_FW : OK_REWRITE, EVERY))) };
  const red = reduceRaw(r, registries);
  const t = red.timing.find((x) => x.role === 'cand' && x.phase === 'open');
  assert.deepEqual([t.n, t.readP50, t.gapP50, t.dominate], [11, 4, 20, false]);
});

test('reps: the rows of two passes are pooled, an empty bucket one pass left is filled by the other', () => {
  const half = (ms) => phaseRows(ms, () => 'off');
  const pooled = (a, b) => [...half(a).map((r) => ({ ...r, rep: 0 })), ...half(b).map((r) => ({ ...r, rep: 1 }))];
  const evens = [0, 2000, 4000, 6000, 8000, 10000], odds = [1000, 3000, 5000, 7000, 9000];
  const r = { engine: 'x', runs: ['orig', 'base', 'cand'].map((role) => runOf(role, morphOf(pooled(evens, odds), role === 'orig' ? NO_FW : OK_REWRITE))) };
  const red = reduceRaw(r, registries);
  const gaps = (x) => x.units.filter((u) => u.phase === 'open' && u.verdict === 'fail:coverage').length;
  assert.equal(gaps(red), 0);
  assert.equal(gaps(reduceRaw({ ...r, runs: r.runs.map((x) => ({ ...x, morph: { ...x.morph, phases: { open: half(evens).map((q) => ({ ...q, rep: 0 })) } } })) }, registries)) > 0, true);
  // the gap is taken inside a pass: the step from the last row of pass 0 to the first of pass 1 is not a frame gap
  const t = red.timing.find((x) => x.role === 'cand' && x.phase === 'open');
  assert.equal(t.n, 11);
  assert.equal(t.gapP90, 20);
});

test('reps: every pass keeps its arm identity, a pass that client-rendered refuses the run', () => {
  const m = morphOf(phaseRows(EVERY, () => 'off'), OK_REWRITE);
  const bad = { ...m, extraArms: [{ config: 'h0', mode: 'client-render' }] };
  const r = { engine: 'x', runs: [runOf('orig', morphOf(phaseRows(EVERY, () => 'off'), NO_FW)), runOf('base', m), runOf('cand', bad)] };
  const red = reduceRaw(r, registries);
  assert.equal(red.refused, true);
  assert.match(red.detail, /cand w=390 morph: config h0 mode client-render/);
});

test('registry: the lane widths and the motion properties are the ones the Lean tolerance table covers', () => {
  assert.deepEqual(WIDTHS, [390, 640, 641, 1280]);
  assert.ok(MOTION_PROPS.every((p) => ['discrete', 'geometry', 'unit', 'colour'].includes(p.kind)));
});
