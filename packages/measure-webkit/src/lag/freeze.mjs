import { RAF_HELPER } from '../page.mjs';

export const FREEZE_OPTIONS = ['hero-accent', 'hero-accent-draw'];

export function parseFreeze(value) {
  if (value === undefined || value === '') return null;
  if (!FREEZE_OPTIONS.includes(value)) throw new Error(`--freeze must be one of ${FREEZE_OPTIONS.join('|')}, got ${JSON.stringify(value)}`);
  return value === 'hero-accent-draw' ? { part: value, mode: 'draw' } : { part: value };
}

const ROOT = '[data-fw="hero-accent"]';

export const FREEZE_CSS = [
  `${ROOT}, ${ROOT} * { animation: none !important; transition: none !important; }`,
  `${ROOT} svg { opacity: 0 !important; transform: none !important; }`,
  `${ROOT} svg:first-child { opacity: 1 !important; }`,
  `${ROOT} path { stroke-dashoffset: 0 !important; }`,
].join('\n');

export const DRAW_ANIMS = '(stroke|clip)(In|Out)(?![a-z])';

export const FREEZE_DRAW_CSS = [
  `${ROOT} path { animation: none !important; stroke-dasharray: none !important; stroke-dashoffset: 0 !important; }`,
  `${ROOT}[class*="drawingIn"] svg { animation: none !important; clip-path: none !important; }`,
  `${ROOT}[class*="drawingOut"] svg { animation: none !important; clip-path: none !important; }`,
  `${ROOT}, ${ROOT} * { transition: none !important; }`,
].join('\n');

const DRAW_COUNTER_JS = `{
    const seen = window.__fwDraw = { animations: 0, transitions: 0 };
    const name = new RegExp(${JSON.stringify(DRAW_ANIMS)});
    const mine = (e) => !!(e.target && e.target.closest && e.target.closest(sel));
    document.addEventListener('animationstart', (e) => { if (mine(e) && name.test(e.animationName)) seen.animations++; }, true);
    document.addEventListener('transitionrun', (e) => { if (mine(e) && e.propertyName === 'width') seen.transitions++; }, true);
  }`;

export const FREEZE_JS = (on, mode = 'all') => `(async () => {
  ${RAF_HELPER}
  const sel = ${JSON.stringify(ROOT)};
  const els = document.querySelectorAll(sel);
  ${mode === 'draw' ? DRAW_COUNTER_JS : ''}
  if (${on ? 'true' : 'false'}) {
    const sheet = new CSSStyleSheet();
    sheet.replaceSync(${JSON.stringify(mode === 'draw' ? FREEZE_DRAW_CSS : FREEZE_CSS)});
    document.adoptedStyleSheets = [...document.adoptedStyleSheets, sheet];
  }
  await raf(); await raf();
  const all = document.getAnimations();
  const own = all.filter((a) => { const t = a.effect && a.effect.target; return !!(t && t.closest && t.closest(sel)); });
  return { on: ${on ? 'true' : 'false'}, ${mode === 'draw' ? "mode: 'draw', " : ''}matched: els.length, sheets: document.adoptedStyleSheets.length, accentAnims: own.length, otherAnims: all.length - own.length };
})()`;

/** The draw starts counted by the draw-mode probe since it was installed; null when it was not installed. */
export const DRAW_READ_JS = '(async () => (window.__fwDraw ? { animations: window.__fwDraw.animations, transitions: window.__fwDraw.transitions } : null))()';

/** Install the freeze in the loaded page; throws when it did not take (no accent found, or its animations still exist). */
export async function freezeApply(c, mode = 'all') {
  const r = await c.runAsync(FREEZE_JS(true, mode), { pollMs: 200 });
  if (r.matched < 1) throw new Error('freeze: no hero-accent element in the page');
  if (mode === 'all' && r.accentAnims > 0) throw new Error(`freeze: ${r.accentAnims} hero-accent animations still exist after the style sheet`);
  return r;
}

/** The same reading without the style sheet (the unfrozen twin of a frozen capture). */
export const freezeProbe = (c, mode = 'all') => c.runAsync(FREEZE_JS(false, mode), { pollMs: 200 });

/** Apply or probe, by the capture's freeze option: `null` calls nothing. */
export const freezeStep = (c, freeze) => (freeze === null || freeze === undefined ? null : freeze.on ? freezeApply(c, freeze.mode) : freezeProbe(c, freeze.mode));

/** The draw starts of a draw-mode capture, read at its end; null for any other freeze. */
export const freezeDrawRead = async (c, freeze) => (freeze?.mode === 'draw' ? c.runAsync(DRAW_READ_JS, { pollMs: 200 }) : null);
