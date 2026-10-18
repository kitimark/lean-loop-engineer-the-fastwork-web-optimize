import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import * as L from './logic';

goldenConformance('people.card', {
  clamp01: (i) => L.clamp01({ x: i.x as number }),
  smooth: (i) => L.smooth({ x: i.x as number }),
  coverage: (i) => L.coverage({ bottom: i.bottom as number, vh: i.vh as number }),
  target: (i) => L.target({ reduced: i.reduced as boolean, t: i.t as number }),
  lerp: (i) => L.lerp({ reduced: i.reduced as boolean, o: i.o as number, n: i.n as number }),
  pending: (i) => L.pending({ n: i.n as number, o: i.o as number }),
  shrinking: (i) => L.shrinking({ t: i.t as number }),
  revealed: (i) => L.revealed({ reduced: i.reduced as boolean, top: i.top as number, height: i.height as number, vh: i.vh as number }),
  scale: (i) => L.scale({ s: i.s as number }),
  painDark: (i) => L.painDark({ narrow: i.narrow as boolean, headerTop: i.headerTop as number }),
});

describe('people.card frame', () => {
  const base = { reduced: false, narrow: false, vh: 900, track: { top: 0, height: 1800 }, cardBottom: 1000, headerTop: 500, shrink: 0 };
  it('is hidden until the hero track is 72 % scrolled', () => {
    expect(L.frame(base).revealed).toBe(false);
    expect(L.frame({ ...base, track: { top: -648, height: 1800 } }).revealed).toBe(true);
    expect(L.frame({ ...base, track: null }).revealed).toBe(true);
  });
  it('converges to the target and stops asking for frames', () => {
    let s = 0;
    let frames = 0;
    for (;;) {
      const r = L.frame({ ...base, cardBottom: 200, shrink: s });
      s = r.shrink!;
      frames++;
      if (!r.again) break;
      expect(frames).toBeLessThan(80);
    }
    expect(s).toBe(1);
  });
  it('reduced motion jumps in one frame', () => {
    const r = L.frame({ ...base, reduced: true, cardBottom: 200 });
    expect(r.shrink).toBe(1);
    expect(r.again).toBe(false);
  });
  it('the Pain section is dark at once on wide viewports and below the heading on narrow ones', () => {
    expect(L.frame(base).painDark).toBe(true);
    expect(L.frame({ ...base, narrow: true }).painDark).toBe(false);
    expect(L.frame({ ...base, narrow: true, headerTop: 0 }).painDark).toBe(true);
  });
});
