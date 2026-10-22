import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readingOf, brief, waitQuiet, measurePass, runCells, summarize, localArms, cadenceOf, takeBaseline } from '../src/safari-local-run.mjs';
import { tokenOf } from '../src/safari-local-lease.mjs';

const mem = (o = {}) => ({ freeMB: 4000, specMB: 0, purgMB: 0, fileMB: 3000, fileMinMB: 2900, swapUsedMB: 0, swapTotalMB: 4096, press: 1, comprMBPerMin: 0, swapOutMBPerMin: 0, ...o });
const status = (o = {}) => ({ sample: { time: 1000, loadCenti: 100, mem: mem(o.mem), ramMB: 16384, compressorMB: 500, cores: 8, ...o.sample }, holders: o.holders ?? [], queue: [] });
const quietR = (t = 1000) => readingOf({ ...status(), sample: { ...status().sample, time: t } });
const loudR = (t = 1000) => readingOf({ ...status({ sample: { loadCenti: 900 } }), sample: { ...status({ sample: { loadCenti: 900 } }).sample, time: t } });

test('readingOf counts holders other than my own tokens', () => {
  const s = status({ holders: [{ token: 'mine', owner: 'x' }, { token: 'other', owner: 'y' }] });
  assert.equal(readingOf(s, ['mine']).holders, 1);
  assert.equal(readingOf(s, []).holders, 2);
});

test('brief keeps numbers only', () => {
  const b = brief(readingOf(status({ holders: [{ token: 't' }] })));
  assert.deepEqual(Object.keys(b).sort(), ['availMB', 'comprMBPerMin', 'holders', 'load', 'press', 'queued', 'swapOutMBPerMin', 'time']);
  assert.equal(b.load, 1);
});

test('waitQuiet stops at the deadline on a loud machine and returns at once on a quiet one', async () => {
  let t = 0, reads = 0;
  const r = await waitQuiet({ floorCenti: 150, read: async () => { reads++; return loudR(); }, waitMs: 100, everyMs: 30, wait: async (ms) => { t += ms; }, now: () => t });
  assert.equal(r.loadCenti, 900);
  assert.ok(reads >= 4 && reads <= 6, `reads ${reads}`);
  reads = 0;
  await waitQuiet({ floorCenti: 150, read: async () => { reads++; return quietR(); }, waitMs: 100, everyMs: 30, wait: async () => {}, now: () => 0 });
  assert.equal(reads, 1);
});

test('measurePass: accept keeps the value, a loud start never runs the window, a loud end drops the value', async () => {
  const wait = async () => {};
  let ran = 0;
  const run = async () => { ran++; return { stat: { long: 1 } }; };
  const ok = await measurePass({ floorCenti: 150, read: async () => quietR(), run, waitMs: 0, wait, now: () => 0 });
  assert.equal(ok.decision, 'accept'); assert.deepEqual(ok.value, { stat: { long: 1 } });
  ran = 0;
  const b = await measurePass({ floorCenti: 150, read: async () => loudR(), run, waitMs: 0, wait, now: () => 0 });
  assert.equal(b.decision, 'refuse'); assert.equal(b.phase, 'before'); assert.equal(b.value, null); assert.equal(ran, 0);
  const seq = [quietR(), loudR()];
  const a = await measurePass({ floorCenti: 150, read: async () => seq.shift(), run, waitMs: 0, wait, now: () => 0 });
  assert.equal(a.decision, 'refuse'); assert.equal(a.phase, 'after'); assert.equal(a.value, null); assert.deepEqual(a.why, ['load']);
  const late = [quietR(1000), quietR(1000 + 1801)];
  const s = await measurePass({ floorCenti: 150, read: async () => late.shift(), run, waitMs: 0, wait, now: () => 0 });
  assert.equal(s.decision, 'stale');
});

const arms = [{ id: 'orig' }, { id: 'base' }, { id: 'hx' }];
const value = (long) => ({ frames: 100, ivs: [], stat: { frames: 100, long, skipped: long, p50: 167, p95: 200, mx: 300 }, profile: null });

test('runCells counts only accepted passes, interleaves arms by rotation and stops when every cell has its passes', async () => {
  const order = [];
  let n = 0;
  const reads = [];
  const read = async () => { n++; return n % 6 === 0 ? loudR() : quietR(); };
  const rows = await runCells({
    engine: 'x', arms, windows: ['hero'], passes: 3, maxRounds: 9, read, floorCenti: 150, waitMs: 0, wait: async () => {},
    readWindow: async (a, w, round) => { order.push(`${round}:${a}`); return value(a === 'hx' ? 5 : 1); }, onRow: (r) => reads.push(r),
  });
  const accepted = (a) => rows.filter((r) => r.arm === a && r.decision === 'accept').length;
  assert.deepEqual(['orig', 'base', 'hx'].map(accepted), [3, 3, 3]);
  assert.deepEqual(order.slice(0, 3), ['0:orig', '0:base', '0:hx']);
  assert.ok(order.includes('1:base') && order.indexOf('1:base') < order.indexOf('1:orig'), 'round 1 starts with base');
  assert.equal(reads.length, rows.length);
  assert.ok(rows.some((r) => r.decision === 'refuse'));
  for (const r of rows.filter((x) => x.decision !== 'accept')) assert.equal(r.ivs, undefined, 'a refused pass carries no values');
});

