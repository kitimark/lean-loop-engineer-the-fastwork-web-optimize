import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readingOf, brief, waitQuiet, measurePass, runCells, summarize, localArms, cadenceOf } from '../src/safari-local-run.mjs';
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
  const r = await waitQuiet({ read: async () => { reads++; return loudR(); }, waitMs: 100, everyMs: 30, wait: async (ms) => { t += ms; }, now: () => t });
  assert.equal(r.loadCenti, 900);
  assert.ok(reads >= 4 && reads <= 6, `reads ${reads}`);
  reads = 0;
  await waitQuiet({ read: async () => { reads++; return quietR(); }, waitMs: 100, everyMs: 30, wait: async () => {}, now: () => 0 });
  assert.equal(reads, 1);
});

test('measurePass: accept keeps the value, a loud start never runs the window, a loud end drops the value', async () => {
  const wait = async () => {};
  let ran = 0;
  const run = async () => { ran++; return { stat: { long: 1 } }; };
  const ok = await measurePass({ read: async () => quietR(), run, waitMs: 0, wait, now: () => 0 });
  assert.equal(ok.decision, 'accept'); assert.deepEqual(ok.value, { stat: { long: 1 } });
  ran = 0;
  const b = await measurePass({ read: async () => loudR(), run, waitMs: 0, wait, now: () => 0 });
  assert.equal(b.decision, 'refuse'); assert.equal(b.phase, 'before'); assert.equal(b.value, null); assert.equal(ran, 0);
  const seq = [quietR(), loudR()];
  const a = await measurePass({ read: async () => seq.shift(), run, waitMs: 0, wait, now: () => 0 });
  assert.equal(a.decision, 'refuse'); assert.equal(a.phase, 'after'); assert.equal(a.value, null); assert.deepEqual(a.why, ['load']);
  const late = [quietR(1000), quietR(1000 + 1801)];
  const s = await measurePass({ read: async () => late.shift(), run, waitMs: 0, wait, now: () => 0 });
  assert.equal(s.decision, 'stale');
});

const arms = [{ id: 'orig' }, { id: 'base' }, { id: 'hx' }];
const value = (long) => ({ frames: 100, ivs: [], stat: { frames: 100, long, skipped: long, p50: 167, p95: 200, mx: 300 }, profile: null });

test('runCells counts only accepted passes, interleaves arms by rotation and stops when every cell has its passes', async () => {
  const order = [];
  let n = 0;
  const reads = [];
  // every third machine read pair is loud: those passes are refused and run again in a later round
  const read = async () => { n++; return n % 6 === 0 ? loudR() : quietR(); };
  const rows = await runCells({
    engine: 'x', arms, windows: ['hero'], passes: 3, maxRounds: 9, read, waitMs: 0, wait: async () => {},
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
    engine: 'x', arms: [{ id: 'orig' }], windows: ['hero'], passes: 1, maxRounds: 3, read: async () => quietR(), waitMs: 0, wait: async () => {},
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
