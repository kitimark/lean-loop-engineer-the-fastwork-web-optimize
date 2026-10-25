import { fade } from '../morph.tween/logic';

export const REST_VARIANT = 'rest';

export const REST_ATTR = 'data-fw-rest';

export type FilterKind = 'none' | 'blur';

export interface RestEl {
  hasAttribute(name: string): boolean;
  toggleAttribute(name: string, force: boolean): boolean;
}

export function kindOf(m: number): FilterKind {
  return fade({ m }) >= 1 ? 'none' : 'blur';
}

export function radiusOf(m: number): number {
  return Math.max(0, (1 - fade({ m })) * 12);
}

export function setRest(el: RestEl, m: number): FilterKind {
  const k = kindOf(m);
  const on = k === 'none';
  if (el.hasAttribute(REST_ATTR) !== on) el.toggleAttribute(REST_ATTR, on);
  return k;
}
