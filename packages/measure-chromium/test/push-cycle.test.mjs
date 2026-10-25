// The push-cycle lane: profiles generated from the Lean plan, and the window sums of a counts file.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseProfile } from '../src/profile.mjs';
import { readGolden, planOf, profileOf, profileText, windowSums, perRun, armTable, armOf, reportMd, DWELLS, SUM_KEYS, MAX_KEYS } from '../src/push-cycle.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const golden = readGolden();

test('the committed profiles are the ones generated from the Lean plan', () => {
  for (const d of DWELLS) {
    const plan = planOf(golden, d);
    const file = readFileSync(join(here, `../profiles/push-cycle-d${d}.json`), 'utf8');
    assert.equal(file, profileText(plan), `push-cycle-d${d}.json is generated: node src/push-cycle.mjs profiles`);
    const r = parseProfile(JSON.parse(file));
    assert.equal(r.profile.id, `push-cycle-d${d}`);
    assert.equal(r.kind, 'counts');
    assert.equal(r.profile.input.strokes.length, 6);
    assert.equal(r.profile.input.maxFrames, plan.endFrame);
  }
});

// a synthetic counts file: replay frames carry a Layout count that is 3 in the first window and `later` in the others
function counts(plan, later, extra = 0) {
  const frames = [];
  for (let n = 0; n < 10; n++) frames.push({ n, phase: 'rest', counts: { 'trace.Layout': 99 } });
  for (let r = 0; r < plan.endFrame; r++) {
    const k = Math.floor(r / plan.cycleLen);
    const inOpen = r - k * plan.cycleLen < 24 + plan.dwellFrames;
    frames.push({ n: 10 + r, phase: 'replay', counts: { 'trace.Layout': inOpen && r % 10 === 0 ? (k === 0 ? 3 : later) + extra : 0, 'census.layers': 100 + k } });
  }
  for (let n = 0; n < 30; n++) frames.push({ n: 10 + plan.endFrame + n, phase: 'tail', counts: { 'trace.Layout': 99 } });
  return { frames };
}

test('window sums cut the replay frames at the plan windows and split open from close', () => {
  const plan = planOf(golden, 300);
  const w = windowSums(counts(plan, 5).frames, plan);
  assert.equal(w.length, 6);
  assert.equal(w[0].all.frames, plan.cycleLen);
  assert.equal(w[0].open.frames + w[0].close.frames, plan.cycleLen);
  assert.equal(w[0].open.frames, 24 + plan.dwellFrames);
  const ticks = Math.ceil((24 + plan.dwellFrames) / 10);
  assert.equal(w[0].open['trace.Layout'], 3 * ticks, 'first window');
  assert.equal(w[1].close['trace.Layout'], 0, 'the close half has none');
  assert.equal(w[3].all['census.layers'], 103, 'a level is a maximum, not a sum');
  assert.ok(SUM_KEYS.every((k) => k in w[0].all) && MAX_KEYS.every((k) => k in w[0].all));
});

test('a later cycle is `more` than the first only when its whole spread lies above', () => {
  const plan = planOf(golden, 300);
  const runs = (later) => [0, 1, 2].map((e) => ({ label: `r${e}`, counts: counts(plan, later, e) }));
  const row = (rs) => armTable(perRun(rs, plan), 'open').find((r) => r.key === 'trace.Layout');
  const more = row(runs(8));
  assert.equal(more.cycles[0].vs0, 'base');
  assert.equal(more.cycles[1].vs0, 'more');
  const same = row(runs(3));
  assert.equal(same.cycles[1].vs0, 'same');
  const less = row(runs(0));
  assert.equal(less.cycles[1].vs0, 'less');
  const two = armTable(perRun(runs(8).slice(0, 2), plan), 'open').find((r) => r.key === 'trace.Layout');
  assert.equal(two.cycles[1].vs0, 'n/a', 'fewer than three runs decide nothing');
});

test('artifact directory names and the markdown table', () => {
  assert.deepEqual(armOf('chromium-counts-f2-3'), { arm: 'f2', run: 3 });
  assert.deepEqual(armOf('chromium-counts-original-1'), { arm: 'original', run: 1 });
  assert.equal(armOf('offscreen-trace-f1-1'), null);
  const plan = planOf(golden, 1000);
  const arms = new Map([['rewrite', [0, 1, 2].map((e) => ({ label: `rewrite-${e}`, counts: counts(plan, 8, e) }))]]);
  const { md, json } = reportMd(arms, plan, 'open');
  assert.match(md, /dwell 1000 ms/);
  assert.match(md, /\| trace\.Layout \| /);
  assert.match(md, /\(more\)/);
  assert.ok(json.rewrite.length > 0);
  assert.equal(profileOf(plan).input.strokes.length, plan.n);
});
