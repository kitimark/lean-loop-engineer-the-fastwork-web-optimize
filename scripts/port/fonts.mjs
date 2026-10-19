// Port completeness gate, check 5 (fonts): a twin of lean/Fw/Port/Fonts.lean, checked against
// packages/contracts/golden/port/fonts.jsonl by apps/site/test/port-fonts.test.mjs. `fontsInPage` only reports (TS
// stand-in, it holds no decision); the browser run is packages/visual-diff/src/fonts.mjs.
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { exclusions, norm, sections, unmatched } from './digest.mjs';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
export const goldenPath = path.join(repo, 'packages/contracts/golden/port/fonts.jsonl');
export const goldenCases = () => readFileSync(goldenPath, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));

/** Section rows read in the page: the table without its page-level rows, one selector per arm. */
export const rowsOf = (arm) => sections.table.filter((r) => !r.pageLevel).map((r) => ({ part: r.part, sel: r[arm] }));

const exclIn = (E, c, s, k) => E.some((e) => e.check === c && e.sec === s && e.key === k);
const exclKey = (E, c, k) => E.some((e) => e.check === c && e.key === k);
const unitKey = (u) => JSON.stringify([u.sec, u.text, u.family, u.weight, u.style]);
const unitOf = (k) => { const [sec, text, family, weight, style] = JSON.parse(k); return { sec, text, family, weight, style }; };

/** Fw.Port.Fonts.units. */
export const units = (E, L) =>
  L.filter((l) => norm(l.text) !== '').map((l) => ({ ...l, text: exclIn(E, 'text', l.sec, '*') ? '' : norm(l.text) }));

/** Fw.Port.Fonts.loaded. */
export const loaded = (E, F) =>
  F.filter((f) => f.status === 'loaded' && !exclKey(E, 'fonts', f.family)).map((f) => [f.family, f.weight, f.style]);

const lacks = (o, r) => { const have = new Set(r.map((t) => t.join('\u0000'))); return o.filter((t) => !have.has(t.join('\u0000'))); };

/** Fw.Port.Fonts.check and pass. */
export function check(E, O, R) {
  const uo = units(E, O.leaves).map(unitKey);
  const ur = units(E, R.leaves).map(unitKey);
  const fo = loaded(E, O.faces);
  const fr = loaded(E, R.faces);
  const v = { missing: unmatched(uo, ur).map(unitOf), extra: unmatched(ur, uo).map(unitOf), missingFaces: lacks(fo, fr), extraFaces: lacks(fr, fo) };
  return { ...v, pass: v.missing.length + v.extra.length + v.missingFaces.length + v.extraFaces.length === 0 };
}

const pairOff = (p, ms, es) => {
  const rest = es.slice();
  const pairs = [];
  const unpaired = [];
  for (const m of ms) {
    const i = rest.findIndex((e) => p(m, e));
    if (i >= 0) pairs.push([m, rest.splice(i, 1)[0]]);
    else unpaired.push(m);
  }
  return { pairs, unpaired, rest };
};
const sameKey = (m, e) => m.sec === e.sec && m.text === e.text;
const sameFont = (m, e) => m.text === e.text && m.family === e.family && m.weight === e.weight && m.style === e.style;

/** Fw.Port.Fonts.split: the lost and added leaves told apart as font changes (same section and text), ownership moves (same text and font) and the rest. */
export function split(missing, extra) {
  const a = pairOff(sameKey, missing, extra);
  const b = pairOff(sameFont, a.unpaired, a.rest);
  return { changes: a.pairs, moves: b.pairs, lost: b.unpaired, added: b.rest };
}

/** The exclusions the check runs with (Fw.Port.Fonts.excl): the text exclusions and the fonts exclusions of the golden list. */
export const excl = exclusions.filter((e) => e.check === 'text' || e.check === 'fonts');

