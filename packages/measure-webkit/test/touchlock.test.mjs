import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { fights, reversals, openCalls, cmp, look, cmpKnown, lockedCmp, traceCounts, lookKnown, known, MIN_SAMPLES, reduce, refusal, tally, summarize, markdown, MIN_OPEN_FRAMES, MAX_RESTARTS, openPhase, repOrder, afterWindow, serveTag, lockOf, windowsOf, ARMS, RANKED_TEXT } from '../src/touchlock.mjs';
import { restartServer, armTrees, armPath } from '../src/touchlock-run.mjs';
import { installJs, nearEndJs, windowJs } from '../src/touchlock-page.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const golden = readFileSync(join(HERE, '../../contracts/golden/measure/touch-lock.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const ops = (op) => golden.filter((g) => g.op === op);
const runOf = (g) => ({ frames: g.frames, events: g.events, calls: g.calls });

test('constants match the golden', () => {
  assert.equal(ops('constants')[0].minOpenFrames, MIN_OPEN_FRAMES);
  assert.equal(ops('constants')[0].maxRestarts, MAX_RESTARTS);
  assert.equal(ops('constants')[0].minSamples, MIN_SAMPLES);
});

test('run cases: refusal and reduction replay the golden', () => {
  assert.ok(ops('run').length >= 8);
  for (const g of ops('run')) {
    assert.equal(refusal(runOf(g)), g.refusal, g.case);
    assert.deepEqual(reduce(runOf(g)), g.result, g.case);
  }
});

test('cmp and look cases replay the golden', () => {
  for (const g of ops('cmp')) assert.equal(cmp(g.faith, g.cand), g.out, g.case);
  for (const g of ops('look')) assert.equal(look(g.faith, g.cand), g.out, g.case);
});

test('cmpKnown and lookKnown replay the golden: a side below the floor is undecided, never a win', () => {
  assert.ok(ops('cmpKnown').length >= 7 && ops('lookKnown').length >= 7);
  for (const g of ops('cmpKnown')) assert.equal(cmpKnown(g.faith, g.cand), g.out, g.case);
  for (const g of ops('lookKnown')) assert.equal(lookKnown(g.faith, g.cand), g.out, g.case);
});

test('with complete evidence cmpKnown and lookKnown equal cmp and look (cmpKnown_of_known, lookKnown_of_known)', () => {
  for (const g of [...ops('cmp'), ...ops('look'), ...ops('cmpKnown'), ...ops('lookKnown')].filter((x) => known(x.faith, x.cand))) {
    assert.equal(cmpKnown(g.faith, g.cand), cmp(g.faith, g.cand), g.case);
    assert.equal(lookKnown(g.faith, g.cand), look(g.faith, g.cand), g.case);
  }
});

test('a side shorter than the floor reads undecided in cmpKnown and lookKnown', () => {
  const xs = (n) => Array.from({ length: n }, () => 0);
  for (let a = 0; a <= MIN_SAMPLES + 1; a++) for (let b = 0; b <= MIN_SAMPLES + 1; b++) {
    const short = a < MIN_SAMPLES || b < MIN_SAMPLES;
    assert.equal(cmpKnown(xs(a), xs(b)) === 'undecided', short, `${a} ${b}`);
    assert.equal(lookKnown(xs(a), xs(b)) === 'undecided', short, `${a} ${b}`);
  }
});

test('tally replays the golden', () => {
  for (const g of ops('tally')) assert.deepEqual(tally(g.runs), { accepted: g.accepted, jitter: g.jitter }, g.case);
});

test('open phase is the first open stretch only', () => {
  assert.deepEqual(openPhase([[1, 0], [2, 1], [3, 1], [4, 0], [5, 1]]), [[2, 1], [3, 1]]);
});

