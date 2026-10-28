import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { C, NEXT_NAME, SWEEP_ARMS, VERDICT_NAME, armSums, dropPm, jobOf, overall, rpf100, styleUsPerFrame, sweepTally, valid, why } from '../src/sweep-pause.mjs';
import { accelHarnessSource } from '../src/accel-page.mjs';
import { MODES, headerOf, isSweep, THREADED_OFF } from '../src/accel-cli.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/device/sweep-pause.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const byName = new Map(lines.filter((l) => l.kind === 'job').map((l) => [l.name, l.job]));

test('constants equal the Lean consts line', () => {
  const k = lines.find((l) => l.kind === 'consts');
  for (const key of Object.keys(C)) assert.equal(C[key], k[key], key);
});

test('job lines: rates, drops and the reason replay the Lean golden', () => {
  const jobs = lines.filter((l) => l.kind === 'job');
  assert.ok(jobs.length >= 12);
  for (const l of jobs) {
    const j = l.job;
    assert.equal(rpf100(j.flipU), l.flipU, `${l.name} flipU`);
    assert.equal(rpf100(j.flipP), l.flipP, `${l.name} flipP`);
    assert.equal(rpf100(j.idleU), l.idleU, `${l.name} idleU`);
    assert.equal(rpf100(j.idleP), l.idleP, `${l.name} idleP`);
    assert.equal(styleUsPerFrame(j.flipU), l.styleU, `${l.name} styleU`);
    assert.equal(styleUsPerFrame(j.flipP), l.styleP, `${l.name} styleP`);
    assert.equal(dropPm(rpf100(j.flipU), rpf100(j.flipP)), l.rpfDrop, `${l.name} rpfDrop`);
    assert.equal(dropPm(styleUsPerFrame(j.flipU), styleUsPerFrame(j.flipP)), l.styleDrop, `${l.name} styleDrop`);
    assert.equal(why(j), l.why, `${l.name} why`);
    assert.equal(valid(why(j)), l.valid, `${l.name} valid`);
  }
});

test('every reason of the Lean decision occurs in the golden', () => {
  const seen = new Set(lines.filter((l) => l.kind === 'job').map((l) => l.why));
  for (const w of ['no-frames', 'idle-not-on', 'idle-not-off', 'explains', 'not-sweep', 'partial']) assert.ok(seen.has(w), w);
});

test('overall lines: verdict and next step replay the Lean golden', () => {
  const ov = lines.filter((l) => l.kind === 'overall');
  assert.ok(ov.length >= 12);
  for (const l of ov) {
    const v = overall(l.jobs.map((n) => byName.get(n) ?? { flipU: { frames: 0, recalcs: 0, styleFrames: 0, styleUs: 0 }, flipP: { frames: 0 }, idleU: { frames: 0 }, idleP: { frames: 0 } }));
    assert.equal(VERDICT_NAME[v], l.verdict, l.name);
    assert.equal(NEXT_NAME[v], l.next, l.name);
  }
});

const row = (arm, frames, recalc, extra = {}) => ({ arm, engaged: true, sw: { kind: arm.includes('idle') ? 'idle' : 'flip' }, stages: [{ frames, ms: 1000, recalc, ...extra }] });

test('jobOf takes recalcs from the plain arms and style from the timed arms', () => {
  const report = {
    rows: [
      row('sw-flip', 4, 12), row('sw-flip', 4, 12), row('sw-flip-t', 5, 20, { styleUs: 5000, layoutUs: 10 }),
      row('sw-flip-p', 4, 1), row('sw-flip-p-t', 5, 5, { styleUs: 500, layoutUs: 0 }),
      row('sw-idle', 40, 80), row('sw-idle-p', 40, 0), row('sw-warm', 3, 99), { arm: 'sw-flip', engaged: false, sw: {}, stages: [] },
    ],
  };
  const j = jobOf(report);
  assert.deepEqual(j.flipU, { frames: 8, recalcs: 24, styleFrames: 5, styleUs: 5000, layoutUs: 10 });
  assert.deepEqual(j.flipP, { frames: 4, recalcs: 1, styleFrames: 5, styleUs: 500, layoutUs: 0 });
  assert.equal(why(j), 'explains');
  assert.equal(armSums(report)['sw-warm'].frames, 3);
  assert.ok(sweepTally(report).some((l) => l.includes('why explains')));
});

test('the arm list pairs every unpaused arm with a paused one and a timed twin', () => {
  assert.equal(SWEEP_ARMS[0], 'sw-warm');
  for (const k of ['flip', 'idle']) for (const suf of ['', '-t']) for (const p of ['', '-p']) assert.ok(SWEEP_ARMS.includes(`sw-${k}${p}${suf}`), `${k}${p}${suf}`);
  assert.equal(SWEEP_ARMS.filter((a) => a === 'sw-flip').length, SWEEP_ARMS.filter((a) => a === 'sw-flip-p').length);
});

test('the sweep mode runs the timed site with the threaded pref off, and the probe carries the identity filter', () => {
  assert.ok(isSweep('sweep-thr-off'));
  assert.equal(MODES['sweep-thr-off'], 'morph.geom:on,morph.tween:geom-timed');
  assert.equal(headerOf('sweep-thr-off', 'H'), `H ${THREADED_OFF}`);
  const src = accelHarnessSource({ mode: 'timed', arms: SWEEP_ARMS });
  assert.ok(src.includes('sweepDoc') && src.includes('CSSAnimation') && src.includes('data-fw=\\"platform\\"') || src.includes("data-fw=\"platform\""));
  assert.ok(src.includes('.pause()') && src.includes('.play()'));
});
