import test from 'node:test';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { FLAG_ARMS, statesOf, zoneArms, NAV_M, elapsedAt, CAROUSEL_AT_MS, SWAP_MS } from './plan.mjs';
import { wantEffects, PUSH_EXPR, STEP_EXPR } from './sim-capture.mjs';
import { CI_PAIRS } from './ci-pairs.mjs';
import { ringSplit, glassOf, glassDelta, againstLoads, maskOf, hashOf } from './pix.mjs';
import { unionBox } from './reduce.mjs';
import { diffImages } from './armpair.mjs';
import { flat, CAROUSEL_ARM, CAROUSEL_STEP } from './mac-capture.mjs';
import { bytesOf, parseIOSurface, simServicePids, iosurfaceSample } from './iosurface.mjs';
import { encodePng } from '../../../packages/measure-webkit/src/pathpix-png.mjs';

const img = (w, h, f) => {
  const rgba = new Uint8Array(w * h * 4);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) { const [r, g, b] = f(x, y); const o = (y * w + x) * 4; rgba[o] = r; rgba[o + 1] = g; rgba[o + 2] = b; rgba[o + 3] = 255; }
  return { w, h, rgba };
};

const RUN_KINDS = Object.freeze({
  'nav-clip-box': ['gate', 'trajectory', 'webkitSim'],
  'nav-bar-fixed': ['gate', 'trajectory', 'webkitSim'],
  'nav-logo-3d': ['gate', 'trajectory', 'webkitSim'],
  'morph-panel-threaded': ['counts', 'gate', 'trajectory', 'webkitSim'],
  'morph-panel-threaded-fade': ['counts', 'gate', 'trajectory', 'webkitSim'],
  'pain-dark-scroll': ['base', 'counts', 'gate', 'webkitSim'],
  'hero-exit-threaded': ['base', 'pathPix', 'trajectory', 'webkitSim'],
  'people-carousel-crop': ['webkitSim'],
  'people-o-preview-translate': ['gate'],
});

test('every flag arm has a zone and a task, and its CI pairing holds exactly the run kinds of its row in the table', () => {
  const ids = FLAG_ARMS.map((a) => a.id);
  assert.equal(new Set(ids).size, ids.length);
  assert.deepEqual([...ids].sort(), Object.keys(RUN_KINDS).sort());
  for (const a of FLAG_ARMS) {
    assert.ok(a.zone && a.task && a.search.startsWith('?fw='));
    const p = CI_PAIRS[a.id];
    const kinds = Object.entries(p ?? {}).filter(([, v]) => (Array.isArray(v) ? v.length > 0 : Boolean(v))).map(([k]) => k).sort();
    assert.deepEqual(kinds, RUN_KINDS[a.id], a.id);
    for (const v of Object.values(p).flat()) assert.match(String(v), /^\d{10,}$/, a.id);
  }
});

test('a zone loads faithful, the A/A control, its flag arms, then faithful again as an order probe', () => {
  assert.deepEqual(zoneArms('morph').map((a) => a.id), ['base', 'base2', 'morph-panel-threaded', 'morph-panel-threaded-fade', 'base3']);
  assert.deepEqual(zoneArms('pain').map((a) => a.id), ['base', 'base2', 'pain-dark-scroll', 'base3']);
  assert.ok(zoneArms('nav').every((a) => a.id.startsWith('base') || a.zone === 'nav'));
});

