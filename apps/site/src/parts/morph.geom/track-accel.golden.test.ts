import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { buildAnims, type Eng, type Layout } from './tracks';

type Line = { fn: string; in: Record<string, unknown>; out: Record<string, unknown> };
const lines = readFileSync(resolve(__dirname, '../../../../../packages/contracts/golden/parts/morph-track-accel.jsonl'), 'utf8')
  .trim()
  .split('\n')
  .map((l) => JSON.parse(l) as Line);

function sample(w: number, eng: Eng): Layout {
  const ph = w <= 640;
  const cols = ph ? 3 : 5;
  return {
    eng,
    a: 0,
    b: 1,
    inset: ph ? 16 : 24,
    logoW: ph ? 120 : 160,
    lw: ph ? 120 : 144,
    w0: ph ? 152 : 176,
    gL: 0,
    imgs: Array.from({ length: cols }, () => [[0, 200], [200, 200], [400, 200]]),
  };
}

const key = (a: { el: string; i: number; j: number; prop: string }) => `${a.el}:${a.i}:${a.j}:${a.prop}`;

describe('morph.geom tracks against the Lean track-accel golden', () => {
  it('every band viewport and engine lists the same tracks, in order, with the same keyframe sets', () => {
    const rows = lines.filter((l) => l.fn === 'tracks');
    expect(rows.length).toBe(24);
    for (const r of rows) {
      const i = r.in as { w: number; h: number; eng: Eng };
      const as = buildAnims({ w: i.w, h: i.h }, sample(i.w, i.eng));
      expect(as.map(key), `${i.w}x${i.h}:${i.eng}`).toEqual(r.out.keys);
      expect(as.map((a) => a.ks)).toEqual(r.out.ks);
      expect(as.length).toBe(r.out.n);
    }
  });

  it('the blur tracks are the tracks Chromium keeps on the main thread in geom-timed', () => {
    for (const r of lines.filter((l) => l.fn === 'tracks')) {
      const i = r.in as { w: number; h: number; eng: Eng };
      const blur = buildAnims({ w: i.w, h: i.h }, sample(i.w, i.eng)).filter((a) => a.prop === 'filter');
      expect(blur.length).toBe(r.out.blur);
      expect((r.out.timedMain as string[]).length).toBe(i.eng === 'chromium' ? blur.length : 0);
      expect(r.out.scrubbedMain).toBe(r.out.n);
      if (i.eng === 'chromium') expect(r.out.timedMain).toEqual(blur.map(key));
    }
  });
});