const fight = ops('run').find((g) => g.case === 'restore after a displaced frame');
const steady = ops('run').find((g) => g.case === 'steady open phase');
const steadyLocked = { ...steady, calls: [[steady.frames[3][0], 1]] };
const rowOf = (arm, g) => ({ arm, frames: g.frames.map((f) => [...f, 0]), events: g.events.map((f) => [...f, 0]), calls: g.calls.map((f) => [...f, 0]) });

test('summarize: a lock arm that never leaves the lock is lower; the look class is change while the base is displaced', () => {
  const rows = [...Array(3).fill(0).flatMap(() => [rowOf('orig', fight), rowOf('base', fight), rowOf('lock', steadyLocked)]), { arm: 'lock', status: 'push:beginLate' }];
  const s = summarize(rows);
  assert.equal(s.arms.base.jitterRuns, 3);
  assert.equal(s.arms.lock.jitterRuns, 0);
  assert.equal(s.arms.lock.windows, 4);
  assert.equal(s.arms.lock.failed, 1);
  assert.equal(s.verdicts.lockVsBase.fights, 'lower');
  assert.equal(s.verdicts.baseVsOrig.fights, 'overlap');
  assert.equal(s.verdicts.look, 'change');
  assert.match(markdown(s), /look change/);
});

test('summarize: no fights anywhere is overlap and the same look', () => {
  const s = summarize([0, 1, 2].flatMap(() => ARMS.map((a) => rowOf(a, steadyLocked))));
  assert.equal(s.verdicts.lockVsBase.fights, 'overlap');
  assert.equal(s.verdicts.look, 'same');
});

test('summarize: an arm whose runs stored no lock reads n/a for every lock-defined count, never lower', () => {
  const s = summarize([0, 1, 2].flatMap(() => ARMS.map((a) => rowOf(a, steady))));
  assert.deepEqual(s.verdicts.lockVsBase, { fights: 'n/a', restores: 'n/a', eventFights: 'n/a' });
  assert.deepEqual(s.verdicts.pinVsBase, { fights: 'n/a', restores: 'n/a', eventFights: 'n/a' });
  assert.match(markdown(s), /pin vs base: fights n\/a, restores n\/a, event fights n\/a; pin vs orig: fights n\/a/);
});

test('summarize states the selection lockedCmp ranks: only runs where the arm wrote, per arm', () => {
  const rows = [...[0, 1, 2].flatMap(() => ARMS.map((a) => rowOf(a, steadyLocked))), rowOf('pin', steady), rowOf('pin', steady)];
  const s = summarize(rows);
  assert.deepEqual(s.verdicts.ranked.pin, { ranked: 3, runs: 5 });
  assert.deepEqual(s.verdicts.ranked.base, { ranked: 3, runs: 3 });
  const { base, pin } = s.arms;
  assert.equal(lockedCmp(base.fightRuns, pin.fightRuns), lockedCmp(base.fightRuns, pin.fightRuns.filter((k) => k[0] !== null)));
  const md = markdown(s);
  assert.ok(md.includes(RANKED_TEXT));
  assert.match(md, /orig 3 of 3, base 3 of 3, lock 3 of 3, pin 3 of 5/);
});

test('lockedCmp replays the Lean golden and never reads a verdict from an arm without a stored lock', () => {
  assert.ok(ops('lockedCmp').length >= 8);
  for (const g of ops('lockedCmp')) assert.equal(lockedCmp(g.faith, g.cand), g.out, g.case);
  assert.ok(ops('lockedCmp').some((g) => g.out === 'n/a') && ops('lockedCmp').some((g) => g.out === 'lower') && ops('lockedCmp').some((g) => g.out === 'undecided'));
});

test('traceCounts replays the Lean golden', () => {
  assert.ok(ops('pinTrace').length >= 5);
  for (const g of ops('pinTrace')) assert.deepEqual(traceCounts(g.names), g.counts, g.case);
});

