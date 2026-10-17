import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { SECTION_IDS, fit, height, type Model, type Sample } from './model';

const here = dirname(fileURLToPath(import.meta.url));
const read = (f: string) => JSON.parse(readFileSync(join(here, f), 'utf8'));
const rows: Sample[] = read('samples.json').rows;
const committed: Model = read('boxes.gen.json');
const gen = read('../breakpoints.gen.json');

describe('shell box model', () => {
  it('the committed model is what the fit gives for the committed samples', () => {
    const must = [...gen.matrix.probes.map((p: { width: number }) => Math.ceil(p.width)), ...gen.edgePairs.width.flat()];
    expect(fit(rows, 0.05, must)).toEqual(committed);
  });

  it('reproduces every sample (both heights, all four sections) within the tolerance', () => {
    for (const r of rows)
      for (const id of SECTION_IDS) expect(Math.abs(height(committed, id, r.w, r.h) - r[id]), `${id} ${r.w}x${r.h}`).toBeLessThanOrEqual(0.06);
  });

  it('is exact at every gate probe of the Lean matrix (fractional widths are hosted at the next whole px)', () => {
    for (const p of gen.matrix.probes as { width: number; height: number }[]) {
      const w = Math.ceil(p.width);
      const rowAt = rows.find((r) => r.w === Math.max(w, 320) && r.h === 900);
      if (!rowAt || p.height !== 900) continue;
      for (const id of SECTION_IDS) expect(Math.abs(height(committed, id, w, 900) - rowAt[id])).toBeLessThanOrEqual(0.06);
    }
  });

  it('the h-forms: a pain box is 3 h when 3 h is larger; commission switches at 1001', () => {
    expect(height(committed, 'pain', 400, 1000)).toBe(3000);
    expect(height(committed, 'commission', 1000, 900)).toBeCloseTo(height(committed, 'commission', 1000, 600), 6);
    expect(height(committed, 'commission', 1001, 1400)).toBeGreaterThan(height(committed, 'commission', 1001, 600));
  });
});
