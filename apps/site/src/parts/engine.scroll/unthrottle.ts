export const UNTHROTTLE_ATTR = 'data-fw-unthrottle';

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