test('runCells records an error row and calls onError', async () => {
  let calls = 0, repaired = 0;
  const rows = await runCells({
    engine: 'x', arms: [{ id: 'orig' }], windows: ['hero'], passes: 1, maxRounds: 3, read: async () => quietR(), floorCenti: 150, waitMs: 0, wait: async () => {},
    readWindow: async () => { if (calls++ === 0) throw new Error('boom'); return value(0); }, onError: async () => { repaired++; },
  });
  assert.deepEqual(rows.map((r) => r.decision), ['error', 'accept']);
  assert.equal(repaired, 1);
});

test('summarize: medians of accepted passes and a verdict against the default arm', () => {
  const mk = (arm, long, n) => Array.from({ length: n }, (_, i) => ({ engine: 'sim', window: 'hero', arm, round: i, decision: 'accept', stat: { long: long + i, skipped: long, p50: 167, p95: 200, mx: 300 } }));
  const rows = [...mk('base', 10, 3), ...mk('hx', 2, 3), ...mk('mp', 30, 3), ...mk('pf', 10, 2), { engine: 'sim', window: 'hero', arm: 'hx', round: 9, decision: 'refuse', phase: 'before', why: ['load'] }];
  const s = Object.fromEntries(summarize(rows).map((r) => [r.arm, r]));
  assert.equal(s.hx.vsBaseLong, 'better');
  assert.equal(s.mp.vsBaseLong, 'worse');
  assert.equal(s.pf.vsBaseLong, 'insufficient');
  assert.equal(s.base.vsBaseLong, null);
  assert.equal(s.hx.refused.before, 1);
  assert.equal(s.hx.passes, 3);
  assert.equal(s.base.long, 11);
});

test('localArms: the original and the four rewrite arms, none dropped', () => {
  const a = localArms('/site');
  assert.deepEqual(a.arms.map((x) => x.id), ['orig', 'base', 'hx', 'mp', 'pf']);
  assert.deepEqual(a.dropped, []);
  assert.deepEqual(a.flags.hx, ['hero.exit:threaded']);
  assert.equal(a.arms[0].tree.dir, null);
});

test('cadenceOf reduces intervals with Lean stat', () => {
  const c = cadenceOf([0, 1, 2, 3], () => [167, 167, 400]);
  assert.equal(c.stat.long, 1);
  assert.equal(c.frames, 4);
});

test('tokenOf reads the token from the acquire output', () => {
  assert.equal(tokenOf('noise\n{"token":"abc-123","kind":"sim"}\n'), 'abc-123');
  assert.equal(tokenOf('acquired 08cadf75-6d9 sim'), '08cadf75-6d9');
  assert.equal(tokenOf('nothing'), null);
});

const steadyR = (t, load = 340) => readingOf({ ...status(), sample: { ...status().sample, time: t, loadCenti: load } });

test('takeBaseline returns the median of a steady window and keeps reading until one exists', async () => {
  let t = 1000, n = 0;
  const loads = [900, 800, 700, 600, 500, 450, 400, 350, 340, 340, 340, 340, 340, 340, 340, 340];
  const read = async () => steadyR(t, loads[Math.min(n++, loads.length - 1)]);
  const wait = async (ms) => { t += ms / 1000; };
  const b = await takeBaseline({ read, everyMs: 10000, waitMs: 1e9, wait, now: () => t * 1000 });
  assert.equal(b.floorCenti, 340);
  assert.equal(b.readings.length, 8);
  assert.equal(n, 13, 'the first window with a spread of at most 150 is readings 6 to 13');
});

test('takeBaseline gives no floor when the machine never steadies, and the passes then do not run', async () => {
  let t = 1000, i = 0;
  const read = async () => steadyR(t, i++ % 2 ? 100 : 900);
  const b = await takeBaseline({ read, everyMs: 10000, waitMs: 120000, wait: async (ms) => { t += ms / 1000; }, now: () => t * 1000 });
  assert.equal(b.floorCenti, null);
  await assert.rejects(() => runCells({ engine: 'x', arms, read, floorCenti: b.floorCenti, readWindow: async () => value(0) }), /no idle floor/);
});

