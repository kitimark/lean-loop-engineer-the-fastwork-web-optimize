import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as S from '../src/smooth/reduce.mjs';
import { pageSink, slowOf, summariseTrace } from '../src/smooth/trace.mjs';
import { cellOf, hitchesOf, summary } from '../src/smooth/cadence-table.mjs';
import { intervalsOf, orderFor } from '../src/smooth/cadence.mjs';
import { byArm, differences, markdown } from '../src/smooth/table.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const golden = readFileSync(resolve(here, '../../contracts/golden/gate/smooth.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const ops = (op) => golden.filter((g) => g.op === op);
const arm = (a) => a.map(([frames, bad]) => ({ frames, bad }));

test('golden: the file holds every kind of case', () => {
  assert.equal(ops('constants').length, 1);
  assert.ok(ops('metrics').length >= 12);
  assert.ok(ops('lerp').length >= 10 && ops('verdict').length >= 8 && ops('quantile').length >= 6);
});

test('constants are the Lean ones', () => {
  const c = ops('constants')[0];
  assert.deepEqual([S.STALL_PM, S.STALL_DIV, S.JUMP_PM, S.REVERSE_PM, S.BAD_TENTHS, S.MIN_REPS],
    [c.stallPm, c.stallDiv, c.jumpPm, c.reversePm, c.badTenths, c.minReps]);
});

test('metrics, flat and flagged equal the golden for every case', () => {
  for (const g of ops('metrics')) {
    const m = S.metrics(g.frames);
    assert.deepEqual(m, g.out, g.case);
    assert.equal(S.flat(m), g.flat, g.case);
    assert.equal(S.flagged(m), g.flagged, g.case);
  }
});

test('lerp rounds down like Lean, including negative values and a descending driver', () => {
  for (const g of ops('lerp')) assert.equal(S.lerp(...g.args), g.out, JSON.stringify(g.args));
});

test('worst is the componentwise maximum, as in Lean', () => {
  const byCase = Object.fromEntries(ops('metrics').map((g) => [g.case, g.out]));
  for (const g of ops('worst')) assert.deepEqual(S.worst(byCase[g.a], byCase[g.b]), g.out, `${g.a}/${g.b}`);
});

test('quantile and median equal the golden, empty input gives null', () => {
  for (const g of ops('quantile')) assert.equal(S.quantile(g.xs, g.p), g.out, JSON.stringify(g));
  const all = ops('metrics');
  const med = ops('median').find((g) => g.cases.length > 0);
  assert.deepEqual(S.median(all.map((g) => g.out)), med.out);
  assert.equal(S.median([]), ops('median').find((g) => g.cases.length === 0).out);
});

test('repeats, rates and verdicts equal the golden', () => {
  for (const g of ops('rep')) assert.deepEqual(Object.values(S.repOf(g.ivs)), g.out, JSON.stringify(g.ivs));
  for (const g of ops('rate')) assert.equal(S.rate(g.frames, g.bad), g.out);
  for (const g of ops('verdict')) {
    const [a, b, aa1, aa2] = [g.a, g.b, g.aa1, g.aa2].map(arm);
    assert.equal(S.spread(aa1, aa2), g.spread);
    assert.equal(S.armRate(a), g.rateA);
    assert.equal(S.armRate(b), g.rateB);
    assert.equal(S.verdict(a, b, aa1, aa2), g.out);
  }
});

test('the verdict set covers first, second, same and insufficient', () => {
  assert.deepEqual([...new Set(ops('verdict').map((g) => g.out))].sort(), ['first', 'insufficient', 'same', 'second']);
});

