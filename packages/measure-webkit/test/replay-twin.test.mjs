import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as R from '../src/device-replay.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const lines = readFileSync(join(here, '../../contracts/golden/device/replay.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const of = (kind) => lines.filter((l) => l.kind === kind);

test('every golden kind has lines', () => {
  for (const k of ['limits', 'profile', 'compile', 'match', 'fastest', 'fastFling', 'zoneLoop', 'cold', 'rotation', 'schedule']) assert.ok(of(k).length > 0, k);
});

test('limits and tick', () => {
  const [g] = of('limits');
  assert.deepEqual({ ...R.LIM }, g.lim);
  assert.equal(R.TICK_MAX, g.tickMax);
});

test('profile of a touch stream, none for a second finger', () => {
  const [ok, multi] = of('profile');
  assert.deepEqual(R.ofTouches('fixture', ok.touches, ok.w, ok.h), ok.profile);
  assert.equal(multi.profile, null);
  assert.equal(R.ofTouches('multi', multi.touches, multi.w, multi.h), null);
  assert.equal(ok.profile.swipes.length, 3, 'the tap is not a swipe');
});

test('compiler: actions and the W3C payload equal Lean, every tick 0..16 ms', () => {
  for (const g of of('compile')) {
    const acts = R.compile(g.profile);
    assert.deepEqual(acts, g.acts, g.profile.id);
    if (g.w3c) assert.deepEqual(R.w3c(acts), g.w3c);
    for (const a of acts) {
      const d = a[0] === 'm' ? a[3] : a[0] === 'p' ? a[1] : 0;
      assert.ok(d >= 0 && d <= 16, `${a}`);
    }
  }
});

test('compiler: the ticks add up to the last lift, the events are the swipes samples in whole px', () => {
  const g = of('compile').find((x) => x.profile.id === 'fixture');
  const last = g.profile.swipes[g.profile.swipes.length - 1];
  assert.equal(R.actsMs(g.acts), R.ms(last.start + last.lift) - R.ms(g.profile.swipes[0].start));
  const ev = R.simulateEvents(g.acts);
  assert.equal(ev.filter((e) => e[1] === 's').length, 3);
  assert.equal(ev.filter((e) => e[1] === 'e').length, 3);
  const starts = ev.filter((e) => e[1] === 's');
  g.profile.swipes.forEach((s, i) => {
    assert.ok(Math.abs(starts[i][0] - (R.ms(s.start) - R.ms(g.profile.swipes[0].start))) <= 1);
    assert.deepEqual(starts[i].slice(2), [R.px(s.s[0][1]), R.px(s.s[0][2])]);
  });
});

test('replay check: conjuncts and verdict equal Lean, one conjunct fails per case', () => {
  for (const g of of('match')) {
    g.src.forEach((a, i) => { if (g.rep[i]) assert.deepEqual(R.conjuncts(g.lim, a, g.rep[i]), g.conj[i], `${g.name} swipe ${i}`); });
    assert.equal(R.replayMatches(g.lim, g.src, g.rep), g.replayMatches, g.name);
  }
  const by = Object.fromEntries(of('match').map((g) => [g.name, g]));
  assert.equal(by.same.replayMatches, true);
  assert.equal(by.nudged.replayMatches, true);
  for (const [name, key] of [['events', 'eventsOk'], ['pos', 'posOk'], ['time', 'timeOk'], ['speed', 'speedOk'], ['start', 'startOk']]) {
    assert.ok(by[name].conj.every((c) => c[key] === false), `${name}: ${key} fails on every swipe`);
    assert.ok(by[name].conj.every((c) => Object.entries(c).every(([k, val]) => k === key || k === 'swipe' || val === true)), `${name}: only ${key} fails`);
  }
});

test('fastest down-scroll fling', () => {
  for (const g of of('fastest')) {
    assert.deepEqual(g.swipes.map(R.speed2), g.speed2);
    assert.deepEqual(g.swipes.map(R.scrollsDown), g.down);
    assert.equal(R.fastest(g.swipes), g.index === null ? null : g.swipes[g.index]);
  }
});

test('generators equal Lean', () => {
  for (const g of of('fastFling')) assert.deepEqual(R.fastFling(g.profile, g.n, g.gap), g.out);
  for (const g of of('zoneLoop')) assert.deepEqual(R.zoneLoop(g.profile, g.zone, g.maxY10, g.frames, g.t0, g.reps, g.gap), g.out, g.zone);
  for (const g of of('cold')) assert.deepEqual(R.cold(g.profile), g.out);
});

test('generators: gaps are exact, mirror is an involution, the loop has reps x 2 x segment swipes', () => {
  const gap = (l, g) => l.slice(1).every((s, i) => s.start === l[i].start + l[i].lift + g);
  for (const g of of('fastFling')) assert.ok(gap(g.out.swipes, g.gap) && g.out.swipes.length === g.n);
  const [hero] = of('zoneLoop');
  assert.equal(hero.out.swipes.length, hero.reps * 2 * 1);
  assert.ok(gap(hero.out.swipes, hero.gap));
  const s = hero.profile.swipes[0];
  assert.deepEqual(R.mirror(8440, R.mirror(8440, s)), s);
});

test('arm rotation: a permutation, every arm leads once in n repeats', () => {
  for (const g of of('rotation')) {
    g.orders.forEach((o, r) => assert.deepEqual(o, R.rotation(g.n, r)));
    for (const o of g.orders) assert.deepEqual([...o].sort(), Array.from({ length: g.n }, (_, i) => i));
    assert.equal(new Set(g.orders.slice(0, g.n).map((o) => o[0])).size, g.n);
  }
  for (const g of of('schedule')) {
    assert.deepEqual(R.schedule(R.KINDS, g.reps, g.n), g.runs);
    assert.equal(g.runs.length, R.KINDS.length * g.reps);
  }
});

test('CI profile adapter keeps the strokes', () => {
  const cp = { id: 'x', hz: 60, viewport: { width: 430, height: 932 }, input: { strokes: [{ f0: 10, path: [[1, 2], [1, 3]] }, { f0: 40, path: [[5, 6], [5, 7], [5, 8]] }] } };
  const p = R.fromCiProfile(cp);
  assert.equal(p.swipes.length, 2);
  assert.equal(p.swipes[0].start, 0);
  assert.equal(p.swipes[1].start, Math.round((30 * 100000) / 60));
  assert.deepEqual(p.swipes[1].s[2], [Math.round((2 * 100000) / 60), 50, 80]);
});

test('pieces: one per swipe with points, equal Lean, joined they are the compiled actions, a timeout above each duration', () => {
  const gs = of('pieces');
  assert.equal(gs.length, 4);
  for (const g of gs) {
    const ps = R.pieces(g.profile);
    assert.deepEqual(ps, g.pieces, g.profile.id);
    assert.deepEqual(ps.flat(), R.compile(g.profile));
    assert.deepEqual(ps.map((p) => R.pieceTimeoutMs(R.actsMs(p))), g.timeouts);
    assert.equal(ps.length, g.profile.swipes.filter((s) => s.s.length > 0).length);
    for (const [i, p] of ps.entries()) {
      assert.equal(p.filter((a) => a[0] === 'd').length, 1);
      assert.equal(p.filter((a) => a[0] === 'u').length, 1);
      assert.equal(p[p.length - 1][0], 'u');
      assert.ok(g.timeouts[i] > R.actsMs(p));
    }
  }
});
