// The Chromium replay lane's pure parts: the CDP touch messages, the timed dispatch, the lateness statistics, the table.
import test from 'node:test';
import assert from 'node:assert/strict';
import { touchMessage, dispatchAt, lateStats, sleepUntil, table } from '../src/replay/chromium-replay.mjs';
import { simulateEvents, compile, fromCiProfile } from '../src/device-replay.mjs';

const cp = { id: 'syn', hz: 60, viewport: { width: 390, height: 844 }, input: { strokes: [{ f0: 0, path: [[100, 500], [100, 480], [100, 440], [100, 380]] }] } };
const profile = fromCiProfile(cp);

test('touch messages: start and move carry the finger, end carries none', () => {
  assert.deepEqual(touchMessage([0, 's', 10, 20]), { type: 'touchStart', touchPoints: [{ x: 10, y: 20, id: 0 }] });
  assert.deepEqual(touchMessage([5, 'm', 10, 30]), { type: 'touchMove', touchPoints: [{ x: 10, y: 30, id: 0 }] });
  assert.deepEqual(touchMessage([9, 'e', 10, 30]), { type: 'touchEnd', touchPoints: [] });
});

test('dispatch sends every event in order, at its time, without waiting for the renderer', async () => {
  let now = 0;
  const clock = () => { now += 0.5; return now; };
  const wait = async (ms) => { now += ms; };
  const sent = [];
  const cdp = { send: (m, p) => { sent.push([now, m, p.type]); return Promise.resolve(); } };
  const events = simulateEvents(compile(profile));
  const late = await dispatchAt(cdp, events, { clock, wait });
  assert.equal(sent.length, events.length);
  assert.ok(sent.every((s) => s[1] === 'Input.dispatchTouchEvent'));
  assert.deepEqual(sent.map((s) => s[2]), events.map((e) => ({ s: 'touchStart', m: 'touchMove', e: 'touchEnd' })[e[1]]));
  assert.ok(late.every((l) => l >= 0 && l <= 3), `late ${late}`);
  const times = sent.map((s) => s[0]);
  assert.deepEqual(times, [...times].sort((a, b) => a - b));
});

test('sleepUntil returns at once when the time has passed', async () => {
  await sleepUntil(0, () => 5, async () => { throw new Error('waited'); });
});

test('lateness statistics', () => {
  assert.deepEqual(lateStats([]), { n: 0, max: 0, p95: 0 });
  assert.deepEqual(lateStats([0.5, 0.1, 0.3, 2.5]), { n: 4, max: 2.5, p95: 2.5 });
});

test('the table has a row per pass', () => {
  const pass = { kind: 'recorded', rep: 0, profile: 'p', swipesSeen: 1, swipesSent: 1, eventCounts: { sent: 5, expected: 5, seen: 4 }, matches: false, report: { total: { over34: 3, over50: 1, n: 60 } }, late: { p95: 0.4, max: 1.2 } };
  const lines = table({ passes: [pass, { ...pass, rep: 1 }] }).trim().split('\n');
  assert.equal(lines.length, 4);
  assert.ok(lines[2].includes('| recorded | 0 | p | 1/1 | 5/5/4 | false | 3 | 1 | 60 | 0.4/1.2 |'));
});
