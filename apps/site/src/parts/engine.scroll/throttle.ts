/**
 * The `throttle-lift` diagnostic of engine.scroll: one scroll-driven animation that the compositor cannot run alone,
 * on an element nobody sees. WebKit (WebPageCocoa.mm:2357, AnimationTimelinesController.cpp:267-279@862f17d) then reports
 * main-thread scroll-driven animations, and WKWebViewIOS.mm:3256-3268 stops throttling visible-rect updates to 100 ms while
 * the toolbar collapses. Never in a preset (part.json: kind ablation, diagnostic); it answers one question for the probe.
 */
export const THROTTLE_LIFT_ATTR = 'data-fw-throttle-lift';

/** The style text: a registered custom property animated by the root scroll timeline (not compositable). */
export function throttleLiftCss(): string {
  return [
    '@property --fw-tl { syntax: "<number>"; inherits: false; initial-value: 0; }',
    '@keyframes fw-tl { from { --fw-tl: 0; } to { --fw-tl: 1; } }',
    `[${THROTTLE_LIFT_ATTR}] { position: fixed; left: 0; top: 0; width: 1px; height: 1px; opacity: 0; pointer-events: none;`,
    ' animation: fw-tl 1s linear both; animation-duration: auto; animation-timeline: scroll(root block); }',
  ].join('\n');
}

/** Install the style and the element; returns the undo. Client only. */
export function installThrottleLift(doc: Document): () => void {
  const style = doc.createElement('style');
  style.textContent = throttleLiftCss();
  const el = doc.createElement('div');
  el.setAttribute(THROTTLE_LIFT_ATTR, '');
  el.setAttribute('aria-hidden', 'true');
  doc.head.appendChild(style);
  doc.body.appendChild(el);
  return () => {
    style.remove();
    el.remove();
  };
}
