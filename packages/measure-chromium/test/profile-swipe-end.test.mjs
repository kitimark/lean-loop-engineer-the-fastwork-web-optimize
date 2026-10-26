import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  swipeIdleFrames, swipeTail, swipeWindowTail, swipeEndFrame, swipeEndReason, swipeStopAt, swipeStops, SWIPE_WINDOW_REACH, SWIPE_END_WIN_FRAMES,
} from '../src/profile.mjs';
import { allWindows, lastFrame, pushWindows, TOUCH_TAIL } from '../src/offscreen-windows.mjs';

const golden = readFileSync(new URL('../../contracts/golden/measure/swipe-end.jsonl', import.meta.url), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const ops = (op) => golden.filter((g) => g.op === op);
const profile = JSON.parse(readFileSync(new URL('../profiles/swipe-touch-v1.json', import.meta.url), 'utf8'));
const runSrc = readFileSync(new URL('../src/run.mjs', import.meta.url), 'utf8');

test('swipe-end: constants match the Lean golden and the reader windows', () => {
  const [c] = ops('consts');
  assert.deepEqual([SWIPE_WINDOW_REACH, SWIPE_END_WIN_FRAMES, swipeWindowTail, TOUCH_TAIL], [c.windowReach, c.endWinFrames, c.windowTail, c.touchTail]);
  assert.equal(pushWindows(0, 1000).at(-1).lo, SWIPE_WINDOW_REACH);
});

test('swipe-end: tail, stop frame, per-frame stop, end frame and reason agree with the Lean golden', () => {
  for (const g of ops('tail')) assert.deepEqual([swipeIdleFrames(g.input), swipeTail(g.input)], [g.idleFrames, g.tail], JSON.stringify(g));
  for (const g of ops('stopAt')) assert.equal(swipeStopAt(g.input, g.end, g.fired), g.stopAt, JSON.stringify(g));
  for (const g of ops('stops')) assert.equal(swipeStops(g.input, g.end, g.n, g.done), g.stops, JSON.stringify(g));
  for (const g of ops('endFrame')) assert.equal(swipeEndFrame(g.n, g.idle), g.end, JSON.stringify(g));
  for (const g of ops('reason')) assert.equal(swipeEndReason(g.limit, g.y), g.reason, JSON.stringify(g));
  assert.ok(ops('tail').length >= 5 && ops('stopAt').length >= 40 && ops('stops').length >= 40 && ops('reason').length >= 5);
});

test('swipe-end: a limit end and a stalled end get the same tail, and the reader windows stay inside it', () => {
  for (const g of ops('tail')) {
    for (const e of [0, 10, 575, 671]) {
      assert.equal(swipeStopAt(g.input, e, e), e + g.tail, 'limit end');
      assert.equal(swipeStopAt(g.input, e, e + g.idleFrames), e + g.tail, 'stalled end');
    }
  }
  for (const g of ops('windows')) {
    assert.equal(g.last, g.end + swipeTail(g.input) + 1);
    const ws = allWindows(g.readerEnd, lastFrame(g.total, TOUCH_TAIL));
    assert.deepEqual(ws, g.windows, JSON.stringify(g));
    for (const w of ws) assert.ok(w.hi <= g.last, `${w.name} reaches past the tail`);
    const e120 = ws.find((w) => w.name === 'end 120+');
    if (g.readerEnd >= 34 && g.readerEnd <= g.end) assert.ok(e120.hi - e120.lo >= SWIPE_END_WIN_FRAMES, JSON.stringify(g));
  }
});

test('swipe-end: swipe-touch-v1 keeps its stalled run length and run.mjs holds no end decision of its own', () => {
  const inp = profile.input;
  assert.equal(swipeTail(inp), 165);
  assert.equal(swipeStopAt(inp, 575, 575 + swipeIdleFrames(inp)), 575 + swipeIdleFrames(inp) + inp.holdFrames + 1);
  assert.ok(swipeTail(inp) <= inp.maxFrames);
  assert.match(runSrc, /swipeStops\(endInp, endAt, n, true\)/);
  assert.match(runSrc, /swipeEndFrame\(n, idle\)/);
  assert.match(runSrc, /swipeEndReason\(scrollLimit/);
  assert.doesNotMatch(runSrc, /'limit' : 'stalled'/);
});
