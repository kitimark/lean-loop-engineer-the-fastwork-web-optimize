import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { MAC_PAGE_JS, MAC_SCHEDULE, MOMENTUM, runRecord } from '../src/lag/macmorph.mjs';
import { analyze, macMd, rangesOfRun, METRICS, DRIVES, FLIGHT_HOLD, MIN_WHEELS, inFlight, flightFrames, splitPush, acceptMomentum, jobLabel } from '../src/lag/macreport.mjs';
import { classify } from '../src/lag/phase.mjs';
import { COUNT_TYPES } from '../src/reduce.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const gold = readFileSync(join(here, '../../contracts/golden/measure/webkit-lag.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => gold.filter((l) => l.kind === kind);

const stamp = (t, message) => ({ type: 'TimeStamp', startTime: t, data: { message } });

function records({ frames = 130, idle = 10, open = 60, layouts = () => 0, noUp = false } = {}) {
  const out = [];
  for (let k = 0; k < frames; k++) {
    if (k === idle) out.push(stamp(2 * k - 1, 'wk:down'));
    if (k === idle + open && !noUp) out.push(stamp(2 * k - 1, 'wk:up'));
    out.push({ type: 'Composite', startTime: 2 * k, endTime: 2 * k + 0.1, children: [] });
    out.push(stamp(2 * k, `wk:s${k}`));
    for (let i = 0; i < layouts(k); i++) out.push({ type: 'Layout', startTime: 2 * k + 0.5, endTime: 2 * k + 0.6, children: [] });
  }
  out.push(stamp(2 * frames, 'wk:end'));
  return out;
}

test('a run with both pushes is split by the rule, its steps keep their counts', () => {
  const r = runRecord(records({ idle: 12, open: 58, layouts: (k) => (k >= 12 && k < 70 ? 2 : 0) }), 130);
  assert.deepEqual([r.outcome, r.idle, r.open, r.close], ['ok', 12, 58, 60]);
  const L = COUNT_TYPES.indexOf('Layout');
  assert.equal(r.perStep.length, 130);
  assert.equal(r.perStep.reduce((s, row) => s + row[L], 0), 116);
});

test('a missing up push or missing step marks refuse the run', () => {
  assert.equal(runRecord(records({ noUp: true }), 130).outcome, 'noUp');
  assert.equal(runRecord(records({ frames: 100 }), 130).outcome, 'marksMissing');
  assert.equal(runRecord(records({ idle: 3 }), 130).outcome, 'idleShort');
});

function stubPage() {
  const marks = [], rafs = [], listeners = [];
  const nav = { style: { getPropertyValue: () => '0.5' } };
  const sandbox = {
    performance: { mark: (m) => marks.push(m) },
    document: { querySelector: () => nav, body: { dispatchEvent: (e) => listeners.forEach((l) => l(e)) } },
    addEventListener: (t, fn, o) => { if (t === 'wheel') { assert.equal(o.capture, true); assert.equal(o.passive, true); listeners.push(fn); } },
    requestAnimationFrame: (fn) => rafs.push(fn),
    WheelEvent: class { constructor(t, o) { Object.assign(this, o, { isTrusted: false, defaultPrevented: false }); } },
    scrollY: 100,
  };
  sandbox.window = sandbox;
  vm.runInNewContext(MAC_PAGE_JS, sandbox);
  const S = sandbox.__wkm;
  const frame = () => rafs.splice(0).forEach((f) => f());
  return { S, marks, frame, sandbox };
}

test('the page script marks frames and the first push in each direction, and keeps what the event was', async () => {
  const { S, marks, frame } = stubPage();
  S.start();
  let idle = false;
  S.until(2, 'idle').then(() => { idle = true; });
  frame(); frame();
  await Promise.resolve();
  assert.equal(idle, true);
  S.push(120); S.push(120); S.push(-120);
  frame();
  const fin = S.finish();
  frame();
  const r = JSON.parse(JSON.stringify(await fin));
  assert.deepEqual([...marks].filter((m) => m !== 'wk:s0' && !/^wk:s\d+$/.test(m)), ['wk:down', 'wk:up', 'wk:end']);
  assert.equal(marks.filter((m) => /^wk:s\d+$/.test(m)).length, 4);
  assert.equal(r.events.length, 3);
  assert.deepEqual(r.events.map((e) => [e.dy, e.trusted, e.prevented]), [[120, false, false], [120, false, false], [-120, false, false]]);
  assert.equal(r.at.find((x) => x.label === 'idle').morph, 0.5);
  assert.ok(!MAC_PAGE_JS.includes('getComputedStyle'));
  assert.deepEqual({ ...MAC_SCHEDULE }, { idle: 10, open: 60, close: 60, dy: 120 });
});

