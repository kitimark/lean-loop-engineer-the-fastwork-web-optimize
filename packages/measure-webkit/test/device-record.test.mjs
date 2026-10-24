// The phone recorder pipeline on the Lean synthetic session (golden/device/session.jsonl, Fw.Device.Session):
// record format -> reductions -> replay export -> CI profile loader -> package. No phone is involved.
import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { spawnSync } from 'node:child_process';
import { readFileSync, readdirSync, mkdtempSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as S from '../src/device-session.mjs';
import { exportProfile, packageSession, sessionMarkdown, readRecord, writeProfile, writePackage } from '../src/device-profile.mjs';
import { RECORD_JS, PART_PROPS, POLL_JS, stepOf } from '../src/device-record.mjs';
import { resolveFlags, sessionPlan } from '../src/device-arms.mjs';
import { parseProfile, replayOk as loaderOk } from '../../measure-chromium/src/profile.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/device/session.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);
const profilesDir = join(here, '../../measure-chromium/profiles');
const [session] = of('session');
const pairs = (p) => p.map((q) => [q[0], q[1]]);

test('every golden kind has lines', () => {
  for (const k of ['consts', 'plan', 'dedup', 'series', 'zone', 'stat', 'verdict', 'part', 'marks', 'stream', 'loader', 'session', 'class.consts', 'class', 'class.report', 'class.compare']) assert.ok(of(k).length > 0, k);
});

const classStr = (cs) => cs.map((c) => c[0]).join('');
const toReport = ([frames, total, hero, finish, rest]) => ({ frames, total: { per50: total }, zones: { hero: { per50: hero }, finish: { per50: finish }, rest: { per50: rest } } });

test('toolbar class: constants and the class of every frame agree with Lean', () => {
  const [c] = of('class.consts');
  assert.deepEqual([S.CLASS_CONST.moveWin, S.CLASS_CONST.moveMin], [c.moveWin, c.moveMin]);
  for (const g of of('class')) {
    assert.equal(classStr(S.classes(g.vh)), g.classes, JSON.stringify(g.vh.slice(0, 5)));
    assert.equal(g.classes.length, g.vh.length);
  }
});

test('toolbar class: the split is a partition of the frames, and a constant height is all still', () => {
  for (const g of of('class')) {
    const cs = S.classes(g.vh);
    assert.equal(cs.filter((c) => c === 'moving').length + cs.filter((c) => c === 'still').length, g.vh.length);
    if (g.vh.every((h) => h === g.vh[0])) assert.ok(cs.every((c) => c === 'still'));
  }
});

test('toolbar class: a pass reduced by class agrees with Lean and the classes add up to today\'s counts', () => {
  const [g] = of('class.report');
  const rec = g.record;
  assert.equal(classStr(S.classesOf(rec)), g.classes);
  const whole = S.reducePass(rec);
  assert.deepEqual(whole.total, g.whole.total);
  assert.deepEqual(S.reduceClass(rec, 'moving'), g.moving);
  assert.deepEqual(S.reduceClass(rec, 'still'), g.still);
  assert.equal(g.moving.total.n + g.still.total.n, whole.total.n);
  assert.equal(g.moving.frames + g.still.frames, rec.t.length);
  assert.ok(g.moving.frames > 0 && g.still.frames > 0, 'the fixture has both classes');
  const old = { ...rec, vh: undefined };
  assert.equal(classStr(S.classesOf(old)), g.noFieldClasses);
  assert.deepEqual(S.reduceClass(old, 'moving'), g.noFieldMoving);
  assert.deepEqual(S.reduceClass(old, 'still'), g.noFieldStill);
  assert.deepEqual(S.reduceClass(old, 'still').total, whole.total, 'a recording without the field keeps today\'s counts');
  assert.deepEqual(S.reduceClass(old, 'still').zones, whole.zones);
  assert.equal(S.reduceClass(old, 'moving').frames, 0);
});

test('toolbar class: a fixture record without the field keeps today\'s reduction and verdict', () => {
  const rec = session.record;
  assert.equal(rec.vh, undefined);
  assert.deepEqual(S.reduceClass(rec, 'still').total, session.report.total);
  const reports = ['original', 'original', 'rewrite', 'rewrite'].map((arm) => ({ arm, report: session.report, ...S.reduceByClass(rec) }));
  const today = S.compareZones(reports);
  const byClass = S.compareClasses(reports).filter((x) => x.class === 'still');
  assert.deepEqual(byClass.map((x) => x.zone), today.map((x) => x.zone));
  for (const [i, x] of byClass.entries()) {
    assert.deepEqual(x.original, today[i].original);
    assert.deepEqual(x.arms.map((a) => a.verdict), today[i].arms.map((a) => a.verdict));
  }
  assert.ok(S.compareClasses(reports).filter((x) => x.class === 'moving').every((x) => x.original.length === 0 && x.arms.every((a) => a.verdict === 'unresolved')));
});

test('toolbar class: per-class per-pass values and verdicts agree with Lean', () => {
  for (const g of of('class.compare')) {
    const [o, a] = [g.orig.map(toReport), g.arm.map(toReport)];
    for (const [k, z] of [['total', null], ['hero', 'hero'], ['finish', 'finish'], ['rest', 'rest']]) {
      assert.deepEqual(S.classVals(z, o), g[k].orig, k);
      assert.deepEqual(S.classVals(z, a), g[k].arm, k);
      assert.equal(S.compareClass(z, o, a), g[k].verdict, `${k} ${JSON.stringify(g.orig)}`);
    }
  }
});

test('zones', () => {
  for (const g of of('zone')) assert.equal(S.zoneOf(g.vh10, g.maxY10, g.y), g.zone, `${g.y}`);
});

test('frame-interval counts, per zone', () => {
  for (const g of of('stat')) {
    const rows = S.movingRows(g.frames);
    assert.deepEqual(rows.map((r) => [r.dt, r.y]), g.rows);
    assert.deepEqual(S.stat(rows), g.total);
    for (const z of S.ZONES) assert.deepEqual(S.stat(S.inZone(g.vh10, g.maxY10, z, rows)), g.zones[z], z);
  }
});

test('comparison verdict and spread', () => {
  for (const g of of('verdict')) {
    assert.equal(S.spread(g.orig), g.spread, JSON.stringify(g));
    assert.equal(S.verdict(g.orig, g.arm), g.verdict, JSON.stringify(g));
  }
});

test('animated part: largest step and stalls', () => {
  for (const g of of('part')) {
    assert.equal(S.maxStep(g.series), g.maxStep, JSON.stringify(g.series));
    assert.equal(S.stalls(g.series), g.stalls, JSON.stringify(g.series));
  }
});

test('part series: each value paired with the position it was computed from', () => {
  for (const g of of('series')) {
    assert.deepEqual(S.partSeries(g.ys, g.vs), g.series, JSON.stringify(g));
    assert.equal(S.stalls(S.partSeries(g.ys, g.vs)), g.stalls, JSON.stringify(g));
    assert.equal(S.maxStep(g.ys.map((y, i) => [y, g.vs[i]])), g.maxStep, JSON.stringify(g));
  }
  // the lagged page: standing at 100, then moving; values 500, 500, 600 read one frame late. No stall happened.
  assert.equal(S.stalls(S.partSeries([100, 100, 200, 300], [0, 500, 500, 600])), 0);
  assert.equal(S.stalls([100, 100, 200, 300].map((y, i) => [y, [0, 500, 500, 600][i]])), 1, 'the unshifted pairing counts a false stall');
});

test('arms that load the same page are one arm (Lean dedupArms)', () => {
  for (const g of of('dedup')) assert.deepEqual(S.dedupArms(g.arms), g.kept, JSON.stringify(g.arms));
  assert.deepEqual(S.dedupArms([['rewrite', []], ['v2', []], ['look', ['a:b']]]), ['rewrite', 'look']);
});

test('felt marks from taps', () => {
  for (const g of of('marks')) assert.deepEqual(S.marksOf(g.taps), g.marks, JSON.stringify(g.taps));
});

test('touch streams: strokes, taps, single finger, replay strokes', () => {
  for (const g of of('stream')) {
    const ss = S.strokes(g.touches);
    assert.deepEqual(ss, g.strokes);
    assert.deepEqual(ss.map(S.isTap), g.isTap);
    assert.deepEqual(S.taps(g.touches), g.taps);
    assert.equal(S.singleFinger(g.touches), g.single);
    const rp = S.replay(g.touches, 430, 932);
    if (g.replay === null) assert.equal(rp, null);
    else {
      assert.deepEqual(rp.map((s) => ({ f0: s.f0, path: s.path })), g.replay.strokes);
      assert.equal(S.t0Of(S.replayStrokes(g.touches)), g.replay.t0);
    }
  }
});

test('the loader check agrees with Lean replayOk', () => {
  for (const g of of('loader')) assert.equal(loaderOk(g.w10, g.h10, g.cap, g.strokes.map((s) => ({ f0: s.f0, path: s.path }))), g.ok, JSON.stringify(g));
  assert.equal(S.CONST.maxReplayFrames, 12000);
});

test('plan: original, the rewrite arms that stay, original; the text is Lean\'s', () => {
  assert.deepEqual(S.PLAN.map((p) => p.arm), ['original', 'rewrite', 'v2', 'look', 'original']);
  for (const kept of [['rewrite'], ['rewrite', 'v2'], ['rewrite', 'look'], ['rewrite', 'v2', 'look']]) {
    const plan = S.planFor(kept);
    assert.deepEqual(plan.map((p) => p.arm), ['original', ...kept, 'original']);
    assert.equal(plan.length * S.CONST.recSeconds <= 900, true);
    for (const p of plan) {
      assert.match(p.text, new RegExp(`^Step ${p.step} of ${plan.length}: `));
      assert.match(p.text, /tap 3 times quickly on an empty area \(not on text, a link or a button\)/);
    }
  }
  assert.throws(() => S.planFor(['v2']));
  assert.equal(stepOf(2, S.PLAN).arm, 'rewrite');
  assert.throws(() => stepOf(9, S.PLAN));
});

test('fixture session: record -> reduction agrees with Lean', () => {
  const rec = session.record;
  assert.equal(rec.t.length, 480);
  const rep = S.reducePass(rec);
  assert.deepEqual(rep.total, session.report.total);
  assert.deepEqual(rep.zones, session.report.zones);
  assert.equal(rep.taps, session.report.taps);
  assert.deepEqual(rep.parts, session.report.parts);
  assert.deepEqual(rep.felt, session.report.felt);
  assert.equal(rep.felt.length, 2);
  assert.deepEqual(rep.felt.map((f) => f.zone), ['hero', 'finish']);
  assert.equal(rep.parts.hero.stalls, 4);
});

test('fixture session: page-unit record round-trips to the integer form', () => {
  const page = S.denormalize(session.record);
  assert.equal(page.schema, 'fw.phone.record/1');
  assert.deepEqual(S.normalize(page), session.record);
  assert.equal('vh' in page.frames, false, 'a record without the field gains none');
  const [g] = of('class.report');
  const withVh = S.denormalize(g.record);
  assert.deepEqual(withVh.frames.vh, g.record.vh.map((v) => v / 10));
  assert.deepEqual(S.normalize(withVh), g.record, 'the viewport height of every frame survives the page-unit round trip');
});

test('fixture session: replay strokes and the felt-mark frames agree with Lean', () => {
  const ss = S.replay(session.record.touches, session.record.w, session.record.h);
  assert.deepEqual(ss.map((s) => ({ f0: s.f0, path: s.path })), session.replay.strokes);
  assert.deepEqual(S.markFrames(session.record.touches), session.replay.marks);
  assert.equal(S.replayOk(session.record.w, session.record.h, ss), session.replay.ok);
});

test('fixture session: the exported profile loads in the CI loader and equals the committed file', () => {
  const p = exportProfile(session.record, { id: 'user-fixture' });
  const { profile, strokes } = parseProfile(p);
  assert.equal(profile.input.mode, 'replay');
  assert.equal(strokes.length, 5);
  assert.deepEqual(p.input.feltFrames, session.replay.marks);
  assert.deepEqual(JSON.parse(readFileSync(join(profilesDir, 'user-fixture.json'), 'utf8')), p);
});

test('every committed profile loads in the CI loader', () => {
  const files = readdirSync(profilesDir).filter((f) => f.endsWith('.json'));
  assert.ok(files.length >= 6);
  for (const f of files) parseProfile(JSON.parse(readFileSync(join(profilesDir, f), 'utf8')));
});

test('two fingers: no replay is made', () => {
  const rec = structuredClone(session.record);
  rec.touches[5][4] = 2;
  assert.equal(S.replay(rec.touches, rec.w, rec.h), null);
  assert.throws(() => exportProfile(rec, { id: 'user-x' }), /second finger/);
});

// A copy of the fixture pass with every frame interval set to `dt` hundredths of a ms (a smooth pass or a janky one).
const withDt = (rec, arm, pass, dt) => ({ ...rec, arm, pass, t: rec.t.map((_, i) => 100000 + i * dt) });

test('package: files in, summary out, no raw timestamps and no device', () => {
  const dir = mkdtempSync(join(tmpdir(), 'fw-session-'));
  const recs = [session.record, { ...session.record, pass: 2 }, withDt(session.record, 'rewrite', 1, 1667), withDt(session.record, 'v2', 1, 10000)];
  const files = recs.map((r, i) => { const f = join(dir, `rec-${i}.json`); writeFileSync(f, JSON.stringify(S.denormalize(r))); return f; });
  // the saved page-unit file reads back as the integer form
  assert.deepEqual(readRecord(files[0]), session.record);
  const out = join(dir, 'results', 'phone', '2026-10-21');
  const pkg = writePackage(files, out, { date: '2026-10-21' });
  assert.deepEqual(readdirSync(out).sort(), ['summary.json', 'summary.md']);
  const verdicts = Object.fromEntries(pkg.compare.find((z) => z.zone === 'total').arms.map((a) => [a.arm, a.verdict]));
  assert.deepEqual(verdicts, { rewrite: 'beats', v2: 'worse' });
  assert.equal(pkg.compare.find((z) => z.zone === 'total').spread, 0);
  const text = readFileSync(join(out, 'summary.json'), 'utf8') + readFileSync(join(out, 'summary.md'), 'utf8');
  assert.doesNotMatch(text, /device|"t":|touches|serial|udid|\.local|192\.168|\/Users\//i);
  for (const f of pkg.passes.flatMap((p) => p.report.felt)) assert.deepEqual(Object.keys(f).sort(), ['stat', 'y', 'zone']);
  assert.match(sessionMarkdown(pkg), /\| total \| .* \| rewrite \| .* \| beats \|/);
});

test('profile file written by the CLI glue loads', () => {
  const dir = mkdtempSync(join(tmpdir(), 'fw-session-'));
  const f = join(dir, 'rec.json');
  writeFileSync(f, JSON.stringify(S.denormalize(session.record)));
  const out = join(dir, 'user-fixture.json');
  writeProfile(f, out, { id: 'user-fixture', dpr: 3 });
  assert.equal(existsSync(out), true);
  assert.deepEqual(JSON.parse(readFileSync(out, 'utf8')), JSON.parse(readFileSync(join(profilesDir, 'user-fixture.json'), 'utf8')));
});

// ---- the page recorder, run against a stubbed page: touch listeners are passive and never prevent the default

test('page recorder: frames, parts and touches; listeners passive; no preventDefault', async () => {
  const listeners = new Map();
  const opts = [];
  let now = 5000, prevented = 0;
  const props = { '--exit-opacity': '1', '--future-shrink': '0', '--morph-fade': '0' };
  const queue = [];
  const sandbox = {
    performance: { now: () => now, timeOrigin: 1.7e12 }, scrollY: 0, innerWidth: 430, innerHeight: 932, devicePixelRatio: 3,
    document: {
      documentElement: { scrollHeight: 3932 },
      querySelector: (sel) => {
        const prop = Object.values(PART_PROPS).find((p) => sel.includes(p));
        return { isConnected: true, style: { getPropertyValue: (n) => (n === prop ? props[prop] : '') } };
      },
    },
    visualViewport: { scale: 1, height: 775.33, offsetTop: 0 },
    addEventListener: (k, f, o) => { listeners.set(k, f); opts.push([k, o]); },
    removeEventListener: (k) => { listeners.delete(k); },
    requestAnimationFrame: (f) => { queue.push(f); },
  };
  vm.createContext(sandbox);
  const done = vm.runInContext(RECORD_JS(0.1), sandbox);
  const ev = (type, x, y, nDown) => ({ type, timeStamp: now + 1.7e12, changedTouches: [{ clientX: x, clientY: y }], touches: new Array(nDown).fill(0), preventDefault() { prevented++; } });
  for (let k = 0; k < 20 && queue.length > 0; k++) {
    const f = queue.shift();
    now += 16.67; sandbox.scrollY += 12.34; props['--exit-opacity'] = String(Math.max(0, 1 - k / 10));
    if (k === 3) sandbox.visualViewport.scale = 1.4;
    if (k === 5) sandbox.visualViewport.scale = 1;
    if (k >= 4) { sandbox.visualViewport.height = 815; sandbox.visualViewport.offsetTop = 40.04; }
    if (k === 2) listeners.get('touchstart')(ev('touchstart', 215.55, 700, 1));
    if (k === 3) listeners.get('touchmove')(ev('touchmove', 215.55, 690, 1));
    if (k === 4) listeners.get('touchend')(ev('touchend', 215.55, 690, 0));
    f(now);
  }
  const rec = JSON.parse(JSON.stringify(await done)); // the CDP evaluate returns JSON
  assert.ok(rec.frames.t.length >= 5);
  assert.equal(rec.frames.t.length, rec.frames.y.length);
  assert.equal(rec.frames.p.hero.length, rec.frames.t.length);
  assert.equal(rec.frames.p.hero[0], 1000);
  assert.ok(rec.frames.p.hero.at(-1) < 1000);
  assert.deepEqual(rec.viewport, { w: 430, h: 932, dpr: 3 });
  assert.equal(rec.maxY, 3000);
  assert.deepEqual(rec.touches.map((t) => t[1]), ['s', 'm', 'e']);
  assert.deepEqual(rec.touches.map((t) => t[4]), [1, 1, 0]);
  assert.ok(Math.abs(rec.touches[0][2] - 215.55) < 0.1 && rec.touches[1][3] === 690);
  assert.equal(rec.touches[0][0], rec.frames.t[2], 'touch and frame stamps share one clock');
  assert.ok(opts.length === 5 && opts.every(([, o]) => o.passive === true && o.capture === true));
  assert.ok(opts.some(([k]) => k === 'pagehide'), 'a passive pagehide listener names a navigation');
  assert.equal(rec.zoom.frames, 2, 'frames at a visual viewport scale other than 1 are counted');
  assert.equal(rec.zoom.max, 1.4);
  assert.equal(rec.frames.vh.length, rec.frames.t.length, 'one viewport height per frame');
  assert.equal(rec.frames.vt.length, rec.frames.t.length, 'one viewport offset per frame');
  assert.deepEqual([rec.frames.vh[0], rec.frames.vt[0]], [775.3, 0]);
  assert.deepEqual([rec.frames.vh.at(-1), rec.frames.vt.at(-1)], [815, 40], 'rounded to 0.1 px, as in the int form');
  const recInt = S.normalize({ ...rec, arm: 'original', pass: 1 });
  assert.equal(recInt.vh.length, recInt.t.length);
  assert.ok(S.classesOf(recInt).every((c) => c === 'moving'), 'a toolbar change within the window of every frame of this short pass makes all of it moving');
  assert.equal(prevented, 0);
  assert.equal(listeners.size, 0, 'listeners are removed at the end');
  assert.doesNotThrow(() => S.reducePass(S.normalize({ ...rec, arm: 'original', pass: 1 })));
});

test('page recorder: pagehide names the navigation; the poll names a page that is gone', () => {
  const hidden = {};
  const sb = { performance: { now: () => 0, timeOrigin: 1.7e12 }, scrollY: 0, innerWidth: 430, innerHeight: 932, devicePixelRatio: 3,
    document: { documentElement: { scrollHeight: 3932 }, querySelector: () => null }, addEventListener: (k, f) => { hidden[k] = f; },
    removeEventListener() {}, requestAnimationFrame() {}, __wkRec: undefined };
  sb.globalThis = sb;
  vm.createContext(sb);
  vm.runInContext(RECORD_JS(0.1), sb);
  hidden.pagehide();
  assert.match(JSON.parse(sb.__wkRec).err, /page navigated/);
  // a fresh page (no liveness flag) answers the poll with the same named failure; a live one with null
  assert.match(JSON.parse(vm.runInContext(POLL_JS, vm.createContext({ window: {} }))).err, /page navigated \(a tap hit a link\)/);
  assert.equal(vm.runInContext(POLL_JS, vm.createContext({ window: { __wkRecOn: true } })), null);
});

// ---- which pages the session visits: the preset is resolved at record time

test('device-arms: the v2 arm is dropped exactly when v2-proved has no flags; a distinct look arm stays', () => {
  assert.deepEqual(resolveFlags(''), []);
  assert.deepEqual(resolveFlags('?preset=original'), []);
  const look = '?fw=hero.exit:scoped';
  assert.deepEqual(resolveFlags(look), ['hero.exit:scoped']);
  assert.deepEqual(resolveFlags('?fw=hero.exit:faithful'), [], 'a default variant is no flag');
  assert.throws(() => resolveFlags('?fw=hero.exit:nope'), /no variant/);
  assert.throws(() => resolveFlags('?preset=nope'), /unknown preset/);
  const sp = sessionPlan(look);
  if (resolveFlags('?preset=v2-proved').length === 0) {
    assert.deepEqual(sp.kept, ['rewrite', 'look']);
    assert.deepEqual(sp.plan.map((p) => p.arm), ['original', 'rewrite', 'look', 'original']);
    assert.deepEqual(sp.dropped.map((d) => [d.arm, d.sameAs]), [['v2', 'rewrite']]);
  } else {
    assert.deepEqual(sp.kept, ['rewrite', 'v2', 'look']);
  }
  const v2kept = resolveFlags('?preset=v2-proved').length === 0 ? ['rewrite'] : ['rewrite', 'v2'];
  assert.deepEqual(sessionPlan('?fw=hero.exit:faithful').kept, v2kept, 'a look arm without flags is the rewrite again');
  assert.throws(() => sessionPlan(''), /needs --search/);
});

test('device-arms: a non-empty preset keeps the v2 arm, in any flag order', () => {
  const dir = mkdtempSync(join(tmpdir(), 'fw-arms-'));
  const w = (rel, o) => { const f = join(dir, rel); mkdirSync(dirname(f), { recursive: true }); writeFileSync(f, JSON.stringify(o)); };
  w('registry/presets/base.json', { name: 'base', fw: {} });
  w('registry/presets/v2-proved.json', { name: 'v2-proved', extends: 'base', fw: { 'a.x': 'fast', 'b.y': 'fast' } });
  w('parts/a.x/part.json', { id: 'a.x', impls: ['mui'], variants: { faithful: {}, fast: {} } });
  w('parts/b.y/part.json', { id: 'b.y', impls: ['mui'], variants: { faithful: {}, fast: {} } });
  const root = { presets: `${dir}/registry/presets/`, parts: `${dir}/parts/` };
  assert.deepEqual(resolveFlags('?preset=v2-proved', root), ['a.x:fast', 'b.y:fast']);
  assert.deepEqual(sessionPlan('?fw=b.y:fast,a.x:fast', root).kept, ['rewrite', 'v2'], 'the look arm equal to v2 (any order) is dropped');
  assert.deepEqual(sessionPlan('?fw=a.x:fast', root).kept, ['rewrite', 'v2', 'look']);
});

// ---- the command line, without a phone: plan, reduce, profile, package, and the refusals that come before any phone contact

test('device-cli: plan, reduce, profile and package run on saved records', () => {
  const dir = mkdtempSync(join(tmpdir(), 'fw-cli-'));
  const cli = join(here, '../src/device-cli.mjs');
  const run = (...args) => spawnSync(process.execPath, [cli, ...args], { encoding: 'utf8', cwd: dir });
  const f1 = join(dir, 'a.json'), f2 = join(dir, 'b.json');
  writeFileSync(f1, JSON.stringify(S.denormalize(session.record)));
  writeFileSync(f2, JSON.stringify(S.denormalize(withDt(session.record, 'rewrite', 1, 1667))));
  const pl = run('plan', '--search', '?fw=hero.exit:scoped');
  assert.equal(pl.status, 0, pl.stderr);
  assert.equal(pl.stdout.trim().split('\n').length, S.planFor(S.dedupArms(['rewrite', 'v2', 'look'].map((a) => [a, resolveFlags(a === 'v2' ? '?preset=v2-proved' : a === 'look' ? '?fw=hero.exit:scoped' : '')]))).length);
  const red = run('reduce', '--in', `${f1},${f2}`);
  assert.equal(red.status, 0, red.stderr);
  assert.equal(JSON.parse(red.stdout).passes, 2);
  const prof = run('profile', '--in', f1, '--id', 'user-fixture', '--out', join(dir, 'p.json'));
  assert.equal(prof.status, 0, prof.stderr);
  assert.deepEqual(JSON.parse(prof.stdout).feltFrames, session.replay.marks);
  const pk = run('package', '--kind', 'session', '--in', `${f1},${f2}`, '--date', '2026-10-21', '--out', join(dir, 'res'));
  assert.equal(pk.status, 0, pk.stderr);
  assert.deepEqual(readdirSync(join(dir, 'res')).sort(), ['summary.json', 'summary.md']);
  // a step whose arm does not match the target, and the look arm without a flag list, are refused before the phone is touched
  assert.match(run('record', '--step', '1', '--target', 'rewrite', '--site', '/x', '--search', '?fw=hero.exit:scoped').stderr, /--target must be original/);
  assert.match(run('record', '--step', '4', '--target', 'rewrite', '--site', '/x').stderr, /needs --search/);
  assert.match(run('record', '--step', '9', '--target', 'rewrite', '--site', '/x', '--search', '?fw=hero.exit:scoped').stderr, /no step 9/);
});
