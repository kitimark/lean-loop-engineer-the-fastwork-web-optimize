/**
 * Pure logic of morph.mount (no DOM). Original: _app/immutable/nodes/2.DyWL8TcE.js
 *   O (arm geometry) 13040-13047, k (take a push) 13048, A/j/M (wheel, touch) 13049-13058, N/P (listeners) 13059-13071,
 *   I (wanted) 13072, L (pin) 13073-13075, IntersectionObserver 13076-13086, C (active) 12911.
 * Lean: lean/Fw/Parts/MorphMount.lean. Golden vectors: packages/contracts/golden/parts/morph.mount.jsonl (logic.test.ts).
 */

/** `rootMargin` of the observer: the panel mounts and the listeners arm 200 % of the viewport before the platform. */
export const IO_ROOT_MARGIN = '200% 0px';
/** The platform must fill at least this fraction of the viewport (O). */
export const ARM_MIN_FRACTION = 0.45;
/** ... and its bottom must be within this many px of the viewport bottom (O). */
export const ARM_BOTTOM_SLACK = 8;
/** `C`: active above this (the tween target or value). */
export const ACTIVE_ABOVE = 0.001;

export interface Rect {
  height: number;
  bottom: number;
}

/** O: the platform is tall enough and sits on the viewport bottom. */
export function armed(r: Rect, vh: number): boolean {
  return r.height >= vh * ARM_MIN_FRACTION && r.bottom <= vh + ARM_BOTTOM_SLACK;
}

/** C: the morph is active. */
export function active(target: number, value: number): boolean {
  return target > ACTIVE_ABOVE || value > ACTIVE_ABOVE;
}

/** k: may this push be taken (and its default prevented). */
export function takes(isActive: boolean, delta: number, geom: boolean): boolean {
  return isActive || (delta > 0 && geom);
}

/** Touch delta: previous y minus current y (a finger moving up pushes forward). */
export function touchDelta(prev: number, cur: number): number {
  return prev - cur;
}

/** The visual viewport's height when it exists, else `innerHeight`. */
export function viewportHeight(visual: number | null, inner: number): number {
  return visual ?? inner;
}

/** I: capture listeners are wanted while the observer says near, or the morph is active. */
export function wanted(near: boolean, isActive: boolean): boolean {
  return near || isActive;
}

export type Action = 'attach' | 'detach' | 'none';

/** N / P with the `d` guard. */
export function action(attached: boolean, want: boolean): Action {
  if (want && !attached) return 'attach';
  if (!want && attached) return 'detach';
  return 'none';
}

/** The panel mounts at the first intersecting entry or the first accepted push, and stays mounted. */
export function mountNext(mounted: boolean, intersecting: boolean, pushed: boolean): boolean {
  return mounted || intersecting || pushed;
}

/** L: while active, a scroll position other than the pin is sent back. */
export function repin(isActive: boolean, y: number, pin: number): boolean {
  return isActive && y !== pin;
}

/** Position on the scroll engine: directly after nav.hitTest (100), as the original runs both in one callback. */
export const MOUNT_PIN_ORDER = 101;

/**
 * Variant `shift` (Lean: lean/Fw/Parts/MorphMountOpt.lean `mountV`): a still moment counts as a trigger like an
 * intersecting entry. `mountNext(m, near || warm, push)`; `mountV_of_mountO`: never later than the original.
 */
export function mountNextWarm(mounted: boolean, intersecting: boolean, pushed: boolean, warm: boolean): boolean {
  return mountNext(mounted, intersecting || warm, pushed);
}

/** A moment is still when the morph is idle and the page has not scrolled or been pushed for this many ms. */
export const WARM_QUIET_MS = 150;

/** `warm` tick: no motion running (morph idle) and no scroll or push for `WARM_QUIET_MS`. */
export function warmStill(isActive: boolean, msSinceMotion: number): boolean {
  return !isActive && msSinceMotion >= WARM_QUIET_MS;
}

export function isShift(variant: string): boolean {
  return variant === 'shift' || variant === 'shift-dormant';
}

/** Variant `shift-dormant` (Lean: lean/Fw/Parts/MorphMountDormant.lean): `shift`, with the columns' marquee off while dormant. */
export function isDormantVariant(variant: string): boolean {
  return variant === 'shift-dormant';
}

/** Lean `MorphMountDormant.dormant`: mounted by the variant and not yet by the original's trigger. */
export function dormant(mountedV: boolean, mountedO: boolean): boolean {
  return mountedV && !mountedO;
}
