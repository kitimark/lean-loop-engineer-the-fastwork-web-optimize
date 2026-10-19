/**
 * Pure logic of pain.notes (no DOM): the sticky notes of the Pain section. Restated from the original
 * (nodes/2.DyWL8TcE.js): palette, rotations, text pool 4416-4421; base notes 4422-4464; clamp and overlap 4488-4504;
 * avoid box 4505-4510; jittered placement 4535-4548; text pick 4549-4554; base layout 4555-4589; the tick 4590-4646;
 * drag and keys 4647-4688, 4712-4713; visibility rule 4698-4703.
 * Spec and proofs: lean/Fw/Parts/PainNotes.lean (and Pain.lean). Golden vectors:
 * packages/contracts/golden/parts/pain.notes.jsonl (logic.test.ts).
 *
 * Delta from the original, by design (PLAN section 4.3): randomness comes from the seeded `mulberry` stream, not
 * `Math.random()`, and the candidate shuffle draws without replacement instead of a random-comparator sort.
 */

/** The commission card the notes avoid (the original's `.commission-card`): the hook on our card. */
export const PAIN_SELECTOR = '[data-fw="pain"]';
export const PAIN_COPY_SELECTOR = '[data-fw="pain-copy"]';
/** Client-written hook on each note (index.tsx renders it); the footprint reports the templated query as `templated-selector`. */
export const NOTE_SELECTOR = (id: string | number): string => `[data-fw-note="${id}"]`;
export const CARD_SELECTOR = '[data-fw="commission-card"]';


export const NOTE_SIZE = 240;
export const MAX_EXTRAS = 12;
export const INTERVAL_MS = 3000;
export const VISIBLE_RATIO = 0.12;
export const CARD_CUT = 0.995;
export const MIN_STAGE = 8;
export const JITTER_SPAN = 3.5;
export const KEY_STEP = 1.5;
export const PALETTE = ['#b3efbd', '#ffe299', '#b3f4ef', '#d3bdff', '#e6e6e6', '#ffafa3', '#ffd3a8'] as const;
export const ROTATIONS = [-9, -7, -5, -3, -2, 2, 3, 4, 5, 6, 8, -8, 7, -4, 9, -6] as const;
export const TEXT_POOL = [15, 21, 16, 12, 17, 13, 22, 14, 18, 20, 19, 23] as const;
export const STICK_MS = 560;
export const STICK_SCALE0 = 1.14;

export interface Box {
  left: number;
  top: number;
  width: number;
  height: number;
}
export interface Note {
  id: string;
  text: number;
  bg: string;
  rotate: number;
  left: number;
  top: number;
  z: number;
  extra: boolean;
}

/** JS 4488 `L`: `min(hi, max(lo, x))`. */
export const clampTo = ({ x, lo, hi }: { x: number; lo: number; hi: number }): number => Math.min(hi, Math.max(lo, x));

/** JS 4491 `te`: the boxes come within `gap` of each other. */
export function overlaps({ a, b, gap }: { a: Box; b: Box; gap: number }): boolean {
  return !(
    a.left + a.width + gap <= b.left ||
    b.left + b.width + gap <= a.left ||
    a.top + a.height + gap <= b.top ||
    b.top + b.height + gap <= a.top
  );
}

/** JS 4505 `re`: the box kept clear around the copy block, in percent of the stage. */
export function avoidBox({ copyTop, copyH, stageTop, stageH }: { copyTop: number; copyH: number; stageTop: number; stageH: number }): Box {
  const n = ((copyTop - stageTop - 36) / stageH) * 100;
  const r = ((copyH + 72) / stageH) * 100;
  const i = Math.max(0, n);
  return { left: 0, top: i, width: 100, height: Math.min(100 - i, r) };
}

/** JS 4582: left in percent on the 1440 x 868 design canvas centred on the stage. */
export const baseLeft = ({ stageW, leftPx }: { stageW: number; leftPx: number }): number => (((stageW - 1440) / 2 + leftPx) / stageW) * 100;
/** JS 4583: top in percent. */
export const baseTop = ({ stageH, topPx }: { stageH: number; topPx: number }): number => (((stageH - 868) / 2 + topPx) / stageH) * 100;