test('the carousel zone parks a swap row and steps the paused animations inside the 220 ms swap; extra loads add base4 on', () => {
  assert.deepEqual(zoneArms('carousel').map((a) => a.id), ['base', 'base2', 'people-carousel-crop', 'base3']);
  assert.deepEqual(zoneArms('morph', 6).map((a) => a.id), ['base', 'base2', 'morph-panel-threaded', 'morph-panel-threaded-fade', 'base3', 'base4', 'base5', 'base6']);
  assert.throws(() => zoneArms('morph', 2));
  const st = statesOf('carousel');
  assert.deepEqual(st.map((s) => s.elapsedMs), CAROUSEL_AT_MS);
  assert.ok(st.every((s) => s.kind === 'swap' && s.mask === 'box' && s.elapsedMs > 0 && s.elapsedMs < SWAP_MS));
  assert.deepEqual(maskOf('box', 2, 860, 1864, [10e6, 100e6, 104e6, 32e6]), [12, 236, 192, 272]);
  assert.match(CAROUSEL_ARM, /lane\.parked = true/);
  assert.match(CAROUSEL_STEP(110), /currentTime = 110/);
  assert.doesNotMatch(CAROUSEL_STEP(110), /finish\(|cancel\(/);
});

test('the nav states hold the task values and the pain states need the flip offset', () => {
  assert.deepEqual(statesOf('nav').map((s) => s.m), NAV_M);
  for (const m of [0.1, 0.5, 0.9, 0.25, 0.75]) assert.ok(statesOf('nav').some((s) => s.m === m));
  assert.throws(() => statesOf('pain'));
  assert.deepEqual(statesOf('pain', 888).map((s) => s.y), [872, 887, 888, 889, 904]);
  assert.throws(() => statesOf('hero'));
});

test('the morph states are driven by a real push and sit at the elapsed time of their value; nav and pain are not', () => {
  assert.ok(statesOf('morph').every((s) => s.drive === 'push' && s.elapsedMs === elapsedAt(s.m)));
  assert.ok(statesOf('nav').every((s) => s.drive === undefined));
  for (const m of [0.25, 0.5, 0.75]) assert.ok(Math.abs(1 - (1 - elapsedAt(m) / 680) ** 3 - m) < 1e-4, String(m));
  assert.equal(elapsedAt(0.5), 140.284);
  assert.throws(() => elapsedAt(1));
  const arm = (id) => FLAG_ARMS.find((a) => a.id === id);
  assert.equal(wantEffects({ search: '' }), 0);
  assert.equal(wantEffects(arm('morph-panel-threaded')), 2);
  assert.equal(wantEffects(arm('morph-panel-threaded-fade')), 3);
  assert.doesNotMatch(STEP_EXPR(62, 0.25), /FREEZE|finish\(/);
  assert.match(PUSH_EXPR, /new WheelEvent\('wheel'/);
});

test('ringSplit separates the mask edge from its interior and ignores the frame border', () => {
  const w = 10, h = 10, del = new Uint8Array(w * h);
  del[2 * w + 2] = 5;
  del[5 * w + 5] = 9;
  del[0] = 7;
  const r = ringSplit(del, w, [2, 8, 2, 8], 2);
  assert.deepEqual(r.edge, { changed: 1, maxDelta: 5 });
  assert.deepEqual(r.interior, { changed: 1, maxDelta: 9 });
  const full = ringSplit(del, w, [0, 10, 0, 10], 2);
  assert.equal(full.edge.changed, 0);
  assert.equal(full.interior.changed, 3);
});

test('glassOf reads mean and median over the shrunk mask and glassDelta subtracts', () => {
  const a = img(40, 40, () => [100, 150, 200]);
  const b = img(40, 40, () => [98, 150, 203]);
  const ga = glassOf(a, [0, 40, 0, 40], 4), gb = glassOf(b, [0, 40, 0, 40], 4);
  assert.deepEqual(ga.mean, [100, 150, 200]);
  assert.deepEqual(ga.median, [100, 150, 200]);
  assert.deepEqual(glassDelta(ga, gb), { mean: [-2, 0, 3], median: [-2, 0, 3] });
  assert.equal(glassOf(a, [0, 10, 0, 10], 8), null);
});

test('againstLoads: an arm equal to one faithful load is within the faithful spread', () => {
  const w = 8, h = 8;
  const f0 = img(w, h, () => [10, 10, 10]);
  const f1 = img(w, h, (x) => (x < 4 ? [10, 10, 10] : [60, 10, 10]));
  const arm = img(w, h, (x) => (x < 4 ? [10, 10, 10] : [60, 10, 10]));
  const r = againstLoads([f0, f1], arm, w, [0, w, 0, h]);
  assert.equal(r.nearest, 0);
  assert.equal(r.spread, 32);
  assert.equal(r.within, true);
  const far = img(w, h, () => [200, 10, 10]);
  const q = againstLoads([f0, f1], far, w, [0, w, 0, h]);
  assert.equal(q.nearest, 64);
  assert.equal(q.within, false);
  const f2 = img(w, h, () => [10, 10, 10]);
  assert.equal(againstLoads([f0, f2], far, w, [0, w, 0, h]).within, false);
});

test('againstLoads: the A/A floor is the later-load pair, the first load is the outlier', () => {
  const w = 8, h = 8, m = [0, w, 0, h];
  const outlier = img(w, h, () => [90, 10, 10]);
  const f1 = img(w, h, () => [10, 10, 10]);
  const f2 = img(w, h, (x) => (x < 2 ? [20, 10, 10] : [10, 10, 10]));
  const r = againstLoads([outlier, f1, f2], img(w, h, () => [10, 10, 10]), w, m);
  assert.equal(r.floor, 16);
  assert.equal(r.spread, 64);
  assert.equal(r.laterNearest, 0);
  assert.equal(r.within, true);
  const q = againstLoads([outlier, f1, f2], img(w, h, () => [90, 10, 10]), w, m);
  assert.equal(q.nearest, 0);
  assert.equal(q.laterNearest, 64);
  assert.equal(q.within, false);
});

test('againstLoads gives the spread of the later-load floors: min, median, max over the pairs without the first load', () => {
  const w = 8, h = 8, m = [0, w, 0, h];
  const L = (n) => img(w, h, (x) => (x < n ? [20, 10, 10] : [10, 10, 10]));
  const r = againstLoads([L(7), L(0), L(1), L(3)], L(0), w, m);
  assert.deepEqual(r.laterFloors, { n: 3, min: 8, median: 16, max: 24 });
  assert.equal(r.floor, 8);
  assert.equal(r.laterNearest, 0);
  assert.equal(againstLoads([L(7), L(0)], L(0), w, m).laterFloors, null);
});

test('diffImages counts changed px, the largest channel delta, their box and how many fall in a named box', () => {
  const a = img(6, 6, () => [10, 10, 10]);
  const b = img(6, 6, (x, y) => (x === 1 && y === 2 ? [10, 14, 10] : x === 4 && y === 5 ? [10, 10, 11] : [10, 10, 10]));
  const r = diffImages(a, b, { left: [0, 3, 0, 6], none: [5, 6, 0, 1] });
  assert.deepEqual(r, { changed: 2, maxDelta: 4, bbox: [1, 2, 4, 5], inside: { left: 1, none: 0 } });
  assert.deepEqual(diffImages(a, a), { changed: 0, maxDelta: 0, bbox: null, inside: {} });
});

test('maskOf takes the nav box in micro px and the whole frame otherwise; unionBox grows both', () => {
  assert.deepEqual(maskOf('frame', 3, 1290, 2325), [0, 1290, 0, 2325]);
  assert.deepEqual(maskOf('nav', 3, 1290, 2325, [12000000, 12000000, 406000000, 100000000]), [35, 1255, 35, 337]);
  assert.throws(() => maskOf('nav', 3, 10, 10));
  assert.deepEqual(unionBox([0, 0, 10, 10], [5, 5, 10, 10]), [0, 0, 15, 15]);
});

test('hashOf is stable and sees one changed pixel', () => {
  const a = img(4, 4, () => [1, 2, 3]);
  const b = img(4, 4, (x, y) => (x === 3 && y === 3 ? [1, 2, 4] : [1, 2, 3]));
  assert.equal(hashOf(a), hashOf(img(4, 4, () => [1, 2, 3])));
  assert.notEqual(hashOf(a), hashOf(b));
});

test('flat refuses the all-black frame a locked screen gives and accepts a real one', () => {
  assert.equal(flat(encodePng(img(8, 8, () => [0, 0, 0]))), true);
  assert.equal(flat(encodePng(img(8, 8, (x) => [x * 10, 0, 0]))), false);
});

test('vmmap IOSurface row: sizes, count, absent row', () => {
  assert.equal(bytesOf('277.5M'), Math.round(277.5 * 1024 * 1024));
  assert.equal(bytesOf('0K'), 0);
  assert.equal(bytesOf('x'), null);
  const text = 'REGION TYPE   VIRTUAL RESIDENT\nIOSurface   277.5M  12.0M  4K  0K  0K  0K  89.2M  205\nMALLOC  1M 1M 1M 0K 0K 0K 0K 3\n';
  const r = parseIOSurface(text);
  assert.equal(r.regions, 205);
  assert.equal(r.residentBytes, 12 * 1024 * 1024);
  assert.equal(r.dirtyBytes, 4096);
  assert.equal(parseIOSurface('MALLOC 1M 1M 1M 0K 0K 0K 0K 3\n'), null);
});

test('service pids come from the base64 service name, only for Simulator processes, and the newest is read', () => {
  const b = (n) => Buffer.from(JSON.stringify({ serviceName: n, type: 8 })).toString('base64');
  const ps = [`11 /x/SimulatorRuntime/y ${b('com.apple.WebKit.GPU')}`, `12 /x/SimulatorRuntime/y ${b('com.apple.WebKit.WebContent')}`,
    `13 /System/Library/WebKit.GPU.xpc/com.apple.WebKit.GPU`, `14 /x/SimulatorRuntime/y ${b('com.apple.WebKit.GPU')}`, `15 /x/SimulatorRuntime/y notbase64`].join('\n');
  assert.deepEqual(simServicePids(ps), { gpu: [11, 14], content: [12] });
  const seen = [];
  const s = iosurfaceSample({ ps: () => ps, vmmap: (pid) => { seen.push(pid); return { status: 0, stdout: 'IOSurface 1M 0K 0K 0K 0K 0K 0K 7\n' }; } });
  assert.deepEqual(seen, [14, 12]);
  assert.equal(s.gpu.regions, 7);
  assert.equal(iosurfaceSample({ ps: () => 'x', vmmap: () => ({ status: 1 }) }).gpu.error, 'no process');
  assert.equal(iosurfaceSample({ ps: () => ps, vmmap: () => ({ status: 1, stdout: '' }) }).gpu.error, 'vmmap exit 1');
});

test('elapsedAt matches the Lean golden (Fw.Measure.GpuElapsed): the floor on the 1/1000 ms grid, rounded', () => {
  const rows = readFileSync(new URL('./elapsed.golden.jsonl', import.meta.url), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
  assert.ok(rows.length >= 10);
  let checked = 0;
  for (const r of rows) {
    const m = Number(r.in.m.num) / Number(r.in.m.den);
    if (!(m > 0 && m < 1)) { assert.ok(r.out === 0 || r.out === 680000, `edge ${m}: ${r.out}`); continue; }
    const got = Math.round(elapsedAt(m) * 1000);
    assert.ok(got === r.out || got === r.out + 1, `m ${m}: TS ${got} vs Lean floor ${r.out}`);
    checked++;
  }
  assert.ok(checked >= 8);
});
