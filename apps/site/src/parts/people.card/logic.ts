/**
 * Pure logic of people.card (no DOM): the reveal of the white card, its shrink and the Pain colour flip. Restated from
 * the original (nodes/2.DyWL8TcE.js): clamp, smoothstep and coverage 11275-11284, frame 11300-11330. Spec and proofs:
 * lean/Fw/Parts/PeopleCard.lean. Golden vectors: packages/contracts/golden/parts/people.card.jsonl (logic.test.ts).
 */

/** Lerp rate per frame (N2:11313). */
export const RATE = 0.22;
/** Snap distance (N2:11314). */
export const SNAP = 0.0008;
/** Reveal threshold on the hero track progress (N2:11305). */
export const REVEAL_AT = 0.72;
/** `is-future-shrinking` above this coverage (N2:11317). */
export const SHRINKING_ABOVE = 0.04;
/** Coverage is 0 when the card bottom is at or below this share of the viewport (N2:11282). */
export const COVER_TOP = 0.85;
/** Coverage is 1 when the card bottom is at or above this share (N2:11283). */
export const COVER_FULL = 0.35;
/** The Pain section is dark once the heading top is at or above this many px (N2:11327). */
export const DARK_TOP = 0.5;

export function clamp01({ x }: { x: number }): number {
  return Math.min(1, Math.max(0, x));
}

/** Smoothstep of the clamped input (N2:11278). */
export function smooth({ x }: { x: number }): number {
  const c = clamp01({ x });
  return c * c * (3 - 2 * c);
}

/** Coverage of the card by the viewport (N2:11279-11284). */
export function coverage({ bottom, vh }: { bottom: number; vh: number }): number {
  if (vh <= 0) return 0;
  const top = COVER_TOP * vh;
  const full = COVER_FULL * vh;
  if (bottom >= top) return 0;
  if (bottom <= full) return 1;
  return clamp01({ x: (top - bottom) / (top - full) });
}

/** Target shrink for a coverage (N2:11308). */
export function target({ reduced, t }: { reduced: boolean; t: number }): number {
  return reduced ? +(t >= 0.5) : smooth({ x: t });
}

/** One lerp step with snap (N2:11309-11310). */
export function lerp({ reduced, o, n }: { reduced: boolean; o: number; n: number }): number {
  const o1 = o + (n - o) * (reduced ? 1 : RATE);
  return Math.abs(n - o1) < SNAP ? n : o1;
}

/** Another frame is wanted while the value is off the target by the snap distance (N2:11312). */
export function pending({ n, o }: { n: number; o: number }): boolean {
  return Math.abs(n - o) >= SNAP;
}

export function shrinking({ t }: { t: number }): boolean {
  return t > SHRINKING_ABOVE;
}

/** Reveal flag from the hero track rect (N2:11300-11306). */
export function revealed({ reduced, top, height, vh }: { reduced: boolean; top: number; height: number; vh: number }): boolean {
  const r = Math.max(1, height - vh);
  return reduced || Math.min(r, Math.max(0, -top)) / r >= REVEAL_AT;
}

/** Card scale at shrink `s` (CSS 2361). */
export function scale({ s }: { s: number }): number {
  return 1 - 0.083333 * s;
}

/** The Pain section is dark (N2:11325-11330). */
export function painDark({ narrow, headerTop }: { narrow: boolean; headerTop: number }): boolean {
  return !narrow || headerTop <= DARK_TOP;
}

export interface FrameIn {
  reduced: boolean;
  narrow: boolean;
  vh: number;
  /** hero track rect; null when the page has none (revealed then) */
  track: { top: number; height: number } | null;
  /** the card's bottom edge; null when the card is not mounted */
  cardBottom: number | null;
  headerTop: number | null;
  /** the value written last frame */
  shrink: number;
}

export interface FrameOut {
  revealed: boolean;
  shrink: number | null;
  shrinking: boolean | null;
  again: boolean;
  painDark: boolean | null;
}

/** The whole frame (N2:11298-11330): flags and the next shrink value; `again` asks for another frame. */
export function frame(i: FrameIn): FrameOut {
  const rev = i.track ? revealed({ reduced: i.reduced, top: i.track.top, height: i.track.height, vh: i.vh }) : true;
  let shrink: number | null = null;
  let shrinking: boolean | null = null;
  let again = false;
  if (i.cardBottom !== null) {
    const t = coverage({ bottom: i.cardBottom, vh: i.vh });
    const n = target({ reduced: i.reduced, t });
    const o = lerp({ reduced: i.reduced, o: i.shrink, n });
    shrink = o;
    shrinking = t > SHRINKING_ABOVE;
    again = pending({ n, o });
  }
  const dark = i.headerTop === null ? painDark({ narrow: i.narrow, headerTop: 1 }) : painDark({ narrow: i.narrow, headerTop: i.headerTop });
  return { revealed: rev, shrink, shrinking, again, painDark: dark };
}
