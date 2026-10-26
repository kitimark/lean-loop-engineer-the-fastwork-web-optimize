import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import * as L from './logic';
import { createPause, type SvgClock } from './pause';

class FakeSvg implements SvgClock {
  accum = 0;
  last: number;
  paused = false;
  constructor(begin: number, private readonly clock: { t: number }) {
    this.last = begin;
  }
  elapsedMs(t = this.clock.t): number {
    return this.paused ? this.accum : t + this.accum - this.last;
  }
  pauseAnimations(): void {
    if (this.paused) return;
    this.accum += this.clock.t - this.last;
    this.paused = true;
  }
  unpauseAnimations(): void {
    if (!this.paused) return;
    this.last = this.clock.t;
    this.paused = false;
  }
  getCurrentTime(): number {
    return this.elapsedMs() / 1000;
  }
  setCurrentTime(seconds: number): void {
    const x = seconds * 1000;
    this.accum = this.paused ? x : 0;
    this.last = this.clock.t - x;
  }
}

interface RunEv {
  kind: 'hide' | 'reveal';
  t: number;
  frames: number[];
}

function run(side: L.Side, b: number, events: RunEv[]): [number, number][][] {
  const clock = { t: 0 };
  const svg = new FakeSvg(b, clock);
  const pause = createPause(() => [svg], () => clock.t);
  return events.map((e) => {
    clock.t = e.t;
    if (e.kind === 'hide') pause.away();
    else pause.back();
    return e.frames.map((f) => L.holdSample({ side, elapsed: svg.elapsedMs(f) }));
  });
}

goldenConformance('platform-glint-hold', {
  'glint.hold.const': () => ({ left: L.holdSegments('left'), right: L.holdSegments('right'), segMs: L.SEG_MS }),
  'glint.hold.plan': (i) => L.holdPlan(i.side as L.Side),
  'glint.hold.sample': (i) => L.holdSample({ side: i.side as L.Side, elapsed: i.elapsed as number }),
  'glint.hold.ticking': (i) => ({
    hold: L.holdTicking({ side: i.side as L.Side, elapsed: i.elapsed as number }),
    faithful: L.FAITHFUL_TICKING,
  }),
  'glint.hold.run': (i) => run(i.side as L.Side, i.b as number, i.events as RunEv[]),
});

describe('platform.glint:hold-freeze', () => {
  it('equals the faithful sample at every elapsed time', () => {
    for (const side of ['left', 'right'] as const) for (let e = 0; e < 30000; e += 37) {
        const a = L.holdSample({ side, elapsed: e });
        const b = L.sample({ side, elapsed: e });
        expect(a[0]).toBeCloseTo(b[0], 6);
        expect(a[1]).toBeCloseTo(b[1], 6);
      }
  });
  it('never ticks more than the original and ticks zero while holding', () => {
    for (const side of ['left', 'right'] as const) for (let e = 0; e < 30000; e += 250) expect(L.holdTicking({ side, elapsed: e })).toBeLessThanOrEqual(L.FAITHFUL_TICKING);
  });
  it('the ring starts each piece where the one before ends', () => {
    const els = L.holdElements('left', 'g');
    expect(els.filter((x) => x.anchor).length).toBe(2);
    expect(els.every((x) => x.fill === 'freeze')).toBe(true);
  });

  it('ids and begin references carry no hyphen (a hyphen in the id broke the begin chain in both engines)', () => {
    for (const side of ['left', 'right'] as const) {
      const els = L.holdElements(side, `fwglint${side}`);
      for (const e of els) {
        expect(e.id).toMatch(/^[A-Za-z0-9]+$/);
        expect(e.begin.replace('indefinite;', '')).toMatch(/^[A-Za-z0-9]*(\.end)?$/);
      }
    }
  });
});
