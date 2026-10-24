import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { createScrollEngine, type ScrollEnv } from '../../engine/scroll';
import type { MotionClock, Tick } from '../../engine/clock';
import {
  FRAME_CAP,
  followDrive,
  followStep,
  followStepG,
  idleState,
  installFollow,
  STILL_MAX,
  wakeState,
  type FollowState,
} from './follow';
import { unthrottleCss } from './unthrottle';
import part from './part.json';

type Row = { fn: string; in?: any; out: any };
const golden: Row[] = readFileSync(
  new URL('../../../../../packages/contracts/golden/parts/engine-scroll-follow.jsonl', import.meta.url),
  'utf8',
)
  .trim()
  .split('\n')
  .map((l) => JSON.parse(l) as Row);
const rows = (fn: string) => golden.filter((r) => r.fn === fn);

type Shape =
  | { kind: 'moving'; start: number; n: number }
  | { kind: 'hold'; y: number; n: number }
  | { kind: 'stairs'; start: number; plateaus: number; p: number };

function ysOf(s: Shape): number[] {
  if (s.kind === 'moving') return Array.from({ length: s.n }, (_, i) => s.start + i + 1);
  if (s.kind === 'hold') return Array.from({ length: s.n }, () => s.y);
  return Array.from({ length: s.plateaus }, (_, i) => Array.from({ length: s.p }, () => s.start + i + 1)).flat();
}

describe('engine.scroll unthrottle-follow against the Lean golden', () => {
  it('has the constants and the style text Lean lists', () => {
    expect(rows('consts')[0]!.out).toEqual({ stillMax: STILL_MAX, frameCap: FRAME_CAP });
    expect(rows('css')[0]!.out).toBe(unthrottleCss());
  });

  it('steps like Lean step on every listed state', () => {
    const r = rows('step');
    expect(r.length).toBe(24);
    for (const x of r) expect(followStep(x.in.state, x.in.y, x.in.ended)).toEqual(x.out);
  });

  it('is a no-op without a coarse pointer and steps with one', () => {
    const r = rows('guarded');
    expect(r.length).toBe(4);
    for (const x of r) expect(followStepG(x.in.coarse, x.in.state, x.in.y, false)).toEqual(x.out);
    for (const x of r) expect(x.out.on).toBe(x.in.coarse && x.in.y !== x.in.state.last);
  });

  it('drives like Lean drive on every listed trace', () => {
    const r = rows('drive');
    expect(r.length).toBe(8);
    for (const x of r) {
      const got = followDrive(wakeState(x.in.wake), ysOf(x.in.shape));
      expect({ state: got.state, frames: got.frames }).toEqual(x.out);
    }
  });

  it('is a variant of engine.scroll', () => {
    expect(Object.keys(part.variants)).toContain('unthrottle-follow');
  });
});

function rig(positions: number[], eventAt: Set<number>) {
  const subs = new Set<Tick>();
  const clock: MotionClock = { subscribe: (t) => (subs.add(t), () => void subs.delete(t)), interval: () => () => {} };
  let now = 0;
  let u = 0;
  const listeners: Record<string, Set<() => void>> = { scroll: new Set(), resize: new Set() };
  const env: ScrollEnv = {
    addEventListener: (t, f) => void listeners[t]!.add(f),
    removeEventListener: (t, f) => void listeners[t]!.delete(f),
    readY: () => positions[u] ?? positions[positions.length - 1]!,
    readVw: () => 390,
    readVh: () => 800,
  };
  const engine = createScrollEngine(clock, env);
  const ended = new Set<() => void>();
  const followEnv = {
    coarse: () => true,
    readY: () => positions[0]!,
    onScrollEnd: (fn: () => void) => (ended.add(fn), () => void ended.delete(fn)),
  };
  const read: number[] = [];
  engine.register('probe', 0, (f) => void read.push(f.y));
  const update = () => {
    u++;
    now += 16;
    if (eventAt.has(u)) listeners.scroll!.forEach((f) => f());
    for (const s of subs) s(now);
  };
  return { engine, update, read, ended, followEnv, subs };
}

describe('follow loop on the scroll engine', () => {
  const moving = Array.from({ length: 40 }, (_, i) => 100 + i * 7);
  const tail = Array.from({ length: 20 }, () => moving[moving.length - 1]!);
  const path = [...moving, ...tail];

  it('reads the newest scrollY at every moving update where the throttled event fires once per window', () => {
    const events = new Set([1, 7, 13, 19, 25, 31, 37]);
    const base = rig(path, events);
    for (let i = 1; i < path.length; i++) base.update();
    const withFollow = rig(path, events);
    installFollow(withFollow.engine, withFollow.followEnv);
    for (let i = 1; i < path.length; i++) withFollow.update();
    const baseMoving = base.read.filter((y) => y > 100).length;
    expect(baseMoving).toBeLessThanOrEqual(events.size);
    expect(withFollow.read.slice(0, 39)).toEqual(path.slice(1, 40));
  });

  it('stops after stillMax still frames and then requests nothing while idle', () => {
    const r = rig(path, new Set([1]));
    installFollow(r.engine, r.followEnv);
    for (let i = 1; i < path.length; i++) r.update();
    const settled = r.read.length;
    expect(r.subs.size).toBe(0);
    expect(settled).toBeLessThanOrEqual(40 + STILL_MAX + 2);
    for (let i = 0; i < 30; i++) r.update();
    expect(r.read.length).toBe(settled);
  });

  it('stops on scrollend', () => {
    const r = rig(path, new Set([1]));
    installFollow(r.engine, r.followEnv);
    for (let i = 1; i < 10; i++) r.update();
    r.ended.forEach((f) => f());
    r.update();
    const n = r.read.length;
    r.update();
    r.update();
    expect(r.read.length).toBe(n);
  });

  it('undoes its registration and its scrollend listener', () => {
    const r = rig(path, new Set([1]));
    const off = installFollow(r.engine, r.followEnv);
    off();
    expect(r.ended.size).toBe(0);
  });

  it('keeps the idle state after install at an unmoved position', () => {
    const s: FollowState = idleState(5);
    expect(followStep(s, 5, false)).toEqual(s);
  });
});
