// Shell box model (PLAN rev 9 Q36): the outer border-box height of the original's four in-flow sections as a pure
// function of the viewport (w, h), fitted to measured samples (samples.json, from scripts/shell-measure.mjs).
// TS stand-in: no Lean spec yet (listed in docs/team/handoffs/shells.md). Pure; no DOM; erasable TS only (Node runs it).
//
// Shape of the original, read off the samples (MEASURED, 2 heights x 150 widths; h-forms confirmed at 18 heights):
//   people      w<=860: B(w);   w>=861: B(w) + 3.15 h + clamp(743, h - 80, 820)
//   pain        max(3 h, 2 h + P(w)),  P = 0 below 861
//   commission  w<=1000: B(w);  w>=1001: max(0.06 h + D(w), 1.06 h + 48)
//   platform    B(w)            (no h term)
// B, P, D, platform are piecewise linear in the layout width with step edges (text wraps), represented as a sum of
// clamped ramps so that CSS needs no media query: v0 + sum s_i * clamp(0, W - k_i, d_i), W = max(w, 320) (the original floors at 320).

export const SECTION_IDS = ['pain', 'commission', 'platform'] as const; // people: ported (people.card ...), no shell box
export type SectionId = 'people' | (typeof SECTION_IDS)[number];

export interface Sample {
  w: number;
  h: number;
  people: number;
  pain: number;
  commission: number;
  platform: number;
}
export type Knot = [number, number];

/** Where an h-dependent term starts (first width with it): people 861, pain 861, commission 1001. */
export const GATE = { people: 860, commission: 1000 } as const;
export const PEOPLE_H = { slopeVh: 3.15, clampLo: 743, clampOffset: 80, clampHi: 820 } as const;
export const COMMISSION_H = { padVh: 0.06, minVh: 1.06, minPx: 48 } as const;
export const PAIN_H = { totalVh: 3, holdVh: 2 } as const;
const FLOOR = 320;

const row = (rows: Sample[], w: number, h: number): Sample => {
  const r = rows.find((x) => x.w === w && x.h === h);
  if (!r) throw new Error(`no sample at ${w}x${h}`);
  return r;
};

/** The h-free base series per section, one value per measured width (from the h = 900 rows; pain and commission D from h = 600). */
export function baseSeries(rows: Sample[]): Record<SectionId, Knot[]> {
  const ws = [...new Set(rows.map((r) => r.w))].sort((a, b) => a - b);
  const out: Record<SectionId, Knot[]> = { people: [], pain: [], commission: [], platform: [] };
  for (const w of ws) {
    const a = row(rows, w, 600);
    const b = row(rows, w, 900);
    out.people.push([w, w <= GATE.people ? b.people : b.people - peopleH(900)]);
    out.pain.push([w, w <= GATE.people ? 0 : a.pain - PAIN_H.holdVh * 600]);
    out.commission.push([w, w <= GATE.commission ? b.commission : a.commission - COMMISSION_H.padVh * 600]);
    out.platform.push([w, b.platform]);
  }
  return out;
}

export const peopleH = (h: number): number =>
  PEOPLE_H.slopeVh * h + Math.min(Math.max(h - PEOPLE_H.clampOffset, PEOPLE_H.clampLo), PEOPLE_H.clampHi);

/** Douglas-Peucker over (w, v): the fewest knots (kept = must + chosen) such that every point is within tol of the polyline. */
export function reduceKnots(points: Knot[], tol: number, must: Set<number>): Knot[] {
  const keep = new Set<number>([0, points.length - 1]);
  points.forEach((p, i) => must.has(p[0]) && keep.add(i));
  const refine = (lo: number, hi: number) => {
    let worst = -1;
    let at = -1;
    for (let i = lo + 1; i < hi; i++) {
      const [x0, y0] = points[lo]!;
      const [x1, y1] = points[hi]!;
      const [x, y] = points[i]!;
      const e = Math.abs(y0 + ((y1 - y0) * (x - x0)) / (x1 - x0) - y);
      if (e > worst) {
        worst = e;
        at = i;
      }
    }
    if (worst > tol) {
      keep.add(at);
      refine(lo, at);
      refine(at, hi);
    }
  };
  const idx = [...keep].sort((a, b) => a - b);
  for (let i = 0; i + 1 < idx.length; i++) refine(idx[i]!, idx[i + 1]!);
  return [...keep].sort((a, b) => a - b).map((i) => points[i]!);
}

export interface Hinge {
  /** value at W = 320 */
  v0: number;
  /** [k, d, s]: adds s * clamp(0, W - k, d); one segment per knot interval (no large opposite terms, so float32 CSS maths stays exact) */
  segs: [number, number, number][];
}

const r4 = (x: number) => Math.round(x * 1e4) / 1e4;
const r6 = (x: number) => Math.round(x * 1e6) / 1e6;

