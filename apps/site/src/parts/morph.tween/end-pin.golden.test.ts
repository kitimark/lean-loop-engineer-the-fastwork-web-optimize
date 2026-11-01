import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { createTweenDriver, type PlatformEl, type TweenEnv } from './driver';
import { active } from './logic';
import { BASE } from './end.logic';
import { due, mayWrite, observe, outcome, play, QUIET_MS, start, touch, why, type Ev, type Pin } from './end-pin.logic';
import { faithWritesLive, writesLive } from './end-pin.live';
import type { TraceEv } from './driver';

type Row = Record<string, unknown> & { op: string };
const rows: Row[] = readFileSync(new URL('../../../../../packages/contracts/golden/measure/touch-lock.jsonl', import.meta.url), 'utf8')
  .split('\n')
  .filter((l) => l.trim() !== '')
  .map((l) => JSON.parse(l) as Row)
  .filter((r) => r.op.startsWith('pin'));
const ofOp = (op: string) => rows.filter((r) => r.op === op);
const pinOf = (r: unknown) => r as Pin;

describe('morph.tween:end-pin against Lean (Fw.Parts.EndPin)', () => {
  it('has every row kind', () => {
    expect(new Set(rows.map((r) => r.op))).toEqual(new Set(['pinConstants', 'pinMay', 'pinObserve', 'pinDue', 'pinTouch', 'pinPlay', 'pinFaith', 'pinTrace']));
    expect(ofOp('pinConstants')[0]!.quietMs).toBe(QUIET_MS);
  });
  it('mayWrite and due give the Lean rows', () => {
    expect(ofOp('pinMay').length).toBe(12);
    for (const r of ofOp('pinMay')) {
      expect(mayWrite(pinOf(r.pin), Number(r.s)), String(r.case)).toBe(r.out);
      expect(why(pinOf(r.pin), Number(r.s)), String(r.case)).toBe(r.why);
      expect(r.why === null, String(r.case)).toBe(r.out === true);
    }
    expect(new Set(ofOp('pinMay').map((r) => r.why))).toEqual(new Set(['touching', 'live', 'onTarget', 'reversal', null]));
    expect(ofOp('pinDue').length).toBe(13);
    for (const r of ofOp('pinDue')) expect(due(pinOf(r.pin), Number(r.s)), String(r.case)).toBe(r.out);
  });
  it('observe gives the Lean pin and write', () => {
    expect(ofOp('pinObserve').length).toBe(8);
    for (const r of ofOp('pinObserve')) {
      const [p, w] = observe(pinOf(r.pin), Number(r.s), Number(r.y), Number(r.dt));
      expect(p, String(r.case)).toEqual(r.pinOut);
      expect(w, String(r.case)).toBe(r.write);
      expect(outcome(pinOf(r.pin), Number(r.s), Number(r.y), Number(r.dt)), String(r.case)).toBe(r.outcome);
    }
  });
  it('a touch flips the state and restarts the quiet time', () => {
    for (const r of ofOp('pinTouch')) expect(touch(pinOf(r.pin), r.down === true)).toEqual(r.pinOut);
  });
  it('play gives the Lean positions', () => {
    expect(ofOp('pinPlay').length).toBe(11);
    for (const r of ofOp('pinPlay')) expect(play(start(Number(r.y0)), r.events as Ev[]), String(r.case)).toEqual(r.positions);
  });
  it('the end pin makes no write in a live state, the faithful pin does (writesLive)', () => {
    for (const r of ofOp('pinPlay')) {
      expect(writesLive(start(Number(r.y0)), r.events as Ev[]), String(r.case)).toBe(r.writesLive);
      expect(r.writesLive, String(r.case)).toBe(0);
      expect(faithWritesLive(Number(r.s), start(Number(r.y0)), r.events as Ev[]), String(r.case)).toBe(r.faithWritesLive);
    }
    expect(ofOp('pinPlay').some((r) => Number(r.faithWritesLive) > 0)).toBe(true);
    for (const r of ofOp('pinFaith')) {
      const moves = (r.moves as number[]).map((y): Ev => ['move', y]);
      expect(faithWritesLive(Number(r.s), start(Number(r.y0)), moves), String(r.case)).toBe(r.writesLive);
      expect(Number(r.writesLive), String(r.case)).toBe((r.moves as number[]).filter((y) => y !== Number(r.s)).length);
    }
  });
});