test('takeBaseline with a boot time ignores the readings of the settle period (Simulator)', async () => {
  let t = 1000;
  const read = async () => steadyR(t);
  const wait = async (ms) => { t += ms / 1000; };
  const b = await takeBaseline({ read, boot: 1000, everyMs: 10000, waitMs: 1e9, wait, now: () => t * 1000 });
  assert.equal(b.floorCenti, 340);
  assert.ok(b.readings.every((r) => r.time >= 1000 + 120), 'every reading of the window is at least 120 s after the boot');
  assert.ok(t >= 1000 + 120 + 70, 'the first baseline came after the settle period and a window of eight readings');
});

test('a pass is refused above the measured floor plus the margin and accepted at it', async () => {
  const wait = async () => {};
  const run = async () => ({ stat: { long: 0 } });
  const at = (load) => async () => steadyR(1000, load);
  const ok = await measurePass({ floorCenti: 340, read: at(440), run, waitMs: 0, wait, now: () => 0 });
  assert.equal(ok.decision, 'accept');
  const no = await measurePass({ floorCenti: 340, read: at(441), run, waitMs: 0, wait, now: () => 0 });
  assert.equal(no.decision, 'refuse');
  assert.deepEqual(no.why, ['load']);
});

import { holdMeasureSlot } from '../src/safari-local-lease.mjs';

const fakeFw = (codes = {}) => {
  const calls = [];
  const fw = async (cwd, args) => {
    calls.push(args.join(' '));
    const c = codes[args[0] === 'pass' ? `pass ${args[1]}` : args[0]];
    if (c) { const e = new Error(`exit ${c}`); e.code = c; throw e; }
    return { stdout: args[0] === 'acquire' ? '{"token":"abcd1234-ef0"}\n' : '' };
  };
  return { fw, calls };
};

test('a macOS lane holds a measure slot and starts and stops a pass through fw slot pass', async () => {
  const { fw, calls } = fakeFw();
  const l = await holdMeasureSlot({ cwd: '.', fw, renewEveryS: 3600, nextS: 30 });
  assert.match(calls[0], /^acquire --kind measure --lease 3600 .* --next 30 --json$/);
  assert.equal(await l.pass.start(900, 60), true);
  assert.match(calls[1], /^pass start --token abcd1234-ef0 --for 900 --wait 60 /);
  await l.pass.stop(45);
  assert.match(calls[2], /^pass stop --token abcd1234-ef0 --next 45 /);
  await l.pass.stop(45);
  assert.equal(calls.length, 3);
  await l.release();
  assert.match(calls.at(-1), /^release --token abcd1234-ef0/);
});

test('a pass that waits out returns false, a lost lease throws, and release ends a live pass first', async () => {
  const w = fakeFw({ 'pass start': 75 });
  const a = await holdMeasureSlot({ cwd: '.', fw: w.fw, renewEveryS: 3600 });
  assert.equal(await a.pass.start(), false);
  await a.release();
  const g = fakeFw({ 'pass start': 1 });
  const b = await holdMeasureSlot({ cwd: '.', fw: g.fw, renewEveryS: 3600 });
  await assert.rejects(() => b.pass.start(), /pass start failed/);
  await b.release();
  const ok = fakeFw();
  const c = await holdMeasureSlot({ cwd: '.', fw: ok.fw, renewEveryS: 3600 });
  await c.pass.start();
  await c.release();
  const tail = ok.calls.slice(-2);
  assert.match(tail[0], /^pass stop /);
  assert.match(tail[1], /^release /);
});

test('measurePass runs inside the slot pass and stops it on success, refusal and throw', async () => {
  const ev = [];
  const pass = { start: async () => { ev.push('start'); return true; }, stop: async () => { ev.push('stop'); } };
  const calm = quietR();
  const mk = (run) => measurePass({ read: async () => calm, run, floorCenti: 150, waitMs: 0, everyMs: 1, wait: async () => {}, now: () => 0, pass });
  const a = await mk(async () => { ev.push('run'); return { v: 1 }; });
  assert.equal(a.decision, 'accept');
  assert.deepEqual(ev, ['start', 'run', 'stop']);
  ev.length = 0;
  await assert.rejects(() => mk(async () => { throw new Error('x'); }), /x/);
  assert.deepEqual(ev, ['start', 'stop']);
  ev.length = 0;
  await assert.rejects(() => measurePass({ read: async () => calm, run: async () => ({}), floorCenti: 150, waitMs: 0, pass: { start: async () => false, stop: async () => ev.push('stop') } }), /no exclusive pass/);
  assert.deepEqual(ev, [], 'no window ran and no stop was needed');
});
