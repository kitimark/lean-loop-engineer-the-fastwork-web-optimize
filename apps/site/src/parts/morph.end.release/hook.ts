import type { Hooks } from '../morph.tween/end.logic';

export const release = (h: Hooks): Hooks => ({ ...h, release: true });