const SIZE = { p: [255.878, 252.167], m: [248.09, 244.232], h: [263.354, 259.794] } as const;
/** The five desktop base notes (JS 4428-4464): design position, size class, text key, colour, rotation, z. */
const BASE = [
  { x: 330, y: 292.7411193847656, k: 'p', text: 12, bg: '#b3efbd', rotate: -4, z: 1 },
  { x: 799, y: 266.3758850097656, k: 'm', text: 14, bg: '#ffafa3', rotate: -2, z: 2 },
  { x: 560.462890625, y: 313.9999084472656, k: 'p', text: 13, bg: '#d3bdff', rotate: 4, z: 3 },
  { x: 677, y: 479.7415466308594, k: 'p', text: 15, bg: '#b3f4ef', rotate: -4, z: 4 },
  { x: 430.4625244140625, y: 499, k: 'p', text: 16, bg: '#ffe299', rotate: 4, z: 5 },
] as const;

/** The eleven notes of the narrow layout (JS 4465-4477). */
const NARROW = [
  { x: 218, y: 353, k: 'p', text: 15, bg: '#b3f4ef', rotate: -4, z: 1 },
  { x: 15, y: 437, k: 'h', text: 21, bg: '#e6e6e6', rotate: -6, z: 2 },
  { x: 392, y: 401, k: 'p', text: 16, bg: '#ffe299', rotate: 4, z: 3 },
  { x: 218, y: 479, k: 'p', text: 12, bg: '#b3efbd', rotate: -4, z: 4 },
  { x: 604, y: 460, k: 'p', text: 17, bg: '#e6e6e6', rotate: 4, z: 5 },
  { x: 413, y: 496, k: 'p', text: 13, bg: '#d3bdff', rotate: 4, z: 6 },
  { x: 36, y: 588, k: 'p', text: 22, bg: '#d3bdff', rotate: 4, z: 7 },
  { x: 303, y: 578, k: 'm', text: 14, bg: '#ffafa3', rotate: -2, z: 8 },
  { x: 215, y: 675, k: 'p', text: 18, bg: '#ffd3a8', rotate: -4, z: 9 },
  { x: 566, y: 591, k: 'm', text: 20, bg: '#b3efbd', rotate: -2, z: 10 },
  { x: 390, y: 664, k: 'p', text: 19, bg: '#ffe299', rotate: 4, z: 11 },
] as const;

/** JS 4555-4588 `ce`: the base notes on the canvas (`stageW` x `stageH` px); `narrow` is `(width<=860px)`. */
export function baseLayout({ narrow, stageW, stageH }: { narrow: boolean; stageW: number; stageH: number }): Note[] {
  const list: ReadonlyArray<{ x: number; y: number; k: 'p' | 'm' | 'h'; text: number; bg: string; rotate: number; z: number }> = narrow ? NARROW : BASE;
  return list.map((b, i) => {
    const [w, h] = SIZE[b.k];
    const leftPx = b.x + w / 2 - 120;
    const topPx = b.y + h / 2 - 120;
    const left = narrow ? ((stageW - 860) / 2 + leftPx) / stageW * 100 : baseLeft({ stageW, leftPx });
    const top = narrow ? ((topPx - 16) / stageH) * 100 : baseTop({ stageH, topPx });
    return { id: `base-${i}`, text: b.text, bg: b.bg, rotate: b.rotate, left, top, z: b.z, extra: false };
  });
}

export type Tick = 'skip' | 'clear' | 'add';

/** JS 4590-4603 `le` before any randomness. */
export function tick(i: {
  visible: boolean;
  dragging: boolean;
  extras: number;
  narrow: boolean;
  reduced: boolean;
  cardTop: number | null;
  vh: number;
  stageW: number;
  stageH: number;
}): Tick {
  const go = i.visible && !i.dragging && i.extras < MAX_EXTRAS && !i.narrow && !i.reduced;
  if (!go) return 'skip';
  if (i.cardTop !== null && i.cardTop < i.vh * CARD_CUT) return 'clear';
  if (i.stageW < MIN_STAGE || i.stageH < MIN_STAGE) return 'skip';
  return 'add';
}

/** JS 4700: the tick runs while the section shows at least 12 %. */
export const visible = ({ intersecting, ratio }: { intersecting: boolean; ratio: number }): boolean => intersecting && ratio >= VISIBLE_RATIO;

/** Seeded stream `mulberry32` (Lean `mulberry`): next state and a draw in [0, 1). */
export function mulberry({ seed }: { seed: number }): { state: number; value: number } {
  const a = (seed + 0x6d2b79f5) >>> 0;
  let t = Math.imul(a ^ (a >>> 15), a | 1);
  t = (t + Math.imul(t ^ (t >>> 7), t | 61)) ^ t;
  return { state: a, value: ((t ^ (t >>> 14)) >>> 0) / 4294967296 };
}

/** A stateful stream over `mulberry`. */
export interface Rng {
  draw(): number;
  state(): number;
}
export function createRng(seed: number): Rng {
  let s = seed >>> 0;
  return {
    draw() {
      const o = mulberry({ seed: s });
      s = o.state;
      return o.value;
    },
    state: () => s,
  };
}

