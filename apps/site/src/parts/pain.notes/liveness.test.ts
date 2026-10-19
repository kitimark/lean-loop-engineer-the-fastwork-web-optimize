import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { prerender } from '../../entry-server';
import { ALLOW_SELECTOR, EXCLUDE_SELECTOR, INCLUDE_SELECTOR, SHRINKING_SELECTOR } from '../nav.hitTest/logic';
import { HERO_TRACK_SELECTOR, PROFILE_SECTION_SELECTOR, PROFILE_STICKY_SELECTOR } from '../nav.hitTest/probe';
import { CARD_SELECTOR } from './logic';

/**
 * Port plan check 6, for the parts that query the page by selector (pain.notes, nav.hitTest): each selector matches at
 * least one element of the prerendered page. The page is parsed with a small matcher (no DOM in this test environment);
 * it supports exactly the selector forms these parts use and throws on any other.
 */

interface El {
  tag: string;
  attrs: Map<string, string>;
  parent: El | null;
}

const VOID = new Set(['area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'source', 'track', 'wbr']);

function parse(html: string): El[] {
  const all: El[] = [];
  const root: El = { tag: '#root', attrs: new Map(), parent: null };
  let cur = root;
  const body = html.replace(/<!--[\s\S]*?-->/g, '').replace(/<(script|style)\b[\s\S]*?<\/\1>/g, '');
  const re = /<(\/?)([a-zA-Z][\w-]*)((?:"[^"]*"|'[^']*'|[^>"'])*)>/g;
  for (let m = re.exec(body); m; m = re.exec(body)) {
    const [, close, name, rest] = m as unknown as [string, string, string, string];
    const tag = name.toLowerCase();
    if (close) {
      for (let e: El | null = cur; e && e !== root; e = e.parent) {
        if (e.tag === tag) {
          cur = e.parent ?? root;
          break;
        }
      }
      continue;
    }
    const attrs = new Map<string, string>();
    for (const a of rest.matchAll(/([^\s=/"']+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+)))?/g)) {
      attrs.set(a[1]!, a[2] ?? a[3] ?? a[4] ?? '');
    }
    const el: El = { tag, attrs, parent: cur };
    all.push(el);
    if (!VOID.has(tag) && !rest.endsWith('/')) cur = el;
  }
  return all;
}

function splitTop(s: string, sep: string): string[] {
  const out: string[] = [];
  let depth = 0;
  let q = '';
  let start = 0;
  for (let i = 0; i < s.length; i++) {
    const c = s[i]!;
    if (q) q = c === q ? '' : q;
    else if (c === '"' || c === "'") q = c;
    else if (c === '(') depth++;
    else if (c === ')') depth--;
    else if (c === sep && depth === 0) {
      out.push(s.slice(start, i));
      start = i + 1;
    }
  }
  out.push(s.slice(start));
  return out.map((x) => x.trim()).filter(Boolean);
}

function matchCompound(el: El, c: string): boolean {
  const re = /([a-zA-Z][\w-]*)|#([\w-]+)|\.([\w-]+)|\[([\w-]+)(?:(\*?=)"([^"]*)")?\]|:not\(((?:[^()]|\([^)]*\))*)\)/y;
  let pos = 0;
  while (pos < c.length) {
    re.lastIndex = pos;
    const m = re.exec(c);
    if (!m) throw new Error(`unsupported selector part: ${c.slice(pos)}`);
    pos = re.lastIndex;
    const classes = (el.attrs.get('class') ?? '').split(/\s+/);
    if (m[1] && el.tag !== m[1].toLowerCase()) return false;
    if (m[2] && el.attrs.get('id') !== m[2]) return false;
    if (m[3] && !classes.includes(m[3])) return false;
    if (m[4]) {
      const v = el.attrs.get(m[4]);
      if (v === undefined) return false;
      if (m[5] === '=' && v !== m[6]) return false;
      if (m[5] === '*=' && !v.includes(m[6]!)) return false;
    }
    if (m[7] !== undefined && splitTop(m[7], ',').some((n) => matchCompound(el, n))) return false;
  }
  return true;
}

function matchComplex(el: El, sel: string): boolean {
  const toks = sel.replace(/\s*>\s*/g, ' > ').split(/\s+/);
  const test = (e: El | null, i: number): boolean => {
    if (!e) return false;
    if (!matchCompound(e, toks[i]!)) return false;
    if (i === 0) return true;
    if (toks[i - 1] === '>') return test(e.parent, i - 2);
    for (let p = e.parent; p; p = p.parent) if (test(p, i - 1)) return true;
    return false;
  };
  return test(el, toks.length - 1);
}

const count = (els: El[], sel: string): number => els.filter((e) => matchComplex(e, sel)).length;

/** Selectors whose last condition is a runtime state; the static part (given) must still be present. */
const STATEFUL: Record<string, { why: string; staticPart: string }> = {
  [SHRINKING_SELECTOR]: { why: 'the class is toggled by the commission driver on scroll', staticPart: '[data-fw="commission"]' },
  '[data-fw="nav"]:not(.is-hero-pill, .is-morphing) [data-fw="nav-earn"]': {
    why: 'the nav carries is-hero-pill until the hero is passed',
    staticPart: '[data-fw="nav"] [data-fw="nav-earn"]',
  },
};

/** Client-mounted: App mounts the morph panel after the hero (`setPanel(true)`), so it is absent from the prerender. */
const CLIENT_MOUNTED = '[data-fw="morph-panel"][data-expanded]';

describe('selectors the parts query match the prerendered page', () => {
  (globalThis as Record<string, unknown>).__FW_ENGINE__ = 'runtime'; // build-time define of scripts/build.mjs
  const els = parse(prerender(['']).homeHtml);
  const units = new Set([
    CARD_SELECTOR,
    HERO_TRACK_SELECTOR,
    PROFILE_STICKY_SELECTOR,
    ...splitTop(PROFILE_SECTION_SELECTOR, ','),
    ...splitTop(EXCLUDE_SELECTOR, ','),
    ...splitTop(INCLUDE_SELECTOR, ','),
    ...splitTop(SHRINKING_SELECTOR, ','),
    ...splitTop(ALLOW_SELECTOR, ','),
  ]);
  it('the page has elements', () => {
    expect(els.length).toBeGreaterThan(100);
  });
  for (const sel of units) {
    const st = STATEFUL[sel];
    if (sel === CLIENT_MOUNTED) {
      it(`${sel}: the panel is mounted on the client; its hook and the attribute the driver writes exist in source`, () => {
        const panel = readFileSync(new URL('../morph.panel/index.tsx', import.meta.url), 'utf8');
        const driver = readFileSync(new URL('../morph.panel/driver.ts', import.meta.url), 'utf8');
        expect(panel).toContain('data-fw="morph-panel"');
        expect(driver).toContain('data-expanded');
      });
    } else if (st) {
      it(`${sel}: ${st.why}; its static part is present`, () => {
        expect(count(els, st.staticPart)).toBeGreaterThan(0);
      });
    } else {
      it(`${sel} matches at least one element`, () => {
        expect(count(els, sel)).toBeGreaterThan(0);
      });
    }
  }
  it('the matcher rejects the original class names', () => {
    expect(count(els, '.commission-card')).toBe(0);
  });
});
