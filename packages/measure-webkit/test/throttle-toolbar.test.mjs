import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  ARMS, ARM_ORDER, FLAG_ARMS, LOOK_CHANGE, stepFrames, stepGaps, medianCs, stepsLifted, frameGapCs, windowCost, rowsOf, gestureCount, perGesture, onsetFrames, refreshHz, foldOf, tbPass,
  columns, columnsKnown, armVerdict, flagVerdict, enters, winPhase, reasonOf, passOf, facts, hzOf,
} from '../src/throttle/toolbar.mjs';
import { opens } from '../src/throttle/morph-end.mjs';
import { armsOf, jobsOf, planOf, overrideOf } from '../src/throttle/toolbar-plan.mjs';
import { reportMd, flagRow, armRow } from '../src/throttle/toolbar-report.mjs';
import { windowWatcher } from '../src/throttle/toolbar-probe.mjs';
import { START_TB_JS, FETCH_TB_JS, COUNT_TB_JS } from '../src/throttle/toolbar-page.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const gold = readFileSync(join(here, '../../contracts/golden/device/morph-end-count.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => gold.filter((l) => l.kind === kind);

test('golden: every toolbar kind has lines', () => {
  for (const k of ['tb-steps', 'tb-gestures', 'tb-onsets', 'tb-pass', 'tb-verdict', 'tb-hz', 'tb-win', 'tb-cost']) assert.ok(of(k).length > 0, k);
});

test('golden: vh steps, their burst gaps, the median and the lifted call', () => {
  for (const g of of('tb-steps')) {
    const fs = stepFrames(g.vh);
    assert.deepEqual(fs, g.frames, g.name);
    const gaps = stepGaps(g.t, fs);
    assert.deepEqual(gaps, g.gaps, g.name);
    assert.equal(medianCs(gaps), g.median, g.name);
    assert.equal(frameGapCs(g.t), g.frameCs, g.name);
    assert.equal(stepsLifted(frameGapCs(g.t), gaps), g.lifted, g.name);
  }
});

test('golden: gestures of a record and the frames in each', () => {
  for (const g of of('tb-gestures')) {
    assert.equal(gestureCount(g.g), g.count, g.name);
    assert.deepEqual(perGesture(g.g, g.frames), g.per, g.name);
  }
});

test('golden: fade onsets are the rises of the morph, as many as the opens', () => {
  for (const g of of('tb-onsets')) {
    assert.deepEqual(onsetFrames(g.r), g.frames, JSON.stringify(g.r));
    assert.equal(onsetFrames(g.r).length, opens(g.r));
    assert.equal(opens(g.r), g.opens);
  }
});

test('golden: the Lean pass record of a recorder record', () => {
  for (const g of of('tb-pass')) assert.deepEqual(tbPass(g.t, g.vh, g.r, g.d, g.g, g.reversals, g.layout, g.recalc, g.frames), g.pass, g.name);
});

test('golden: the comparison columns, the look, and the verdict of a flag', () => {
  for (const g of of('tb-verdict')) {
    const c = columns(g.base, g.cand);
    assert.equal(c.reversals, g.reversals, g.name);
    assert.equal(c.swaps, g.swaps, g.name);
    assert.equal(c.onsets, g.onsets, g.name);
    assert.equal(c.layout, g.layout, g.name);
    assert.equal(c.recalc, g.recalc, g.name);
    assert.equal(c.lifted, g.lifted, g.name);
    assert.equal(c.look, g.look, g.name);
    assert.equal(c.costKnown, g.costKnown, g.name);
    const v = flagVerdict(g.base, g.cand);
    assert.equal(v, g.verdict, g.name);
    assert.equal(enters(false, v), g.entersPlain, g.name);
    assert.equal(enters(true, v), g.entersLook, g.name);
  }
});

test('the printed columns: a side with no rate reads undecided, every other cell is the golden one, and the verdict is unchanged', () => {
  let undecided = 0;
  for (const g of of('tb-verdict')) {
    const c = columnsKnown(g.base, g.cand);
    for (const k of ['reversals', 'swaps', 'onsets', 'layout', 'recalc']) {
      if (c[k] === 'undecided') {
        undecided++;
        assert.equal(g[k], 'overlap', `${g.name} ${k}`);
      } else assert.equal(c[k], g[k], `${g.name} ${k}`);
    }
    const lay = c.costKnown ? c.layout : 'overlap', rec = c.costKnown ? c.recalc : 'overlap';
    const v = armVerdict(c.reversals, c.swaps, c.onsets, lay, rec, c.lifted, c.look);
    assert.equal(!c.costKnown && v === 'win' ? 'undecided' : v, g.verdict, g.name);
  }
  assert.ok(undecided > 0);
  const none = of('tb-verdict').find((g) => g.name === 'no candidate pass');
  assert.deepEqual(['reversals', 'swaps', 'onsets', 'layout', 'recalc'].map((k) => columnsKnown(none.base, none.cand)[k]), Array(5).fill('undecided'));
});

