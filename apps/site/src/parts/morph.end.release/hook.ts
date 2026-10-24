import type { Hooks } from '../morph.tween/end.logic';

/** Brick C (Lean `Brick.apply .release`): a close start drops the pin and stops `preventDefault` until the next open. */
export const release = (h: Hooks): Hooks => ({ ...h, release: true });
