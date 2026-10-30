import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { buildAnims, keyframes, type Layout } from './tracks';

type Line = { fn: string; in: Record<string, unknown>; out: unknown };
const lines = readFileSync(resolve(__dirname, '../../../../../packages/contracts/golden/parts/flip-accel.jsonl'), 'utf8')
  .trim()
  .split('\n')
  .map((l) => JSON.parse(l) as Line);

const accelerated = new Set(lines.filter((l) => l.fn === 'css' && l.out === true).map((l) => l.in.css as string));

function sample(w: number): Layout {
  const ph = w <= 640;
  const cols = ph ? 3 : 5;
  return {
    eng: 'webkit',
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

describe('morph.geom end-of-page flip tracks against the Lean flip-accel golden (WebKit accelerated properties)', () => {
  it('every property the tracks animate is one WebKit accelerates, and none forces a recalc', () => {
    const props = lines.filter((l) => l.fn === 'prop');
    expect(props.length).toBe(6);
    for (const p of props) {
      const out = p.out as { accelerated: boolean; forces: boolean };
      expect(out.accelerated).toBe(true);
      expect(out.forces).toBe(false);
      expect(accelerated.has(p.in.prop as string)).toBe(true);
    }
  });

  it('layout properties and offset-path stay non-accelerated in the golden', () => {
    for (const c of ['max-width', 'padding-inline', 'width', 'left', 'offset-path']) expect(accelerated.has(c), c).toBe(false);
  });

  it('at every band viewport the built tracks use accelerated properties only, with explicit end keyframes', () => {
    const rows = lines.filter((l) => l.fn === 'tracks');
    expect(rows.length).toBe(12);
    for (const r of rows) {
      const i = r.in as { w: number; h: number };
      const out = r.out as { n: number; forcing: number; eligible: number; variant: number };
      const as = buildAnims({ w: i.w, h: i.h }, sample(i.w));
      const forcing = as.filter((a) => !accelerated.has(a.prop));
      const ends = as.filter((a) => a.offsets[0] === 0 && a.offsets[a.offsets.length - 1] === 1 && keyframes(a).length === a.offsets.length);
      expect(forcing.length, `${i.w}x${i.h}`).toBe(out.forcing);
      expect(as.length).toBe(out.n);
      expect(ends.length).toBe(out.eligible);
      expect(as.length - forcing.length).toBe(out.variant);
    }
  });
});
