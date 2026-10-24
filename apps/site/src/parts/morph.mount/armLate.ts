// WebKit holds a scroll only on a non-passive listener (ScrollingTree.cpp:118-134@862f17d).
import { ARM_BOTTOM_SLACK } from './logic';

export type ArmMode = 'none' | 'passive' | 'blocking';
export type ListenType = 'touchstart' | 'wheel' | 'touchmove';

export function lead(vh: number): number {
  return vh + vh / 4;
}

export function edge(vh: number): number {
  return vh + ARM_BOTTOM_SLACK + lead(vh);
}

export function inBand(vh: number, bottom: number): boolean {
  return bottom <= edge(vh);
}

export function attached(near: boolean, act: boolean): boolean {
  return near || act;
}

export function blocking(near: boolean, band: boolean, act: boolean): boolean {
  return (near && band) || act;
}

export function mode(near: boolean, band: boolean, act: boolean): ArmMode {
  if (blocking(near, band, act)) return 'blocking';
  return attached(near, act) ? 'passive' : 'none';
}

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

export interface ArmStats {
  frames: Record<ArmMode, number>;
}

export function armStats(): ArmStats {
  const w = window as unknown as { __fwArmLate?: ArmStats };
  return (w.__fwArmLate ??= { frames: { none: 0, passive: 0, blocking: 0 } });
}
