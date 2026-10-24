import { clamp } from '../morph.end.clamp/hook';
import { flip } from '../morph.end.flip/hook';
import { release } from '../morph.end.release/hook';
import { BASE, type Hooks } from './end.logic';

export const CLAMP_ID = 'morph.end.clamp';
export const FLIP_ID = 'morph.end.flip';
export const RELEASE_ID = 'morph.end.release';
export const ON = 'on';

export interface EndCfg {
  clamp: boolean;
  flip: boolean;
  release: boolean;
}

export function hooksOf(c: EndCfg): Hooks {
  let h = BASE;
  if (c.clamp) h = clamp(h);
  if (c.flip) h = flip(h);
  if (c.release) h = release(h);
  return h;
}

export function cfgOf(variants: Record<string, string>): EndCfg {
  return { clamp: variants[CLAMP_ID] === ON, flip: variants[FLIP_ID] === ON, release: variants[RELEASE_ID] === ON };
}