const rb = (pid, id, state, ts, seq, tree) => ({ name: 'PipelineReporter', ph: 'b', pid, cat: 'cc', id2: { local: id }, ts, args: { frame_reporter: { state, frame_sequence: seq, layer_tree_host_id: tree } } });
const re = (pid, id, ts) => ({ name: 'PipelineReporter', ph: 'e', pid, cat: 'cc', id2: { local: id }, ts, args: {} });
const ev = (pid, name, tree) => ({ name, ph: 'I', pid, ts: 1, args: { layerTreeId: tree } });
const twoProcess = () => [
  { name: 'process_name', ph: 'M', pid: 1, args: { name: 'Browser' } }, { name: 'process_name', ph: 'M', pid: 2, args: { name: 'Renderer' } },
  rb(1, '0x1', 'STATE_DROPPED', 100, 7, 1), re(1, '0x1', 5000), rb(1, '0x2', 'STATE_DROPPED', 6000, 8, 1), re(1, '0x2', 9000),
  rb(1, '0x3', 'STATE_DROPPED', 9100, 9, 1), re(1, '0x3', 9900), rb(1, '0x4', 'STATE_PRESENTED_ALL', 10000, 10, 1), re(1, '0x4', 12000),
  ev(1, 'BeginFrame', 1), ev(1, 'DrawFrame', 1), ev(1, 'DroppedFrame', 1),
  rb(2, '0x5', 'STATE_PRESENTED_ALL', 1000, 11, 2), re(2, '0x5', 18000), rb(2, '0x6', 'STATE_PRESENTED_PARTIAL', 1000, 11, 2), re(2, '0x6', 19000),
  rb(2, '0x5', 'STATE_PRESENTED_ALL', 20000, 12, 2), re(2, '0x5', 38000), rb(2, '0x7', 'STATE_DROPPED', 20000, 12, 2), re(2, '0x7', 60000),
  rb(2, '0x5', 'STATE_DROPPED', 40000, 13, 2), re(2, '0x5', 70000), rb(2, '0x8', 'STATE_DROPPED', 40000, 13, 2), re(2, '0x8', 71000),
  rb(2, '0x5', 'STATE_NO_UPDATE_DESIRED', 80000, 14, 2), re(2, '0x5', 90000),
  ev(2, 'BeginFrame', 2), ev(2, 'BeginFrame', 2), ev(2, 'DrawFrame', 2), ev(2, 'DroppedFrame', 2), ev(2, 'DroppedFrame', 2),
  ev(2, 'BeginMainThreadFrame', 2), ev(2, 'BeginMainThreadFrame', 2), ev(2, 'BeginMainThreadFrame', 2),
  ev(3, 'BeginMainThreadFrame', 9), rb(3, '0x9', 'STATE_DROPPED', 1000, 99, 9), re(3, '0x9', 2000),
];

test('trace: the page sink is the renderer that began the most frames, not the browser or another renderer', () => {
  assert.deepEqual(pageSink(twoProcess()), { pid: 2, layerTree: 2 });
  assert.equal(pageSink([{ name: 'x', ph: 'X', pid: 1 }]), null);
});

test('trace: counts come from the page sink only (two-process fixture)', () => {
  const t = summariseTrace(twoProcess());
  assert.equal(t.sink.pid, 2);
  assert.equal(t.reporters, 7);
  assert.equal(t.frames, 4);
  assert.equal(t.presented, 1);
  assert.equal(t.dropped, 2);
  assert.equal(t.droppedAll, 1);
  assert.equal(t.noUpdate, 1);
  assert.deepEqual([t.BeginFrame, t.DrawFrame, t.DroppedFrame, t.BeginMainThreadFrame], [2, 1, 2, 3]);
  assert.equal(t.states.STATE_DROPPED, 3);
  assert.equal(t.presentedMax, 180);
  const all = twoProcess().filter((e) => e.name === 'PipelineReporter' && e.ph === 'b' && e.args.frame_reporter.state === 'STATE_DROPPED').length;
  assert.equal(all, 7);
});

test('trace: a trace without a renderer main thread has no sink and counts nothing', () => {
  const t = summariseTrace([rb(1, '0x1', 'STATE_DROPPED', 0, 1, 1), re(1, '0x1', 100)]);
  assert.equal(t.sink, null);
  assert.equal(t.frames, 0);
  assert.equal(t.dropped, 0);
});

