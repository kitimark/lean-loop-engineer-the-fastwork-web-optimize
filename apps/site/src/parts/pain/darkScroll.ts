import { mediaCondition } from '../../breakpoints';
import { DARK_TOP } from '../people.card/logic';

/**
 * pain `dark-scroll`: the range start of the dark layer's scroll animation. Spec and proofs:
 * lean/Fw/Parts/PainDarkScroll.lean (`measuredFlip`, `measure_eq`); golden vectors:
 * packages/contracts/golden/parts/pain-dark-scroll.jsonl (darkScroll.test.ts).
 */

/** The property on the Pain section the layer's `animation-range` reads. */
export const RANGE_VAR = '--fw-pain-dark-t';

/** What the variant needs: the root scroll timeline and a range start (the CSS `@supports` restates this text). */
export const SUPPORTS = '(animation-timeline: scroll(root)) and (animation-range-start: 1px)';

/** The People card, whose first child is the header the original flips on. */
const CARD = '[data-fw="people-card"]';

let supported: boolean | undefined;

/** True when the engine runs the variant; elsewhere the page stays faithful (the people card keeps the class flip). */
export function darkScrollSupported(): boolean {
  supported ??= typeof CSS !== 'undefined' && typeof CSS.supports === 'function' && CSS.supports(SUPPORTS);
  return supported;
}

/** The layer owns the flip (the people part leaves `is-pain-dark` alone) when the Pain variant is `dark-scroll` and the engine runs it. */
export function layerOwnsFlip(variant: string | null, supports: boolean): boolean {
  return variant === 'dark-scroll' && supports;
}

/** Scroll px before the flip at which the animation's range starts (Lean `window`). */
export const WINDOW = 256;

/** The animation's range length in scroll px (Lean `rangeLen`); the CSS restates it. */
export const RANGE_LEN = 32768;

/** Lean `measuredStart`: the range start, `WINDOW` before the scroll offset at which the header's top reaches `DARK_TOP`. */
export function rangeStart({ rectTop, scrollY, ty }: { rectTop: number; scrollY: number; ty: number }): number {
  return rectTop + scrollY - ty - DARK_TOP - WINDOW;
}

/** The y translation of a computed `transform` (`none`, `matrix(...)` or `matrix3d(...)`); 0 when there is none. */
export function translateY(transform: string): number {
  const m = /^matrix(3d)?\(([^)]*)\)$/.exec(transform.trim());
  if (!m) return 0;
  const v = m[2]!.split(',').map((s) => Number.parseFloat(s));
  const y = m[1] ? v[13] : v[5];
  return y !== undefined && Number.isFinite(y) ? y : 0;
}

/**
 * Keeps `RANGE_VAR` on the Pain section equal to the range start (the flip offset minus `WINDOW`) while the viewport is in the narrow band. It measures
 * when a layout changes (a ResizeObserver on the page, the card and the section, the band edge, load), never per scroll
 * frame, and writes only when the value changes. Returns the disposer.
 */
export function installRangeStart(section: HTMLElement): () => void {
  if (!darkScrollSupported()) return () => {};
  const narrow = window.matchMedia(mediaCondition('mq.w-le-860'));
  let last = '';
  const measure = () => {
    const card = document.querySelector<HTMLElement>(CARD);
    const header = card?.firstElementChild;
    let next = '';
    if (narrow.matches && card && header) {
      const t = rangeStart({
        rectTop: header.getBoundingClientRect().top,
        scrollY: window.scrollY,
        ty: translateY(getComputedStyle(card).transform),
      });
      next = `${t}px`;
    }
    if (next === last) return;
    last = next;
    if (next === '') section.style.removeProperty(RANGE_VAR);
    else section.style.setProperty(RANGE_VAR, next);
  };
  const ro = typeof ResizeObserver === 'function' ? new ResizeObserver(measure) : null;
  ro?.observe(document.body);
  ro?.observe(section);
  const card = document.querySelector(CARD);
  if (card) ro?.observe(card);
  narrow.addEventListener('change', measure);
  window.addEventListener('load', measure);
  measure();
  return () => {
    ro?.disconnect();
    narrow.removeEventListener('change', measure);
    window.removeEventListener('load', measure);
    section.style.removeProperty(RANGE_VAR);
  };
}
