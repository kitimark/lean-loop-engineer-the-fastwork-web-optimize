// The still-run twin against the Lean golden (Fw.Device.StillRuns, packages/contracts/golden/device/stillruns.jsonl).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as S from '../src/throttle/stillruns.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/device/stillruns.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);

test('every golden kind has lines', () => {
  for (const k of ['consts', 'runs', 'stairs', 'throttleK', 'verdict', 'cruns', 'cverdict']) assert.ok(of(k).length > 0, k);
});

test('constants', () => {
  const [c] = of('consts');
  assert.deepEqual([S.BAND_LO, S.BAND_HI, S.MIN_BASE, S.DROP_DEN], [c.bandLo, c.bandHi, c.minBase, c.dropDen]);
});

test('runs and counts', () => {
  for (const g of of('runs')) {
    assert.deepEqual(S.runs(g.rows), g.runs);
    assert.equal(S.shortRuns(g.rows), g.short);
    assert.equal(S.bandRuns(g.rows), g.band);
    assert.equal(S.exitFrames(g.rows), g.exitFrames);
    assert.equal(S.allMove(g.rows), g.moving);
  }
});

test('stairs', () => {
  for (const g of of('stairs')) {
    assert.equal(S.moves(g.positions), g.moves);
    const rows = S.stairs(g.positions, g.period, g.value);
    assert.deepEqual(rows, g.rows);
    assert.deepEqual(S.runs(rows), g.runs);
    assert.equal(S.bandRuns(rows), g.band);
  }
});

test('throttle frames', () => {
  for (const g of of('throttleK')) assert.equal(S.throttleK(g.d), g.k, `${g.d}`);
});

test('verdict', () => {
  for (const g of of('verdict')) {
    assert.equal(S.sameHeight(g.heights), g.sameHeight);
    assert.equal(S.verdict(g.heights, g.base, g.lift), g.verdict, JSON.stringify(g));
  }
});

test('part series pairs a position with the next frame value', () => {
  assert.deepEqual(S.partSeries([1, 2, 3], [9, 10, 11]), [[1, 10], [2, 11]]);
  assert.deepEqual(S.armCounts([{ ys: [0, 0, 0, 0, 0, 0, 100, 100], vs: [0, 400, 400, 400, 400, 400, 400, 400] }]), { runs: 1, frames: 7 });
});

// ---- the verdict by toolbar class (Lean StillRuns "The verdict by toolbar class")

const cls = (c) => (c === 'm' ? 'moving' : 'still');
const letters = (cs) => cs.map((c) => c[0]).join('');

test('runs by toolbar class: runs, band counts and exit frames per class agree with Lean', () => {
  for (const g of of('cruns')) {
    const rows = g.rows.map(([y, v, c]) => [y, v, cls(c)]);
    assert.deepEqual(S.runsC(rows), g.runs.map((r) => ({ run: { k: r.k, jump: r.jump, mid: r.mid }, cls: cls(r.cls) })));
    for (const c of ['moving', 'still']) {
      assert.equal(S.countC(c, S.BAND_LO, S.BAND_HI, rows), g.band[c], c);
      assert.equal(S.exitFramesC(c, rows), g.exitFrames[c], c);
    }
    const plain = rows.map((r) => [r[0], r[1]]);
    assert.equal(g.band.moving + g.band.still, g.wholeBand, 'the two classes hold every band run once');
    assert.equal(g.exitFrames.moving + g.exitFrames.still, g.wholeExit, 'the two classes hold every exit frame once');
    assert.equal(S.bandRuns(plain), g.wholeBand);
    assert.equal(S.exitFrames(plain), g.wholeExit);
    assert.deepEqual(S.runsC(rows).map((r) => r.run), S.runs(plain), 'the classes change nothing about which runs exist');
  }
});

test('verdict by toolbar class: classes, arms and verdicts agree with Lean', () => {
  let startCollapsed = 0;
  for (const g of of('cverdict')) {
    assert.deepEqual(g.base.map((p) => letters(S.passClasses(p))), g.classes.base);
    assert.deepEqual(g.lift.map((p) => letters(S.passClasses(p))), g.classes.lift);
    assert.deepEqual([...g.base, ...g.lift].flatMap((p) => S.passHeights('still', p)), g.stillHeights);
    for (const [arm, ps] of [['base', g.base], ['lift', g.lift]]) {
      assert.deepEqual(S.armOf('moving', ps), g.arms[arm].moving);
      assert.deepEqual(S.armOf('still', ps), g.arms[arm].still);
      assert.deepEqual(S.armCounts(ps), g.arms[arm].today);
    }
    assert.deepEqual(S.verdictByClass(g.base, g.lift), { moving: g.moving, still: g.still, today: g.today }, JSON.stringify(g.classes));
    if (g.today === 'confounded' && g.still !== 'confounded') startCollapsed++;
  }
  assert.ok(startCollapsed > 0, 'the fixture holds a pass that starts with the toolbar collapsed: today confounded, the still class decides');
});

test('verdict by toolbar class: a recording without the field keeps today\'s verdict', () => {
  for (const g of of('cverdict')) {
    const strip = (ps) => ps.map(({ h, ys, vs }) => ({ h, ys, vs }));
    const [base, lift] = [strip(g.base), strip(g.lift)];
    const v = S.verdictByClass(base, lift);
    assert.equal(v.still, v.today, JSON.stringify(g.classes));
    assert.deepEqual(S.armOf('moving', base), { runs: 0, frames: 0 });
  }
});

test('verdict by toolbar class: a height that never changes keeps today\'s verdict', () => {
  for (const g of of('cverdict')) {
    if (![...g.base, ...g.lift].every((p) => p.ys.length > 0)) continue;
    const flat = (ps) => ps.map((p) => ({ ...p, vh: p.ys.map(() => p.h) }));
    const v = S.verdictByClass(flat(g.base), flat(g.lift));
    assert.equal(v.still, v.today, JSON.stringify(g.classes));
  }
});
