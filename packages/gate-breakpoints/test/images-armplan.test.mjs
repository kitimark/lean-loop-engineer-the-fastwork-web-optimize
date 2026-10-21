// The drawn-size arm's decisions (src/images/armplan.mjs) against the golden vectors Lean generates
// (packages/contracts/golden/gate/image-arm.jsonl, lean/Fw/Measure/ImageArm.lean). Nothing is decided here.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { ARM_GOLDEN } from '../src/images/armgen.mjs';
import { agreeCopy, decoded, disputedCopy, exactCopy, exactFile, exactSaving, fitCopy, fitFile, imgOf, integral, needW, partDecision, partDecisionWithCopies, reachWhy, saving, snapSize } from '../src/images/armplan.mjs';

const lines = readFileSync(ARM_GOLDEN, 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);

test('the golden file has every kind of case', () => {
  for (const k of ['snap', 'reach', 'file', 'part', 'partc', 'reps', 'saving']) assert.ok(of(k).length > 0, k);
  assert.ok(of('reach').some((l) => l.why === 'ok') && of('part').some((l) => l.decision === 'admissible'));
  for (const w of ['notImg', 'cropped', 'scaled', 'fractional', 'noSaving']) assert.ok(of('reach').some((l) => l.why === w), `reason ${w}`);
  for (const d of ['admissible', 'lookChange', 'shippedFails', 'undecided']) assert.ok(of('part').some((l) => l.decision === d), `decision ${d}`);
  for (const d of ['admissible', 'lookChange', 'shippedFails', 'undecided', 'noCopy']) assert.ok(of('partc').some((l) => l.decision === d), `decision with copies ${d}`);
});

test('snapping: size and integral flag', () => {
  for (const l of of('snap')) {
    assert.equal(snapSize(l.dpr, l.left, l.right), l.size, JSON.stringify(l));
    assert.equal(integral(l.dpr, l.right - l.left), l.integral, JSON.stringify(l));
  }
});

test('reach: the reason, the exact and the fit copy, the need', () => {
  for (const l of of('reach')) {
    assert.equal(reachWhy(l.dpr, l.img), l.why, l.name);
    assert.deepEqual(exactCopy(l.dpr, l.img), l.exact, l.name);
    assert.deepEqual(fitCopy(l.dpr, l.img), l.fit, l.name);
    assert.equal(needW(l.dpr, l.img), l.need, l.name);
  }
});

test('files drawn by several elements: the agreed exact copy, the covering fit copy, the saving', () => {
  for (const l of of('file')) {
    assert.deepEqual(exactFile(l.dpr, l.imgs), l.exact, l.name);
    assert.deepEqual(fitFile(l.dpr, l.imgs), l.fit, l.name);
    assert.equal(exactSaving(l.dpr, l.imgs), l.exactSaving, l.name);
  }
});

test('the decision of a part from its cells', () => {
  for (const l of of('part')) assert.equal(partDecision(l.cells.map(([base, drawn]) => ({ base, drawn }))), l.decision, l.name);
});

test('the decision of a part over cells with and without copies (noCopy, an error cell among the cells)', () => {
  for (const l of of('partc')) assert.equal(partDecisionWithCopies(l.cells.map(([copy, base, drawn]) => ({ copy, base, drawn }))), l.decision, l.name);
});

test('one file planned in several reps: the agreed copy and the dispute', () => {
  for (const l of of('reps')) {
    assert.deepEqual(agreeCopy(l.plans), l.agreed, l.name);
    assert.equal(disputedCopy(l.plans), l.disputed, l.name);
  }
});

test('decoded bytes and the saving', () => {
  for (const l of of('saving')) {
    assert.equal(decoded(...l.nat), l.decoded);
    assert.equal(saving(...l.nat, ...l.copy), l.saving);
  }
});

test('snapSize_shift: a whole-device-pixel size snaps to the same size at every position (the proved statement, swept)', () => {
  for (const dpr of [1, 2, 3]) {
    for (const w of [500, 1000, 29000, 30000, 213000, 320000]) {
      if (!integral(dpr, w)) continue;
      for (let l = 0; l < 3000; l += 7) assert.equal(snapSize(dpr, l, l + w), (w * dpr) / 1000, `${dpr} ${w} ${l}`);
    }
  }
});

test('imgOf: an avatar reading is exact, a scaled card and a cover crop are not', () => {
  const avatar = { kind: 'img', nat: [200, 200], box: [30, 30], img: [30, 30], fit: 'fill', vis: 1, visMin: 1, visMax: 1, rw: 30, rh: 30 };
  assert.deepEqual(exactCopy(2, imgOf(avatar)), [60, 60]);
  assert.equal(reachWhy(2, imgOf({ ...avatar, visMin: 0.35, visMax: 1.19, vis: 1 })), 'scaled');
  assert.equal(reachWhy(2, imgOf({ ...avatar, img: [60, 30], fit: 'cover' })), 'cropped');
  assert.equal(reachWhy(2, imgOf({ ...avatar, fit: 'none' })), 'cropped');
  assert.equal(reachWhy(2, imgOf({ ...avatar, kind: 'bg' })), 'notImg');
  assert.equal(reachWhy(3, imgOf({ ...avatar, rw: 29.6, box: [30, 30], vis: 29.6 / 30, visMin: 29.6 / 30, visMax: 29.6 / 30 })), 'scaled');
});
