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
const rows: Row[] = readFileSync(resolve(root, 'packages/contracts/golden/parts/hero.countdown.onechain.jsonl'), 'utf8')
  .trim()
  .split('\n')
  .map((l) => JSON.parse(l) as Row);

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
