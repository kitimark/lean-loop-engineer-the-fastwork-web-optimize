// Tests of the combo replay's pure parts (task combo-scroll-fight): metrics on synthetic streams, the profile events, the arm sets.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { reversalsNoFinger, jumps, scriptJumps, writeStats, metrics, JUMP_PX } from '../src/replay/combo-metrics.mjs';
import { eventsOf } from '../src/replay/combo-replay.mjs';
import { SCENARIOS, profileOf, render } from '../src/replay/combo-profile.mjs';
import { BISECT, FIX, USER_FLAGS, armsArg } from '../src/replay/combo-arms.mjs';

test('a smooth fling has no reversal and no jump', () => {
  const ys = [0, 10, 25, 45, 60, 70, 76, 79, 80];
  const down = ys.map(() => 0);
  assert.equal(reversalsNoFinger(ys, down), 0);
  assert.equal(jumps(ys).n, 0);
});

test('a script write against a fling shows as reversals and jumps', () => {
  const ys = [100, 140, 100, 150, 100, 150];
  const down = ys.map(() => 0);
  assert.equal(reversalsNoFinger(ys, down), 4);
  const j = jumps(ys);
  assert.equal(j.n, 4);
  assert.equal(j.max, 50);
});

test('reversals count only frames with no finger down on both sides', () => {
  const ys = [0, 30, 0, 30];
  assert.equal(reversalsNoFinger(ys, [0, 0, 1, 0]), 0);
  assert.equal(reversalsNoFinger(ys, [0, 0, 0, 0]), 2);
});

test('a jump needs both legs at the bound', () => {
  assert.equal(jumps([0, JUMP_PX, 0]).n, 1);
  assert.equal(jumps([0, JUMP_PX - 1, 0]).n, 0);
  assert.equal(jumps([0, 50, 49]).n, 0);
});

test('write stats split by finger and ignore writes that did not move the page', () => {
  const w = [[1, 100, 100, 0], [2, 100, 130, 1], [3, 100, 90, 0]];
  assert.deepEqual(writeStats(w), { n: 2, down: 1, free: 1, pxDown: 30, pxFree: 10 });
  assert.equal(metrics({ ts: [0, 16], ys: [0, 1], down: [0, 0], writes: w }).frames, 2);
});

test('events of a profile: a start, the moves, an end one frame later, in time order', () => {
  const p = { hz: 60, input: { strokes: [{ f0: 0, path: [[1, 2], [3, 4]] }, { f0: 10, path: [[5, 6]] }] } };
  const e = eventsOf(p);
  assert.deepEqual(e.map((x) => x[1]), ['s', 'm', 'e', 's', 'e']);
  assert.ok(e.every((x, i) => i === 0 || e[i - 1][0] <= x[0]));
  assert.deepEqual(e[2].slice(2), [3, 4]);
});

test('committed scripted profiles equal their generator and keep to the committed profile shape', () => {
  for (const name of Object.keys(SCENARIOS)) {
    const file = new URL(`../../measure-chromium/profiles/user-bug-1025-reopen-${name}.json`, import.meta.url);
    const text = readFileSync(file, 'utf8');
    assert.equal(text, render(profileOf(name)));
    const p = JSON.parse(text);
    assert.equal(p.input.mode, 'replay');
    assert.equal(p.input.unit, 'css-px');
    assert.ok(p.input.strokes.every((s) => Number.isInteger(s.f0) && s.path.every((q) => q.length === 2)));
  }
});

test('the recorded profile holds strokes only', () => {
  const p = JSON.parse(readFileSync(new URL('../../measure-chromium/profiles/user-bug-1025.json', import.meta.url), 'utf8'));
  assert.deepEqual(Object.keys(p.input).sort(), ['maxFrames', 'maxY', 'mode', 'strokes', 'unit']);
  assert.ok(p.input.strokes.every((s) => Object.keys(s).sort().join() === 'f0,path'));
});

test('arm sets: the user set is eight flags, the bisect drops each once, names are unique, the fix set is a subset', () => {
  assert.equal(USER_FLAGS.length, 8);
  const names = BISECT.map((a) => a.name);
  assert.equal(new Set(names).size, names.length);
  const drops = BISECT.filter((a) => a.name.startsWith('user-minus-'));
  assert.equal(drops.length, 8);
  assert.deepEqual(drops.map((a) => a.search.split(',').length).sort(), [6, 7, 7, 7, 7, 7, 7, 7]);
  // morph.countdown:strip needs hero.countdown:strip: no arm holds the first without the second
  for (const a of BISECT) assert.ok(!a.search.includes('morph.countdown:strip') || a.search.includes('hero.countdown:strip'));
  assert.ok(FIX.every((a) => BISECT.includes(a)));
  assert.ok(armsArg('fix').split(';').length === FIX.length);
});

test('a script jump needs a page write inside the pair; a finger that turns round is not one', () => {
  const ts = [0, 16, 32, 48];
  const ys = [100, 140, 100, 100];
  assert.equal(jumps(ys).n, 1);
  assert.deepEqual(scriptJumps(ts, ys, []), { n: 0, max: 0 });
  assert.deepEqual(scriptJumps(ts, ys, [[20, 100, 140, 0]]), { n: 1, max: 40 });
  assert.deepEqual(scriptJumps(ts, ys, [[20, 140, 140, 0]]), { n: 0, max: 0 });
  assert.deepEqual(scriptJumps(ts, ys, [[60, 100, 140, 0]]), { n: 0, max: 0 });
});