/** `Math.floor(r * n)` (Lean `idx`). */
export const idx = ({ r, n }: { r: number; n: number }): number => Math.floor(r * n);

/** Draw without replacement (Lean `permute`): one draw per element. */
export function permute<T>({ draws, xs }: { draws: readonly number[]; xs: readonly T[] }): T[] {
  const rest = [...xs];
  const out: T[] = [];
  for (const r of draws) {
    if (rest.length === 0) break;
    const k = idx({ r, n: rest.length });
    const [x] = rest.splice(k, 1);
    out.push(x as T);
  }
  return draws.length >= xs.length ? out : [...out, ...rest];
}

/** JS 4541-4542: a jittered start, held inside the stage. */
export const jit = ({ c, r, s }: { c: number; r: number; s: number }): number =>
  clampTo({ x: c + (r - 0.5) * JITTER_SPAN, lo: 0, hi: Math.max(0, 100 - s) });

/** JS 4549 `oe`: a text key not on the stage, else any (Lean `pickText`). */
export function pickText({ used, r }: { used: readonly number[]; r: number }): number {
  const free = TEXT_POOL.filter((k) => !used.includes(k));
  const pool: readonly number[] = free.length === 0 ? TEXT_POOL : free;
  return pool[idx({ r, n: pool.length })] ?? 15;
}

export const rotation = ({ j }: { j: number }): number => ROTATIONS[j % 16] ?? -4;

/** The percent box of a note on a stage of the given px size (JS 4608-4613). */
export const noteBox = (n: Pick<Note, 'left' | 'top'>, stageW: number, stageH: number): Box => ({
  left: n.left,
  top: n.top,
  width: (NOTE_SIZE / stageW) * 100,
  height: (NOTE_SIZE / stageH) * 100,
});

/** JS 4535 `ae`: place a new note near an existing one; null when nothing exists to start from. */
function place(cands: Box[], w: number, h: number, avoid: Box[], rng: Rng): [number, number] | null {
  if (cands.length === 0) return null;
  const draws = Array.from({ length: cands.length }, () => rng.draw());
  const order = permute({ draws, xs: cands });
  for (const c of order) {
    const r1 = rng.draw();
    const r2 = rng.draw();
    const l = jit({ c: c.left, r: r1, s: w });
    const t = jit({ c: c.top, r: r2, s: h });
    if (!avoid.some((a) => overlaps({ a: { left: l, top: t, width: w, height: h }, b: a, gap: 0 }))) return [l, t];
  }
  const first = order[0];
  if (!first) return null;
  return [clampTo({ x: first.left, lo: 0, hi: Math.max(0, 100 - w) }), clampTo({ x: first.top, lo: 0, hi: Math.max(0, 100 - h) })];
}

const dist = (a: Box, b: Box): number => {
  const dx = a.left + a.width / 2 - (b.left + b.width / 2);
  const dy = a.top + a.height / 2 - (b.top + b.height / 2);
  return Math.sqrt(dx * dx + dy * dy);
};

/** JS 4511 `ie`: the scored placement (canvas 1100 px and up): 120 tries, best clean candidate else best overall. */
function scoredPlace(w: number, h: number, base: Box[], avoid: Box[], extras: Box[], rng: Rng): [number, number] | null {
  const a = Math.max(0, 100 - w);
  const o = Math.max(0, 100 - h);
  let best: { l: number; t: number; score: number } | null = null;
  let any: { l: number; t: number; score: number } | null = null;
  for (let k = 0; k < 120; k++) {
    const l = rng.draw() * a;
    const t = rng.draw() * o;
    const d: Box = { left: l, top: t, width: w, height: h };
    if (avoid.some((e) => overlaps({ a: d, b: e, gap: 0 }))) continue;
    let f = 0;
    let p = 0;
    let m = Infinity;
    let hh = Infinity;
    for (const e of base) {
      if (overlaps({ a: d, b: e, gap: 1.2 })) f += 1;
      m = Math.min(m, dist(d, e));
    }
    for (const e of extras) {
      if (overlaps({ a: d, b: e, gap: 1.2 })) p += 1;
      hh = Math.min(hh, dist(d, e));
    }
    if (!Number.isFinite(hh)) hh = 80;
    const g = +(hh < Math.max(w, h) * 0.85);
    const score = -f * 600 - p * 220 - g * 180 + m * 0.9 + hh * 2.4 + rng.draw() * 8;
    const cand = { l, t, score };
    if (f === 0 && p === 0 && (!best || score > best.score)) best = cand;
    if (!any || score > any.score) any = cand;
  }
  const r = best ?? any;
  return r ? [r.l, r.t] : null;
}

