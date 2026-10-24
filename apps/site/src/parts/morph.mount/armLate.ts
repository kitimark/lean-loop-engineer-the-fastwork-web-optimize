/**
 * Variant `arm-late` of morph.mount (Lean: lean/Fw/Parts/MorphMountArmLate.lean). The wheel and touchmove capture
 * listeners stay registered whenever the original has them, but are non-passive only while the platform bottom is in the
 * band (or the morph is active); outside it they are passive, so WebKit does not hold each scroll for the main thread
 * (ScrollingTree.cpp:118-134@862f17d). The handler is the same in both modes, so only whether `preventDefault` is honored
 * changes; `late_same` proves it is always honored when the original would call it.
 * Golden vectors: packages/contracts/golden/parts/morph-mount-arm-late.jsonl (armLate.test.ts).
 */
import { ARM_BOTTOM_SLACK } from './logic';

export type ArmMode = 'none' | 'passive' | 'blocking';
export type ListenType = 'touchstart' | 'wheel' | 'touchmove';

/** Lean `lead`: one viewport of pan inside a touch gesture plus a quarter viewport of scroll between two evaluations. */
export function lead(vh: number): number {
  return vh + vh / 4;
}

/** Lean `edge`: the platform bottom edge of the band (the arming edge `vh + 8`, then `lead`). */
export function edge(vh: number): number {
  return vh + ARM_BOTTOM_SLACK + lead(vh);
}

/** Lean `inBand`: a half line, `bottom <= edge`. */
export function inBand(vh: number, bottom: number): boolean {
  return bottom <= edge(vh);
}

/** Lean `attached`: the listeners the original has. */
export function attached(near: boolean, act: boolean): boolean {
  return near || act;
}

/** Lean `blocking`: the listeners that are non-passive. */
export function blocking(near: boolean, band: boolean, act: boolean): boolean {
  return (near && band) || act;
}

/** Lean `mode`. */
export function mode(near: boolean, band: boolean, act: boolean): ArmMode {
  if (blocking(near, band, act)) return 'blocking';
  return attached(near, act) ? 'passive' : 'none';
}

/** Lean `ops`: the registry changes from mode `cur` to mode `next`, as `+type[:passive|blocking]` and `-type`. */
export function ops(cur: ArmMode, next: ArmMode): string[] {
  if (cur === next) return [];
  const out: string[] = [];
  if (cur !== 'none') out.push('-wheel', '-touchmove');
  if (cur === 'none') out.push('+touchstart');
  else if (next === 'none') out.push('-touchstart');
  if (next !== 'none') out.push(`+wheel:${next}`, `+touchmove:${next}`);
  return out;
}

export function isArmLate(variant: string): boolean {
  return variant === 'arm-late';
}

export interface ArmEnv {
  add(type: ListenType, fn: (e: never) => void, passive: boolean): void;
  remove(type: ListenType, fn: (e: never) => void): void;
}

export interface ArmHandlers {
  touchstart: (e: TouchEvent) => void;
  wheel: (e: WheelEvent) => void;
  touchmove: (e: TouchEvent) => void;
}

/** Applies `ops` to an environment; one controller per mounted part. */
export function createArm(env: ArmEnv, handlers: ArmHandlers) {
  let cur: ArmMode = 'none';
  const fn = (t: ListenType) => handlers[t] as (e: never) => void;
  const set = (near: boolean, band: boolean, act: boolean) => {
    const next = mode(near, band, act);
    for (const op of ops(cur, next)) {
      const sign = op[0];
      const [type, how] = op.slice(1).split(':') as [ListenType, string | undefined];
      if (sign === '-') env.remove(type, fn(type));
      else env.add(type, fn(type), type === 'touchstart' || how === 'passive');
    }
    cur = next;
  };
  return { set, mode: () => cur };
}

/** Measure hook: scroll frames spent in each mode (a plain counter, no React state). Read from the page as
 * `window.__fwArmLate`. */
export interface ArmStats {
  frames: Record<ArmMode, number>;
}

export function armStats(): ArmStats {
  const w = window as unknown as { __fwArmLate?: ArmStats };
  return (w.__fwArmLate ??= { frames: { none: 0, passive: 0, blocking: 0 } });
}
