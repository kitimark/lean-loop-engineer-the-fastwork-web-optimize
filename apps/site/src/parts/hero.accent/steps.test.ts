import { describe, expect, it } from 'vitest';
import { createBoil, type BoilTarget } from './boil';
import { bounds, chain, chainVal, CHAIN_CYCLES, CYCLE_MS, origVal, plan } from './steps';

describe('hero.accent variant steps (Lean HeroAccentOpt)', () => {
  it('bounds restate Lean `bounds`', () => {
    expect(bounds(0)).toEqual([{ at: 0, opacity: 1 }, { at: 199.98, opacity: 0 }]);
    expect(bounds(1).map((s) => s.at)).toEqual([0, 199.98, 399.96]);
    expect(bounds(2).map((s) => s.opacity)).toEqual([0, 1]);
    expect(bounds(3)).toEqual([]);
  });
  it('exact_chain_vis: the chain equals the step-end original at every instant of the window', () => {
    for (const j of [0, 1, 2]) {
      const c = chain(j, CHAIN_CYCLES);
      for (let e = 0; e < CHAIN_CYCLES * CYCLE_MS; e += 0.37) {
        const u = e - CYCLE_MS * Math.floor(e / CYCLE_MS);
        const near = [199.92, 199.98, 399.9, 399.96].some((b) => Math.abs(u - b) < 1e-6);
        if (near) continue; // float rounding of offset * 600 at the exact edge; Lean uses exact rationals
        expect(chainVal(c, e)).toBe(origVal(j, u));
      }
    }
  });
  it('the three boxes show exactly one frame at a time except the 0.06 ms overlap gaps', () => {
    for (let u = 0; u < CYCLE_MS; u += 0.5) {
      const shown = [0, 1, 2].filter((j) => origVal(j, u) === 1).length;
      expect(shown).toBe(1);
    }
  });
  it('plan resumes mid-window: same value as the full chain at the current instant, delays relative to now', () => {
    for (const j of [0, 1, 2])
      for (const elapsed of [0, 150, 599.5, 600, 1234.5]) {
        const p = plan(j, elapsed);
        const value = p.filter((s) => s.delay <= 0).at(-1)?.opacity ?? null;
        expect(value).toBe(chainVal(chain(j, 8), elapsed));
      }
  });
});

describe('boil driver', () => {
  it('creates one zero-duration fill-forwards animation per step, in order, and cancels them on end', () => {
    const made: { delay: number; v: number; cancelled: boolean }[][] = [[], [], []];
    const targets: BoilTarget[] = [0, 1, 2].map((j) => ({
      animate: (kf, o) => {
        const rec = { delay: o.delay, v: kf[0]!.opacity, cancelled: false };
        expect(o.duration).toBe(0);
        expect(o.fill).toBe('forwards');
        made[j]!.push(rec);
        return { cancel: () => void (rec.cancelled = true) };
      },
    }));
    const b = createBoil(targets);
    b.begin(0);
    expect(made.map((m) => m.length)).toEqual([8, 12, 8]);
    expect(b.count()).toBe(28);
    for (const m of made) expect(m.map((r) => r.delay)).toEqual([...m.map((r) => r.delay)].sort((x, y) => x - y));
    b.end();
    expect(made.flat().every((r) => r.cancelled)).toBe(true);
    expect(b.count()).toBe(0);
  });
});
