import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { EW } from '../src/end-wktr.mjs';
import { ARM_OF, FLOOR_ARMS, FLOOR_OPTS, KEYS, QSETS, W, WRITERS, band, cellNums, cut, decideJobF, dominant, finding, framesOf, jobLinesF, judge, overallF, overallFloor, overallW } from '../src/end-floor.mjs';
import { decideDirsF } from '../src/end-floor-cli.mjs';
import { accelHarnessSource } from '../src/accel-page.mjs';
import { probeSource } from '../src/mid-page.mjs';
import { MODES, THREADED_OFF, headerOf, isFloor } from '../src/accel-cli.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/device/end-floor.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (k) => lines.filter((l) => l.kind === k);
const fr = (a) => a.map(([r, keys]) => ({ r, keys }));
const cellOf = (c) => ({ pall: c.pall.map(fr), all: fr(c.all), var: fr(c.var), muted: c.muted });

test('constants equal the Lean consts line', () => {
  const k = of('consts')[0];
  for (const key of ['minFlip', 'bandDen', 'minValid']) assert.equal(EW[key], k[key], key);
});

test('writer lines equal the key sets and the arm names', () => {
  assert.equal(of('writer').length, WRITERS.length + 1);
  for (const l of of('writer')) {
    assert.deepEqual(QSETS[l.writer], l.keys, l.writer);
    const w = Object.keys(ARM_OF).find((x) => ARM_OF[x] === l.writer);
    assert.deepEqual(KEYS[w], l.keys, l.writer);
  }
});

test('judge lines replay the Lean golden (edges of every branch)', () => {
  assert.ok(of('judge').length >= 10);
  for (const l of of('judge')) {
    assert.equal(band(l.nums), l.band, `${l.name} band`);
    assert.equal(cut(l.nums), l.cut, `${l.name} cut`);
    assert.equal(judge(l.nums), l.verdict, l.name);
  }
  assert.deepEqual(new Set(of('judge').map((l) => l.verdict)), new Set(Object.values(W)));
});

test('cell lines replay the Lean golden (nums from the frames, verdict)', () => {
  assert.ok(of('cell').length >= 6);
  for (const l of of('cell')) {
    const x = cellNums(cellOf(l.cell));
    for (const k of Object.keys(l.nums)) assert.equal(x[k], l.nums[k], `${l.name} ${k}`);
    assert.equal(band(x), l.band, `${l.name} band`);
    assert.equal(cut(x), l.cut, `${l.name} cut`);
    assert.equal(judge(x), l.verdict, l.name);
  }
});

test('finding lines replay the Lean golden', () => {
  assert.ok(of('finding').length >= 6);
  for (const l of of('finding')) {
    const es = l.entries.map(([arm, v, p, c]) => ({ w: Object.keys(ARM_OF).find((x) => ARM_OF[x] === arm), v, p, cut: c }));
    assert.equal(finding(l.all, es), l.finding, l.name);
  }
  assert.ok(of('finding').some((l) => l.finding.startsWith('dominant')));
});

test('a writer that carries more than half of the floor is dominant, one at half is not', () => {
  assert.equal(dominant({ v: W.carries, p: 80, cut: 41 }), true);
  assert.equal(dominant({ v: W.carries, p: 80, cut: 40 }), false);
  assert.equal(dominant({ v: W.raises, p: 80, cut: 80 }), false);
});

test('overall lines replay the Lean golden', () => {
  for (const l of of('overallW')) assert.equal(overallW(l.verdicts), l.overall, l.name);
  for (const l of of('overall')) assert.equal(overallF(l.findings), l.overall, l.name);
});

const row = (arm, frames, kt = ['nav#style', 'nav#data-fw-morph']) => ({ arm, rs: { frames: frames.map(([r, k]) => ({ r, k })), kt } });
const rep = (rows) => ({ rows });

