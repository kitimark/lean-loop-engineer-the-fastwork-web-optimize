/**
 * Track builder of morph.geom:on (no DOM). Every function restates a Lean definition of
 * lean/Fw/Parts/MorphGeom{,Rect,Earn,Anim}.lean in floats; `tracks.golden.test.ts` replays the `sample` lines of
 * packages/contracts/golden/morph-geom.jsonl against it (1e-6). TS stand-in: the Rat arithmetic and the 40-step bisection
 * are floats here; the Lean statements hold for the rational twins.
 */
import { tween } from '../morph.tween/logic';

export type Eng = 'webkit' | 'chromium';
export type Prop = 'translate' | 'scale' | 'transform' | 'opacity' | 'filter' | 'backdrop-filter';
export type Ks = 'grid' | 'unit' | 'earn' | 'panel' | 'fade' | 'time';

export interface Vp {
  w: number;
  h: number;
}

/** The measured sizes the tracks depend on (Lean `Ctx`). */
export interface Layout {
  eng: Eng;
  a: number;
  b: number;
  inset: number;
  logoW: number;
  lw: number;
  w0: number;
  gL: number;
  imgs: [number, number][][];
}

export interface Anim {
  el: string;
  i: number;
  j: number;
  prop: Prop;
  ks: Ks;
  offsets: number[];
  /** values[f][k]: function f at knot k */
  values: number[][];
}

export const FRAME_MS = 50 / 3;
export const FRAMES = 90;
export const TIME_END = FRAMES * FRAME_MS;
const DARK_CUT = 1 / 5;
const clamp01 = (x: number) => Math.min(1, Math.max(0, x));
const phone = (w: number) => w <= 640;
export const wp = (v: Vp) => (phone(v.w) ? v.w - 24 : Math.min(1398, v.w - 40));
export const hp = (v: Vp) => (phone(v.w) ? v.h - 24 : Math.min(820, v.h - 40));
const pillW = (v: Vp) => Math.min(984, v.w - (phone(v.w) ? 32 : 48));
const pillH = (v: Vp) => (phone(v.w) ? 52 : 64);
const wd = (v: Vp, m: number) => pillW(v) + (wp(v) - pillW(v)) * m;
const ht = (v: Vp, m: number) => pillH(v) + (hp(v) - pillH(v)) * m;
const top = (v: Vp, m: number) => 16 + ((phone(v.w) ? 12 : 20) - 16) * m;
const x0 = (v: Vp, m: number) => (wp(v) - wd(v, m)) / 2;
const y0 = (v: Vp, m: number) => top(v, m) - top(v, 1);
const rad = (v: Vp, m: number) => Math.min(32 - 12 * m, ht(v, m) / 2, wd(v, m) / 2);
const earnOut = (m: number) => clamp01(m / DARK_CUT);
const dP = (v: Vp, m: number) => y0(v, m) + ht(v, m) / 2 - hp(v) / 2;
const nCols = (v: Vp) => (phone(v.w) ? 3 : 5);
const cw = (v: Vp, m: number) => (1.06 * wd(v, m) - (nCols(v) - 1) * (phone(v.w) ? 8 : 12)) / nCols(v);
const panelO = (m: number) => clamp01((m - 0.08) / 0.72);
const fade = (m: number) => 1 - Math.min(1, m / 0.55);
const mKnot = (v: Vp) => 12 / (v.h - 52);

/** Lean `knots`: the grid whose chords stay within 1/64 px (phone: finer below the radius kink). */
export function gridKnots(v: Vp): number[] {
  const from = (p: number, h: number, k: number) => Array.from({ length: k + 1 }, (_, i) => p + i * h);
  if (!phone(v.w)) return from(0, 1 / 320, 320);
  const mk = mKnot(v);
  const n1 = Math.floor(mk * 320 * 16) + 1;
  const a = mk / n1;
  return [...Array.from({ length: n1 }, (_, i) => i * a), ...from(mk, (1 - mk) / 320, 320)];
}

const KNOTS: Record<Exclude<Ks, 'grid'>, number[]> = {
  unit: [0, 1],
  earn: [0, 0.2, 1],
  panel: [0, 0.08, 0.8, 1],
  fade: [0, 0.55, 1],
  time: Array.from({ length: FRAMES + 1 }, (_, k) => k * FRAME_MS),
};

const bez = (a: number, b: number, s: number) => 3 * (1 - s) * (1 - s) * s * a + 3 * (1 - s) * s * s * b + s * s * s;
function easeBez([x1, y1, x2, y2]: number[], t: number): number {
  if (t <= 0) return 0;
  if (t >= 1) return 1;
  let lo = 0;
  let hi = 1;
  for (let k = 0; k < 40; k++) {
    const mid = (lo + hi) / 2;
    if (bez(x1, x2, mid) < t) lo = mid;
    else hi = mid;
  }
  return bez(y1, y2, (lo + hi) / 2);
}

