import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { offsets, mask, rawOf, rawOk, premises, grade, cellS1, accelerated } from '../src/pathpix.mjs';
import { splitUnion } from '../src/pathpix-exit.mjs';
import { gradeRel, whyL, region, exitOffsets, exitClaim, armPin, pinAt, shownAccent, pinMasks, accentPinned, rowsPinned, rowsPlaced, checkedRows, gradePinned, unpinnedWhy, floorPinned, coverAll, occludedBoth, hookSearch, yieldsShared, foreignMasks, countedIn, FOREIGN_REASON, zoneAgree, zoneSeen, joinSeen, verdictOf, consensusOf, probeHit, probesHit, zoneOdd, mzoneSeen, mzoneEff, zonedOf, zonedCell, zonedPinned, rowsOk, listedVerdict, drawTimes, drawOf, drawWorst, drawBase, aboveBase, DRAW_MS, DRAW_FRAMES } from '../src/pathpix-exit.mjs';
import { outsideLane, withAbove, aboveTable, zoneTable } from '../src/pathpix-exit-draw-zones.mjs';
import { fwcoreBin } from '../src/handoff.mjs';
import { clockNow, exitClockPinned, secondsLeft, hookSearch as chromiumHookSearch } from '../../measure-chromium/src/pathpix-pure.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/gate/path-pix.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);

