// Harness-side freeze of the hero.accent part (I/O only). Premise: it removes the animations and transitions of the elements
// inside [data-fw="hero-accent"] and nothing else, with the same visible result as that part's own prefers-reduced-motion block
// (apps/site/src/parts/hero.accent/accent.module.css, @media (prefers-reduced-motion: reduce)): no CSS animation, no width
// transition, stroke fully drawn, idle frame 0 shown. The chain of timers still runs and still writes the class, the width, the
// view box and the path, so the DOM writes stay; only the per-frame animation work goes. Applied after the load through an
// adopted style sheet (no DOM node added, no change to the page's own sheets); unset, nothing is called.
import { RAF_HELPER } from '../page.mjs';

export const FREEZE_OPTIONS = ['hero-accent'];

export function parseFreeze(value) {
  if (value === undefined || value === '') return null;
  if (!FREEZE_OPTIONS.includes(value)) throw new Error(`--freeze must be one of ${FREEZE_OPTIONS.join('|')}, got ${JSON.stringify(value)}`);
  return { part: value };
}

const ROOT = '[data-fw="hero-accent"]';

export const FREEZE_CSS = [
  `${ROOT}, ${ROOT} * { animation: none !important; transition: none !important; }`,
  `${ROOT} svg { opacity: 0 !important; transform: none !important; }`,
  `${ROOT} svg:first-child { opacity: 1 !important; }`,
  `${ROOT} path { stroke-dashoffset: 0 !important; }`,
].join('\n');

export const FREEZE_JS = (on) => `(async () => {
  ${RAF_HELPER}
  const sel = ${JSON.stringify(ROOT)};
  const els = document.querySelectorAll(sel);
  if (${on ? 'true' : 'false'}) {
    const sheet = new CSSStyleSheet();
    sheet.replaceSync(${JSON.stringify(FREEZE_CSS)});
    document.adoptedStyleSheets = [...document.adoptedStyleSheets, sheet];
  }
  await raf(); await raf();
  const all = document.getAnimations();
  const own = all.filter((a) => { const t = a.effect && a.effect.target; return !!(t && t.closest && t.closest(sel)); });
  return { on: ${on ? 'true' : 'false'}, matched: els.length, sheets: document.adoptedStyleSheets.length, accentAnims: own.length, otherAnims: all.length - own.length };
})()`;

/** Install the freeze in the loaded page; throws when it did not take (no accent found, or its animations still exist). */
export async function freezeApply(c) {
  const r = await c.runAsync(FREEZE_JS(true), { pollMs: 200 });
  if (r.matched < 1) throw new Error('freeze: no hero-accent element in the page');
  if (r.accentAnims > 0) throw new Error(`freeze: ${r.accentAnims} hero-accent animations still exist after the style sheet`);
  return r;
}

/** The same reading without the style sheet (the unfrozen twin of a frozen capture). */
export const freezeProbe = (c) => c.runAsync(FREEZE_JS(false), { pollMs: 200 });

/** Apply or probe, by the capture's freeze option: `null` calls nothing. */
export const freezeStep = (c, freeze) => (freeze === null || freeze === undefined ? null : freeze.on ? freezeApply(c) : freezeProbe(c));
