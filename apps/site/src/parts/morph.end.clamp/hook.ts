import type { Hooks } from '../morph.tween/end.logic';

/** Brick A (Lean `Brick.apply .clamp`): the pin is restored to `min(pin, maxY)`, so the page never fights the rubber band past the real end. */
export const clamp = (h: Hooks): Hooks => ({ ...h, target: (pin, maxY) => Math.min(h.target(pin, maxY), maxY()) });