interface Tr {
  delay: number;
  dur: number;
}
const CURVE = [0.33, 0, 0.2, 1];
const MAXW_TR: Tr = { delay: 0, dur: 680 };
const OPACITY_TR: Tr = { delay: 120, dur: 320 };

/** Lean `shown`: the retargeted-transition run of one property over the 60 Hz grid (all frames at once). */
function shownRun(tr: Tr, g: number[]): number[] {
  const value = (r: { f: number; t: number; s: number; live: boolean }, now: number) =>
    r.live ? r.f + (r.t - r.f) * easeBez(CURVE, (now - r.s - tr.delay) / tr.dur) : r.t;
  let r = { f: g[0], t: g[0], s: 0, live: false };
  return g.map((gk, k) => {
    const now = k * FRAME_MS;
    if (k > 0 && gk !== g[k - 1]) r = { f: value(r, now), t: gk, s: now, live: true };
    return value(r, now);
  });
}

/** Lean `padRuns`: WebKit never starts the `padding-inline` transition. */
const padRuns = (e: Eng) => e === 'chromium';

export function buildAnims(v: Vp, c: Layout): Anim[] {
  const ph = phone(v.w);
  const grid = gridKnots(v);
  const one = (el: string, prop: Prop, ks: Ks, fns: ((x: number) => number)[], key: [number, number] = [0, 0]): Anim => {
    const xs = ks === 'grid' ? grid : KNOTS[ks];
    return { el, i: key[0], j: key[1], prop, ks, offsets: ks === 'time' ? xs.map((t) => t / TIME_END) : xs, values: fns.map((f) => xs.map(f)) };
  };
  const zero = () => 0;
  const unit = () => 1;
  const frames = Array.from({ length: FRAMES + 1 }, (_, k) => tween({ from: c.a, to: c.b, elapsed: k * FRAME_MS }).value);
  const maxW = shownRun(MAXW_TR, frames.map((m) => (1 - earnOut(m)) * (ph ? 152 : 176)));
  const padOf = (m: number) => (1 - earnOut(m)) * (ph ? 16 : 24);
  const pad = padRuns(c.eng) ? shownRun(MAXW_TR, frames.map(padOf)) : frames.map(padOf);
  const op = shownRun(OPACITY_TR, frames.map((m) => 1 - earnOut(m)));
  const width = frames.map((_, k) => Math.max(2 * pad[k], Math.min(maxW[k], c.lw + 2 * pad[k])));
  const atT = (arr: number[]) => (t: number) => arr[Math.min(FRAMES, Math.floor(t / FRAME_MS + 1e-9))];
  const gap = (m: number) => (1 - earnOut(m)) * (ph ? 4 : 8);
  const s = (m: number) => cw(v, m) / cw(v, 1);
  const tauX = (m: number) => (20 * wd(v, m)) / rad(v, m) - 2 * wp(v);
  const tauY = (m: number) => (20 * ht(v, m)) / rad(v, m) - 2 * hp(v);
  const out: Anim[] = [
    one('K0', 'transform', 'grid', [(m) => x0(v, m), (m) => y0(v, m), (m) => rad(v, m) / 20, (m) => rad(v, m) / 20]),
    one('K1', 'translate', 'grid', [tauX, zero]),
    one('K2', 'translate', 'grid', [(m) => -tauX(m), tauY]),
    one('K3', 'translate', 'grid', [tauX, zero]),
    one('U', 'transform', 'grid', [
      (m) => 2 * wp(v) - (20 * (x0(v, m) + wd(v, m))) / rad(v, m),
      (m) => 2 * hp(v) - (20 * (y0(v, m) + ht(v, m))) / rad(v, m),
      (m) => 20 / rad(v, m),
      (m) => 20 / rad(v, m),
    ]),
    one('G', 'backdrop-filter', 'unit', [(m) => 20 * (1 - m)]),
    one('D', 'opacity', 'unit', [(m) => m]),
    one('bar', 'translate', 'unit', [zero, (m) => y0(v, m)]),
    one('logo', 'translate', 'grid', [
      (m) => x0(v, m) + (c.inset + (wd(v, m) / 2 - c.inset) * m) - (m * c.logoW) / 2 - (wp(v) / 2 - c.logoW / 2),
      zero,
    ]),
    one('actions', 'translate', 'unit', [(m) => -x0(v, m), zero]),
    one('lang', 'translate', 'earn', [(m) => c.gL - gap(m), zero]),
    one('lang', 'transform', 'time', [(t) => c.w0 - atT(width)(t), zero, unit, unit]),
    one('earn', 'opacity', 'time', [atT(op)]),
    one('earn', 'filter', 'earn', [(m) => earnOut(m) * 10]),
    one('earn', 'translate', 'earn', [zero, (m) => earnOut(m) * -8]),
    one('earnClip', 'translate', 'time', [(t) => c.w0 - atT(width)(t), zero]),
    padRuns(c.eng)
      ? one('earnLabel', 'translate', 'time', [(t) => atT(pad)(t) - padOf(0), zero])
      : one('earnLabel', 'translate', 'earn', [(m) => padOf(m) - padOf(0), zero]),
    one('panel', 'translate', 'unit', [zero, (m) => dP(v, m)]),
    one('panel', 'scale', 'unit', [(m) => 0.96 + 0.04 * m, (m) => 0.96 + 0.04 * m]),
    one('panel', 'transform', 'unit', [zero, (m) => -dP(v, m), unit, unit]),
    one('panel', 'opacity', 'panel', [panelO]),
  ];
  if (v.w > 720) out.push(one('panel', 'filter', 'panel', [(m) => 12 * (1 - panelO(m))]));
  out.push(
    one('backdropClip', 'translate', 'unit', [(m) => 1.06 * x0(v, m), (m) => y0(v, m)]),
    one('Kb', 'translate', 'unit', [(m) => -2.12 * x0(v, m), (m) => ht(v, m) - hp(v)]),
    one('Ub', 'translate', 'unit', [(m) => 2.12 * x0(v, m), (m) => hp(v) - ht(v, m)]),
  );
  for (let i = 0; i < nCols(v); i++) out.push(one('column', 'translate', 'unit', [(m) => i * (cw(v, m) - cw(v, 1)), zero], [i, 0]));
  c.imgs.forEach((col, i) => col.forEach(([y], j) => out.push(one('image', 'transform', 'unit', [zero, (m) => (s(m) - 1) * y, s, s], [i, j]))));
  out.push(
    one('centre', 'translate', 'unit', [zero, (m) => dP(v, m)]),
    one('footer', 'translate', 'unit', [(m) => x0(v, m), (m) => y0(v, m) + ht(v, m) - hp(v)]),
    one('footerGrad', 'scale', 'unit', [(m) => wd(v, m) / wp(v), unit]),
    one('footerEnd', 'translate', 'unit', [(m) => -2 * x0(v, m), zero]),
    one('platform', 'opacity', 'fade', [fade]),
    one('platform', 'filter', 'fade', [(m) => 12 * (1 - fade(m))]),
  );
  return out;
}

