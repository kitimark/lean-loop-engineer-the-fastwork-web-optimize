import { HIDDEN_FRACTION, hiddenAtFraction, sceneHidden } from './logic';

export type HiddenKind = 'fraction' | 'rect';

/** IntersectionObserver thresholds for a kind. `fraction` takes the Lean constant; `rect` needs only 0. */
export const thresholdsFor = (kind: HiddenKind): number[] => (kind === 'fraction' ? [HIDDEN_FRACTION] : [0]);

/**
 * One IntersectionObserver for a part. `fraction`: thresholds come from the Lean constant (HIDDEN_FRACTION), hidden
 * while intersectionRatio <= it (morph.columns, morph.countdown). `rect`: threshold 0, hidden without a
 * positive-area overlap (engine.scene). Callbacks fire on observe and on each crossing; they run after rAF callbacks
 * and before paint, so the caller's writes land in the same frame.
 */
export function watchHidden(
  els: Element[],
  kind: HiddenKind,
  onChange: (el: Element, hidden: boolean) => void,
  IO: typeof IntersectionObserver = IntersectionObserver,
): () => void {
  const io = new IO(
    (entries) => {
      for (const e of entries) {
        const hidden =
          kind === 'fraction'
            ? hiddenAtFraction(e.intersectionRatio)
            : sceneHidden(e.isIntersecting, e.intersectionRect.width, e.intersectionRect.height);
        onChange(e.target, hidden);
      }
    },
    { threshold: thresholdsFor(kind) },
  );
  for (const el of els) io.observe(el);
  return () => io.disconnect();
}