test('a window with a pin trace shows its counts, a window without one shows none', () => {
  const entries = [['touch', 1, null, null, 1], ['moved', 2, 40, 0, 16], ['due', 3, null, 0, 120], ['reversal', 4, 40, 0, 200], ['inactive', 5, null, null, null]];
  const rows = [{ ...rowOf('pin', steady), rep: 0, pin: { seen: 9, entries } }, { ...rowOf('base', steady), rep: 0, pin: null }, { ...rowOf('pin', steady), rep: 1, pin: { seen: 0, entries: [] } }];
  const w = windowsOf(rows);
  assert.equal(w[0].pin.seen, 9);
  assert.deepEqual([w[0].pin.touches, w[0].pin.moved, w[0].pin.due, w[0].pin.reversal, w[0].pin.inactive, w[0].pin.ran], [1, 1, 1, 1, 1, true]);
  assert.equal(w[1].pin, null);
  assert.equal(w[2].pin.ran, false);
  const md = markdown(summarize(rows));
  assert.match(md, /\| window \| arm \| pin calls seen \|/);
  assert.match(md, /\| 1 \| pin \| 9 \| 1 \| 1 \| 1 \| 1 \| 0 \| 0 \| 0 \| 0 \| 1 \| yes \|/);
  assert.match(md, /\| 3 \| pin \| 0 \| 0 \| 0 \| 0 \| 0 \| 0 \| 0 \| 0 \| 0 \| 0 \| no \|/);
});

test('the page hook records pin entries; the window keeps those from its first touchstart to its stop', async () => {
  const listeners = {};
  const win = { scrollY: 0, scrollTo: () => {}, innerHeight: 800 };
  let t = 0;
  const doc = { querySelector: () => ({ style: { getPropertyValue: () => '0' } }), documentElement: { classList: { toggle: () => {} } }, createElement: () => ({}), head: { appendChild: () => {} } };
  const install = new Function('window', 'document', 'addEventListener', 'requestAnimationFrame', 'performance', `return ${installJs(false)}`);
  install(win, doc, (n, f) => { listeners[n] = f; }, () => 0, { now: () => t });
  t = 5; win.__fwPinTrace({ kind: 'pin', op: 'moved', y: 10, s: 0, dt: 16 });
  t = 20; win.__fwPinTrace({ kind: 'pin', op: 'write', y: 0, s: 0, dt: 130, write: 0 });
  t = 30; win.__fwPinTrace({ kind: 'push' });
  t = 40; win.__fwPinTrace({ kind: 'pin', op: 'due', at: 40, ms: 80, s: 0 });
  assert.equal(win.__tl.pinSeen, 3);
  assert.deepEqual(win.__tl.pin.map((e) => e[0]), ['moved', 'write', 'due']);
  assert.deepEqual(win.__tl.pin[1], ['write', 20, 0, 0, 0]);
  assert.deepEqual(win.__tl.pin[2], ['due', 40, null, 0, 80]);
});

test('summarize: an arm with no accepted run is undecided, not overlap or the same look', () => {
  const s = summarize([rowOf('base', fight), rowOf('base', fight), { arm: 'lock', status: 'push:beginLate' }]);
  assert.deepEqual(s.verdicts.lockVsBase, { fights: 'undecided', restores: 'undecided', eventFights: 'undecided' });
  assert.deepEqual(s.verdicts.baseVsOrig, { fights: 'undecided', restores: 'undecided' });
  assert.equal(s.verdicts.look, 'undecided');
  assert.match(markdown(s), /fights undecided, restores undecided, event fights undecided; base vs orig: fights undecided, restores undecided; look class of the candidate: undecided/);
});

test('page scripts parse', () => {
  for (const src of [installJs(false), installJs(true), nearEndJs(250), windowJs]) assert.doesNotThrow(() => new Function(`return ${src}`));
});

test('nearEndJs is invoked: it yields a promise of the end position', async () => {
  const win = { innerHeight: 800, scrollY: 0, scrollTo: ({ top }) => { win.scrollY = top; } };
  const doc = { documentElement: { scrollHeight: 5000 } };
  const run = new Function('window', 'document', 'setTimeout', `return ${nearEndJs(250)}`);
  const got = await run(win, doc, (f) => f());
  assert.deepEqual(got, { maxY: 4200, y: 3950, vh: 800 });
});

