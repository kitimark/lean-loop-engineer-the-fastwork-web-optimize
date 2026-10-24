/**
 * The `unthrottle` variant of engine.scroll: the shippable form of the `throttle-lift` diagnostic. One fixed 1x1 element
 * with opacity 0 runs a scroll-driven animation of a registered custom property, which the compositor cannot run alone.
 * WebKit then reports main-thread scroll-driven animations (WebPageCocoa.mm:2357, AnimationTimelinesController.cpp:267-279
 * @862f17d) and WKWebViewIOS.mm:3256-3268 stops holding visible-rect updates to 100 ms while Mobile Safari's toolbar collapses.
 * The condition, the same-look facts (paints nothing, no layout, no hit target, hidden from assistive technology) and the
 * per-frame cost bound (one element restyled, no layout) are proved in lean/Fw/Parts/EngineScrollUnthrottle.lean; the
 * style text and attributes are checked against its golden (packages/contracts/golden/parts/engine.scroll.unthrottle.jsonl).
 * The rule sits inside `@supports (animation-timeline: scroll())`, so an engine without the property sees no animation.
 */
export const UNTHROTTLE_ATTR = 'data-fw-unthrottle';

/** The style text (Lean `Fw.Parts.EngineScrollUnthrottle.css`). */
export function unthrottleCss(): string {
  return [
    '@property --fw-ut { syntax: "<number>"; inherits: false; initial-value: 0; }',
    '@keyframes fw-ut { from { --fw-ut: 0; } to { --fw-ut: 1; } }',
    '@supports (animation-timeline: scroll()) {',
    `[${UNTHROTTLE_ATTR}] { position: fixed; left: 0; top: 0; width: 1px; height: 1px; opacity: 0; pointer-events: none;`,
    ' animation: fw-ut 1s linear both; animation-duration: auto; animation-timeline: scroll(root block); }',
    '}',
  ].join('\n');
}

/** Install the style and the element; returns the undo. Client only; no per-frame JavaScript. */
export function installUnthrottle(doc: Document): () => void {
  const style = doc.createElement('style');
  style.textContent = unthrottleCss();
  const el = doc.createElement('div');
  el.setAttribute(UNTHROTTLE_ATTR, '');
  el.setAttribute('aria-hidden', 'true');
  doc.head.appendChild(style);
  doc.body.appendChild(el);
  return () => {
    style.remove();
    el.remove();
  };
}
