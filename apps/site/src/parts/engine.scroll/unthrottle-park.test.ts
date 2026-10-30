import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import part from './part.json';
import { STILL_FRAMES, STILL_MS, createUtPark, unthrottleParkCss, utStep, UT_PARKED_ATTR, type ParkEnv, type UtEvent } from './unthrottle-park';
import { UNTHROTTLE_ATTR } from './unthrottle';

type Row = { fn: string; in: Record<string, unknown>; out: unknown };
const golden: Row[] = readFileSync(new URL('../../../../../packages/contracts/golden/parts/scroll-park.jsonl', import.meta.url), 'utf8')
  .trim()
  .split('\n')
  .map((l) => JSON.parse(l) as Row);

function env() {
  const log: string[] = [];
  let cb: (ev: 'scroll' | 'touch') => void = () => {};
  let nextId = 1;
  const timers = new Map<number, { f: () => void; ms: number }>();
  const e: ParkEnv = {
    setParked: (on) => log.push(on ? 'park' : 'unpark'),
    listen: (c) => {
      cb = c;
      return () => log.push('unlisten');
    },
    setTimer: (f, ms) => {
      const id = nextId++;
      timers.set(id, { f, ms });
      return id;
    },
    clearTimer: (id) => void timers.delete(id),
  };
  const fire = () => {
    const [id, t] = [...timers.entries()][0]!;
    timers.delete(id);
    t.f();
  };
  return { e, log, event: (ev: 'scroll' | 'touch') => cb(ev), timers, fire };
}

describe('engine.scroll:unthrottle-park against the Lean golden', () => {
  it('constants equal the Lean consts line', () => {
    const k = golden.find((r) => r.fn === 'consts')!.out as { utStillFrames: number; utStillMs: number };
    expect(STILL_FRAMES).toBe(k.utStillFrames);
    expect(STILL_MS).toBe(k.utStillMs);
  });

  it('utStep equals the Lean step on all 6 cases', () => {
    const rows = golden.filter((r) => r.fn === 'utStep');
    expect(rows.length).toBe(6);
    for (const r of rows) expect(utStep(r.in.parked as boolean, r.in.event as UtEvent)).toBe(r.out);
  });

  it('the park rule keeps the flag selector and the flag conditions', () => {
    const css = unthrottleParkCss();
    expect(css).toContain(`[${UNTHROTTLE_ATTR}][${UT_PARKED_ATTR}] { animation-name: none; }`);
    expect(css).toContain('@supports (animation-timeline: scroll())');
    expect(css).toContain('@media (pointer: coarse)');
  });
});

describe('still timer controller', () => {
  it('arms a timer of STILL_MS on start, parks when it fires', () => {
    const a = env();
    const p = createUtPark(a.e);
    expect([...a.timers.values()].map((t) => t.ms)).toEqual([STILL_MS]);
    a.fire();
    expect(p.isParked()).toBe(true);
    expect(a.log).toEqual(['park']);
  });

  it('a scroll event or a touch start restores and re-arms; each event leaves one timer', () => {
    for (const ev of ['scroll', 'touch'] as const) {
      const a = env();
      const p = createUtPark(a.e);
      a.fire();
      a.event(ev);
      expect(p.isParked()).toBe(false);
      expect(a.log).toEqual(['park', 'unpark']);
      expect(a.timers.size).toBe(1);
      a.event('scroll');
      expect(a.timers.size).toBe(1);
    }
  });

  it('stop removes the listener and the timer, and restores a parked flag', () => {
    const a = env();
    const p = createUtPark(a.e);
    a.fire();
    p.stop();
    expect(a.log).toEqual(['park', 'unlisten', 'unpark']);
    expect(a.timers.size).toBe(0);
  });

  it('is an optimized class E variant with the Lean module', () => {
    const v = (part.variants as Record<string, { kind: string; visClass?: string; provenance?: { lean?: string } }>)['unthrottle-park']!;
    expect(v.kind).toBe('optimized');
    expect(v.visClass).toBe('E');
    expect(v.provenance?.lean).toBe('Fw.Parts.ScrollPark');
  });
});
