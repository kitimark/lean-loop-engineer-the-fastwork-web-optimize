import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { GH_C, cellNums, numsBand } from '../src/glint-hold.mjs';
import { VC, decideJobC, judgeC, judgeLiveC, overallC } from '../src/glint-compositor.mjs';
import { decideDirsC } from '../src/glint-compositor-cli.mjs';
import { accelHarnessSource } from '../src/accel-page.mjs';
import { GLINT_HOLD_ARMS, GLINT_OPTS, MODES, headerOf, isGlint, THREADED_OFF } from '../src/accel-cli.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/device/glint-compositor.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (k) => lines.filter((l) => l.kind === k);

test('constants equal the Lean consts line', () => {
  const k = of('consts')[0];
  for (const key of Object.keys(GH_C)) assert.equal(GH_C[key], k[key], key);
});

test('judge lines replay the Lean golden (edges of every branch)', () => {
  assert.ok(of('judge').length >= 10);
  for (const l of of('judge')) {
    assert.equal(numsBand({ ...l.nums, bq: 0, q: 0 }), l.band, `${l.name} band`);
    assert.equal(judgeC(l.minF, l.nums), l.verdict, l.name);
  }
});

test('cell lines replay the Lean golden (nums from the frames, verdict)', () => {
  assert.ok(of('cell').length >= 6);
  for (const l of of('cell')) {
    const x = cellNums(l.cell);
    for (const k of Object.keys(l.nums)) assert.equal(x[k], l.nums[k], `${l.name} ${k}`);
    assert.equal(judgeC(l.minF, x), l.verdict, l.name);
  }
  assert.deepEqual(new Set(of('cell').map((l) => l.verdict)), new Set([VC.atFloor, VC.partly, VC.noCut, VC.unread, VC.noContrast]));
  assert.deepEqual(new Set(of('judge').map((l) => l.verdict)), new Set(Object.values(VC).filter((v) => v !== VC.notRunning)));
});

test('live lines replay the Lean golden (a paused variant animation is not a reading)', () => {
  assert.ok(of('live').length >= 5);
  for (const l of of('live')) assert.equal(judgeLiveC(l.minF, l.live, l.nums), l.verdict, l.name);
  assert.ok(of('live').some((l) => l.verdict === VC.notRunning) && of('live').some((l) => l.verdict !== VC.notRunning));
});

test('overall lines replay the Lean golden', () => {
  assert.ok(of('overall').length >= 7);
  for (const l of of('overall')) assert.equal(overallC(l.verdicts), l.overall, l.name);
});

const asRow = (arm, a, glintLive) => ({ arm, rs: { frames: a.flat().map(([r]) => ({ r, g: null })), wins: a.map((w) => w.length), glintLive } });
test('glue: rows by arm name to the cell the golden judges', () => {
  const c = of('cell').find((l) => l.name === 'at floor');
  const base = { rows: [asRow('rs-idle', c.cell.baseOn[0]), asRow('rs-idle-smil', c.cell.baseOff), asRow('rs-idle', c.cell.baseOn[1])] };
  const comp = { rows: [asRow('rs-idle', c.cell.holdOn, 2)] };
  const d = decideJobC(base, comp);
  assert.equal(d.idle.verdict, c.verdict);
  assert.equal(decideJobC(base, { rows: [asRow('rs-idle', c.cell.holdOn, 0)] }).idle.verdict, VC.notRunning);
  assert.equal(decideJobC(base, { rows: [asRow('rs-idle', c.cell.holdOn)] }).idle.verdict, VC.notRunning);
  assert.equal(d.flip.verdict, VC.notRunning);
});

test('compositor mode: the base page plus platform.glint:compositor, pref OFF header, the hold arms', () => {
  assert.ok(MODES['glint-comp-thr-off'].startsWith(MODES['glint-base-thr-off']) && MODES['glint-comp-thr-off'].endsWith('platform.glint:compositor'));
  assert.ok(isGlint('glint-comp-thr-off'));
  assert.ok(headerOf('glint-comp-thr-off', 'H').endsWith(THREADED_OFF));
  assert.deepEqual(GLINT_HOLD_ARMS, ['rs-idle', 'rs-flip']);
  assert.equal(GLINT_OPTS.gk, true);
  assert.match(accelHarnessSource({ mode: 'timed', arms: GLINT_HOLD_ARMS, ...GLINT_OPTS }), /"gk":true/);
});

test('decideDirsC reports missing result files instead of a verdict', () => {
  const r = decideDirsC(['/nonexistent-glint-dir']);
  assert.match(r.lines[0], /result files missing/);
  assert.equal(r.overall.idle, 'inconclusive');
});