function file(reps, layout, { scrollin = true } = {}) {
  const runs = [];
  for (let rep = 0; rep < reps; rep++) for (const arm of ['orig', 'rewrite']) for (const drive of DRIVES) {
    const r = runRecord(records({ layouts: (k) => (k >= 10 && k < 70 ? layout(arm, drive, rep) : 0) }), 130);
    const scrolls = drive === 'scrollin' || drive === 'momentum';
    const startY = scrolls ? (scrollin ? 4800 : 5102) : 5102;
    const events = drive === 'momentum'
      ? [{ f: 5, m: false }, { f: 7, m: false }, { f: 9, m: false }, { f: 10, m: true }, { f: 70, m: true }].map((e) => ({ ...e, y: 5102, dy: 120, trusted: true, cancelable: true, prevented: false }))
      : [{ f: 10, dy: 120, trusted: drive !== 'synthetic', cancelable: true, prevented: false, m: true }];
    runs.push({ rep, arm, drive, ...r, startY, pushY: 5102, wheels: scrolls ? 3 : 0, info: { maxY: 5102 }, fin: { frames: 130, y: 5102, events, at: [{ label: 'open', f: 70, morph: drive === 'synthetic' ? 0.5 : 1, y: 5102 }] } });
  }
  return { runs };
}

test('tables: each job is decided on its own, refused runs are counted per job', () => {
  const lay = (arm, drive) => (drive === 'synthetic' ? 5 : 1);
  const files = [file(3, lay), file(3, lay), file(3, lay)];
  files[0].runs.push({ rep: 9, arm: 'orig', drive: 'trusted', outcome: 'noUp', marks: [], down: 1, up: null });
  const a = analyze(files);
  assert.equal(a.jobs, 3);
  assert.deepEqual(a.stat['orig|trusted|open'].map((s) => s.n), [3, 3, 3]);
  assert.equal(a.stat['orig|trusted|open'][0].mean.Layout, 1);
  assert.equal(a.stat['orig|synthetic|open'][1].mean.Layout, 5);
  assert.deepEqual(a.drive['orig|trusted|open'].Layout.verdicts, ['lower', 'lower', 'lower']);
  assert.deepEqual(a.drive['orig|trusted|open'].Layout.tally, { lower: 3, higher: 0, overlap: 0 });
  assert.deepEqual(a.arm['trusted|open'].Layout.verdicts, ['overlap', 'overlap', 'overlap']);
  assert.equal(a.cls['orig|trusted|open'][2].Layout, 'deterministic');
  assert.deepEqual(a.refused[0]['orig|trusted'].map((r) => r.outcome), ['noUp']);
  assert.deepEqual(a.refused[1], {});
  assert.equal(a.facts[0]['orig|trusted'].trusted, 3);
  assert.equal(a.facts[0]['orig|synthetic'].trusted, 0);
  assert.equal(a.facts[0]['orig|trusted'].morphMax, 1);
  assert.equal(a.facts[0]['orig|scrollin'].scrolledIn, 3);
  assert.equal(a.facts[0]['orig|trusted'].scrolledIn, 0);
  assert.equal(a.facts[0]['orig|momentum'].inFlight, 3);
  assert.equal(a.facts[0]['orig|momentum'].atEnd, 3);
  assert.deepEqual(a.facts[0]['orig|momentum'].gapFrames, [1, 1, 1]);
  assert.deepEqual(a.facts[0]['orig|momentum'].flightOpen, [2, 2, 2]);
  assert.deepEqual(a.labels, ['job 1', 'job 2', 'job 3']);
  const md = macMd(a);
  for (const h of ['Scroll in flight at the push', 'orig: momentum vs synthetic', 'Pushes seen by the page', 'open phase', 'orig: trusted vs synthetic', 'orig: scrollin vs synthetic', 'lower / lower / lower', 'refused', 'never pooled']) assert.ok(md.includes(h), h);
  assert.equal(METRICS.length, 7);
});

test('a difference in one job is stated for that job only, not diluted or lifted by the other jobs', () => {
  const sep = (arm, drive) => (drive === 'synthetic' ? 5 : 1);
  const same = () => 3;
  const a = analyze([file(3, sep), file(3, same), file(3, sep)]);
  assert.deepEqual(a.drive['orig|trusted|open'].Layout.verdicts, ['lower', 'overlap', 'lower']);
  assert.deepEqual(a.drive['orig|trusted|open'].Layout.tally, { lower: 2, higher: 0, overlap: 1 });
  const wide = (arm, drive, rep) => (drive === 'synthetic' ? 5 : 1) + (rep % 3) * 3;
  const b = analyze([file(3, wide)]);
  assert.deepEqual(b.drive['orig|trusted|open'].Layout.verdicts, ['overlap']);
});

test('the run that scrolls into the push is used only when it scrolled and the push opened the morph', () => {
  const f = file(2, () => 1);
  const base = f.runs.find((r) => r.drive === 'scrollin');
  assert.deepEqual(rangesOfRun(base), { idle: [0, 10], open: [10, 70], close: [70, 130] });
  assert.equal(rangesOfRun({ ...base, startY: 5102 }), null);
  assert.equal(rangesOfRun({ ...base, fin: { ...base.fin, at: [{ morph: 0.5 }] } }), null);
  const trusted = f.runs.find((r) => r.drive === 'trusted');
  assert.notEqual(rangesOfRun({ ...trusted, startY: 5102, fin: { ...trusted.fin, at: [{ morph: 0 }] } }), null);
  const a = analyze([{ runs: [{ ...base, startY: 5102 }, { ...base, rep: 1 }] }]);
  assert.deepEqual(a.refused[0]['orig|scrollin'].map((r) => r.outcome), ['noScroll']);
});