test('golden: the refresh rate and the unthrottle fold', () => {
  for (const g of of('tb-hz')) {
    assert.equal(refreshHz(g.gapCs), g.hz, `gap ${g.gapCs}`);
    assert.equal(foldOf(g.hz), g.fold, `gap ${g.gapCs}`);
  }
});

test('golden: the Timeline window phase', () => {
  for (const g of of('tb-win')) assert.equal(winPhase(g.g, g.inMs), g.phase, `${g.g} ${g.inMs}`);
});

test('the arms: one search per arm; the three mount flags and nobounce are look-change', () => {
  assert.deepEqual(ARM_ORDER, ['default', 'touch-first', 'open-once', 'unthrottle', 'overscroll-lock', 'threaded', 'nobounce']);
  assert.equal(ARMS.nobounce, '?fw=morph.end.nobounce:on');
  assert.equal(ARMS.default, '');
  assert.equal(ARMS.unthrottle, '?fw=engine.scroll:unthrottle');
  assert.deepEqual([...LOOK_CHANGE].sort(), ['nobounce', 'open-once', 'overscroll-lock', 'touch-first']);
});

test('the plan: default first, ten jobs cover each flag arm four times, both positions', () => {
  const plan = planOf('');
  assert.equal(plan.length, 10);
  assert.ok(plan.every((a) => a[0] === 'default' && a.length === 3 && a[1] !== a[2]));
  for (const arm of FLAG_ARMS.filter((a) => a !== 'nobounce')) {
    assert.equal(plan.filter((a) => a.includes(arm)).length, 4, arm);
    assert.ok(plan.some((a) => a[1] === arm) && plan.some((a) => a[2] === arm), `${arm} in both positions`);
  }
});

test('the plan override replaces the plan and sets the job count', () => {
  const m = 'toolbar [ci:toolbar-throttle] [throttle:toolbar] [toolbar-plan:threaded+unthrottle,open-once]';
  assert.deepEqual(overrideOf(m), [['threaded', 'unthrottle'], ['open-once']]);
  assert.equal(jobsOf(m), 2);
  assert.deepEqual(armsOf(2, m), ['default', 'open-once']);
  assert.equal(jobsOf(`${m} [toolbar-top:4]`), 4);
  assert.throws(() => armsOf(3, m), /no entry for job 3/);
  assert.throws(() => armsOf(1, '[toolbar-plan:nope]'), /unknown arm nope/);
  assert.equal(overrideOf('plain'), null);
});

function record({ every = 6, open = [3, 21], n = 60, extra = {} } = {}) {
  const t = [], y = [], mx = [], o = [], r = [], d = [], g = [], ih = [], vh = [];
  for (let i = 0; i < n; i++) {
    t.push(i * 16.67);
    y.push(50000 + i * 30); mx.push(52000);
    const on = open.some((s) => i >= s && i < s + 6);
    o.push(on ? 1 : 0); r.push(on ? 600 : 0);
    d.push(i < 20 ? -1 : 1); g.push(Math.floor(i / 20) + 1);
    ih.push(7750); vh.push(7750 + Math.floor(i / every) * 10);
  }
  return { start: { ih: 7750, vh: 7750, y: 5000, scale: 1 }, nav: true, frames: n, t, y, mx, o, r, d, g, ih, vh, ca: [], hz: Array.from({ length: 40 }, (_, i) => i * 16.67), wobble: 0, moves: 30, total: n, ...extra };
}
const pass = (arm, job, rec = record(), cost = { layout: 12, recalc: 20, frames: 600, counts: true }) => ({ arm, job, rec, cost, drag: { code: 0 } });

test('a pass: the Lean record from the recorder arrays, the cost window folded in', () => {
  const p = passOf(pass('default', 'job 1'));
  assert.equal(p.gestures, 3);
  assert.equal(p.onsets, 2);
  assert.equal(p.onsetGestures, 2);
  assert.equal(p.frames, 600);
  assert.deepEqual([p.layout, p.recalc], [12, 20]);
  assert.ok(p.gaps.every((x) => x > 9000), 'throttled cadence in hundredths of ms');
  const none = passOf({ ...pass('default', 'job 1'), cost: { layout: 5, recalc: 5, frames: 0, error: 'stop timed out' } });
  assert.deepEqual([none.layout, none.recalc, none.frames], [0, 0, 0]);
  assert.equal(facts(pass('default', 'job 1')).steps, 9);
});

