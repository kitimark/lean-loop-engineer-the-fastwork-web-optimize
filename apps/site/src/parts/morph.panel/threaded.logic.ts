import { panelBlurPx, panelOpacity, panelScale } from './logic';

export const THREADED = 'threaded';

export const DURATION_MS = 680;

export const EASING = [1 / 3, 1, 2 / 3, 1] as const;

export const EASING_CSS = `cubic-bezier(${EASING.join(', ')})`;

export const K_A = 0.08;
export const K_B = 0.8;

export const EFFECT_PROPS = [['opacity', 'transform'], ['filter']] as const;

export interface PanelKf {
  off: number;
  opacity: number;
  blur: number;
  scale: number;
}

export function offsets(from: number, to: number): number[] {
  const at = (c: number) => (c - from) / (to - from);
  const inner: number[] = [];
  if (from < to) {
    if (from < K_A && K_A < to) inner.push(at(K_A));
    if (from < K_B && K_B < to) inner.push(at(K_B));
  } else {
    if (to < K_B && K_B < from) inner.push(at(K_B));
    if (to < K_A && K_A < from) inner.push(at(K_A));
  }
  return [0, ...inner, 1];
}

export function keyframes(from: number, to: number): PanelKf[] {
  return offsets(from, to).map((off) => {
    const m = from + (to - from) * off;
    return { off, opacity: panelOpacity(m), blur: panelBlurPx(m), scale: panelScale(m) };
  });
}

export function effects(from: number, to: number) {
  const kfs = keyframes(from, to);
  return {
    main: kfs.map((k) => ({ offset: k.off, opacity: k.opacity, transform: `scale(${k.scale})` })),
    blur: kfs.map((k) => ({ offset: k.off, filter: `blur(${k.blur}px)` })),
  };
}

export const installed = (reduced: boolean): boolean => !reduced;

export function caAccepts(keyframeCount: number): boolean {
  const [, y1, , y2] = EASING;
  return keyframeCount >= 2 && y1 >= 0 && y1 <= 1 && y2 >= 0 && y2 <= 1;
}
