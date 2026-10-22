/**
 * pain `dark-scroll`: the range start of the dark layer's scroll animation. Spec and proofs:
 * lean/Fw/Parts/PainDarkScroll.lean (`measuredStart`, `measure_eq`); golden vectors:
 * packages/contracts/golden/parts/pain-dark-scroll.jsonl (darkScroll.test.ts).
 */
import { mediaCondition } from '../../breakpoints';
import { DARK_TOP } from '../people.card/logic';

export const RANGE_VAR = '--fw-pain-dark-t';

export const SUPPORTS = '(animation-timeline: scroll(root)) and (animation-range-start: 1px)';

const CARD = '[data-fw="people-card"]';

let supported: boolean | undefined;

export function darkScrollSupported(): boolean {
  supported ??= typeof CSS !== 'undefined' && typeof CSS.supports === 'function' && CSS.supports(SUPPORTS);
  return supported;
}

export function layerOwnsFlip(variant: string | null, supports: boolean): boolean {
  return variant === 'dark-scroll' && supports;
}

export const WINDOW = 256;

export const RANGE_LEN = 32768;

export function rangeStart({ rectTop, scrollY, ty }: { rectTop: number; scrollY: number; ty: number }): number {
  return rectTop + scrollY - ty - DARK_TOP - WINDOW;
}

export function translateY(transform: string): number {
  const m = /^matrix(3d)?\(([^)]*)\)$/.exec(transform.trim());
  if (!m) return 0;
  const v = m[2]!.split(',').map((s) => Number.parseFloat(s));
  const y = m[1] ? v[13] : v[5];
  return y !== undefined && Number.isFinite(y) ? y : 0;
}

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
