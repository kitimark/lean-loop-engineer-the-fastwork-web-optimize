import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { cmp, look, cmpKnown, lookKnown, known, MIN_SAMPLES, reduce, refusal, tally, summarize, markdown, MIN_OPEN_FRAMES, MAX_RESTARTS, openPhase, repOrder, afterWindow, serveTag, lockOf, windowsOf, ARMS } from '../src/touchlock.mjs';
import { restartServer } from '../src/touchlock-run.mjs';
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
const rowOf = (arm, g) => ({ arm, frames: g.frames.map((f) => [...f, 0]), events: g.events.map((f) => [...f, 0]), calls: g.calls.map((f) => [...f, 0]) });

test('summarize: a lock arm that never leaves the lock is lower; the look class is change while the base is displaced', () => {
  const rows = [...Array(3).fill(0).flatMap(() => [rowOf('orig', fight), rowOf('base', fight), rowOf('lock', steady)]), { arm: 'lock', status: 'push:beginLate' }];
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
  const s = summarize([0, 1, 2].flatMap(() => ARMS.map((a) => rowOf(a, steady))));
  assert.equal(s.verdicts.lockVsBase.fights, 'overlap');
  assert.equal(s.verdicts.look, 'same');
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
  for (const g of ops('order')) assert.deepEqual(repOrder(g.rep), g.arms, `rep ${g.rep}`);
  assert.equal(ops('lane').length, 5);
  for (const g of ops('lane')) assert.equal(afterWindow(g.used, g.stalled), g.out, `${g.used} ${g.stalled}`);
});

test('every rep runs the original last, so a stall cannot erase the faithful or candidate window', () => {
  for (let rep = 0; rep < 6; rep++) {
    const o = repOrder(rep);
    assert.equal(o[2], 'orig');
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
