import { FLIP_N, type Hooks } from '../morph.tween/end.logic';

/** Brick B (Lean `Brick.apply .flip`): an active morph flips only on a new touch or after `FLIP_N` px of net travel against the goal. */
export const flip = (h: Hooks): Hooks => ({ ...h, allow: (fresh, ctr) => h.allow(fresh, ctr) && (fresh || FLIP_N <= ctr) });
