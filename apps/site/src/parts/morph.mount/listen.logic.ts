import { taken } from '../morph.tween/logic';
import { takes } from './logic';

/** Lean `MorphListen.Mode`: the merged touchmove listener is absent, passive or blocking. */
export type Mode = 'none' | 'watch' | 'take';

/** Lean `MorphListen.bandRootMargin`. */
export const BAND_ROOT_MARGIN = '1000% 0px 150% 0px';

/** Lean `MorphListen.full`. */
export function full(ratio: number): boolean {
  return ratio >= 1;
}

/** Lean `MorphListen.want`. */
export function want(attached: boolean, act: boolean, inBand: boolean): Mode {
  if (!attached) return 'none';
  return act || inBand ? 'take' : 'watch';
}

/** Lean `MorphListen.next`. */
export function next(cur: Mode, w: Mode, down: boolean): Mode {
  return down && cur === 'take' && w === 'watch' ? 'take' : w;
}

/** Lean `MorphListen.takesAny`. */
export function takesAny(actM: boolean, actT: boolean, delta: number, geomM: boolean, geomT: boolean): boolean {
  return takes(actM, delta, geomM) || taken({ active: actT, delta, armed: geomT });
}

/** Variant `band` of morph.mount and morph.tween: touch listeners go through the merged hub. */
export function isBand(variant: string): boolean {
  return variant === 'band';
}