test('golden file holds every kind the twin replays', () => {
  for (const k of ['grade', 'accelerated', 'premises', 'offsets', 'mask', 'raw', 'rel', 'region', 'exitOffsets', 'exitClaim', 'accentPin', 'pinRegion', 'accentRow', 'accentGrade', 'hook', 'chainStarts', 'clockPin', 'cover', 'foreign', 'yield', 'seen', 'consensus', 'zoned', 'zonedPinned', 'drawTimes', 'draw', 'drawWorst', 'drawBase', 'probeHit']) assert.ok(of(k).length > 0, k);
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
  assert.deepEqual([...new Set(rows.map((r) => r.arm))], ['A', 'A2', 'A3', 'P']);
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

test('the consensus rule equals the Lean golden: a P change counts only where the identical arms agree', () => {
  const ss = of('seen');
  assert.deepEqual([...new Set(ss.map((x) => x.seen))].sort(), ['counted', 'quiet', 'varied']);
  for (const x of ss) {
    assert.equal(zoneAgree(x.region), x.agree, x.name);
    assert.equal(zoneSeen(x.region), x.seen, x.name);
  }
  const cs = of('consensus');
  assert.ok(cs.some((c) => c.verdict === 'varied') && cs.some((c) => c.verdict === c.grade) && cs.some((c) => c.verdict === 'invalid'));
  for (const c of cs) {
    assert.equal(consensusOf(c.cell, c.floor, c.live, c.a2, c.a3), c.verdict, c.name);
    assert.equal(gradeRel(c.cell, c.floor, c.live), c.grade, c.name);
    assert.ok(c.verdict === 'varied' || c.verdict === c.grade, `${c.name}: a verdict is the grade or varied`);
  }
  for (const a of ['quiet', 'varied', 'counted']) for (const b of ['quiet', 'varied', 'counted']) assert.equal(joinSeen(a, b), joinSeen(b, a));
  assert.equal(verdictOf('invalid', { p: { changed: 1, maxDelta: 1 }, aa2: { changed: 1, maxDelta: 1 }, aa3: null }, { p: { changed: 0, maxDelta: 0 }, aa2: { changed: 0, maxDelta: 0 }, aa3: null }), 'invalid');
});

test('the zoned reading equals the Lean golden: varied zones drop out of mixed cells, an odd arm A is read against A2', () => {
  const zs = of('zoned');
  assert.ok(zs.length > 70);
  const names = new Set(zs.map((z) => z.verdict));
  assert.ok(names.has('varied') && names.has('L') && names.has('invalid') && names.has('Q'));
  assert.ok(zs.some((z) => z.seen[0] === 'varied' && z.seen[1] === 'counted' && z.verdict === 'L'), 'mixed: inside counted, outside varied');
  assert.ok(zs.some((z) => z.seen[0] === 'counted' && z.seen[1] === 'varied' && z.verdict === 'L'), 'mixed: outside counted, inside varied');
  assert.ok(zs.some((z) => z.odd[0] && z.seen[0] === 'quiet'), 'A odd, P equals the majority');
  for (const z of zs) {
    const mo = { z: z.out.zone, p2: z.out.p2, a23: z.out.a23 }, mi = { z: z.inside.zone, p2: z.inside.p2, a23: z.inside.a23 };
    assert.deepEqual([zoneOdd(mo), zoneOdd(mi)], z.odd, z.name);
    assert.deepEqual([mzoneSeen(mo), mzoneSeen(mi)], z.seen, z.name);
    assert.deepEqual([mzoneEff(mo), mzoneEff(mi)], z.eff, z.name);
    const g = gradeRel(z.cell, z.floor, z.live);
    assert.equal(g, z.grade, z.name);
    const v = zonedOf(g, gradeRel(zonedCell(z.cell, mo, mi), z.floor, z.live), mo, mi);
    assert.equal(v, z.verdict, z.name);
    assert.equal(listedVerdict(v), z.listed, z.name);
    assert.equal(v === 'L' ? whyL(zonedCell(z.cell, mo, mi), z.floor, z.live) : null, z.why, z.name);
    assert.ok(!(z.listed && v === 'varied'));
  }
});

test('the pinned zoned reading equals the Lean golden: zoned when the accent rows are pinned and placed, invalid otherwise', () => {
  const zs = of('zonedPinned');
  assert.ok(zs.some((z) => z.ok && z.verdict === 'L') && zs.some((z) => !z.ok && z.zoned === 'L') && zs.some((z) => z.ok && z.verdict === 'varied'));
  for (const z of zs) {
    const mo = { z: z.out.zone, p2: z.out.p2, a23: z.out.a23 }, mi = { z: z.inside.zone, p2: z.inside.p2, a23: z.inside.a23 };
    assert.equal(rowsOk(z.served, z.maxY, checkedRows(z.rows, z.floorRows, z.floor)), z.ok, z.name);
    assert.equal(zonedPinned(z.served, z.maxY, z.rows, z.floorRows, z.cell, z.floor, z.live, mo, mi), z.verdict, z.name);
    assert.equal(z.verdict, z.ok ? z.zoned : 'invalid', z.name);
  }
});

test('the outside-band baseline of a draw lane equals the Lean golden; the three measured F lanes give one column', () => {
  const bs = of('drawBase');
  assert.ok(bs.some((b) => b.base === null) && bs.some((b) => b.base !== null));
  for (const b of bs) {
    assert.equal(drawBase(b.lane), b.base, b.name);
    assert.deepEqual(aboveBase(b.lane), b.above, b.name);
    if (b.above) assert.equal(b.above.length, DRAW_FRAMES);
  }
  const f = bs.filter((b) => b.name.startsWith('run ') && b.name.endsWith(' F')).map((b) => JSON.stringify(b.above));
  assert.equal(f.length, 3);
  assert.equal(new Set(f).size, 1);
});

const RUN = join(here, '../../../results/accent-draw-nolayout-pixels/run-40037992429');
const artifactJobs = [1, 2, 3].map((n) => ({ label: `d${n}`, n, cells: JSON.parse(readFileSync(join(RUN, `job-${n}`, 'cells.json'), 'utf8')) }));
const hasFwcore = (() => { try { fwcoreBin(); return true; } catch { return false; } })();

test('each of the six committed lanes of run 40037992429 (outside-band changed counts) equals its Lean drawBase golden row', () => {
  const bs = of('drawBase');
  let seen = 0;
  for (const j of artifactJobs) {
    for (const n of ['N', 'F']) {
      const name = `run 40037992429 job-${j.n} ${n}`;
      const row = bs.find((b) => b.name === name);
      assert.ok(row, name);
      const lane = outsideLane(j, n);
      assert.equal(lane.length, DRAW_FRAMES, name);
      assert.deepEqual(lane, row.lane, name);
      assert.equal(drawBase(lane), row.base, name);
      assert.notEqual(row.base, null, name);
      assert.deepEqual(aboveBase(lane), row.above, name);
      seen++;
    }
  }
  assert.equal(seen, 6);
});

test('fwcore gate.pathpixDrawBase gives the golden base and above of the six committed lanes and null for the golden negatives', { skip: !hasFwcore && 'fwcore binary not built' }, async () => {
  const jobs = await withAbove(artifactJobs);
  const bs = of('drawBase');
  for (const j of jobs) {
    for (const n of ['N', 'F']) {
      const row = bs.find((b) => b.name === `run 40037992429 job-${j.n} ${n}`);
      assert.deepEqual(j.above[n], { base: row.base, above: row.above }, `${j.label} ${n}`);
    }
  }
  const bad = bs.filter((b) => !b.name.startsWith('run '));
  const rep = await withAbove(bad.map((b) => ({ label: b.name, cells: { frames: b.lane.map((x) => ({ arms: { N: { rest: { changed: x } }, F: { rest: { changed: x } } } })) } })));
  bad.forEach((b, i) => assert.deepEqual(rep[i].above.N, { base: b.base, above: b.above }, b.name));
});

test('zones.md carries the above-baseline table that fwcore computed for the committed run', { skip: !hasFwcore && 'fwcore binary not built' }, async () => {
  const jobs = await withAbove(artifactJobs);
  assert.equal(readFileSync(join(RUN, 'zones.md'), 'utf8'), `${zoneTable(jobs)}\n`);
  assert.match(aboveTable(jobs), /\| baseline \| 100 \| 1965 \| 17 \| 35751 \| 101 \| 100 \|/);
  assert.match(aboveTable(jobs), /\| above baseline, in 0 ms \| 0 \| 0 \| 0 \| 17622 \| 17622 \| 17622 \|/);
});

test('the draw-window rule equals the Lean golden: frame times, same/floor/above per frame, the worst frame', () => {
  const [t] = of('drawTimes');
  assert.equal(t.ms, DRAW_MS);
  assert.deepEqual(drawTimes(), t.times);
  for (const d of of('draw')) assert.equal(drawOf(d.aa, d.arm), d.draw, d.name);
  for (const w of of('drawWorst')) assert.equal(drawWorst(w.draws), w.worst);
});

test('the probe overlap equals the Lean golden: touching edges do not hit, the recorded order is kept', () => {
  const ps = of('probeHit');
  assert.ok(ps.some((p) => p.hit.length === 0) && ps.some((p) => p.hit.length > 1));
  for (const p of ps) {
    const probes = Object.fromEntries(p.probes.map(([n, x, y, w, h]) => [n, [x, y, w, h]]));
    assert.deepEqual(probesHit(probes, p.bbox, p.dpr).map((h) => h[0]), p.hit, p.name);
  }
  assert.equal(probeHit(1, [10, 0, 20, 5], [20e6, 1e6, 5e6, 1e6]), false);
  assert.equal(probeHit(1, [10, 0, 21, 5], [20e6, 1e6, 5e6, 1e6]), true);
});
