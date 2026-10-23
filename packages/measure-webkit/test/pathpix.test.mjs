import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { offsets, mask, rawOf, rawOk, premises, grade, cellS1, accelerated } from '../src/pathpix.mjs';
import { splitUnion } from '../src/pathpix-exit.mjs';
import { gradeRel, whyL, region, exitOffsets, exitClaim, armPin, pinAt, shownAccent, pinMasks, accentPinned, rowsPinned, rowsPlaced, checkedRows, gradePinned, unpinnedWhy, floorPinned, coverAll, occludedBoth, hookSearch, yieldsShared, foreignMasks, countedIn, FOREIGN_REASON } from '../src/pathpix-exit.mjs';
import { clockNow, exitClockPinned, secondsLeft, hookSearch as chromiumHookSearch } from '../../measure-chromium/src/pathpix-pure.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/gate/path-pix.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);

test('golden file holds every kind the twin replays', () => {
  for (const k of ['grade', 'accelerated', 'premises', 'offsets', 'mask', 'raw', 'rel', 'region', 'exitOffsets', 'exitClaim', 'accentPin', 'pinRegion', 'accentRow', 'accentGrade', 'hook', 'chainStarts', 'clockPin', 'cover', 'foreign', 'yield']) assert.ok(of(k).length > 0, k);
});

test('grade, S1 and premises per cell equal the Lean golden', () => {
  for (const g of of('grade')) {
    assert.equal(grade(g.cell), g.grade, g.name);
    assert.equal(cellS1(g.cell), g.s1, g.name);
    assert.deepEqual(premises(g.cell.engine, g.cell.claim), g.premises, g.name);
  }
});

test('premises equal the Lean golden', () => {
  for (const p of of('premises')) assert.deepEqual(premises(p.engine, p.claim), p.premises, p.name);
});

test('accelerated equals the Lean golden', () => {
  for (const a of of('accelerated')) assert.equal(accelerated(a.props), a.accelerated, a.props.join());
});

test('offsets equal the Lean golden and span the range', () => {
  for (const o of of('offsets')) {
    assert.deepEqual(offsets(o.maxY), o.offsets, `maxY ${o.maxY}`);
    assert.equal(o.offsets.length, 9);
    assert.equal(o.offsets[0], 0);
    assert.equal(o.offsets[8], o.maxY);
  }
});

test('masks equal the Lean golden', () => {
  for (const m of of('mask')) assert.deepEqual(mask(m.dpr, m.fw, m.fh, m.box), m.mask, m.name);
});

test('count reduction equals the Lean golden', () => {
  for (const r of of('raw')) {
    assert.deepEqual(rawOf(r.pixels), r.raw);
    assert.equal(rawOk(r.raw), r.ok);
  }
});

test('the shared-pixel rule equals the Lean golden: hero_copy yields pixels another graded layer owns, every other layer counts its whole mask', () => {
  for (const f of of('foreign')) {
    assert.equal(yieldsShared(f.layer), f.yields, f.name);
    assert.deepEqual(foreignMasks(f.layer, f.others), f.foreign, f.name);
    assert.equal(countedIn(f.foreign, f.mine, f.x, f.y), f.counted, f.name);
    assert.equal(f.reason, FOREIGN_REASON);
  }
  assert.ok(of('foreign').some((f) => f.yields && f.counted === false) && of('foreign').some((f) => !f.yields && f.counted === true));
});

test('the cell decision against the floor equals the Lean golden', () => {
  for (const r of of('rel')) {
    assert.equal(gradeRel(r.cell, r.floor, r.live), r.grade, r.name);
    assert.equal(whyL(r.cell, r.floor, r.live), r.why, r.name);
    assert.equal(gradeRel({ ...r.cell, stripsAccepted: true }, r.floor, r.live), r.ifAccepted, r.name);
  }
});

test('regions of a pixel equal the Lean golden', () => {
  for (const g of of('region')) assert.equal(region(g.masks, g.masks[g.mine] ?? [0, 0, 0, 0], g.x, g.y), g.region, JSON.stringify(g));
});

test('exit offsets and claims equal the Lean golden', () => {
  for (const o of of('exitOffsets')) assert.deepEqual(exitOffsets(o.T, o.n), o.offsets, `T ${o.T} n ${o.n}`);
  for (const c of of('exitClaim')) assert.deepEqual(exitClaim(c.layer, c.le600), c.claim, `${c.layer} ${c.le600}`);
});

test('the accent pin is the same in every arm and shows the served word, as the Lean golden says', () => {
  const rows = of('accentPin');
  assert.deepEqual([...new Set(rows.map((r) => r.arm))], ['A', 'A2', 'P']);
  for (const r of rows) {
    assert.equal(armPin(r.arm), r.pin, r.arm);
    assert.deepEqual(r.perOffset.map((_, i) => pinAt(r.arm, i)), r.perOffset, `${r.arm} per offset`);
    assert.equal(r.perOffset.length, 9);
    assert.ok(r.perOffset.every((x) => x === r.pin));
    assert.deepEqual(shownAccent(armPin(r.arm), { cursor: r.live.cursor, phase: r.live.phase }), r.shown, JSON.stringify(r));
  }
  assert.deepEqual(shownAccent('none', { cursor: 3, phase: 'draw-in' }), { cursor: 3, phase: 'draw-in' });
});

