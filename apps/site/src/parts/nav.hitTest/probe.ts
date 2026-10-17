import { changed, classifyHit, EXCLUDE_SELECTOR, hitPoint, INCLUDE_SELECTOR, SHRINKING_SELECTOR, firstOutside } from './logic';

/** DOM adapters over the pure logic. Reads and writes are in the original's order (2.DyWL8TcE.js:12955-12963). */
function classify(el: Element | null): boolean {
  return classifyHit({
    hasElement: el !== null,
    inExclude: !!el?.closest(EXCLUDE_SELECTOR),
    inInclude: !!el?.closest(INCLUDE_SELECTOR),
    inShrinking: !!el?.closest(SHRINKING_SELECTOR),
  });
}

/** faithful: rect read, write `pointer-events: none` on the nav, elementFromPoint (forces style + layout), restore. */
export function probeFaithful(nav: HTMLElement): boolean {
  const { x, y } = hitPoint(nav.getBoundingClientRect());
  const prev = nav.style.pointerEvents;
  nav.style.pointerEvents = 'none';
  const el = document.elementFromPoint(x, y);
  nav.style.pointerEvents = prev;
  return classify(el);
}

/** hit-skip: rect read, elementsFromPoint, first element outside the nav subtree. No style write. */
export function probeSkip(nav: HTMLElement): boolean {
  const { x, y } = hitPoint(nav.getBoundingClientRect());
  const stack = document.elementsFromPoint(x, y);
  const i = firstOutside(stack.map((e) => nav.contains(e)));
  return classify(i < 0 ? null : (stack[i] ?? null));
}

export { changed };
