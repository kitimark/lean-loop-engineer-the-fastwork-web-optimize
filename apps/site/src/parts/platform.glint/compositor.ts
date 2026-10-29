import gen from './compositor.gen';
import type { Side } from './logic';

export function compositorKeyframes(side: Side): Keyframe[] {
  return gen.keyframes[side].map((k) => ({ offset: k.offset, transform: `translateX(${k.tx}px)` }));
}

export function compositorTiming(): KeyframeAnimationOptions {
  return { duration: gen.durMs, iterations: Infinity, easing: gen.easing };
}

export const LAYER = { left: gen.layerLeft, width: gen.layerWidth } as const;
