import type { MotionClock } from '../../engine/clock';

/**
 * A one-shot timer on the clock: a real `setInterval(ms)` cancelled in its first callback, so it costs the same timer
 * registration as the original's `setTimeout` (parts never call the timer functions themselves, PLAN 6.5 rule 2).
 * Returns the cancel function.
 */
export function after(clock: MotionClock, ms: number, fn: () => void): () => void {
  let off: (() => void) | null = clock.interval(ms, () => {
    off?.();
    off = null;
    fn();
  });
  return () => {
    off?.();
    off = null;
  };
}

/** The original's `lE` (nodes/2.DyWL8TcE.js:2733): the element is within one viewport above or two below the viewport. */
export function nearViewport(rect: { top: number; bottom: number }, vh: number): boolean {
  return rect.bottom >= -vh && rect.top <= vh * 2;
}

/**
 * The original's scene activity (`dE`, 2.DyWL8TcE.js:2749-2780 with the default `rootMargin: 100% 0px`): the callback gets
 * the initial activity at once (rect test) and every change of an IntersectionObserver with that margin. The scene
 * pausing and content-visibility deferral that `dE` also offers are not part of this port.
 */
export function watchActive(el: Element, onChange: (active: boolean) => void): () => void {
  onChange(nearViewport(el.getBoundingClientRect(), window.innerHeight));
  if (!('IntersectionObserver' in window)) return () => undefined;
  const io = new IntersectionObserver((entries) => {
    for (const e of entries) onChange(e.isIntersecting);
  }, { rootMargin: '100% 0px' });
  io.observe(el);
  return () => io.disconnect();
}

/** Scroll-engine orders of the People parts (the original registers hero 10, then the People components, then the nav). */
export const ORDER = { o: 20, deck: 30, card: 40 } as const;
