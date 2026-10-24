import { FLIP_N, type Hooks } from '../morph.tween/end.logic';

export const flip = (h: Hooks): Hooks => ({ ...h, allow: (fresh, ctr) => h.allow(fresh, ctr) && (fresh || FLIP_N <= ctr) });