function arm(y0: number, s: number) {
  let now = 0;
  let tgt = s;
  const trace: TraceEv[] = [];
  let y = s;
  const timers: { at: number; cb: () => void }[] = [];
  const writes: number[] = [];
  const listeners = new Map<string, (e: never) => void>();
  let touchCb: ((down: boolean) => void) | null = null;
  const platform: PlatformEl = { getBoundingClientRect: () => ({ height: 500, bottom: 800 }), style: { pointerEvents: '', setProperty: () => {} } };
  const env: TweenEnv = {
    clock: {
      subscribe: () => () => {},
      interval: (ms, cb) => {
        const t = { at: now + ms, cb };
        timers.push(t);
        return () => {
          const i = timers.indexOf(t);
          if (i >= 0) timers.splice(i, 1);
        };
      },
    },
    now: () => now,
    reduced: () => false,
    viewportHeight: () => 800,
    platform: () => platform,
    scrollY: () => y,
    scrollToInstant: (to) => void (writes.push(to), (y = to)),
    addListener: (t, fn) => void listeners.set(t, fn),
    removeListener: (t) => void listeners.delete(t),
    publish: () => {},
    hooks: { ...BASE, target: () => tgt },
    trace: (ev) => void trace.push(ev),
    endPin: { touch: (cb) => ((touchCb = cb), () => void (touchCb = null)) },
  };
  const d = createTweenDriver(env);
  d.setNear(true);
  (listeners.get('wheel') as unknown as (e: { deltaY: number; defaultPrevented: boolean; preventDefault(): void }) => void)({ deltaY: 50, defaultPrevented: false, preventDefault: () => {} });
  y = y0;
  d.pin();
  const advance = (ms: number, target?: number) => {
    if (target !== undefined) tgt = target;
    const to = now + ms;
    for (;;) {
      const next = timers.filter((t) => t.at <= to).sort((a, b) => a.at - b.at)[0];
      if (!next) break;
      timers.splice(timers.indexOf(next), 1);
      now = next.at;
      next.cb();
    }
    now = to;
    d.pin();
  };
  return {
    d,
    writes,
    trace,
    timers: () => timers.length,
    move: (to: number) => {
      y = to;
      d.pin();
    },
    advance,
    down: () => touchCb?.(true),
    up: () => touchCb?.(false),
  };
}

describe('the driver wires the end pin as Lean plays it', () => {
  it('writes exactly the Lean writes for each play row (the morph opens on a wheel at the target)', () => {
    for (const r of ofOp('pinPlay')) {
      const a = arm(Number(r.y0), Number(r.s));
      expect(active(a.d.state()), String(r.case)).toBe(true);
      for (const e of r.events as Ev[]) {
        if (e[0] === 'move') a.move(e[1]);
        else if (e[0] === 'idle') a.advance(e[1], e[2]);
        else if (e[0] === 'down') a.down();
        else a.up();
      }
      expect(a.writes, String(r.case)).toEqual(r.writes);
      const pins = a.trace.filter((t) => t.kind === 'pin');
      expect(pins.filter((t) => t.op === 'write').length, String(r.case)).toBe((r.writes as number[]).length);
      expect(pins.filter((t) => t.op === 'write').map((t) => t.write), String(r.case)).toEqual(r.writes);
    }
  });
  it('the target is read again at every reading: a write goes to the target of its own reading', () => {
    const a = arm(100, 0);
    a.move(80);
    a.advance(200, 60);
    expect(a.writes).toEqual([60]);
    a.move(70);
    a.advance(200, 0);
    expect(a.writes).toEqual([60]);
    const declined = a.trace.filter((t) => t.kind === 'pin' && t.op === 'reversal');
    expect(declined.length).toBeGreaterThan(0);
    expect(declined.every((t) => t.kind === 'pin' && t.s === 0)).toBe(true);
  });
  it('the trace shows the pin ran: due, each decline with its reason, each write with its y', () => {
    const a = arm(30, 0);
    a.down();
    a.move(20);
    a.advance(300);
    a.up();
    a.advance(QUIET_MS + 1);
    const ops = a.trace.filter((t) => t.kind === 'pin').map((t) => (t.kind === 'pin' ? t.op : ''));
    expect(ops).toContain('touch');
    expect(ops).toContain('moved');
    expect(ops).toContain('touching');
    expect(ops).toContain('due');
    expect(ops).toContain('write');
    expect(a.trace.filter((t) => t.kind === 'pin' && t.op === 'write').map((t) => (t.kind === 'pin' ? t.write : null))).toEqual([0]);
  });
  it('the trace is silent without a trace hook', () => {
    const a = arm(30, 0);
    a.move(20);
    a.advance(QUIET_MS + 1);
    expect(a.writes).toEqual([0]);
  });
  it('a timer, not a scroll frame, makes the write once the page is quiet', () => {
    const a = arm(30, 0);
    a.move(20);
    expect(a.timers()).toBe(1);
    a.advance(QUIET_MS + 1);
    expect(a.writes).toEqual([0]);
  });
  it('a finger down blocks every write, however long the page is quiet; lifting it arms the timer', () => {
    const a = arm(30, 0);
    a.down();
    a.move(20);
    a.advance(5000);
    expect(a.writes).toEqual([]);
    expect(a.timers()).toBe(0);
    a.up();
    expect(a.timers()).toBe(1);
    a.advance(QUIET_MS + 1);
    expect(a.writes).toEqual([0]);
  });
});
