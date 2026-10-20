// closegap.mjs is a TS stand-in for Lean `Fw.Parts.HeroExitCloseStart`; these pins are the literals of its #guard lines.
import test from 'node:test';
import assert from 'node:assert/strict';
import { redCh, prevBound, floorOk, gapFor, closeCells, ownGapCheck, capCheck, gapStats, permutationP, closeStartOk, identityCheck, frameIntervals, blockDiffs, CUT } from '../src/trajectory/closegap.mjs';

const micro = (x) => Math.floor(x * 1e6 + 1e-6);
const redFloor = (g) => redCh(prevBound(g));

test('red channel equals the Lean guards', () => {
  assert.equal(micro(redCh(0)), 255000000);
  assert.equal(micro(redCh(1)), 19000000);
  assert.equal(micro(redCh(1 / 1000)), 252705593);
  assert.equal(micro(redCh(138 / 10000)), 226519948);
  assert.equal(micro(redCh(22 / 10000)), 250004640);
  assert.equal(micro(redFloor(113)), 217567243);
  assert.equal(micro(redFloor(202)), 161602802);
});

test('prevBound starts at the cut and the red falls with m', () => {
  assert.ok(Math.abs(prevBound(0) - CUT) < 1e-12);
  assert.ok(redCh(0.5) < redCh(0.1));
  assert.ok(redFloor(200) < redFloor(100));
});

// Lean `closeStartCases` (HeroExitCloseStart.lean): (reading, m, expected), the same literals as its #guard.
const closeStartCases = [
  [226.520, 138 / 10000, true], [226.520 + 0.49, 138 / 10000, true], [226.520 - 0.49, 138 / 10000, true],
  [226.520 + 0.51, 138 / 10000, false], [226.520 - 0.51, 138 / 10000, false],
  [255, 138 / 10000, false], [255, 0, true], [19, 1, true], [255, 1, false], [252, 1 / 1000, false], [252.705, 1 / 1000, true],
];

test('closeStartOk follows the Lean golden cases', () => {
  for (const [reading, m, want] of closeStartCases) assert.equal(closeStartOk(reading, m), want, `${reading} at m ${m}`);
});

test('closeStartOk accepts bgRed m itself and rejects the target reading while bgRed m < 254.5', () => {
  for (const m of [0.0001, 0.001, 0.0138, 0.1, 0.5, 1]) {
    assert.equal(closeStartOk(redCh(m), m), true);
    assert.equal(closeStartOk(redCh(0), m), redCh(m) >= 254.5);
  }
});

test('floorOk follows the Lean guards', () => {
  assert.equal(floorOk(67, 17, 235), true);
  assert.equal(floorOk(67, 17, 160), false);
});

test('gapFor inverts the floor', () => {
  for (const g of [10, 80, 200]) assert.ok(Math.abs(gapFor(redFloor(g)) - g) < 1e-6);
  assert.equal(gapFor(255), 0);
});

const row = (rep, t, on, red, m = 0) => ({ rep, t, since: t, m, nodes: { nav: [Object.assign([0, 0, on ? 'on' : 'off', 0, 0, 0, 0, 0, 0], { 9: [red * 1000, 0, 0, 1000] })], earn: [[[-1000], 'true', [250], 'blur(#px)', [10000], [30000]]] } });
const raw = {
  runs: [
    { width: 390, role: 'orig', search: '', want: null, morph: { phases: { close: [row(0, 0, true, 100, 100), row(0, 40, false, 240), row(1, 0, true, 100, 100), row(1, 60, false, 230)] } } },
    { width: 390, role: 'cand', search: '?x', want: null, morph: { phases: { close: [row(0, 0, true, 100, 100), row(0, 150, false, 150)] } } },
  ],
};

test('closeCells reads the last morphing sample and the first without', () => {
  const cells = closeCells(raw, 'r');
  assert.equal(cells.length, 3);
  assert.deepEqual(cells.map((c) => c.g), [40, 60, 150]);
  assert.deepEqual(cells.map((c) => c.redJ), [240, 230, 150]);
});

test('capCheck caps by the original arm only and flags the candidate', () => {
  const cells = closeCells(raw, 'r');
  const { cap, viol } = capCheck(cells);
  assert.equal(cap[390], 60);
  assert.deepEqual(viol.map((c) => c.role), ['cand']);
  assert.equal(ownGapCheck(cells).every((c) => c.slack > 0), true);
});

test('gapStats and the permutation test are deterministic', () => {
  assert.equal(gapStats([10, 20, 30]).median, 20);
  const cells = [10, 11, 12, 100, 110, 120].map((g, i) => ({ run: 'r', width: 390, role: i < 3 ? 'orig' : 'cand', g }));
  const a = permutationP(cells, 'cand', 2000), b = permutationP(cells, 'cand', 2000);
  assert.deepEqual(a, b);
  assert.ok(a.mean < 0.1);
});

test('identityCheck judges every cell by closeStartOk and frameIntervals / blockDiffs read the same rows', () => {
  const cells = closeCells(raw, 'r');
  const ids = identityCheck(cells);
  assert.equal(ids.length, 3);
  assert.deepEqual(ids.map((c) => c.m), [0.01, 0.01, 0.01]);
  assert.deepEqual(ids.map((c) => c.ok), [false, false, false]); // reds 240, 230, 150 against bgRed(0.01) = 233.7
  assert.equal(closeStartOk(redCh(0.01), 0.01), true);
  assert.equal(cells[0].earnOpacity, 0.25);
  assert.equal(cells[0].earnMaxWidth, 30);
  assert.deepEqual(frameIntervals(raw).orig, [40, 60]);
  assert.equal(blockDiffs(cells).length, 1);
});