/** JS 4604-4645 after the guards (Lean `addExtra`): the new extra note, or null when nothing fits. */
export function addExtra(i: { stageW: number; stageH: number; base: readonly Note[]; extras: readonly Note[]; avoid: Box[]; j: number }, rng: Rng): Note | null {
  const w = (NOTE_SIZE / i.stageW) * 100;
  const h = (NOTE_SIZE / i.stageH) * 100;
  const bb = i.base.map((n) => noteBox(n, i.stageW, i.stageH));
  const eb = i.extras.map((n) => noteBox(n, i.stageW, i.stageH));
  const p = i.stageW < 1100 ? place([...bb, ...eb], w, h, i.avoid, rng) : scoredPlace(w, h, bb, i.avoid, eb, rng);
  if (!p) return null;
  const r1 = rng.draw();
  const r2 = rng.draw();
  return {
    id: `extra-${i.j}`,
    text: pickText({ used: [...i.base, ...i.extras].map((n) => n.text), r: r1 }),
    bg: PALETTE[idx({ r: r2, n: PALETTE.length })] ?? '#b3efbd',
    rotate: rotation({ j: i.j }),
    left: p[0],
    top: p[1],
    z: 10 + i.extras.length,
    extra: true,
  };
}

/** The golden `session`: base layout then `ticks` ticks (visible, wide, no reduced motion, card below the fold). */
export function session(i: { stageW: number; stageH: number; seed: number; copyTop: number; copyH: number; stageTop: number; ticks: number }): Note[] {
  const rng = createRng(i.seed);
  const avoid = [avoidBox({ copyTop: i.copyTop, copyH: i.copyH, stageTop: i.stageTop, stageH: i.stageH })];
  const base = baseLayout({ narrow: false, stageW: i.stageW, stageH: i.stageH });
  const extras: Note[] = [];
  let j = 0;
  for (let k = 0; k < i.ticks; k++) {
    const t = tick({ visible: true, dragging: false, extras: extras.length, narrow: false, reduced: false, cardTop: null, vh: 900, stageW: i.stageW, stageH: i.stageH });
    if (t !== 'add') continue;
    const n = addExtra({ stageW: i.stageW, stageH: i.stageH, base, extras, avoid, j }, rng);
    if (n) {
      extras.push(n);
      j += 1;
    }
  }
  return [...base, ...extras];
}

/** JS 4650-4654: whether a pointer-down starts a drag. */
export const dragAllowed = ({ c860, button, mouse }: { c860: boolean; button: number; mouse: boolean }): boolean => !c860 && !(button !== 0 && mouse);

/** JS 4712-4713: position while dragging, percent, held inside the stage. */
export const dragPos = ({ origin, start, cur, container, sizePct }: { origin: number; start: number; cur: number; container: number; sizePct: number }): number =>
  clampTo({ x: origin + ((cur - start) / container) * 100, lo: 0, hi: 100 - sizePct });

/** JS 4672: arrow-key step in percent. */
export function keyDelta({ key }: { key: string }): [number, number] | null {
  switch (key) {
    case 'ArrowLeft':
      return [-KEY_STEP, 0];
    case 'ArrowRight':
      return [KEY_STEP, 0];
    case 'ArrowUp':
      return [0, -KEY_STEP];
    case 'ArrowDown':
      return [0, KEY_STEP];
    default:
      return null;
  }
}

/** JS 4676-4677: position after a key step. */
export const keyPos = ({ pos, delta, sizePct }: { pos: number; delta: number; sizePct: number }): number => clampTo({ x: pos + delta, lo: 0, hi: 100 - sizePct });

/** The constants of `pain-note-stick` the CSS module restates (CSS 2273-2298). */
export const stickTiming = () => ({ durationMs: STICK_MS, scaleFrom: STICK_SCALE0, x1: 0.33, y1: 1, x2: 0.68, y2: 1, opacityFrom: 0 });

/**
 * The scene gate of the whole Pain section (JS 2681-2783 `dE`, registered at 4736 with `deferRendering` and root margin
 * `150% 0px`). Spec: Lean `PainNotes.sceneActive`, `Render.after`, `resize_follows_scene`.
 */
export const SCENE_MARGIN = '150% 0px';
/** JS 2723-2726 `lE`: in range from one viewport above to two below. */
export const sceneActive = ({ top, bottom, h }: { top: number; bottom: number; h: number }): boolean => -h <= bottom && top <= 2 * h;
/** Whether the canvas' resize observer runs: a `deferred` section skips its subtree (`content-visibility: auto`). */
export const renderObserves = ({ active }: { active: boolean }): boolean => active;
