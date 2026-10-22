import { taken } from '../morph.tween/logic';
import { takes } from './logic';

export type Mode = 'none' | 'watch' | 'take';

export const BAND_ROOT_MARGIN = '1000% 0px 150% 0px';

export function full(ratio: number): boolean {
  return ratio >= 1;
}

export function want(attached: boolean, act: boolean, inBand: boolean): Mode {
  if (!attached) return 'none';
  return act || inBand ? 'take' : 'watch';
}

export function next(cur: Mode, w: Mode, down: boolean): Mode {
  return down && cur === 'take' && w === 'watch' ? 'take' : w;
}

export function takesAny(actM: boolean, actT: boolean, delta: number, geomM: boolean, geomT: boolean): boolean {
  return takes(actM, delta, geomM) || taken({ active: actT, delta, armed: geomT });
}

export function isBand(variant: string): boolean {
  return variant === 'band';
}
