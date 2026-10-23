import { describe, expect, it } from 'vitest';
import { readGolden } from '../../engine/golden.testutil';
import { createPanelWriter } from './driver';

const rows = readGolden('morph-idle-none', 'main').filter((g) => g.fn === 'removed');

/** The value the writer puts on `data-start-selling-scene` when it is driven with `morph`, null when it writes none. */
function sceneWritten(morph: number): string | null {
  let scene: string | null = null;
  const panel = {
    setAttribute: (n: string, v: string) => { if (n === 'data-start-selling-scene') scene = v; },
    removeAttribute: () => undefined,
  };
  createPanelWriter({ panel, cta: null }).apply(morph);
  return scene;
}

describe('morph.panel writer: the scene attribute against the Lean scene rule (morph-idle-none golden)', () => {
  it('writes paused exactly where Lean says the removal holds, at every listed milli-morph value', () => {
    expect(rows.length).toBeGreaterThan(5);
    for (const g of rows) {
      const mm = (g.in as { mm: number }).mm;
      expect(sceneWritten(mm / 1000), JSON.stringify(g.in)).toBe(g.out ? 'paused' : 'active');
    }
  });

  it('the listed values reach both sides of the threshold', () => {
    expect(rows.some((g) => g.out === true)).toBe(true);
    expect(rows.some((g) => g.out === false)).toBe(true);
  });
});