/** Continuous piecewise-linear through the knots, flat after the last one, as a sum of clamped ramps. */
export function toHinge(knots: Knot[]): Hinge {
  const ks = knots.map(([k, v]) => [Math.max(k, FLOOR), r4(v)] as Knot);
  const segs: [number, number, number][] = [];
  for (let i = 0; i + 1 < ks.length; i++) {
    const [x0, y0] = ks[i]!;
    const [x1, y1] = ks[i + 1]!;
    if (x1 === x0) continue;
    const s = r6((y1 - y0) / (x1 - x0));
    if (s !== 0) segs.push([x0, x1 - x0, s]);
  }
  return { v0: ks[0]![1], segs };
}

export const evalHinge = (hg: Hinge, w: number): number => {
  const W = Math.max(w, FLOOR);
  return hg.v0 + hg.segs.reduce((a, [k, d, s]) => a + s * Math.min(Math.max(W - k, 0), d), 0);
};

export interface Model {
  schema: 'fw.shells.boxes/1';
  tolerance: number;
  sections: Record<SectionId, Hinge>;
}

export function fit(rows: Sample[], tol: number, mustWidths: number[]): Model {
  const base = baseSeries(rows);
  const must = new Set(mustWidths.map((w) => Math.max(w, FLOOR)));
  const sections = {} as Record<SectionId, Hinge>;
  for (const id of SECTION_IDS) sections[id] = toHinge(reduceKnots(base[id], tol, must));
  return { schema: 'fw.shells.boxes/1', tolerance: tol, sections };
}

/** Evaluates the whole model: the height the shell takes at viewport w x h. */
export function height(m: Model, id: SectionId, w: number, h: number): number {
  const b = evalHinge(m.sections[id], w);
  switch (id) {
    case 'people':
      return b + (w >= GATE.people + 1 ? peopleH(h) : 0);
    case 'pain':
      return Math.max(PAIN_H.totalVh * h, PAIN_H.holdVh * h + b);
    case 'commission':
      return w >= GATE.commission + 1
        ? Math.max(b + COMMISSION_H.padVh * h, COMMISSION_H.minVh * h + COMMISSION_H.minPx)
        : b;
    case 'platform':
      return b;
  }
}

const n = (x: number) => String(r6(x));
const px = (x: number) => `${n(x)}px`;

/** The calc() of the ramp sum, with `--fw-w` holding max(100vw, 320px). */
export function hingeCss(hg: Hinge): string {
  const terms = hg.segs.map(([k, d, c]) => `${c < 0 ? '-' : '+'} ${n(Math.abs(c))} * clamp(0px, var(--fw-w) - ${px(k)}, ${px(d)})`);
  return `${px(hg.v0)} ${terms.join(' ')}`;
}

/** Gate: 0px for W <= edge, huge for W > edge (integer widths), so min(x, gate) is x only past the edge. */
const gate = (edge: number) => `calc(100000 * max(0px, var(--fw-w) - ${edge}px))`;

/** Generated CSS (a CSS Module) for one section; the model decides every number. */
export function sectionCss(m: Model, id: SectionId): string {
  const hg = hingeCss(m.sections[id]);
  const head = `/* Generated by scripts/gen-shells.mjs from src/shells/samples.json; do not edit. Static box of the section "${id}" (PLAN Q36). */\n@layer parts {\n`;
  const root = `  .box {\n    --fw-w: max(100vw, 320px);\n    box-sizing: border-box;\n    position: relative;\n`;
  let body: string;
  switch (id) {
    case 'people':
      body =
        `    margin-top: calc(1px - 100svh);\n` +
        `    height: calc(${hg} + min(calc(${n(PEOPLE_H.slopeVh * 100)}svh + clamp(${PEOPLE_H.clampLo}px, calc(100vh - ${PEOPLE_H.clampOffset}px), ${PEOPLE_H.clampHi}px)), ${gate(GATE.people)}));\n`;
      break;
    case 'pain':
      body =
        `    margin-top: -100svh;\n` +
        `    height: max(${n(PAIN_H.totalVh * 100)}svh, calc(${n(PAIN_H.holdVh * 100)}svh + ${hg}));\n`;
      break;
    case 'commission':
      body =
        `    margin-top: -100svh;\n` +
        `    height: max(calc(${hg} + min(${n(COMMISSION_H.padVh * 100)}svh, ${gate(GATE.commission)})), min(calc(${n(COMMISSION_H.minVh * 100)}svh + ${COMMISSION_H.minPx}px), ${gate(GATE.commission)}));\n`;
      break;
    case 'platform':
      body = `    height: calc(${hg});\n`;
      break;
  }
  return `${head}${root}${body}  }\n}\n`;
}
