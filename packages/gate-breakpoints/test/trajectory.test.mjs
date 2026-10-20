// The trajectory reducer against the vectors Lean generates (lean/Fw/Gate/Trajectory.lean, scripts/TrajectoryGolden.lean), and the
// loop around it (reduceWidth) on small synthetic readings whose answers are worked out by hand.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { byM, byStep, bucket, judgeAgainst, pickWidths, reduceRaw, reduceWidth, verdictLines, window as windowOf } from '../src/trajectory/reduce.mjs';
import { HERO_NODES, MORPH_NODES, PAGE_PROPS, HERO_STEPS, WIDTHS, MOTION_PROPS } from '../src/trajectory/registry.mjs';

const golden = readFileSync(fileURLToPath(new URL('../../contracts/golden/gate/trajectory.jsonl', import.meta.url)), 'utf8')
  .split('\n').filter(Boolean).map((l) => JSON.parse(l));

test('the golden file holds every operation', () => {
  assert.deepEqual([...new Set(golden.map((g) => g.op))].sort(), ['against', 'window', 'bucket', 'byM', 'byStep', 'widths'].sort());
  assert.ok(golden.length >= 50);
});

for (const g of golden) {
  test(`golden ${g.op}: ${g.name}`, () => {
    if (g.op === 'against') assert.equal(judgeAgainst(g.kind, g.win, g.r), g.verdict);
    else if (g.op === 'window') assert.deepEqual(windowOf(g.ms, g.m), g.idx);
    else if (g.op === 'bucket') assert.equal(bucket(g.m), g.bucket);
    else if (g.op === 'byM') assert.deepEqual(byM(g.kind, g.orig, g.rew).map((x) => x[1]), g.verdicts);
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

function raw({ origCopy, rewCopy }) {
  const heroRows = (copy) => HERO_STEPS.map((s) => row(HERO_NODES, { step: s.id, frame: 'rest', tag: `${s.id}/rest`, settled: true }, fill,
    { 'hero.copy.opacity': copy(s.id) }));
  const morph = () => ({ watched: true, approach: [], phases: {} });
  const run = (site, copy) => ({ width: 390, site, hero: { ready: { ready: true }, rows: heroRows(copy) }, morph: morph() });
  return { engine: 'x', runs: [run('orig', origCopy), run('rewrite', rewCopy)] };
}

test('reduceRaw: equal arms pass, nothing fails', () => {
  const red = reduceRaw(raw({ origCopy: () => [750], rewCopy: () => [750] }), registries);
  assert.equal(red.fails, false);
  assert.equal(red.totals.fail, 0);
  assert.ok(red.totals.pass > 0);
});

test('reduceRaw: one stale step fails only that unit (bug A shape)', () => {
  const red = reduceRaw(raw({ origCopy: (s) => (s === 's25' ? [750] : [1000]), rewCopy: () => [1000] }), registries);
  const failed = red.units.filter((u) => u.verdict.startsWith('fail:'));
  assert.deepEqual(failed.map((u) => `${u.node}.${u.prop}@${u.step}`), ['hero.copy.opacity@s25']);
  assert.equal(red.fails, true);
  assert.match(verdictLines('chromium', '', red).join('\n'), /VERDICT trajectory chromium w=390 hero hero.copy.opacity FAIL 1\/10 units: s25=apart/);
});

test('reduceWidth: a morph class that stays off fails at the buckets where the original has it on (bug B shape)', () => {
  const ci = propIdx(MORPH_NODES, 'nav', 'cls.is-expanded');
  const mk = (ms, cls) => ms.map((m, i) => {
    const r = row(MORPH_NODES, { m, since: 1000 }, fill);
    r.nodes.nav[0][ci] = cls(i);
    return r;
  });
  const ms = [0, 2000, 4000, 6000, 8000, 9000, 9300, 9600, 9900, 10000];
  const orig = { hero: { rows: [] }, morph: { approach: [], phases: { open: mk(ms, (i) => (ms[i] >= 9300 ? 'on' : 'off')) } } };
  const rewrite = { hero: { rows: [] }, morph: { approach: [], phases: { open: mk(ms, () => 'off') } } };
  const units = reduceWidth({ width: 390, orig, rewrite, registries }).filter((u) => u.node === 'nav' && u.prop === 'cls.is-expanded' && u.phase === 'open');
  const failing = units.filter((u) => u.verdict.startsWith('fail:')).map((u) => u.step);
  assert.deepEqual(failing, ['open@10']);
  assert.equal(units.find((u) => u.step === 'open@5').verdict, 'skip:noSample');
});

test('registry: the lane widths and the motion properties are the ones the Lean tolerance table covers', () => {
  assert.deepEqual(WIDTHS, [390, 640, 641, 1280]);
  assert.ok(MOTION_PROPS.every((p) => ['discrete', 'geometry', 'unit', 'colour'].includes(p.kind)));
});
