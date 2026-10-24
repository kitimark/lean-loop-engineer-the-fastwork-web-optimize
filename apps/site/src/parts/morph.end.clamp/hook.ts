import type { Hooks } from '../morph.tween/end.logic';

export const clamp = (h: Hooks): Hooks => ({ ...h, target: (pin, maxY) => Math.min(h.target(pin, maxY), maxY()) });
