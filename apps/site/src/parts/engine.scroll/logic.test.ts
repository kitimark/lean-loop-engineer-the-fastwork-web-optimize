import { describe, expect, it } from 'vitest';
import { createScrollEngine, type ScrollEnv } from '../../engine/scroll';
import type { MotionClock, Tick } from '../../engine/clock';
import { goldenConformance } from '../../engine/golden.testutil';
import * as logic from './logic';

goldenConformance('engine.scroll', {
  orderCallbacks: (i) => logic.orderCallbacks(i.entries),
  framePlan: (i) => logic.framePlan(i.variant, i.writers),
  shouldSchedule: (i) => logic.shouldSchedule(i.pending),
  listenerAction: (i) => logic.listenerAction(i.attached, i.size),
  forcedCounts: (i) => logic.forcedCounts(i.accesses, i.dirty),
  forcedCountsBatched: (i) => logic.forcedCountsBatched(i.accesses, i.dirty),
  planLayouts: (i) => logic.planLayouts(i.variant, i.writers, i.dirty),
  engineRuns: (i) => logic.engineRuns(i.pending, i.events),
});

describe('engine.scroll logic', () => {
  it('pilot frame cost: faithful 3-4 forced style passes, batched at most 1', () => {
    expect(logic.forcedCounts(logic.PILOT_FRAME, true).style).toBe(4);
    expect(logic.forcedCounts(logic.PILOT_FRAME, false).style).toBe(3);
    expect(logic.forcedCounts(logic.PILOT_FRAME, true).layout).toBe(1);
    expect(logic.forcedCountsBatched(logic.PILOT_FRAME, true).style).toBe(1);
    expect(logic.forcedCountsBatched(logic.PILOT_FRAME, false).style).toBe(0);
  });
  it('faithful plan cost formula [d and nonempty] + writers among all but the last', () => {
    for (const ws of [[], [true], [true, true], [false, true, true], [true, false, true, true]])
      for (const d of [false, true]) {
        const expected = (d && ws.length > 0 ? 1 : 0) + ws.slice(0, -1).filter(Boolean).length;
        expect(logic.planLayouts('faithful', ws, d)).toBe(expected);
        expect(logic.planLayouts('batched', ws, d)).toBeLessThanOrEqual(1);
      }
  });
  it('orders by order then registration', () => {
    expect(logic.orderCallbacks([{ id: 'b', order: 2, seq: 0 }, { id: 'a', order: 1, seq: 1 }, { id: 'c', order: 1, seq: 2 }])).toEqual(['a', 'c', 'b']);
  });
  it('faithful interleaves, batched separates', () => {
    expect(logic.framePlan('faithful', [true, false, true])).toEqual([
      { op: 'read', i: 0 }, { op: 'write', i: 0 }, { op: 'read', i: 1 }, { op: 'read', i: 2 }, { op: 'write', i: 2 },
    ]);
    expect(logic.framePlan('batched', [true, false, true])).toEqual([
      { op: 'read', i: 0 }, { op: 'read', i: 1 }, { op: 'read', i: 2 }, { op: 'write', i: 0 }, { op: 'write', i: 2 },
    ]);
  });
  it('schedules once, attaches on first and detaches on last', () => {
    expect(logic.shouldSchedule(false)).toBe(true);
    expect(logic.shouldSchedule(true)).toBe(false);
    expect(logic.listenerAction(false, 1)).toBe('attach');
    expect(logic.listenerAction(true, 2)).toBe('none');
    expect(logic.listenerAction(true, 0)).toBe('detach');
    expect(logic.listenerAction(false, 0)).toBe('none');
  });
});

// Fake clock with the real clock's Set iteration semantics, fake window.
function rig() {
  const subs = new Set<Tick>();
  const clock: MotionClock = { subscribe: (t) => (subs.add(t), () => void subs.delete(t)), interval: () => () => {} };
  let now = 0;
  const frame = () => {
    now += 16;
    for (const s of subs) s(now);
  };
  const listeners: Record<string, Set<() => void>> = { scroll: new Set(), resize: new Set() };
  const reads: string[] = [];
  const env: ScrollEnv = {
    addEventListener: (t, f) => void listeners[t]!.add(f),
    removeEventListener: (t, f) => void listeners[t]!.delete(f),
    readY: () => (reads.push('y'), 100),
    readVw: () => (reads.push('vw'), 390),
    readVh: () => (reads.push('vh'), 800),
  };
  return { clock, env, frame, subs, listeners, reads, emit: (t: string) => listeners[t]!.forEach((f) => f()) };
}

describe('scroll engine', () => {
  it('registering requests one frame; events coalesce into one frame; unsubscribes after it', () => {
    const r = rig();
    const e = createScrollEngine(r.clock, r.env);
    const seen: number[] = [];
    e.register('a', 0, (f) => void seen.push(f.t));
    expect(r.subs.size).toBe(1);
    r.emit('scroll');
    r.emit('resize');
    expect(r.subs.size).toBe(1);
    r.frame();
    expect(seen).toEqual([16]);
    expect(r.subs.size).toBe(0);
    r.frame();
    expect(seen).toEqual([16]);
    r.emit('scroll');
    r.frame();
    expect(seen).toEqual([16, 48]);
  });
  it('detaches listeners with the last callback', () => {
    const r = rig();
    const e = createScrollEngine(r.clock, r.env);
    const off = e.register('a', 0, () => {});
    expect(r.listeners.scroll!.size).toBe(1);
    off();
    expect(r.listeners.scroll!.size + r.listeners.resize!.size).toBe(0);
    expect(r.subs.size).toBe(0);
  });
  it('registering inside a frame does not run a second frame in the same tick', () => {
    const r = rig();
    const e = createScrollEngine(r.clock, r.env);
    let n = 0;
    e.register('a', 0, () => {
      n++;
      if (n === 1) e.register('b', 1, () => {});
    });
    r.frame();
    expect(n).toBe(1);
    r.frame();
    expect(n).toBe(2);
  });
  it('faithful interleaves read and write, reads y lazily; batched reads once, then writes', () => {
    for (const variant of ['faithful', 'batched'] as const) {
      const r = rig();
      const e = createScrollEngine(r.clock, r.env, variant);
      const log: string[] = [];
      e.register('b', 2, () => (log.push('read b'), () => void log.push('write b')));
      e.register('a', 1, (f) => (log.push('read a'), f.y, () => void log.push('write a')));
      r.frame();
      expect(log).toEqual(
        variant === 'faithful'
          ? ['read a', 'write a', 'read b', 'write b']
          : ['read a', 'read b', 'write a', 'write b'],
      );
      expect(r.reads).toEqual(variant === 'faithful' ? ['y'] : ['y', 'vw', 'vh']);
    }
  });
  it('follows framePlan', () => {
    const r = rig();
    const e = createScrollEngine(r.clock, r.env, 'batched');
    const log: string[] = [];
    const mk = (n: string, w: boolean) => () => (log.push('r' + n), w ? () => void log.push('w' + n) : undefined);
    e.register('0', 0, mk('0', true));
    e.register('1', 1, mk('1', false));
    e.register('2', 2, mk('2', true));
    r.frame();
    expect(log).toEqual(logic.framePlan('batched', [true, false, true]).map((s) => (s.op === 'read' ? 'r' : 'w') + s.i));
  });
});