test('a record without gesture reads is not counted', () => {
  const rec = record();
  delete rec.g;
  assert.equal(reasonOf({ arm: 'default', rec, drag: { code: 0 } }), 'record has no gesture reads');
  assert.equal(reasonOf(pass('default', 'job 1')), null);
});

test('the refresh rate of idle frames', () => {
  assert.equal(hzOf(Array.from({ length: 40 }, (_, i) => i * 16.67)), 60);
  assert.equal(hzOf(Array.from({ length: 40 }, (_, i) => i * 8.33)), 120);
  assert.equal(hzOf([]), 0);
});

const costOf = (layout, recalc) => ({ layout, recalc, frames: 600, counts: true });
const none = { layout: 0, recalc: 0, frames: 0, counts: true };
const jobsOfPasses = (n, cand, base) => Array.from({ length: n }, (_, i) => ({
  vm: `job ${i + 1}`,
  passes: [pass('default', `job ${i + 1}`, record({ extra: { total: 60 + i } }), base(i)), pass('unthrottle', `job ${i + 1}`, record({ every: 1 }), cand(i))],
}));

test('the report: per-frame steps of unthrottle with three cost windows per side and higher costs are a trade', () => {
  const vms = jobsOfPasses(3, (i) => costOf(300 + i, 500 + i), (i) => costOf(12 + i, 20 + i));
  const k = flagRow('unthrottle', vms.flatMap((v) => v.passes.map((p) => ({ ...p, job: v.vm }))));
  assert.equal(k.verdict, 'trade');
  assert.equal(k.cols.layout, 'higher');
  assert.equal(k.cols.lifted, true);
  assert.equal(k.cols.costKnown, true);
  assert.equal(k.enters, false);
  const md = reportMd(vms);
  assert.match(md, /\| engine\.scroll:unthrottle \| plain \| 3 \| 3 \| 3 \|/);
  assert.match(md, /\| unthrottle \| 3 \(3\) \|/);
  assert.match(md, /per frame/);
  assert.match(md, /## Not measured here \(task toolbar-cost-sample\)/);
  assert.match(md, /does not detect touch-first's designed change of the first push/);
});

test('the report: a lifted cadence without three cost windows per side is undecided and never enters', () => {
  for (const [name, base, cand] of [
    ['two windows each', () => costOf(12, 20), () => costOf(13, 21)],
    ['empty cost base', () => none, () => costOf(13, 21)],
  ]) {
    const vms = jobsOfPasses(name === 'two windows each' ? 2 : 3, cand, base);
    const k = flagRow('unthrottle', vms.flatMap((v) => v.passes.map((p) => ({ ...p, job: v.vm }))));
    assert.equal(k.cols.costKnown, false, name);
    assert.equal(k.verdict, 'undecided', name);
    assert.equal(k.enters, false, name);
    assert.match(reportMd(vms), /undecided \(cost not measured\)/, name);
  }
});

test('the report: a flag with no default pass beside it has no data, a look-change arm never enters', () => {
  const k = flagRow('open-once', [pass('open-once', 'job 1')]);
  assert.equal(k.verdict, 'no-data');
  assert.equal(k.enters, false);
  assert.equal(armRow([]).usable, 0);
  assert.match(reportMd([{ vm: 'job 3', passes: [] }]), /Jobs with no pass: job 3/);
});

test('the page scripts name the counters the reducers read', () => {
  assert.match(START_TB_JS, /st\.gc\+\+; console\.timeStamp\('tbg' \+ st\.gc\)/);
  assert.match(START_TB_JS, /console\.timeStamp\('tbf'\)/);
  assert.match(START_TB_JS, /st\.gc\+\+/);
  assert.match(START_TB_JS, /st\.g\.push\(st\.gc\)/);
  assert.match(FETCH_TB_JS, /g: st\.g\.slice\(0, n\)/);
  assert.match(COUNT_TB_JS, /nf: st\.nf/);
});

function fakeClient(counts) {
  let i = 0;
  return { evaluate: async () => JSON.stringify(counts[Math.min(i++, counts.length - 1)]) };
}

const stampRows = () => [
  ['Layout', 0.5, 0.6, null],
  ['TimeStamp', 1, 1, 'tbg4'], ['TimeStamp', 1.1, 1.1, 'tbf'], ['Layout', 1.2, 1.3, null], ['Layout', 1.3, 1.4, null], ['TimeStamp', 1.4, 1.4, 'tbf'],
  ['RecalculateStyles', 1.5, 1.6, null], ['Paint', 1.6, 1.7, null], ['TimeStamp', 2, 2, 'tbg5'], ['Layout', 2.1, 2.2, null],
];

test('Lean windowCost on the rows of a Timeline: stamps of gesture 4 and 5 bound the count', () => {
  assert.deepEqual(windowCost(4, rowsOf(stampRows())), { layout: 2, recalc: 1, frames: 2 });
  assert.equal(windowCost(4, rowsOf(stampRows().slice(0, 8))), null);
  assert.equal(windowCost(4, rowsOf(stampRows().slice(3))), null);
  assert.equal(windowCost(4, []), null);
});

test('golden: the cost between the stamps of a gesture', () => {
  for (const g of of('tb-cost')) assert.deepEqual(windowCost(g.g, g.rows), g.cost, g.name);
});

test('the window watcher opens at gesture 2, closes at gesture 5 and keeps the counts of gesture 4', async () => {
  const log = [];
  let clock = 0;
  const tl = { stop: async () => stampRows() };
  const c = fakeClient([{ g: 1, nf: 10 }, { g: 2, nf: 100 }, { g: 3, nf: 130 }, { g: 4, nf: 160 }, { g: 5, nf: 190 }, { g: 5, nf: 190 }]);
  const w = windowWatcher(c, { log: (s) => log.push(s), tag: 't' }, { sleep: async () => { clock += 250; }, now: () => clock, startTimeline: async () => tl });
  await w.done;
  assert.deepEqual([w.state.cost.layout, w.state.cost.recalc, w.state.cost.frames], [2, 1, 2]);
  assert.equal(w.state.cost.why, 'next gesture');
  assert.equal(w.state.cost.counts, true);
  assert.equal(w.state.cost.g0, 2);
  assert.equal(w.state.cost.g1, 5);
});

test('the window watcher flags a window whose stamps are missing, and the pass drops its cost', async () => {
  let clock = 0;
  const tl = { stop: async () => stampRows().slice(0, 8) };
  const c = fakeClient([{ g: 3, nf: 1 }, { g: 5, nf: 2 }]);
  const w = windowWatcher(c, { log() {}, tag: 't' }, { sleep: async () => { clock += 250; }, now: () => clock, startTimeline: async () => tl });
  await w.done;
  assert.equal(w.state.cost.counts, false);
  assert.equal(w.state.cost.frames, 0);
  const q = passOf({ ...pass('default', 'job 1'), cost: w.state.cost });
  assert.deepEqual([q.layout, q.recalc, q.frames], [0, 0, 0]);
  assert.equal(armRow([{ ...pass('default', 'job 1'), cost: w.state.cost }]).overran, 1);
});

test('the window watcher keeps no counts when the stop fails, and misses a window it saw too late', async () => {
  const bad = fakeClient([{ g: 2, nf: 1 }, { g: 5, nf: 2 }, { g: 5, nf: 2 }]);
  const w = windowWatcher(bad, { log() {}, tag: 't' }, { sleep: async () => {}, now: () => 0, startTimeline: async () => ({ stop: async () => { throw new Error('Timeline.stop timed out'); } }) });
  await w.done;
  assert.equal(w.state.cost.frames, 0);
  assert.match(w.state.cost.error, /timed out/);
  const late = fakeClient([{ g: 4, nf: 1 }]);
  const w2 = windowWatcher(late, { log() {}, tag: 't' }, { sleep: async () => {}, now: () => 0, startTimeline: async () => { throw new Error('must not start'); } });
  await w2.done;
  assert.match(w2.state.cost.note, /missed/);
});

test('the window watcher closes an open window when the touches end', async () => {
  const c = fakeClient([{ g: 2, nf: 5 }, { g: 3, nf: 40 }]);
  let calls = 0;
  const w = windowWatcher(c, { log() {}, tag: 't' }, {
    sleep: async () => { if (++calls === 3) w.state.stop = true; }, now: () => 0, startTimeline: async () => ({ stop: async () => [['Layout', 1, 2, null]] }),
  });
  await w.done;
  assert.equal(w.state.cost.why, 'touches ended');
  assert.equal(w.state.cost.rows, 1);
  assert.equal(w.state.cost.counts, false);
});
