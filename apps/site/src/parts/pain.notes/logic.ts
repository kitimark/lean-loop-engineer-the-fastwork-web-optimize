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

/** JS 4575-4588 `ce` (desktop branch, the only one reachable: the narrow stage has width 0). */
export function baseLayout({ stageW, stageH }: { stageW: number; stageH: number }): Note[] {
  return BASE.map((b, i) => {
    const [w, h] = SIZE[b.k];
    const leftPx = b.x + w / 2 - 120;
    const topPx = b.y + h / 2 - 120;
    return { id: `base-${i}`, text: b.text, bg: b.bg, rotate: b.rotate, left: baseLeft({ stageW, leftPx }), top: baseTop({ stageH, topPx }), z: b.z, extra: false };
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

/** JS 4604-4645 after the guards (Lean `addExtra`): the new extra note, or null when nothing fits. */
export function addExtra(i: { stageW: number; stageH: number; notes: readonly Note[]; avoid: Box[]; j: number; extras: number }, rng: Rng): Note | null {
  const w = (NOTE_SIZE / i.stageW) * 100;
  const h = (NOTE_SIZE / i.stageH) * 100;
  const p = place(i.notes.map((n) => noteBox(n, i.stageW, i.stageH)), w, h, i.avoid, rng);
  if (!p) return null;
  const r1 = rng.draw();
  const r2 = rng.draw();
  return {
    id: `extra-${i.j}`,
    text: pickText({ used: i.notes.map((n) => n.text), r: r1 }),
    bg: PALETTE[idx({ r: r2, n: PALETTE.length })] ?? '#b3efbd',
    rotate: rotation({ j: i.j }),
    left: p[0],
    top: p[1],
    z: 10 + i.extras,
    extra: true,
  };
}

/** The golden `session`: base layout then `ticks` ticks (visible, wide, no reduced motion, card below the fold). */
export function session(i: { stageW: number; stageH: number; seed: number; copyTop: number; copyH: number; stageTop: number; ticks: number }): Note[] {
  const rng = createRng(i.seed);
  const avoid = [avoidBox({ copyTop: i.copyTop, copyH: i.copyH, stageTop: i.stageTop, stageH: i.stageH })];
  const notes = baseLayout({ stageW: i.stageW, stageH: i.stageH });
  let j = 0;
  for (let k = 0; k < i.ticks; k++) {
    const extras = notes.length - 5;
    const t = tick({ visible: true, dragging: false, extras, narrow: false, reduced: false, cardTop: null, vh: 900, stageW: i.stageW, stageH: i.stageH });
    if (t !== 'add') continue;
    const n = addExtra({ stageW: i.stageW, stageH: i.stageH, notes, avoid, j, extras }, rng);
    if (n) {
      notes.push(n);
      j += 1;
    }
  }
  return notes;
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
