import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { C, MF, RS_ARMS, emptyPm, jobOf, jobOfGolden, kindOf, overall, recalcTally, res, rpf100, sources, suspects, why, withRecalc, withoutRecalc } from '../src/recalc-source.mjs';
import { accelHarnessSource } from '../src/accel-page.mjs';
import { MODES, headerOf, isRecalc, THREADED_OFF } from '../src/accel-cli.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/device/recalc-source.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const jobs = lines.filter((l) => l.kind === 'job');
const byName = new Map(jobs.map((l) => [l.name, l]));

test('constants equal the Lean consts line', () => {
  const k = lines.find((l) => l.kind === 'consts');
  for (const key of Object.keys(C)) assert.equal(C[key], k[key], key);
});

test('job lines: rates, suspects, sources and the reason replay the Lean golden', () => {
  assert.ok(jobs.length >= 25);
  for (const l of jobs) {
    const j = jobOfGolden(l.job);
    assert.equal(rpf100(j.floor), l.floorRpf, `${l.name} floorRpf`);
    assert.equal(rpf100(j.base), l.baseRpf, `${l.name} baseRpf`);
    assert.equal(withRecalc(j).length, l.withRecalc, `${l.name} withRecalc`);
    assert.equal(withoutRecalc(j).length, l.withoutRecalc, `${l.name} withoutRecalc`);
    assert.deepEqual(suspects(l.mf, j), l.suspects, `${l.name} suspects`);
    assert.deepEqual(sources(l.mf, j), l.sources, `${l.name} sources`);
    const r = res(l.mf, j);
    assert.equal(r.why, l.why, `${l.name} why`);
    assert.equal(r.src, l.src, `${l.name} src`);
    assert.equal(emptyPm(j.base), l.emptyPm, `${l.name} emptyPm`);
  }
});

test('every reason of the Lean decision occurs in the golden', () => {
  const seen = new Set(jobs.map((l) => l.why));
  for (const w of ['no-frames', 'no-residual', 'observer-shift', 'engine-internal', 'named', 'several', 'no-contrast']) assert.ok(seen.has(w), w);
});

test('overall lines: verdict and next step replay the Lean golden', () => {
  const ov = lines.filter((l) => l.kind === 'overall');
  assert.ok(ov.length >= 10);
  for (const l of ov) {
    const v = overall(l.jobs.map((n) => { const g = byName.get(n); return res(g.mf, jobOfGolden(g.job)); }));
    assert.equal(v.name, l.verdict, l.name);
    assert.equal(v.next, l.next, l.name);
  }
});

test('kindOf is the prefix before the first colon', () => {
  assert.equal(kindOf('raf:a>b:1:2'), 'raf');
  assert.equal(kindOf('mut:platform#style'), 'mut');
});

const frame = (r, k = [], z = []) => ({ r, k, z });
const row = (arm, frames) => ({ arm, engaged: true, rs: { frames } });
const rep = (n, f) => Array.from({ length: n }, () => f);

test('jobOf pools the rows of an arm and builds the idle and flip jobs; the tally prints the verdict inputs', () => {
  const report = { rows: [
    row('rs-idle-floor', rep(50, frame(1))), row('rs-idle-floor', rep(50, frame(1))),
    row('rs-idle-obs', rep(50, frame(1, ['raf:x']))), row('rs-idle-obs', rep(50, frame(1, ['raf:x']))),
    row('rs-idle-blockraf', rep(50, frame(0))), row('rs-idle-blocktimer', rep(50, frame(1))),
    row('rs-flip-floor', rep(24, frame(2))), row('rs-flip-obs', rep(24, frame(2, ['raf:x']))),
    { arm: 'rs-idle-obs', engaged: false, rs: { frames: rep(9, frame(5)) } },
  ] };
  const j = jobOf(report, 'idle');
  assert.equal(j.floor.length, 100);
  assert.equal(j.base.length, 100);
  assert.equal(why(MF.idle, j), 'named');
  assert.equal(why(MF.flip, jobOf(report, 'flip')), 'no-contrast');
  assert.ok(recalcTally(report).some((l) => l.startsWith('idle: suspects ["raf:x"] sources ["raf:x"] why named')));
});

test('armFrames reads interned keys', () => {
  const rows = [{ arm: 'rs-idle-obs', engaged: true, rs: { kt: ['mut:a#b', 'raf:x'], frames: [{ r: 1, k: [0, 1], z: [3] }] } }];
  assert.deepEqual(jobOf({ rows }, 'idle').base, [{ recalcs: 1, keys: ['mut:a#b', 'raf:x'], sizes: [3] }]);
});

test('the arm list holds the floor, observed, flushed and intervention arms; the mode runs with the pref off', () => {
  for (const a of ['rs-idle-floor', 'rs-idle-obs', 'rs-idle-obsf', 'rs-flip-floor', 'rs-flip-obs', 'rs-flip-obsf', 'rs-idle-blockraf', 'rs-idle-blocktimer', 'rs-warm']) assert.ok(RS_ARMS.includes(a), a);
  assert.equal(RS_ARMS.slice(-4).every((a) => a.startsWith('rs-idle-block')), true);
  assert.equal(MODES['recalc-thr-off'], 'morph.geom:on,morph.tween:geom-timed');
  assert.equal(isRecalc('recalc-thr-off'), true);
  assert.ok(headerOf('recalc-thr-off', 'H').endsWith(THREADED_OFF));
  const src = accelHarnessSource({ mode: 'timed', arms: RS_ARMS });
  assert.ok(src.includes('rs-idle-blockraf'));
});
