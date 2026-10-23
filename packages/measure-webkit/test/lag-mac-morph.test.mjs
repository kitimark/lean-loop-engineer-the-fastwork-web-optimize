// The Playwright WebKit morph runs: records to a per-run phase record, the page script, and the tables over several jobs.
import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { MAC_PAGE_JS, MAC_SCHEDULE, runRecord } from '../src/lag/macmorph.mjs';
import { analyze, macMd, rangesOfRun, METRICS } from '../src/lag/macreport.mjs';
import { COUNT_TYPES } from '../src/reduce.mjs';

const stamp = (t, message) => ({ type: 'TimeStamp', startTime: t, data: { message } });

/** Protocol records of a run: frames 2 ms apart, pushes after `idle` and `idle + open` frames, `layouts(k)` Layout records inside frame k. */
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

/** The page script run against a stub page: a manual rAF queue, a mark log and a capture wheel listener. */
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

/** A run file: per arm x drive, `reps` runs; `layout(arm, drive, rep)` Layout records per open frame. */
function file(reps, layout) {
  const runs = [];
  for (let rep = 0; rep < reps; rep++) for (const arm of ['orig', 'rewrite']) for (const drive of ['trusted', 'synthetic']) {
    const r = runRecord(records({ layouts: (k) => (k >= 10 && k < 70 ? layout(arm, drive, rep) : 0) }), 130);
    runs.push({ rep, arm, drive, ...r, info: { maxY: 100 }, fin: { frames: 130, y: 100, events: [{ f: 10, dy: 120, trusted: drive === 'trusted', cancelable: true, prevented: false }], at: [{ label: 'open', f: 70, morph: drive === 'trusted' ? 1 : 0.5, y: 100 }] } });
  }
  return { runs };
}

test('tables: separated per-run ranges give a verdict, equal ones do not, refused runs are counted', () => {
  const lay = (arm, drive, rep) => (drive === 'synthetic' ? 5 : 1) + (arm === 'rewrite' ? 0 : 0) + (rep % 2) * 0;
  const files = [file(3, lay), file(3, lay), file(3, lay)];
  files[0].runs.push({ rep: 9, arm: 'orig', drive: 'trusted', outcome: 'noUp', marks: [], down: 1, up: null });
  const a = analyze(files);
  assert.equal(a.jobs, 3);
  assert.equal(a.stat['orig|trusted|open'].n, 9);
  assert.equal(a.stat['orig|trusted|open'].mean.Layout, 1);
  assert.equal(a.stat['orig|synthetic|open'].mean.Layout, 5);
  assert.equal(a.drive['orig|open'].Layout, 'lower');
  assert.equal(a.arm['trusted|open'].Layout, 'overlap');
  assert.equal(a.cls['orig|trusted|open'].Layout, 'deterministic');
  assert.deepEqual(a.refused['orig|trusted'].map((r) => r.outcome), ['noUp']);
  assert.equal(a.facts['orig|trusted'].trusted, 9);
  assert.equal(a.facts['orig|synthetic'].trusted, 0);
  assert.equal(a.facts['orig|trusted'].morphMax, 1);
  const md = macMd(a);
  for (const h of ['Pushes seen by the page', 'open phase', 'orig: synthetic vs trusted', 'trusted lower', 'refused']) assert.ok(md.includes(h), h);
  assert.equal(METRICS.length, 7);
});

test('rangesOfRun uses the rule on the recorded marks', () => {
  const r = runRecord(records({ idle: 12, open: 58 }), 130);
  assert.deepEqual(rangesOfRun(r), { idle: [0, 12], open: [12, 70], close: [70, 130] });
  assert.equal(rangesOfRun({ ...r, up: null }), null);
});
