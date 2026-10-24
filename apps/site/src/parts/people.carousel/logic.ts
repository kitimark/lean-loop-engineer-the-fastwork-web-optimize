/**
 * Pure logic of people.carousel (no DOM): the avatar ring and the rest/swap loop. Restated from the original
 * (nodes/2.DyWL8TcE.js): loop 11289-11302, templates 11330-11356 and 11415-11447. Spec and proofs:
 * lean/Fw/Parts/PeopleCarousel.lean. Golden vectors: packages/contracts/golden/parts/people.carousel.jsonl (logic.test.ts).
 */

/** Wait before a swap, ms (N2:11291). */
export const REST_MS = 800;
/** Duration of the swap template, ms (N2:11295; CSS 0.22s). */
export const SWAP_MS = 220;
export const PERIOD_MS = REST_MS + SWAP_MS;
/** Avatars in the ring (the six professions). */
export const RING = 6;
/** Avatars shown at rest. */
export const SHOWN = 4;
export const AVATAR_PX = 32;
export const OVERLAP_PX = 8;

export interface State {
  x: number;
  swapping: boolean;
}

export const START: State = { x: 0, swapping: false };

export function slot({ x, k }: { x: number; k: number }): number {
  return (x + k) % RING;
}

export function restWindow({ x }: { x: number }): number[] {
  return Array.from({ length: SHOWN }, (_, k) => slot({ x, k }));
}

export function swapWindow({ x }: { x: number }): number[] {
  return Array.from({ length: SHOWN + 1 }, (_, k) => slot({ x, k }));
}

/** The rest timer ended (N2:11291-11296): swap if active. */
export function afterRest({ x, swapping, active }: State & { active: boolean }): State {
  return active ? { x, swapping: true } : { x, swapping };
}

/** The swap timer ended (N2:11297-11302): advance if still active; either way hide the swap template. */
export function afterSwap({ x, active }: State & { active: boolean }): State {
  return active ? { x: (x + 1) % RING, swapping: false } : { x, swapping: false };
}

/** State of an uninterrupted loop `t` ms into it. */
export function stateAt({ t }: { t: number }): State {
  return { x: Math.floor(t / PERIOD_MS) % RING, swapping: REST_MS <= t % PERIOD_MS };
}

/** Width in px of a row of `k` avatars with the overlap (CSS 2884-2888). */
export function rowPx({ k }: { k: number }): number {
  return k * AVATAR_PX - (k - 1) * OVERLAP_PX;
}

export const CROP_VARIANT = 'crop';

export function cropTranslate({ p }: { p: number }): number {
  return (AVATAR_PX - OVERLAP_PX) * p;
}

export type SwapRole = 'exit' | 'shift' | 'enter';

export function swapRole({ i, len }: { i: number; len: number }): SwapRole {
  return i === 0 ? 'exit' : i === len - 1 ? 'enter' : 'shift';
}
