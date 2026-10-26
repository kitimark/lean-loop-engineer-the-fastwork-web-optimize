import { PERIOD_MS, color, phase, pos } from './logic';

export const VARIANT = 'layer-sweep';
export const FLAG = 'platform.sweep:layer-sweep';

/** The `translateX` keyframe start (a fraction of the gradient layer's own width, `-66.6667%` in sweep.module.css). */
export const FROM_PCT = 0.666667;
/** Layers the variant adds: one gradient layer per title word. */
export const LAYERS = 4;
/** Layer memory the variant may add, bytes (Lean `budgetBytes`). */
export const BUDGET_BYTES = 8 * 1024 * 1024;

/** Left edge of the gradient layer at time t for a word w px wide, from the exact keyframe `-2/3 * 3w` to 0. */
export const layerX = ({ w, t }: { w: number; t: number }): number => -(2 / 3) * (3 * w) * (1 - phase({ t }));

/** The same offset with the CSS's rounded start. */
export const layerXCss = ({ w, t }: { w: number; t: number }): number => -FROM_PCT * (3 * w) * (1 - phase({ t }));

/** The original's background offset `-2w * pos(t)`. */
export const bgOffset = ({ w, t }: { w: number; t: number }): number => -2 * w * pos({ t });

/** Gradient fraction under element point `v` (0..1 of the word) for a layer whose left edge is at `x`. */
export const bandU = ({ w, x, v }: { w: number; x: number; v: number }): number => (v * w - x) / (3 * w);

/** The original's image fraction at element point `v` and position fraction `p`. */
export const imageU = ({ v, p }: { v: number; p: number }): number => (v + 2 * p) / 3;

export { PERIOD_MS, color };