test('window order and lane decisions replay the golden', () => {
  assert.equal(ops('order').length, 4);
  assert.deepEqual(ops('order').map((g) => g.arms[0]), ['base', 'pin', 'base', 'pin']);
  for (const g of ops('order')) assert.deepEqual(repOrder(g.rep), g.arms, `rep ${g.rep}`);
  assert.equal(ops('lane').length, 5);
  for (const g of ops('lane')) assert.equal(afterWindow(g.used, g.stalled), g.out, `${g.used} ${g.stalled}`);
});

test('every rep runs the original last, so a stall cannot erase the faithful or candidate window', () => {
  for (let rep = 0; rep < 6; rep++) {
    const o = repOrder(rep);
    assert.equal(o[o.length - 1], 'orig');
    assert.deepEqual([...o].sort(), [...ARMS].sort());
  }
});

const run = (name) => ops('run').find((g) => g.case === name);

test('the lock is the site stored value, not the first open sample', () => {
  const end = run('overscroll first sample, lock stored at the end');
  assert.equal(end.frames.find((f) => f[1])[0], 53460);
  assert.equal(lockOf(runOf(end)), 52270);
  assert.equal(reduce(runOf(end)).frameFights, 3);
  assert.equal(reduce(runOf(run('overscroll first sample, lock stored at the other end'))).lock, 52360);
});

test('restore calls that disagree refuse the window; closed calls are ignored; no call means no lock and no fight', () => {
  assert.equal(refusal(runOf(run('restore calls disagree'))), 'lockMoved');
  assert.equal(lockOf(runOf(run('restore call before the morph opened'))), 5000);
  const none = reduce(runOf(run('drift and the site never restored')));
  assert.deepEqual([none.lock, none.frameFights, none.displacedFrames], [null, 0, 0]);
});

test('every restart gets a result-bundle tag no earlier server used', async () => {
  for (const g of ops('tag')) assert.equal(serveTag(g.restarts), g.tag);
  const tags = [];
  const touch = { driver: 'd', restarts: 0, server: null, on: true, why: null };
  const start = async (_d, o) => { tags.push(o.tag); return { tag: o.tag }; };
  tags.push(serveTag(0));
  for (let i = 0; i < MAX_RESTARTS; i++) await restartServer(touch, { udid: 'u', log: () => {}, push: {}, start });
  assert.deepEqual(tags, ['serve', 'serve-r1', 'serve-r2']);
  assert.equal(new Set(tags).size, tags.length);
  assert.equal(touch.server.tag, 'serve-r2');
});

test('a restart that fails ends the touch lane with its reason', async () => {
  const touch = { driver: 'd', restarts: 0, server: null, on: true, why: null };
  await restartServer(touch, { udid: 'u', log: () => {}, push: {}, start: async () => { throw new Error('xcodebuild: error: Existing file'); } });
  assert.equal(touch.on, false);
  assert.match(touch.why, /restart failed: xcodebuild: error: Existing file/);
});

