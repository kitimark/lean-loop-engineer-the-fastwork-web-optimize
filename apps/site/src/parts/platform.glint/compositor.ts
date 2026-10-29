/**
 * platform.glint:compositor. The keyframes of the moving gradient layer come from `compositor.gen.ts`, which Lean writes
 * (lean/Fw/Parts/PlatformGlintCompositorGolden.lean, theorem Fw.Parts.PlatformGlintCompositor.stops_eq): a fixed layer
 * `layerWidth` wide at `layerLeft` in dash coordinates, moved by `translateX` with linear easing over `durMs`.
 */
import gen from './compositor.gen';
import type { Side } from './logic';

/** The CSS keyframes of one dash (`offset` k/5, `transform` translateX in px). */
export function compositorKeyframes(side: Side): Keyframe[] {
  return gen.keyframes[side].map((k) => ({ offset: k.offset, transform: `translateX(${k.tx}px)` }));
}

/** The timing of the transform animation: the original's 5 s cycle, repeating, linear between key times. */
export function compositorTiming(): KeyframeAnimationOptions {
  return { duration: gen.durMs, iterations: Infinity, easing: gen.easing };
}

/** The fixed layer's left edge and width in dash coordinates (the CSS module restates them). */
export const LAYER = { left: gen.layerLeft, width: gen.layerWidth } as const;
