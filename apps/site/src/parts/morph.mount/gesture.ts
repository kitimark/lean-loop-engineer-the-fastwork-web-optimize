// One decision per touch gesture (Lean: lean/Fw/Parts/MorphMountToolbar.lean). The first touchmove is cancelable because the native
// pan waits for it; after the pan began preventDefault no longer stops it (WKContentViewInteraction.mm:1368, :2562, :4239-4245@862f17d).
import { takes } from './logic';

export type Gesture = 'fresh' | 'native' | 'pushing' | 'spent';
export interface GestureOpt {
  first: boolean;
  once: boolean;
}

export const FIRST: GestureOpt = { first: true, once: false };
export const ONCE: GestureOpt = { first: false, once: true };

export function gestureOpt(variant: string): GestureOpt | undefined {
  if (variant === 'touch-first') return FIRST;
  if (variant === 'open-once') return ONCE;
  return undefined;
}

export function isOverscrollLock(variant: string): boolean {
  return variant === 'overscroll-lock';
}

/** Lean `step`: whether this touchmove's push is taken, and the gesture after it. `cancelable` is the event's flag. */
export function step(o: GestureOpt, g: Gesture, act: boolean, delta: number, geom: boolean, cancelable: boolean): { take: boolean; next: Gesture } {
  switch (g) {
    case 'fresh': {
      const t = o.first && !cancelable ? act : takes(act, delta, geom);
      return { take: t, next: t ? 'pushing' : o.first ? 'native' : 'fresh' };
    }
    case 'native':
      return { take: act, next: act ? 'pushing' : 'native' };
    case 'pushing':
      return o.once && !act ? { take: false, next: 'spent' } : { take: takes(act, delta, geom), next: 'pushing' };
    case 'spent':
      return { take: act, next: act ? 'pushing' : 'spent' };
  }
}

/** Lean `lockWanted`: lock the root's overscroll while the platform is near and armed, or the morph is active. */
export function lockWanted(near: boolean, geom: boolean, act: boolean): boolean {
  return (near && geom) || act;
}

export type LockOp = 'set' | 'clear' | 'none';

/** Lean `lockOp`: write the style only when the wish changes. */
export function lockOp(cur: boolean, want: boolean): LockOp {
  return cur === want ? 'none' : want ? 'set' : 'clear';
}
