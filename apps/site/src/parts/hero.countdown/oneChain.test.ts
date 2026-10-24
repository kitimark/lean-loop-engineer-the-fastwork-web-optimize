import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { createRafClock, type ClockEnv, type MotionClock } from '../../engine/clock';
import { oneChainClock, startFaithful, type FaithfulOptions } from './driver';

interface Row {
  scenario: string;
  events: ({ refresh: [number, number][] } | { frame: number })[];
  frames: { steps: number[]; faithful: number; oneChain: number }[];
}
const root = resolve(__dirname, '../../../../..');
interface OrderRow {
  scenario: 'order499';
  faithful: [number, number];
  atSubscriber: [number, number];
  last: [number, number];
}
const lines = readFileSync(resolve(root, 'packages/contracts/golden/parts/hero.countdown.onechain.jsonl'), 'utf8')
  .trim()
  .split('\n')
  .map((l) => JSON.parse(l) as Row | OrderRow);
const rows = lines.filter((r): r is Row => r.scenario !== 'order499');
const order = lines.find((r): r is OrderRow => r.scenario === 'order499')!;

const mkEnv = () => {
  const raf = new Map<number, (t: number) => void>();
  const timers = new Map<number, () => void>();
  let id = 0;
  const env: ClockEnv = {
    raf: (cb) => (raf.set(++id, cb), id),
    caf: (h) => void raf.delete(h),
    setInterval: (cb) => (timers.set(++id, cb), id),
    clearInterval: (h) => void timers.delete(h as number),
  };
  const frame = (t: number) => {
    const cbs = [...raf.values()];
    raf.clear();
    cbs.forEach((cb) => cb(t));
    return cbs.length;
  };
  return { env, timers, frame };
};

/** Replays a golden scenario through `startFaithful` on `wrap(clock)`; per frame: digits stepped and rAF callbacks. */
const replay = (row: Row, wrap: (c: MotionClock) => MotionClock) => {
  const e = mkEnv();
  const left = new Map<number, number>();
  const refreshes = row.events.filter((ev): ev is { refresh: [number, number][] } => 'refresh' in ev);
  let next = 0;
  let steps: number[] = [];
  const driver = {
    refresh: () => {
      const ss = refreshes[next++]!.refresh;
      for (const [d, k] of ss) left.set(d, k);
      return { changed: true, started: ss.map(([d]) => d) };
    },
    step: (i: number) => {
      steps.push(i);
      const k = Math.max(0, (left.get(i) ?? 0) - 1);
      left.set(i, k);
      return k === 0;
    },
  } as unknown as FaithfulOptions['driver'];
  const doc = new EventTarget();
  startFaithful({ clock: wrap(createRafClock(e.env)), driver, perfNow: () => 0, doc });
  const out: Row['frames'] = [];
  let first = true;
  for (const ev of row.events) {
    if ('refresh' in ev) {
      if (!first) [...e.timers.values()].forEach((cb) => cb());
      first = false;
      continue;
    }
    steps = [];
    const rafs = e.frame(ev.frame);
    out.push({ steps, faithful: rafs, oneChain: rafs });
  }
  return out;
};

describe('hero.countdown one-chain against the Lean golden', () => {
  it('has the six scenarios', () => {
    expect(rows.map((r) => r.scenario)).toEqual(['mount', 'ones', 'tens', 'minute', 'restart', 'still']);
  });
  for (const row of rows) {
    it(`${row.scenario}: faithful steps and rAF callbacks`, () => {
      const got = replay(row, (c) => c);
      expect(got.map((f) => f.steps)).toEqual(row.frames.map((f) => f.steps));
      expect(got.map((f) => f.faithful)).toEqual(row.frames.map((f) => f.faithful));
    });
    it(`${row.scenario}: one-chain steps and rAF callbacks`, () => {
      const got = replay(row, oneChainClock);
      expect(got.map((f) => f.steps)).toEqual(row.frames.map((f) => f.steps));
      expect(got.map((f) => f.oneChain)).toEqual(row.frames.map((f) => f.oneChain));
    });
  }
  /**
   * Frame 499 of swipe-touch-v1 through the real shared loop: the scroll tick (a shared subscriber added by the scroll
   * event, after the digits' subscriber) reads layout, then dirties a subtree of 320 elements; the digits write 10
   * faces. TS stand-in of Lean `fstep`/`frameCost`: a read flushes only dirty style; the frame ends with one more.
   */
  const frame499 = (wrap: (c: MotionClock) => MotionClock, chainShared: boolean): [number, number] => {
    const e = mkEnv();
    const clock = createRafClock(e.env);
    const dirt = { faces: false, walk: false };
    let flushes = 0;
    let elems = 0;
    const read = () => {
      if (!dirt.faces && !dirt.walk) return;
      flushes++;
      elems += dirt.walk ? 320 : 10;
      dirt.faces = dirt.walk = false;
    };
    const faces = () => void (dirt.faces = true);
    clock.subscribe(() => {}); // another part keeps the shared loop running, so its rAF comes first in the frame
    if (chainShared) clock.subscribe(faces);
    else wrap(clock).subscribe(faces, { own: true });
    clock.subscribe(() => {
      read();
      dirt.walk = true;
    });
    e.frame(16);
    read();
    return [flushes, elems];
  };
  it('frame 499: faithful, the first one-chain (digits at their subscriber) and the fixed one-chain', () => {
    expect(frame499((c) => c, false)).toEqual(order.faithful);
    expect(frame499((c) => c, true)).toEqual(order.atSubscriber);
    expect(frame499(oneChainClock, false)).toEqual(order.last);
  });
  it('one-chain passes shared subscribers and intervals through', () => {
    const e = mkEnv();
    const c = oneChainClock(createRafClock(e.env));
    let n = 0;
    const off = c.subscribe(() => n++);
    const stop = c.interval(1000, () => {});
    expect(e.frame(16)).toBe(1);
    expect(n).toBe(1);
    expect(e.timers.size).toBe(1);
    off();
    stop();
    expect(e.frame(32)).toBe(0);
    expect(e.timers.size).toBe(0);
  });
});
