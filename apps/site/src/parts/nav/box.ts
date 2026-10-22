import { MORPHING_CUT } from './logic';

export interface Vp {
  w: number;
  h: number;
}

export interface Rect {
  left: number;
  top: number;
  width: number;
  height: number;
}

export const BOX_VARIANTS = ['clip-box', 'bar-fixed', 'logo-3d'] as const;
export type BoxVariant = (typeof BOX_VARIANTS)[number];

export const BOX_ATTR = 'data-fw-box';

export const BOX_ROLE_ATTR = 'data-fw-box-role';

export function boxVariant(variant: string): BoxVariant | null {
  return (BOX_VARIANTS as readonly string[]).includes(variant) ? (variant as BoxVariant) : null;
}

const phone = (w: number): boolean => w <= 640;
const pillW = (v: Vp): number => Math.min(984, v.w - (phone(v.w) ? 32 : 48));
const pillH = (v: Vp): number => (phone(v.w) ? 52 : 64);
const panelW = (v: Vp): number => (phone(v.w) ? v.w - 24 : Math.min(1398, v.w - 40));
const panelH = (v: Vp): number => (phone(v.w) ? v.h - 24 : Math.min(820, v.h - 40));

export function unionRect(v: Vp): Rect {
  return { left: (v.w - panelW(v)) / 2, top: phone(v.w) ? 12 : 16, width: panelW(v), height: panelH(v) + (phone(v.w) ? 0 : 4) };
}

export function insets(v: Vp, m: number): { x: number; t: number; b: number } {
  return {
    x: ((panelW(v) - pillW(v)) * (1 - m)) / 2,
    t: phone(v.w) ? 4 * (1 - m) : 4 * m,
    b: (panelH(v) - pillH(v) + (phone(v.w) ? -4 : 4)) * (1 - m),
  };
}

export function clipRect(v: Vp, m: number): Rect {
  const u = unionRect(v);
  const i = insets(v, m);
  return { left: u.left + i.x, top: u.top + i.t, width: u.width - 2 * i.x, height: u.height - i.t - i.b };
}

export function boxActive(m: number, localeOpen: boolean): boolean {
  return m > MORPHING_CUT && !localeOpen;
}

export function logoX(v: Vp, m: number): number {
  const d = panelW(v) - pillW(v);
  const inset = phone(v.w) ? 16 : 24;
  return d / 2 + ((pillW(v) - d) / 2 - inset) * m + (d / 2) * m * m;
}

export function actionsX(v: Vp, m: number): number {
  return ((panelW(v) - pillW(v)) / 2) * (m - 1);
}