test('framesOf resolves key-table indices and plain keys', () => {
  const fs = framesOf(row('rs-flip-pall', [[1, [0, 1]], [0, []], [1, ['x#y']]]));
  assert.deepEqual(fs, [{ r: 1, keys: ['nav#style', 'nav#data-fw-morph'] }, { r: 0, keys: [] }, { r: 1, keys: ['x#y'] }]);
});

test('decideJobF: publish carries the floor, every other writer is idle', () => {
  const n = 100;
  const on = (keys) => Array.from({ length: n }, () => [1, keys]);
  const off = () => Array.from({ length: n }, () => [0, []]);
  const rows = [row('rs-flip-nat', on([0, 1])), row('rs-flip-pall', on([0, 1])), row('rs-flip-pall', on([0, 1])), row('rs-flip-qwrite', off())];
  for (const w of WRITERS) rows.push(row(`rs-flip-${ARM_OF[w]}`, w === 'pub' ? off() : on([0, 1])));
  const d = decideJobF(rep(rows));
  assert.equal(d.cells.pub.verdict, W.carries);
  assert.equal(d.cells.write.verdict, W.carries);
  assert.equal(d.cells.cls.verdict, W.noEffect);
  assert.equal(d.finding, 'dominant qpub');
  const { lines: ls } = jobLinesF('j1', rep(rows));
  assert.ok(ls.some((l) => l.includes('qpub') && l.includes('verdict carries')));
  assert.ok(ls.at(-1).startsWith('end-floor j1 finding:'));
});

test('decideJobF reads a missing arm as unread', () => {
  const d = decideJobF(rep([]));
  assert.equal(d.cells.write.verdict, W.unread);
  assert.equal(d.finding, 'unread');
  assert.equal(overallFloor([d, d, d]).finding, 'inconclusive');
});

test('decideDirsF reports a missing result file and decides the others', () => {
  const dir = mkdtempSync(join(tmpdir(), 'ef-'));
  const r = decideDirsF([dir]);
  assert.ok(r.lines.some((l) => l.includes('result file missing')));
  const f = join(dir, 'accel-floor-v2p-thr-off-1.json');
  writeFileSync(f, JSON.stringify(rep([])));
  const r2 = decideDirsF([dir]);
  assert.ok(r2.lines.some((l) => l.includes('overall v2p finding')));
  assert.equal(r2.lines.some((l) => l.includes('result file missing')), false);
});

test('the floor arms are one process: natural, floor, every writer set, reference, floor again', () => {
  assert.deepEqual(FLOOR_ARMS, ['rs-flip-nat', 'rs-flip-pall', ...WRITERS.map((w) => `rs-flip-${ARM_OF[w]}`), 'rs-flip-qwrite', 'rs-flip-pall']);
  assert.equal(FLOOR_OPTS.rsReps, 12);
  assert.equal(FLOOR_OPTS.rsWin, 48);
  assert.equal(FLOOR_OPTS.tk, true);
});

test('floor modes exist, are threaded off, and carry the arms and the key sets to the page', () => {
  for (const m of ['floor-v2p-thr-off']) {
    assert.ok(MODES[m], m);
    assert.equal(isFloor(m), true);
    assert.ok(headerOf(m, 'x').includes(THREADED_OFF), m);
  }
  assert.equal(isFloor('end-v2p-thr-off'), false);
  assert.equal(isFloor('floor-fp-thr-off'), false);
  assert.equal(MODES['floor-fp-thr-off'], undefined);
  const src = accelHarnessSource({ mode: 'timed', arms: FLOOR_ARMS, ...FLOOR_OPTS, qsets: QSETS });
  assert.ok(src.includes('rs-flip-qwrite'));
  assert.ok(src.includes('"qstyle"') && src.includes('nav#data-fw-morph'));
});

test('the probe silences a set only in its own arm and fails loudly for an unknown one', () => {
  const src = probeSource({ mode: 'timed', qsets: QSETS });
  assert.match(src, /\|pall\|pallf\|q\[a-z\]\+/);
  assert.match(src, /unknown writer set/);
  assert.match(src, /muteOn\(QSETS\[vv\]\)/);
  assert.match(src, /muteOff\(\)/);
});
