import { describe, expect, it } from 'vitest';
import { readGolden } from '../../engine/golden.testutil';
import { idleRemoved, idleStep, type IdleState } from './idle';

const golden = readGolden('morph-idle-none', 'main');

describe('morph.columns:idle-none golden', () => {
  it('the removal rule equals the Lean scene rule at every listed morph value', () => {
    const rows = golden.filter((g) => g.fn === 'removed');
    expect(rows.length).toBeGreaterThan(5);
    for (const g of rows) {
      const mm = (g.in as { mm: number }).mm;
      expect(idleRemoved(mm > 1 ? 'active' : 'paused'), JSON.stringify(g.in)).toBe(g.out);
    }
  });

  it('the run state machine equals the Lean variant clock after every prefix', () => {
    const rows = golden.filter((g) => g.fn === 'run');
    expect(rows.length).toBeGreaterThan(3);
    for (const g of rows) {
      const frames = (g.in as { frames: [number, number][] }).frames;
      let s: IdleState = { clock: 0, present: true };
      frames.forEach(([dt, mm], i) => {
        s = idleStep(s, dt, mm);
        expect(s, `${JSON.stringify(g.in)} @${i}`).toEqual((g.out as IdleState[])[i]);
      });
    }
  });
});
