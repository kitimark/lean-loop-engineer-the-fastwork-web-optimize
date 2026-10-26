import { PERIOD_MS, color, phase, pos } from './logic';

export const VARIANT = 'layer-sweep';
export const FLAG = 'platform.sweep:layer-sweep';

export const FROM_PCT = 0.33333333;
export const LAYERS = 4;
export const BUDGET_BYTES = 16 * 1024 * 1024;

export const layerX = ({ w, t }: { w: number; t: number }): number => -(1 / 3) * (6 * w) * (1 - phase({ t }));

export const layerXCss = ({ w, t }: { w: number; t: number }): number => -FROM_PCT * (6 * w) * (1 - phase({ t }));

export const bgOffset = ({ w, t }: { w: number; t: number }): number => -2 * w * pos({ t });

export const bandU = ({ w, x, v }: { w: number; x: number; v: number }): number => (v * w - x) / (3 * w);

export const imageU = ({ v, p }: { v: number; p: number }): number => (v + 2 * p) / 3;

const frac = (x: number): number => x - Math.floor(x);

/** Tile fraction under layer-local pixel y of the two-tile (6w) layer (Lean layerU). */
export const layerU = ({ w, y }: { w: number; y: number }): number => (y < 3 * w ? y / (3 * w) : (y - 3 * w) / (3 * w));

/** Tile fraction of the original with repeat at element pixel x, background position p (Lean repU). */
export const repU = ({ w, x, p }: { w: number; x: number; p: number }): number => frac((x + 2 * w * p) / (3 * w));

/** Snapped width in device pixels of a box at css left with css width: each edge rounded half up (Lean snapPx). */
export const snapPx = ({ dpr, left, width }: { dpr: number; left: number; width: number }): number =>
  Math.floor((left + width) * dpr + 0.5) - Math.floor(left * dpr + 0.5);

/** Snapped width in css px (Lean snapW). */
export const snapW = ({ dpr, left, width }: { dpr: number; left: number; width: number }): number => snapPx({ dpr, left, width }) / dpr;

/** The custom property carrying the layer width (6 snapped word widths, css px) to the stylesheet. */
export const LAYER_WIDTH_VAR = '--sw6';

/**
 * Sets LAYER_WIDTH_VAR on each word once per resize (no per-frame work). The count comes from ResizeObserver
 * devicePixelContentBoxSize; an engine without it gets the same count from the rect through snapPx.
 * TS stand-in: the observer wiring is glue; the arithmetic is checked against the Lean golden.
 */
export function watchLayerWidth(words: readonly HTMLElement[]): () => void {
  if (typeof ResizeObserver === 'undefined') return () => undefined;
  const apply = (el: HTMLElement, px: number | null): void => {
    const dpr = window.devicePixelRatio || 1;
    let n = px;
    if (n === null) {
      const r = el.getBoundingClientRect();
      n = snapPx({ dpr, left: r.left, width: r.width });
    }
    el.style.setProperty(LAYER_WIDTH_VAR, `${(6 * n) / dpr}px`);
  };
  const onResize = (entries: ResizeObserverEntry[]): void => {
    for (const e of entries) apply(e.target as HTMLElement, e.devicePixelContentBoxSize?.[0]?.inlineSize ?? null);
  };
  let ro = new ResizeObserver(onResize);
  try {
    for (const w of words) ro.observe(w, { box: 'device-pixel-content-box' });
  } catch {
    ro.disconnect();
    ro = new ResizeObserver(onResize);
    for (const w of words) ro.observe(w);
  }
  return () => ro.disconnect();
}

export { PERIOD_MS, color };
