import { describe, expect, it } from 'vitest';
import { readGolden } from '../../engine/golden.testutil';
import { REST_ATTR, kindOf, radiusOf, setRest, type FilterKind } from './rest.logic';

const golden = readGolden('morph.panel.rest', 'main');

function fakeEl() {
  const attrs = new Set<string>();
  let writes = 0;
  return {
    el: {
      hasAttribute: (n: string) => attrs.has(n),
      toggleAttribute: (n: string, force: boolean) => {
        writes += 1;
        if (force) attrs.add(n);
        else attrs.delete(n);
        return force;
      },
    },
    on: () => attrs.has(REST_ATTR),
    writes: () => writes,
  };
}

describe('morph.panel:rest golden (Lean MorphPanelRest)', () => {
  it('the filter decision and its blur radius equal the Lean rows at every listed morph value', () => {
    const rows = golden.filter((g) => g.fn === 'filter');
    expect(rows.length).toBeGreaterThan(10);
    for (const g of rows) {
      const m = (g.in as { mm: number }).mm / 1000;
      const out = g.out as { kind: FilterKind; radiusNum: number; radiusDen: number };
      expect(kindOf(m), JSON.stringify(g.in)).toBe(out.kind);
      expect(radiusOf(m), JSON.stringify(g.in)).toBeCloseTo(out.radiusNum / out.radiusDen, 9);
      expect(out.kind === 'none', JSON.stringify(g.in)).toBe(out.radiusNum === 0);
    }
  });

  it('the section writer follows the Lean kind frame by frame and writes the DOM only on the Lean toggle frames', () => {
    const rows = golden.filter((g) => g.fn === 'run');
    expect(rows.length).toBeGreaterThan(3);
    for (const g of rows) {
      const frames = (g.in as { frames: number[] }).frames;
      const out = g.out as { kinds: FilterKind[]; toggles: number };
      const f = fakeEl();
      const kinds = frames.map((mm) => setRest(f.el, mm / 1000));
      expect(kinds, JSON.stringify(g.in)).toEqual(out.kinds);
      expect(f.on()).toBe(out.kinds[out.kinds.length - 1] === 'none');
      expect(f.writes(), JSON.stringify(g.in)).toBe(out.toggles + (out.kinds[0] === 'none' ? 1 : 0));
    }
  });
});