test('the page script marks only the armed push, so wheels that scroll in leave no mark', () => {
  const { S, marks, frame } = stubPage();
  S.start(); frame();
  S.arm('none'); S.push(120); S.push(120);
  S.arm('down'); S.push(120);
  frame();
  const fin = S.finish();
  frame();
  return fin.then((r) => {
    assert.deepEqual(marks.filter((m) => m === 'wk:down' || m === 'wk:up'), ['wk:down']);
    assert.equal(r.events.length, 3);
  });
});

test('rangesOfRun uses the rule on the recorded marks', () => {
  const r = runRecord(records({ idle: 12, open: 58 }), 130);
  assert.deepEqual(rangesOfRun(r), { idle: [0, 12], open: [12, 70], close: [70, 130] });
  assert.equal(rangesOfRun({ ...r, up: null }), null);
});

test('in flight, flight frames, the push split and the momentum acceptance agree with every Lean golden case', () => {
  const k = of('momentumConst')[0];
  assert.equal(FLIGHT_HOLD, k.flightHold);
  assert.equal(MIN_WHEELS, k.minWheels);
  const fl = of('flight');
  assert.ok(fl.length >= 8);
  for (const g of fl) {
    assert.equal(inFlight(g.scrolls, g.push), g.inFlight, JSON.stringify(g));
    assert.equal(flightFrames(g.scrolls, g.push, g.n), g.frames, JSON.stringify(g));
  }
  const sp = of('splitPush');
  assert.ok(sp.length >= 5);
  for (const g of sp) assert.deepEqual(splitPush(g.events.map(([f, m]) => ({ f, m }))), { scrolls: g.scrolls, push: g.push }, JSON.stringify(g.events));
  const mo = of('momentum');
  for (const g of mo) {
    const o = acceptMomentum(classify(g.marks, g.down, g.up), g.startY, g.pushY, g.morphMilli, g.scrolls, g.push);
    assert.equal(o.outcome, g.outcome, JSON.stringify([g.scrolls, g.push, g.startY, g.pushY, g.morphMilli]));
    if (g.outcome === 'ok') assert.deepEqual([o.idle, o.open, o.close], [g.idle, g.open, g.close]);
  }
  for (const o of ['ok', 'noScroll', 'noOpen', 'noPush', 'fewWheels', 'settled', 'noUp', 'openShort']) assert.ok(mo.some((g) => g.outcome === o), o);
  for (const g of of('jobLabel')) assert.equal(jobLabel(g.index ?? undefined, g.pos, g.n), g.label, JSON.stringify(g));
});

test('job labels name the matrix job when the file knows it, else this job or the position', () => {
  const f = file(2, () => 1);
  assert.deepEqual(analyze([f]).labels, ['this job']);
  assert.deepEqual(analyze([{ ...f, jobIndex: 2 }]).labels, ['job 2']);
  assert.deepEqual(analyze([f, f]).labels, ['job 1', 'job 2']);
  const md = macMd(analyze([{ ...f, jobIndex: 3 }]));
  assert.ok(md.includes('| job 3 | orig | trusted |') && !md.includes('| job 1 |') && md.includes('job 3 in that order'));
  assert.ok(macMd(analyze([f])).includes('| this job | orig | trusted |'));
});

test('the page script skips the armed push on request, so the last scroll wheel is told from the push by order', async () => {
  const { S, marks, frame } = stubPage();
  S.start(); frame();
  S.arm('none'); S.push(120); S.push(120);
  frame();
  S.arm('down', 1); S.push(120);
  frame();
  S.push(120);
  frame();
  const fin = S.finish();
  frame();
  const r = await fin;
  assert.deepEqual(marks.filter((m) => m === 'wk:down'), ['wk:down']);
  assert.deepEqual([...r.events.map((e) => e.m)], [false, false, false, true]);
  assert.equal(splitPush(r.events).scrolls.length, 3);
  assert.equal(MOMENTUM.before, 1);
});

test('a momentum run whose push lands after the scroll settled, or with one wheel, or with no push, is refused for that reason', () => {
  const f = file(2, () => 1);
  const base = f.runs.find((r) => r.drive === 'momentum');
  const ev = (list) => ({ ...base, fin: { ...base.fin, events: list.map(([fr, m]) => ({ f: fr, m, dy: 120, trusted: true, cancelable: true, prevented: false })) } });
  assert.deepEqual(rangesOfRun(base), { idle: [0, 10], open: [10, 70], close: [70, 130] });
  assert.equal(rangesOfRun(ev([[5, false], [7, false], [9, false], [13, true]])), null);
  const a = analyze([{ runs: [ev([[5, false], [7, false], [9, false], [13, true]]), ev([[9, false], [10, true]]), ev([[5, false], [7, false]]), base] }]);
  assert.deepEqual(a.refused[0]['orig|momentum'].map((r) => r.outcome), ['settled', 'fewWheels', 'noPush']);
});
