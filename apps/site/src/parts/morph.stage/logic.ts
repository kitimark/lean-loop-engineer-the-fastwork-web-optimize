import { clamp01 } from '../morph.tween/logic';
import { band, THETA_POINTER } from '../morph.tween/waapi.logic';

export const STAGE_ID = 'morph.stage';
export const STAGE_ON = 'on';
export const STAGE_ATTR = 'data-fw-stage';
export const NARROW_MAX = 640;
export const RANGE_CSS = 'calc(100% - var(--stage-t)) 100%';
export const TRACK_CSS = 'max(min(820px,100vh - 40px) - 64px,min(1398px,100vw - 40px) - min(984px,100vw - 48px),20px)';
export const TRACK_CSS_NARROW = 'max(100vh - 76px,100vw - 24px - min(984px,100vw - 32px),20px)';

export const jackOn = (variant: string): boolean => variant !== STAGE_ON;

export interface Win {
  vw: number;
  vh: number;
  narrow: boolean;
}

export const narrowOf = (vw: number): boolean => vw <= NARROW_MAX;

const pillW = (w: Win): number => Math.min(984, w.vw - (w.narrow ? 32 : 48));
const pillH = (w: Win): number => (w.narrow ? 52 : 64);
const panelW = (w: Win): number => (w.narrow ? w.vw - 24 : Math.min(1398, w.vw - 40));
const panelH = (w: Win): number => (w.narrow ? w.vh - 24 : Math.min(820, w.vh - 40));
export const spanW = (w: Win): number => panelW(w) - pillW(w);
export const spanH = (w: Win): number => panelH(w) - pillH(w);
export const BLUR_SPAN = 20;

export const trackT = (w: Win): number => Math.max(spanH(w), spanW(w), BLUR_SPAN);

export function progress({ y, maxY, t }: { y: number; maxY: number; t: number }): number {
  return t > 0 ? clamp01((y - (maxY - t)) / t) : 0;
}

export const pointerNone = (m: number): boolean => m > THETA_POINTER;

export const stateKey = (m: number): boolean[] => [pointerNone(m), ...band(m)];

export const sameKey = (a: readonly boolean[], b: readonly boolean[]): boolean => a.length === b.length && a.every((v, i) => v === b[i]);

export const maxYOf = (platformBottom: number, t: number, vh: number): number => platformBottom + t - vh;

export const sceneBottom = (pb: number, t: number, vh: number, y: number): number => Math.min(Math.max(pb - y, vh), pb + t - y);