test('trace: the slow table has a fixed set of rows, none capped, absent events are 0, other processes are left out', () => {
  const s = slowOf([
    { name: 'Layout', ph: 'X', pid: 2, dur: 40000 }, { name: 'Layout', ph: 'X', pid: 2, dur: 20000 }, { name: 'Layout', ph: 'X', pid: 2, dur: 1000 },
    { name: 'Paint', ph: 'X', pid: 2, dur: 14999 }, { name: 'ProxyMain::BeginMainFrame', ph: 'X', pid: 2, dur: 177000 }, { name: 'ProxyMain::BeginMainFrame', ph: 'X', pid: 2, dur: 3000 },
    { name: 'SoftwareImageDecodeTaskImpl::RunOnWorkerThread', ph: 'X', pid: 2, dur: 60000 }, { name: 'GpuImageDecodeTaskImpl::RunOnWorkerThread', ph: 'X', pid: 2, dur: 16000 },
    { name: 'Layout', ph: 'X', pid: 1, dur: 99000 }, { name: 'Decode', ph: 'B', pid: 2, dur: 90000 }, { name: 'Other', ph: 'X', pid: 2, dur: 90000 },
  ], { pid: 2, layerTree: 2 });
  assert.deepEqual(s.map((r) => r.name), ['BeginMainFrame', 'Paint', 'UpdateLayoutTree', 'Layout', 'image decode task']);
  assert.deepEqual(s.map((r) => [r.n, r.nLong, r.max]), [[2, 1, 1770], [1, 0, 150], [0, 0, 0], [3, 2, 400], [2, 2, 600]]);
  assert.deepEqual(s.find((r) => r.name === 'Layout').long, [400, 200]);
  assert.equal(slowOf([]).length, 5);
});

test('golden: hitches, hitch verdict, across, acrossDecisive and agreeNeeded equal the Lean values', () => {
  const c = ops('constants')[0];
  assert.deepEqual([S.HITCH_TENTHS, S.MIN_SAMPLES], [c.hitchTenths, c.minSamples]);
  for (const g of ops('hitches')) assert.equal(S.hitches(g.ivs), g.out, JSON.stringify(g.ivs));
  for (const g of ops('hitchVerdict')) assert.equal(S.hitchVerdict(g.a, g.b, g.aa1, g.aa2), g.out, JSON.stringify(g));
  for (const g of ops('across')) assert.equal(S.across(g.k, g.vs), g.out, JSON.stringify(g));
  for (const g of ops('agreeNeeded')) assert.equal(S.agreeNeeded(g.n), g.out, String(g.n));
  for (const g of ops('acrossDecisive')) assert.deepEqual([S.decisive(g.vs), S.acrossDecisive(g.vs)], [g.decisive, g.out], JSON.stringify(g));
  assert.deepEqual([...new Set(ops('acrossDecisive').map((g) => g.out))].sort(), ['first', 'insufficient', 'same', 'second']);
  assert.deepEqual([...new Set(ops('hitchVerdict').map((g) => g.out))].sort(), ['first', 'insufficient', 'same', 'second']);
  assert.deepEqual([...new Set(ops('across').map((g) => g.out))].sort(), ['first', 'insufficient', 'same', 'second']);
});

test('cadence table: hitches are the gaps of 60 ms or more with their scroll position', () => {
  const h = hitchesOf([{ arm: 'base', rep: 2, ivs: [167, 833, 599, 600], ys: [10, 20, 30, 40], loaf: [{ d: 76, block: 0, scripts: [] }] }]);
  assert.deepEqual(h.base.map((x) => [x.rep, x.i, x.ms, x.y]), [[2, 1, 83.3, 20]]);
  assert.deepEqual(h.orig, []);
});

test('cadence: intervals are tenths of ms between rAF times; the rep order rotates', () => {
  assert.deepEqual(intervalsOf([0, 16.7, 33.4, 100]), [167, 167, 666]);
  assert.deepEqual(orderFor(['a', 'b', 'c'], 0), ['a', 'b', 'c']);
  assert.deepEqual(orderFor(['a', 'b', 'c'], 1), ['b', 'c', 'a']);
  assert.deepEqual(orderFor(['a', 'b', 'c'], 3), ['a', 'b', 'c']);
});

test('cadence table: a cell takes its verdicts from the Lean-twin verdict over the base/aa pair', () => {
  const rep = (arm, rep, bad) => ({ width: 390, arm, window: 'end', rep, ivs: [...Array(100 - bad).fill(167), ...Array(bad).fill(500)] });
  const runs = [];
  for (let r = 0; r < 5; r++) {
    runs.push(rep('orig', r, 10), rep('base', r, 0), rep('aa', r, 0), rep('cand', r, 0));
  }
  const cell = cellOf('1', { runs, traces: [], search: '?x', hash: 'h', baseHash: 'b', version: 'v' }, 390, 'end');
  assert.equal(cell.spread, 0);
  assert.equal(cell.verdicts['orig|base'], 'second');
  assert.equal(cell.verdicts['base|cand'], 'same');
  assert.equal(cell.arms.orig.rate, 1000);
  const sum = summary([cell]);
  assert.equal(sum.find((e) => e.first === 'orig' && e.second === 'base').counts.second, 1);
  const few = cellOf('2', { runs: runs.filter((r) => r.rep < 3), traces: [] }, 390, 'end');
  assert.equal(few.verdicts['orig|base'], 'insufficient');
});

