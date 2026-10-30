import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { ARMS, MIN_FRAMES, PAIRS, PROBE_BAND, V, cancelFrame, cancelSpan, cancelVerdict, creFacts, decideProbeJob, jobLinesP, overall, overallLinesP, rate, rowLineP, rowsByName, verdict } from '../src/end-floor-probe.mjs';
import { probeSource } from '../src/mid-page.mjs';
import { MIN_REPS } from '../src/end-floor-window.mjs';
import { decideDirsP } from '../src/end-floor-probe-cli.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/device/end-floor-probe.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (k) => lines.filter((l) => l.kind === k);

test('constants equal the Lean consts line', () => {
  const k = of('consts')[0];
  assert.equal(PROBE_BAND, k.probeBand);
  assert.equal(MIN_FRAMES, k.minFrames);
});

test('pair lines: rate and verdict', () => {
  assert.ok(of('pair').length >= 17);
  for (const l of of('pair')) {
    assert.equal(rate(l.on), l.onRate, l.name);
    assert.equal(rate(l.off), l.offRate, l.name);
    assert.equal(verdict(l.on, l.off), l.verdict, l.name);
  }
});

test('overall lines', () => {
  assert.ok(of('overall').length >= 5);
  for (const l of of('overall')) assert.equal(overall(l.verdicts), l.overall, l.name);
});

test('cancel lines: first sample where every made track is idle', () => {
  assert.ok(of('cancel').length >= 7);
  for (const l of of('cancel')) assert.equal(cancelFrame(l.seen.map(([made, idle]) => ({ made, idle }))), l.frame, l.name);
});

test('cv lines: verdict and span', () => {
  assert.ok(of('cv').length >= 7);
  for (const l of of('cv')) {
    assert.equal(cancelVerdict(l.cancels), l.verdict, l.name);
    assert.deepEqual(cancelSpan(l.cancels), l.span, l.name);
  }
});

const pbRow = (arm, reps, n, r, src = 'raf') => ({ arm, rs: { pb: Array.from({ length: reps }, () => ({ n, r, u: n, ms: n * 16, src })), frames: [] } });
const sample = (t, made, running, idle) => [t, made, running, 0, 0, idle, made - idle - running, 0, 0, 0, 0, 1];

test('rowsByName tells a repeated arm apart by occurrence', () => {
  const m = rowsByName({ rows: [pbRow('rs-flip-pbon', 6, 48, 48), pbRow('rs-flip-pboff', 6, 48, 0), pbRow('rs-flip-pbon', 6, 48, 40)] });
  assert.deepEqual([...m.keys()], ['pbon', 'pboff', 'pbon#2']);
});

test('a job report: floor caused by the probe, innocent, and unread pairs', () => {
  const rep = { rows: [
    pbRow('rs-flip-pbon', 12, 48, 48), pbRow('rs-flip-pboff', 12, 48, 0),
    pbRow('rs-flip-pbconly', 12, 48, 48), pbRow('rs-flip-pbpon', 3, 48, 48), pbRow('rs-flip-pbpoff', 12, 48, 0),
  ] };
  const d = decideProbeJob(rep);
  const by = Object.fromEntries(d.pairs.map((p) => [p.name, p.v]));
  assert.equal(by.primary, V.causes);
  assert.equal(by['group counter only'], V.innocent);
  assert.equal(by['paused page'], V.unread);
  assert.equal(by.repeat, V.unread);
  const { lines: ls } = jobLinesP('j1', rep);
  assert.equal(ls.length, PAIRS.length);
  assert.match(ls[0], /^end-floor-probe j1 primary: on pbon frames 576 recalcs 576 rate 100 per 100 rAF callbacks, off pboff frames 576 recalcs 0 rate 0 per 100 rAF callbacks, verdict probeCauses$/);
  const o = overallLinesP([d, d, d]);
  assert.match(o[0], /^end-floor-probe overall primary: probeCauses \(jobs probeCauses probeCauses probeCauses\)$/);
});

test('a rendering-update reading is named as such', () => {
  const rep = { rows: [pbRow('rs-flip-pbon', 12, 48, 48), pbRow('rs-flip-pbnoraf', 12, 48, 0, 'update')] };
  const ls = jobLinesP('j', rep).lines.find((l) => l.includes('no harness rAF'));
  assert.match(ls, /off pbnoraf frames 576 recalcs 0 rate 0 per 100 rendering updates/);
});

test('creation rows: cancel frame, verdict and span from the samples', () => {
  const rep = [sample(0, 4, 4, 0), sample(16, 4, 4, 0), sample(32, 4, 0, 4), sample(48, 4, 0, 4)];
  const row = { arm: 'rs-flip-pbcre', rs: { cre: Array.from({ length: MIN_REPS }, () => rep) } };
  const f = creFacts(row);
  assert.deepEqual(f.cancels, Array(MIN_REPS).fill(2));
  assert.equal(f.verdict, 'all cancelled');
  assert.deepEqual(f.span, [2, 2]);
  assert.match(rowLineP('wktr-j1', 'f.json', 3, row, 1), /^wktr-j1 f\.json rows\[3\] rs-flip-pbcre: reps 6, .*cancel sample 2 to 2 \(frames from creation\)/);
});

test('rowLineP of a probe row carries the window counts', () => {
  const l = rowLineP('wktr-j1', 'f.json', 1, pbRow('rs-flip-pbon', 12, 48, 48), 2);
  assert.match(l, /rs-flip-pbon#2: window frames 576 recalcs 576 rate 100 per 100 rAF callbacks, reps 12, window frames 48 to 48/);
});

test('decideDirsP reports a missing result file', () => {
  assert.match(decideDirsP(['/nonexistent-dir']).lines[0], /result file missing/);
});

test('the page source carries the probe-off windows and the creation sampler, and the arms are wired', () => {
  const src = probeSource({ mode: 'timed', rsWin: 48, tk: true });
  assert.match(src, /pbWindow/);
  assert.match(src, /creRun/);
  assert.match(src, /pbnoraf/);
  assert.equal(ARMS.filter((a) => a === 'rs-flip-pbon').length, 2);
  const cli = readFileSync(join(here, '../src/accel-cli.mjs'), 'utf8');
  assert.match(cli, /probe-v2p-thr-off/);
});
