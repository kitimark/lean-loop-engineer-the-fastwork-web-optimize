import { fade } from '../morph.tween/logic';

/** The variant name: `morph.panel:rest`. */
export const REST_VARIANT = 'rest';

/** The attribute on the platform section while the panel is at rest; platform.module.css turns it into `filter: none`. */
export const REST_ATTR = 'data-fw-rest';

export type FilterKind = 'none' | 'blur';

export interface RestEl {
  hasAttribute(name: string): boolean;
  toggleAttribute(name: string, force: boolean): boolean;
}

/**
 * The decision per frame (Lean `MorphPanelRest.kindOf`, golden `morph.panel.rest.jsonl`): no filter when the written
 * `--morph-fade` is 1 (the blur radius is 0), else the fade's own blur. Read from the same float the writer stores, so a
 * morph value that rounds the fade to 1 also gives `none`.
 */
export function kindOf(m: number): FilterKind {
  return fade({ m }) >= 1 ? 'none' : 'blur';
}

/** The blur radius in px of the fade at morph value `m` (`blur(calc((1 - fade) * 12px))`, a negative length clamps to 0). */
export function radiusOf(m: number): number {
  return Math.max(0, (1 - fade({ m })) * 12);
}

/** Writes the decision onto the section; touches the DOM only when the kind changes (the toggle frames). */
export function setRest(el: RestEl, m: number): FilterKind {
  const k = kindOf(m);
  const on = k === 'none';
  if (el.hasAttribute(REST_ATTR) !== on) el.toggleAttribute(REST_ATTR, on);
  return k;
}
