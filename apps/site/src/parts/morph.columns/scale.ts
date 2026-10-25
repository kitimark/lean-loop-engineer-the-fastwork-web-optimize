export const SCALE_MAX_W = 1000;
const PHONE_MAX_W = 640;
const GAP = 12;
const BLEED = 1.06;

export interface ScaleVars {
  readonly n: number;
  readonly cf: number;
  readonly a: number;
  readonly d: number;
}

const pillW = (w: number): number => Math.min(984, w - (w <= PHONE_MAX_W ? 32 : 48));
const panelW = (w: number): number => (w <= PHONE_MAX_W ? w - 24 : Math.min(1398, w - 40));
export const columnCount = (w: number): number => (w <= PHONE_MAX_W ? 3 : 5);

export function colW(w: number, m: number): number {
  const n = columnCount(w);
  const nav = pillW(w) + (panelW(w) - pillW(w)) * m;
  return (BLEED * nav - GAP * (n - 1)) / n;
}

export const scaleApplies = (w: number): boolean => w <= SCALE_MAX_W;

export function scaleVars(w: number): ScaleVars {
  const cf = colW(w, 1);
  const c0 = colW(w, 0);
  return { n: columnCount(w), cf, a: c0 / cf, d: c0 - cf };
}

export const sxAt = (v: ScaleVars, m: number): number => v.a + (1 - v.a) * m;

export const txAt = (v: ScaleVars, m: number, i: number): number => i * (1 - m) * v.d;

export function drawnEdges(v: ScaleVars, m: number, i: number): [number, number] {
  const left = i * (v.cf + GAP) + txAt(v, m, i);
  return [left, left + sxAt(v, m) * v.cf];
}