const rec = (run, arm, nodes) => ({ run, engine: 'chromium', width: 390, arm, ideal: 'line', window: 'hero', judgedNodes: Object.keys(nodes).length, flaggedNodes: 0, defectsPerPush: 0, tailPerPush: 0, nodes });
const nd = (stalls, jumps, tail, peakRatio = 1000) => ({ judged: 5, flagged: 0, stalls, jumps, reversals: 0, tail, tailT: 0, peakRatio });

test('table: byArm keeps a median and a range per node with the run ids; differences lists what is outside the original range', () => {
  const rows = byArm([
    rec('1', 'orig', { 'hero.copy': nd(1, 0, 0) }), rec('2', 'orig', { 'hero.copy': nd(1, 0, 0) }),
    rec('1', 'base', { 'hero.copy': nd(2, 2, 0), 'hero.stage': nd(0, 0, 0, 1099) }), rec('2', 'base', { 'hero.copy': nd(3, 2, 0) }),
  ]);
  const base = rows.find((r) => r.arm === 'base');
  assert.deepEqual(base.nodes['hero.copy'].runs, ['1', '2']);
  assert.equal(base.nodes['hero.copy'].defects, 4);
  assert.deepEqual(base.nodes['hero.copy'].defectsRange, [4, 5]);
  assert.equal(base.nodes['hero.stage'].moved, 1);
  assert.equal(base.nodes['hero.stage'].ofRuns, 2);
  assert.equal(base.nodes['hero.copy'].part, 'hero');
  const d = differences(rows, 'orig', (a) => a === 'base');
  assert.deepEqual(d.map((x) => [x.node, x.measure, x.dir]).sort(), [['hero.copy', 'defects', 'higher'], ['hero.stage', 'moved', 'arm moving']]);
  assert.match(markdown(rows), /hero\.stage \| hero\.exit \| orig \| 0 \/ 2/);
});

test('golden: the > 25 ms, 34 ms and 50 ms counts, the skipped slots and the window counts equal the Lean values', () => {
  const [k] = ops('missConstants');
  assert.equal(S.MISS_TENTHS, k.missTenths);
  assert.equal(S.FAIL_TENTHS, k.failTenths);
  for (const g of ops('over')) {
    assert.deepEqual({ frames: g.ivs.length, over25: S.over25(g.ivs), over34: S.over34(g.ivs), over50: S.over50(g.ivs), hitches: S.hitches(g.ivs) }, g.out, JSON.stringify(g.ivs));
    assert.equal(S.over34(g.ivs), S.repOf(g.ivs).bad);
    assert.ok(g.out.over50 <= g.out.over34 && g.out.over34 <= g.out.over25 && g.out.hitches <= g.out.over50);
  }
  for (const g of ops('skips')) {
    assert.deepEqual({ pairs: Math.max(0, g.ts.length - 1), skips: S.skips(g.ts), longGaps: S.longGaps(g.ts) }, g.out, JSON.stringify(g.ts));
    assert.ok(g.out.longGaps <= g.out.skips && g.out.skips <= g.out.pairs);
  }
  for (const g of ops('counts')) assert.deepEqual(S.countsOf(g.ivs, g.ts), g.out, JSON.stringify(g.ts));
  for (const g of ops('countsAdd')) assert.deepEqual(S.addCounts(g.a, g.b), g.out);
  assert.equal(ops('over').length + ops('skips').length + ops('counts').length + ops('countsAdd').length, 6 + 11 + 11 + 10);
});

test('hundredthsFrom keeps the exact times that the tenths of the intervals round away', () => {
  assert.deepEqual(S.hundredthsFrom([100, 116.67, 133.34, 150.01]), [0, 1667, 3334, 5001]);
  assert.equal(S.skips(S.hundredthsFrom([100, 116.67, 133.34, 150.01, 183.34])), 1);
});