/** Piecewise-linear value of function `f` of `a` at domain position `x` (m, or ms for time tracks). */
export function evalAt(a: Anim, f: number, x: number): number {
  const u = a.ks === 'time' ? x / TIME_END : x;
  const o = a.offsets;
  const ys = a.values[f];
  let k = 0;
  while (k < o.length - 2 && u > o[k + 1]) k++;
  return ys[k] + ((ys[k + 1] - ys[k]) * (u - o[k])) / (o[k + 1] - o[k]);
}

const n = (x: number) => String(Math.round(x * 1e4) / 1e4);

/** The CSS value of one keyframe (the shape of Lean `decl`). */
export function cssValue(p: Prop, xs: number[]): string {
  switch (p) {
    case 'translate':
      return `${n(xs[0])}px ${n(xs[1])}px`;
    case 'scale':
      return `${n(xs[0])} ${n(xs[1])}`;
    case 'transform':
      return `translate(${n(xs[0])}px, ${n(xs[1])}px) scale(${n(xs[2])}, ${n(xs[3])})`;
    case 'opacity':
      return n(xs[0]);
    case 'filter':
    case 'backdrop-filter':
      return `blur(${n(xs[0])}px)`;
  }
}

export interface Kf {
  offset: number;
  [prop: string]: string | number;
}

/** The keyframes of one effect: one per knot, one function-list shape everywhere, linear easing. */
export function keyframes(a: Anim): Kf[] {
  return a.offsets.map((offset, k) => ({ offset, [a.prop]: cssValue(a.prop, a.values.map((ys) => ys[k])) }));
}

/** `data-mg` selector of an effect's element (Lean `selector`). */
export function selector(a: Anim): string {
  const b = `[data-mg="${a.el}"]`;
  return a.el === 'column' ? `${b}[data-i="${a.i}"]` : a.el === 'image' ? `${b}[data-i="${a.i}"][data-j="${a.j}"]` : b;
}