test('the pin changes no mask: regions under the pin equal the Lean golden', () => {
  for (const g of of('pinRegion')) {
    const ms = pinMasks(g.pin, g.masks);
    assert.deepEqual(ms, g.masks);
    assert.equal(region(ms, ms[g.mine] ?? [0, 0, 0, 0], g.x, g.y), g.region, JSON.stringify(g));
  }
});

test('the accent pin and the row placement are enforced per measured row as the Lean golden says', () => {
  for (const r of of('accentRow')) assert.equal(accentPinned(r.served, r.start, r.stop, r.n), r.pinned, JSON.stringify(r));
  const gs = of('accentGrade');
  assert.ok(gs.some((g) => !g.pinned) && gs.some((g) => g.pinned));
  assert.ok(gs.some((g) => !g.placed) && gs.some((g) => g.placed));
  assert.ok(gs.some((g) => g.why === 'misplaced') && gs.some((g) => g.why === 'accent-unpinned') && gs.some((g) => g.why === null));
  for (const g of gs) {
    const rs = checkedRows(g.rows, g.floorRows, g.floor);
    assert.equal(rowsPinned(g.served, rs), g.pinned, g.name);
    assert.equal(rowsPlaced(g.maxY, rs), g.placed, g.name);
    assert.equal(unpinnedWhy(g.served, g.maxY, g.rows, g.floorRows, g.floor), g.why, g.name);
    assert.deepEqual(g.floor && floorPinned(g.served, g.maxY, g.floorRows, g.floor), g.floorPinned, g.name);
    assert.equal(gradePinned(g.served, g.maxY, g.rows, g.floorRows, g.cell, g.floor, g.live), g.grade, g.name);
  }
});

test('opaque cover of a layer in both arms equals the Lean golden', () => {
  const cs = of('cover');
  assert.ok(cs.some((c) => c.occluded) && cs.some((c) => !c.occluded));
  for (const c of cs) assert.equal(occludedBoth(c.a, c.b), c.occluded, JSON.stringify(c));
  assert.equal(coverAll(undefined), false, 'an old manifest without cover is never occluded');
  assert.equal(occludedBoth({ n: 0, k: 0 }, { n: 0, k: 0 }), false);
});

test('the page clock an exit run reads equals the Lean golden: pinned, the countdown seconds do not depend on the arm', () => {
  const cs = of('clockPin');
  assert.ok(cs.some((c) => c.pinned) && cs.some((c) => !c.pinned));
  assert.equal(exitClockPinned('chromium'), true);
  assert.equal(exitClockPinned('webkit'), true);
  for (const c of cs) {
    const now = clockNow(c.pinned, c.epoch, c.vnow);
    assert.equal(now, c.now, JSON.stringify(c));
    assert.equal(secondsLeft(c.target, now), c.seconds, JSON.stringify(c));
  }
  const secs = (pinned) => new Set(cs.filter((c) => c.pinned === pinned).map((c) => c.seconds)).size;
  assert.equal(secs(true), 1);
  assert.ok(secs(false) > 1);
});

test('the capture opens every exit arm with the site hook set, keeping the arm query', () => {
  for (const h of [hookSearch, chromiumHookSearch]) {
    assert.equal(h(''), '?fwpin=accent');
    assert.equal(h('?fw=hero.exit:threaded'), '?fw=hero.exit:threaded&fwpin=accent');
  }
  assert.ok(of('hook').some((g) => g.search === '?fwpin=accent' && g.hook === true));
  assert.ok(of('hook').some((g) => g.search === '?fw=hero.exit:threaded&fwpin=accent' && g.hook === true));
});

test('the yield rule equals the Lean golden: hero_copy hands a pixel to the cells of other graded layers and they count it, A/A and P changes alike', () => {
  const ys = of('yield');
  assert.ok(ys.some((y) => y.heroCounts.length && y.heroCounts.every((c) => c === false) && y.countedBy.length > 0), 'a yielded pixel is counted by a receiver');
  assert.ok(ys.some((y) => y.countedBy.length === 0), 'a pixel in no mask is counted by none');
  for (const y of ys) {
    const masks = y.layers.map((l) => l.mask);
    const foreign = y.layers.map((l, n) => foreignMasks(l.layer, masks.filter((_, o) => y.layers[o].layer !== l.layer)));
    for (const d of [1, 13]) {
      const del = new Uint8Array(200 * 200);
      del[y.y * 200 + y.x] = d;
      const sp = splitUnion(del, 200, 200, masks, foreign);
      const counting = y.layers.filter((_, n) => sp.inside[n].raw.changed === 1).map((l) => l.key);
      assert.deepEqual(counting, y.countedBy, `${y.name}, delta ${d}`);
      y.layers.forEach((l, n) => {
        if (l.layer === 'hero_copy') assert.deepEqual(sp.inside[n].raw.changed === 1, y.heroCounts[0], y.name);
        const inOwn = masks[n][0] <= y.x && y.x < masks[n][1] && masks[n][2] <= y.y && y.y < masks[n][3];
        const yielded = inOwn && sp.inside[n].raw.changed === 0;
        assert.deepEqual(sp.receivers[n].map((o) => y.layers[o].key).every((k) => y.countedBy.includes(k)), true, y.name);
        assert.equal(sp.shared[n].changed, yielded ? 1 : 0, y.name);
        assert.equal(sp.receivers[n].length > 0, yielded, y.name);
      });
    }
  }
});
