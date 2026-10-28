import { DURATION_MS, ease, tween } from './logic';
import { FRAME_MS, evalAt, type Anim } from '../morph.geom/tracks';

export const EASING_CSS = `cubic-bezier(${1 / 3},1,${2 / 3},1)`;
export const REWARM_MS = 1000;
export const CUTS: readonly number[] = [0.001, 0.2, 0.4, 0.5225, 0.55, 0.72, 0.92];

export interface Knots {
  offsets: number[];
  values: number[];
}

function lin(p: number, a: number, q: number, b: number, m: number): number {
  return a + ((b - a) * (m - p)) / (q - p);
}

export function at(xs: number[], ys: number[], m: number): number {
  let k = 0;
  while (k < xs.length - 2 && m > xs[k + 1]) k++;
  return lin(xs[k], ys[k], xs[k + 1], ys[k + 1], m);
}

function rebaseUp(xs: number[], ys: number[], m0: number, g: number): Knots {
  const c = g - m0;
  if (c === 0) return { offsets: [0, 1], values: [at(xs, ys, m0), at(xs, ys, m0)] };
  const inner = xs.map((x, i) => i).filter((i) => xs[i] > m0 && xs[i] < g);
  return {
    offsets: [0, ...inner.map((i) => (xs[i] - m0) / c), 1],
    values: [at(xs, ys, m0), ...inner.map((i) => ys[i]), at(xs, ys, g)],
  };
}

export function rebase(xs: number[], ys: number[], m0: number, g: number): Knots {
  if (m0 < g) return rebaseUp(xs, ys, m0, g);
  return rebaseUp(xs.map((x) => -x).reverse(), [...ys].reverse(), -m0, -g);
}

const EPS = 1e-12;

export function crossMs(m0: number, g: number, c: number): number | null {
  for (let n = 0; n <= DURATION_MS; n++) {
    const v = m0 + (g - m0) * ease({ x: n / DURATION_MS });
    if (m0 <= g ? c <= v + EPS : v <= c + EPS) return n;
  }
  return null;
}

export const idealAt = (from: number, to: number, ms: number): number => tween({ from, to, elapsed: ms }).value;

export function crossings(m0: number, g: number): { c: number; ms: number }[] {
  const out: { c: number; ms: number }[] = [];
  for (const c of CUTS) {
    if (!((m0 < c && c <= g) || (g <= c && c < m0))) continue;
    const ms = crossMs(m0, g, c);
    if (ms !== null) out.push({ c, ms });
  }
  return out.sort((a, b) => a.ms - b.ms);
}

const timeOf = (m: number): number => DURATION_MS * (1 - Math.cbrt(1 - Math.min(1, Math.max(0, m))));

export function timeKnots(a: Anim, comp: number, m0: number, g: number): Knots {
  const end = a.offsets.length - 1;
  const ys = a.values[comp];
  if (m0 === 0 && g === 1) {
    const xs = a.offsets.slice(0, end + 1).map((o) => o * (end * FRAME_MS));
    return rebaseUp(xs, ys, 0, DURATION_MS);
  }
  const n = Math.ceil(DURATION_MS / FRAME_MS);
  const ts = [...Array.from({ length: n }, (_, k) => k * FRAME_MS), DURATION_MS];
  return { offsets: ts.map((t) => t / DURATION_MS), values: ts.map((t) => evalAt(a, comp, timeOf(idealAt(m0, g, t)))) };
}
