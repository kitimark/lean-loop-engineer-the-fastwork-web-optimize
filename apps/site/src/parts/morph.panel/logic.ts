/**
 * morph.panel decisions, mirrored from `lean/Fw/Parts/MorphPanel.lean` (golden: `morph.panel.jsonl`). Original:
 * nodes/2.DyWL8TcE.js:12947 (scene flag), 13196-13199 (aria-hidden, tabindex), 12683-12684 (0.55, 0.92); the three
 * calc() readings are the CSS of the panel root (assets/2.gBuqKVzi.css, `.start-selling-morph-panel`).
 */

/** JM (JS 12685): clamp to [0, 1]. */
export function clamp01(x: number): number {
  return Math.max(0, Math.min(1, x));
}

/** `clamp(0, (m - .08) / .72, 1)`. */
export function panelProgress(morph: number): number {
  return clamp01((morph - 0.08) / 0.72);
}
export function panelOpacity(morph: number): number {
  return panelProgress(morph);
}
/** `(1 - progress) * 12px`. */
export function panelBlurPx(morph: number): number {
  return (1 - panelProgress(morph)) * 12;
}
/** `scale(.96 + .04 m)`. */
export function panelScale(morph: number): number {
  return 0.96 + 0.04 * morph;
}

/** E: the morph has started (`> 0.001`); `data-start-selling-scene` is `active`, else `paused`. */
export function sceneActive(morph: number): boolean {
  return morph > 0.001;
}
/** `aria-hidden` on the panel while `morph < 0.35`. */
export function ariaHidden(morph: number): boolean {
  return morph < 0.35;
}
/** the call-to-action has `tabindex=-1` while `morph < 0.55`. */
export function ctaTabOff(morph: number): boolean {
  return morph < 0.55;
}
/** the nav is expanded (`morph > 0.92`): the panel takes pointer events. */
export function expanded(morph: number): boolean {
  return morph > 0.92;
}

/** Golden-vector argument names per function (lines are {fn, in: {name: value}, out}). */
export const GOLDEN_ARGS: Record<string, string[]> = {
  panelProgress: ['morph'],
  panelOpacity: ['morph'],
  panelBlurPx: ['morph'],
  panelScale: ['morph'],
  sceneActive: ['morph'],
  ariaHidden: ['morph'],
  ctaTabOff: ['morph'],
  expanded: ['morph'],
};

export interface PanelFlags {
  scene: 'active' | 'paused';
  ariaHidden: boolean;
  ctaTabindexOff: boolean;
  expanded: boolean;
}
export function panelFlags(morph: number): PanelFlags {
  return { scene: sceneActive(morph) ? 'active' : 'paused', ariaHidden: ariaHidden(morph), ctaTabindexOff: ctaTabOff(morph), expanded: expanded(morph) };
}