/**
 * Page side: every text-carrying element (its own text nodes joined, so a text split by the framework is one leaf) with its
 * computed first font family, weight and style, the section that owns it (the innermost element matching a section row, else
 * `page`), and every FontFace of document.fonts. The read is deterministic by construction: it scrolls the page in viewport steps and
 * then each section row's first element into view, two frames and a pause at each stop (an IntersectionObserver reports at the frame
 * after the scroll, so a section that mounts when it comes near, as morph.mount does, has mounted), returns to the top (the deck's
 * profile follows the scroll position, so both arms show their first one), and polls until the leaves, the deck tab and the face
 * states are equal for `stableFor` polls in a row. `settled` is false when `settleMs` ran out first.
 * Native scrolling and requestAnimationFrame only; no animation is sought. arg: { rows: [{part, sel}], waitMs, settleMs, stableFor, pollMs }
 */
export async function fontsInPage({ rows, waitMs, settleMs = 15000, stableFor = 6, pollMs = 250 }) {
  const sleepP = (ms) => new Promise((r) => setTimeout(r, ms));
  const frames = async (n) => { for (let i = 0; i < n; i++) await Promise.race([new Promise((r) => requestAnimationFrame(() => r())), sleepP(250)]); };
  const unq = (s) => s.trim().replace(/^["']|["']$/g, '');
  const faces = () => Array.from(document.fonts).map((f) => ({ family: unq(f.family), weight: f.weight, style: f.style, status: f.status }));
  const visit = async (top) => { window.scrollTo({ top, behavior: 'instant' }); await frames(2); await sleepP(120); };
  const step = Math.max(200, window.innerHeight);
  for (let y = 0, i = 0; i < 300; i++, y += step) {
    await visit(y);
    if (y + window.innerHeight >= document.documentElement.scrollHeight) break;
  }
  for (const { sel } of rows) {
    const el = document.querySelector(sel);
    if (!el) continue;
    el.scrollIntoView({ block: 'center', behavior: 'instant' });
    await frames(2);
    await sleepP(60);
  }
  await visit(0);
  const t0 = performance.now();
  while (performance.now() - t0 < waitMs && faces().some((f) => f.status === 'loading')) await sleepP(50);
  try { await Promise.race([document.fonts.ready, sleepP(500)]); } catch { /* the faces report their status */ }
  const skip = new Set(['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEMPLATE']);
  const read = () => {
    const owned = new Map();
    for (const { part, sel } of rows) for (const el of document.querySelectorAll(sel)) if (!owned.has(el)) owned.set(el, part);
    const ownerOf = (el) => { for (let e = el; e; e = e.parentElement) if (owned.has(e)) return owned.get(e); return 'page'; };
    const texts = new Map();
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    for (let n = walker.nextNode(); n && texts.size < 20000; n = walker.nextNode()) {
      const el = n.parentElement;
      if (!el || skip.has(el.tagName)) continue;
      texts.set(el, (texts.get(el) ?? '') + n.nodeValue);
    }
    const leaves = [];
    for (const [el, text] of texts) {
      if (text.trim() === '') continue;
      const cs = getComputedStyle(el);
      leaves.push({ sec: ownerOf(el), text, family: unq(cs.fontFamily.split(',')[0] ?? ''), weight: cs.fontWeight, style: cs.fontStyle });
    }
    return leaves;
  };
  const deckTab = () => document.querySelector('[data-profession-tab][aria-selected="true"]')?.getAttribute('data-profession-tab') ?? null;
  const t1 = performance.now();
  let prev = null;
  let same = 0;
  let polls = 0;
  while (performance.now() - t1 < settleMs) {
    await sleepP(pollMs);
    polls++;
    const sig = JSON.stringify([read(), deckTab(), faces().map((f) => f.status)]);
    if (sig === prev) { if (++same >= stableFor) break; } else { same = 0; prev = sig; }
  }
  return { leaves: read(), faces: faces(), settled: same >= stableFor, polls, deckTab: deckTab() };
}