test('the driver names the result bundle after the tag', () => {
  const src = readFileSync(join(HERE, '../src/throttle/driver.mjs'), 'utf8');
  assert.match(src, /serve\(driver[\s\S]*?'-resultBundlePath', join\(driver\.dir, `\$\{tag\}\.xcresult`\)/);
});

test('the scrollTo hook records the instant restore targets while recording and forwards every call', () => {
  const calls = [];
  const nav = { style: { getPropertyValue: () => '0.5' } };
  const win = { scrollY: 5227.04, scrollTo: (...a) => { calls.push(a); } };
  const doc = { querySelector: () => nav, documentElement: { classList: { toggle() {} } }, createElement: () => ({}), head: { appendChild() {} } };
  const fn = new Function('window', 'document', 'addEventListener', 'requestAnimationFrame', 'performance', `return ${installJs(false)}`);
  const got = fn(win, doc, () => {}, () => 0, { now: () => 7 });
  assert.equal(got.hook, true);
  win.scrollTo({ top: 1, behavior: 'instant' });
  win.__tl.on = true;
  win.scrollTo({ top: 5227.04, behavior: 'instant' });
  win.scrollTo({ top: 80, behavior: 'smooth' });
  win.scrollTo(0, 5);
  assert.deepEqual(win.__tl.ca, [[52270, 1, 7]]);
  assert.equal(calls.length, 4);
});

test('the hook reports false when the scrollTo assignment is ignored', () => {
  const win = { scrollY: 0 };
  Object.defineProperty(win, 'scrollTo', { value: () => {}, writable: false });
  const doc = { querySelector: () => null, documentElement: { classList: { toggle() {} } }, createElement: () => ({}), head: { appendChild() {} } };
  const fn = new Function('window', 'document', 'addEventListener', 'requestAnimationFrame', 'performance', `return ${installJs(false)}`);
  assert.equal(fn(win, doc, () => {}, () => 0, { now: () => 0 }).hook, false);
});

test('markdown carries the push failure reason and one line per window with its state', () => {
  const rows = [rowOf('base', fight), { arm: 'lock', rep: 0, status: 'push:pageLost' }, { arm: 'orig', rep: 0, status: 'refused:config' },
    { arm: 'lock', rep: 1, frames: [[1, 0, 0]], events: [], calls: [] }];
  const s = summarize(rows);
  assert.deepEqual(s.arms.lock.failures, { pageLost: 1 });
  assert.deepEqual(windowsOf(rows).map((w) => [w.arm, w.state, w.reason]), [['base', 'open', null], ['lock', 'push failed', 'pageLost'], ['orig', 'refused', 'config'], ['lock', 'refused', 'noOpen']]);
  const md = markdown(s);
  assert.match(md, /\| push failure reasons \|/);
  assert.match(md, /\| 2 \| lock \| 0 \| push failed \| pageLost \|/);
  assert.match(md, /\| 4 \| lock \| 1 \| refused \| noOpen \|/);
});

test('end-pin rows: the metric counts the Lean fights and reversals over the frames', () => {
  assert.ok(ops('pinPlay').length >= 11 && ops('pinFaith').length >= 1);
  for (const g of ops('pinPlay')) {
    assert.equal(fights(g.s, g.frames), g.fights, g.case);
    assert.equal(fights(g.s, g.frames), 0, g.case);
    assert.equal(reversals(g.frames), g.reversals, g.case);
  }
  for (const g of ops('pinFaith')) assert.equal(fights(g.s, g.frames), g.fights, g.case);
});

test('the lane has a pin arm served from the site build with the end-pin flag, and every run reports its open calls', () => {
  assert.ok(ARMS.includes('pin'));
  assert.deepEqual(armTrees('/site').pin, { dir: '/site', search: '?fw=morph.tween:end-pin' });
  for (const g of ops('run')) assert.equal(openCalls(runOf(g)), g.result.openCalls, g.case);
});

test('summarize: a pin arm that never writes has no open calls; it counts as unrestored, not as a win by itself', () => {
  const noWrite = { ...steady, calls: [] };
  const s = summarize([0, 1, 2].flatMap(() => [rowOf('orig', fight), rowOf('base', fight), rowOf('lock', steady), rowOf('pin', noWrite)]));
  assert.equal(s.arms.pin.unrestored, 3);
  assert.deepEqual(s.arms.pin.calls, [0, 0, 0]);
  assert.equal(s.arms.base.unrestored, 0);
  assert.equal(s.verdicts.pinVsBase.fights, 'n/a');
  assert.match(markdown(s), /pin vs base: fights n\/a/);
});

test('a window reloads the arm path: only the pin arm keeps its flag in the query, the others reload the root', () => {
  assert.deepEqual(ARMS.map((id) => armPath('/site', id)), ['/', '/', '/', '/?fw=morph.tween:end-pin']);
});
