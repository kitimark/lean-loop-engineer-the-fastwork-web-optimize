import { describe, expect, it } from 'vitest';
import { readGolden } from '../../engine/golden.testutil';
import { createPanelWriter } from '../morph.panel/driver';
import { idleRemoved, idleStep, type IdleState } from './idle';

const golden = readGolden('morph-idle-none', 'main');

/** The attribute the panel's writer leaves for a milli-morph value: the same path the page takes to the removal. */
function sceneAttr(mm: number): string | null {
  let scene: string | null = null;
  const panel = {
    setAttribute: (n: string, v: string) => { if (n === 'data-start-selling-scene') scene = v; },
    removeAttribute: () => undefined,
  };
  createPanelWriter({ panel, cta: null }).apply(mm / 1000);
  return scene;
}

describe('morph.columns:idle-none golden', () => {
  it('the removal rule, read from the attribute the panel writer sets, equals the Lean scene rule at every listed morph value', () => {
    const rows = golden.filter((g) => g.fn === 'removed');
    expect(rows.length).toBeGreaterThan(5);
    for (const g of rows) {
      const mm = (g.in as { mm: number }).mm;
      expect(idleRemoved(sceneAttr(mm)), JSON.stringify(g.in)).toBe(g.out);
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
