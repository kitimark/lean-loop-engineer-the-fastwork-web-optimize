import { readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { createElement } from 'react';
import { renderToString } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';
import { Hero } from '../hero';
import heroCss from '../hero/hero.module.css';
import accentCss from '../hero.accent/accent.module.css';
import countdownCss from '../hero.countdown/hero.module.css';
import cueCss from '../hero.cue/cue.module.css';
import deckCss from '../hero.deck/deck.module.css';
import cardCss from '../hero.orbit/card.module.css';
import orbitCss from '../hero.orbit/orbit.module.css';
import exitCss from './hero.module.css';
import part from './part.json';
import { createExitDriver } from './driver';
import { READER_SELECTOR, readerWrites, SCOPE_ATTR, SCOPED, SCOPED_PROPS } from './scope';

type GNode = [string, string] | [string, string, GNode[]];
interface Golden {
  variant: string;
  scopeAttr: string;
  register: { name: string; syntax: string; inherits: boolean }[];
  readers: string[];
  inheritRules: string[];
  stageDefaults: { opacity: string; scatter: string; reducedScatter: string };
  trees: { narrow: GNode; wide: GNode };
  units: Record<'narrow' | 'wide', { chromiumFaithful: number; webkitFaithful: number; chromiumScoped: number; webkitScoped: number }>;
  inline: Record<'narrow' | 'wide', { touched: number; chromium: number; webkit: number }>;
  readerWrites: { reduced: boolean; opacity: string; writes: [string, string][] }[];
  frameWrites: { element: string; property: string }[];
}

const root = resolve(__dirname, '../../../../..');
const golden = JSON.parse(readFileSync(resolve(root, 'packages/contracts/golden/parts/hero.exit.scoped.json'), 'utf8')) as Golden;
const partsDir = resolve(__dirname, '..');
const stylesDir = resolve(__dirname, '../../styles');
const EXIT_PROPS = ['--exit-opacity', '--exit-scatter'];
const INHERITED_PROPS = new Set(['color', 'font']);
const MODULES: Record<string, { part: string; map: Record<string, string> }> = {
  'hero/hero.module.css': { part: 'hero', map: heroCss },
  'hero.accent/accent.module.css': { part: 'hero.accent', map: accentCss },
  'hero.countdown/hero.module.css': { part: 'hero.countdown', map: countdownCss },
  'hero.cue/cue.module.css': { part: 'hero.cue', map: cueCss },
  'hero.deck/deck.module.css': { part: 'hero.deck', map: deckCss },
  'hero.orbit/card.module.css': { part: 'hero.orbit', map: cardCss },
  'hero.orbit/orbit.module.css': { part: 'hero.orbit', map: orbitCss },
  'hero.exit/hero.module.css': { part: 'hero.exit', map: exitCss },
};

const LAYERS = ['reset', 'mui', 'parts', 'flags'];
const UNLAYERED = LAYERS.length;

interface Rule {
  file: number;
  order: number;
  layer: number;
  selectors: string[];
  raw: string[];
  decls: [string, string, boolean][];
  media: string[];
}

function splitTop(s: string, sep: string): string[] {
  const out: string[] = [];
  let depth = 0;
  let cur = '';
  for (const ch of s) {
    if (ch === '(' || ch === '[') depth++;
    if (ch === ')' || ch === ']') depth--;
    if (ch === sep && depth === 0) {
      out.push(cur);
      cur = '';
    } else cur += ch;
  }
  out.push(cur);
  return out;
}

function translate(sel: string, map: Record<string, string>): string {
  let out = '';
  let i = 0;
  while (i < sel.length) {
    if (sel.startsWith(':global(', i)) {
      let depth = 1;
      let j = i + 8;
      while (depth > 0) {
        if (sel[j] === '(') depth++;
        if (sel[j] === ')') depth--;
        j++;
      }
      out += sel.slice(i + 8, j - 1);
      i = j;
    } else if (sel[i] === '.' && /[A-Za-z_]/.test(sel[i + 1] ?? '')) {
      const m = /^\.([A-Za-z_][\w-]*)/.exec(sel.slice(i))!;
      out += '.' + (map[m[1]] ?? m[1]);
      i += m[0].length;
    } else if (sel[i] === '[') {
      const j = sel.indexOf(']', i);
      out += sel.slice(i, j + 1);
      i = j + 1;
    } else {
      out += sel[i];
      i++;
    }
  }
  return out;
}

function parseCss(src: string, file: number, map: Record<string, string>, layer0: number): Rule[] {
  const text = src.replace(/\/\*[\s\S]*?\*\//g, '');
  const rules: Rule[] = [];
  const stack: { prelude: string; body: string }[] = [];
  let buf = '';
  let order = 0;
  for (const ch of text) {
    if (ch === '{') {
      stack.push({ prelude: buf.trim(), body: '' });
      buf = '';
    } else if (ch === '}') {
      const top = stack.pop()!;
      top.body += buf;
      buf = '';
      if (top.prelude.startsWith('@')) continue;
      const outer = stack.map((s) => s.prelude);
      if (outer.some((p) => /^@(keyframes|property|font-face)/.test(p))) continue;
      const layerAt = [...outer].reverse().find((p) => p.startsWith('@layer'));
      const layer = layerAt ? LAYERS.indexOf(layerAt.slice(6).trim()) : layer0;
      if (layer < 0) throw new Error(`unknown layer ${layerAt}`);
      const decls = top.body
        .split(';')
        .map((d) => d.trim())
        .filter((d) => d.includes(':'))
        .map((d) => {
          const v = d.slice(d.indexOf(':') + 1).trim();
          const imp = /!important$/.test(v);
          return [d.slice(0, d.indexOf(':')).trim(), imp ? v.replace(/\s*!important$/, '') : v, imp] as [string, string, boolean];
        });
      const raw = splitTop(top.prelude, ',').map((s) => s.trim().replace(/\s+/g, ' '));
      rules.push({ file, order: order++, layer, raw, selectors: raw.map((s) => translate(s, map)), decls, media: outer.filter((p) => p.startsWith('@media')) });
    } else if (ch === ';' && stack.length > 0) {
      stack[stack.length - 1].body += buf + ';';
      buf = '';
    } else {
      buf += ch;
    }
  }
  return rules;
}

const cssFiles = (dir: string): string[] =>
  readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
    e.isDirectory() ? cssFiles(join(dir, e.name)) : e.name.endsWith('.css') ? [join(dir, e.name)] : [],
  );
const relOf = (f: string): string => f.slice(partsDir.length + 1);
const heroFiles = cssFiles(partsDir).filter((f) => relOf(f).startsWith('hero'));
const files = [resolve(stylesDir, 'reset.css'), ...heroFiles];
const fileRules = files.map((f, i) => ({ rel: relOf(f), rules: parseCss(readFileSync(f, 'utf8'), i, MODULES[relOf(f)]?.map ?? {}, UNLAYERED) }));
const partOf = (rel: string): string => rel.split('/')[0];
const nameOfClass = new Map(
  fileRules.flatMap(({ rel, rules }) =>
    MODULES[rel]
      ? rules.flatMap((r) => r.raw.flatMap((s) => [...s.replace(/:global\([^)]*\)/g, '').matchAll(/\.([A-Za-z_][\w-]*)/g)]))
          .map((m) => [MODULES[rel].map[m[1]], `${MODULES[rel].part}/${m[1]}`] as [string, string])
      : [],
  ),
);

interface Env {
  width: number;
  reduced: boolean;
  hoverNone: boolean;
  coarse: boolean;
}

function mediaOk(prelude: string, env: Env): boolean {
  return splitTop(prelude.replace(/^@media/, ''), ',').some((alt) =>
    alt
      .trim()
      .split(/\s+and\s+/)
      .every((f) => {
        const w = /^\(width\s*(<=|>=|<|>)\s*(\d+)px\)$/.exec(f.trim());
        if (w) {
          const n = +w[2];
          return w[1] === '<=' ? env.width <= n : w[1] === '>=' ? env.width >= n : w[1] === '<' ? env.width < n : env.width > n;
        }
        if (f.trim() === '(prefers-reduced-motion: reduce)') return env.reduced;
        if (f.trim() === '(hover: none)') return env.hoverNone;
        if (f.trim() === '(pointer: coarse)') return env.coarse;
        throw new Error(`media feature ${f}`);
      }),
  );
}

interface El {
  tag: string;
  attrs: string;
  kids: El[];
  parent?: El;
}

function parseHtml(html: string): El {
  const VOID = new Set(['area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'source', 'track', 'wbr']);
  const re = /<!--[\s\S]*?-->|<(\/?)([a-zA-Z][\w:-]*)([^>]*?)(\/?)>/g;
  const top: El = { tag: '#root', attrs: '', kids: [] };
  const stack: El[] = [top];
  let raw: string | null = null;
  for (let m = re.exec(html); m; m = re.exec(html)) {
    if (m[0].startsWith('<!--')) continue;
    const [, close, tag0, attrs, self] = m;
    const tag = tag0.toLowerCase();
    if (raw) {
      if (close && tag === raw) {
        raw = null;
        stack.pop();
      }
      continue;
    }
    if (close) {
      while (stack.length > 1 && stack[stack.length - 1].tag !== tag) stack.pop();
      stack.pop();
      continue;
    }
    const el: El = { tag, attrs, kids: [], parent: stack[stack.length - 1] };
    if (VOID.has(tag) || self) {
      stack[stack.length - 1].kids.push(el);
      continue;
    }
    if (tag === 'script' || tag === 'style') raw = tag;
    else stack[stack.length - 1].kids.push(el);
    stack.push(el);
  }
  return top;
}

const classes = (el: El): string[] => (/class="([^"]*)"/.exec(el.attrs)?.[1] ?? '').split(/\s+/).filter(Boolean);
const attr = (el: El, name: string): string | undefined => {
  const m = new RegExp(`(?:^|\\s)${name}(?:="([^"]*)")?(?=\\s|$)`).exec(el.attrs);
  return m ? (m[1] ?? '') : undefined;
};
const find = (el: El, p: (e: El) => boolean): El | undefined => (p(el) ? el : el.kids.map((k) => find(k, p)).find(Boolean));
const nameOf = (el: El): string => classes(el).map((c) => nameOfClass.get(c)).find(Boolean) ?? el.tag;
const isLink = (el: El): boolean => el.tag === 'a' && attr(el, 'href') !== undefined;

function matchesCompound(el: El, c: string): boolean {
  let i = 0;
  while (i < c.length) {
    const rest = c.slice(i);
    let m: RegExpExecArray | null;
    if ((m = /^\*/.exec(rest))) {
      i += 1;
    } else if ((m = /^[a-zA-Z][\w-]*/.exec(rest)) && i === 0) {
      if (el.tag !== m[0].toLowerCase()) return false;
      i += m[0].length;
    } else if ((m = /^\.([\w-]+)/.exec(rest))) {
      if (!classes(el).includes(m[1])) return false;
      i += m[0].length;
    } else if ((m = /^\[([\w-]+)(?:=['"]?([^'"\]]*)['"]?)?\]/.exec(rest))) {
      const v = attr(el, m[1]);
      if (v === undefined || (m[2] !== undefined && v !== m[2])) return false;
      i += m[0].length;
    } else if ((m = /^::?[\w-]+/.exec(rest))) {
      const name = m[0];
      let args = '';
      i += name.length;
      if (c[i] === '(') {
        let depth = 1;
        let j = i + 1;
        while (depth > 0) {
          if (c[j] === '(') depth++;
          if (c[j] === ')') depth--;
          j++;
        }
        args = c.slice(i + 1, j - 1);
        i = j;
      }
      if (name.startsWith('::')) return false;
      if ([':hover', ':focus', ':focus-visible', ':active', ':focus-within', ':visited'].includes(name)) return false;
      if (name === ':first-child') {
        if (!el.parent || el.parent.kids[0] !== el) return false;
      } else if (name === ':is' || name === ':where') {
        if (!splitTop(args, ',').some((a) => matchesComplex(el, a.trim()))) return false;
      } else if (name === ':not') {
        if (splitTop(args, ',').some((a) => matchesComplex(el, a.trim()))) return false;
      } else if (name === ':link' || name === ':any-link') {
        if (!isLink(el)) return false;
      } else throw new Error(`pseudo ${name}`);
    } else throw new Error(`selector ${c} at ${rest}`);
  }
  return true;
}

function matchesComplex(el: El, sel: string): boolean {
  const parts = splitTop(sel.replace(/\s*>\s*/g, ' > ').replace(/\s*([+~])\s*/g, ' $1 '), ' ').filter(Boolean);
  if (parts.some((p) => p === '+' || p === '~')) throw new Error(`combinator in ${sel}`);
  const go = (e: El | undefined, k: number): boolean => {
    if (!e || e.tag === '#root') return false;
    if (!matchesCompound(e, parts[k])) return false;
    if (k === 0) return true;
    if (parts[k - 1] === '>') return go(e.parent, k - 2);
    for (let a = e.parent; a && a.tag !== '#root'; a = a.parent) if (go(a, k - 1)) return true;
    return false;
  };
  return go(el, parts.length - 1);
}

function specificity(sel: string): number {
  const ids = (sel.match(/#[\w-]+/g) ?? []).length;
  const cls = (sel.match(/\.[\w-]+|\[[^\]]*\]|:(?!:|is|where|not|global)[\w-]+/g) ?? []).length;
  const tags = (sel.replace(/\[[^\]]*\]|\([^)]*\)/g, '').match(/(?:^|[\s>])[a-zA-Z][\w-]*/g) ?? []).length;
  return ids * 10000 + cls * 100 + tags;
}

interface Flags {
  vars: boolean;
  slow: boolean;
  hidden: boolean;
  inh: boolean;
  explicit: boolean;
  reads: boolean;
}
interface FNode {
  name: string;
  f: Flags;
  kids: FNode[];
}

const readsExit = (v: string): boolean => EXIT_PROPS.some((p) => v.includes(`var(${p}`));

function flagTree(variants: Record<string, string>, env: Env): { stage: El; tree: FNode } {
  const html = renderToString(createElement(Hero, { variants }));
  const rules = fileRules.flatMap((r) => r.rules);
  const emotion = [...html.matchAll(/<style[^>]*>([\s\S]*?)<\/style>/g)].map((m) => m[1]).join('\n');
  rules.push(...parseCss(emotion, files.length, {}, UNLAYERED));
  const live = rules.filter((r) => r.media.every((m) => mediaOk(m, env)));
  const winners = (el: El): Map<string, string> => {
    const best = new Map<string, { key: number[]; v: string }>();
    for (const r of live)
      for (const s of r.selectors) {
        if (!matchesComplex(el, s)) continue;
        for (const [p, v, imp] of r.decls) {
          const key = [imp ? 1 : 0, imp ? UNLAYERED - r.layer : r.layer, specificity(s), r.file, r.order];
          const cur = best.get(p);
          if (!cur || key.some((x, i) => key.slice(0, i).every((y, j) => y === cur.key[j]) && x > cur.key[i])) best.set(p, { key, v });
        }
      }
    const out = new Map([...best].map(([p, x]) => [p, x.v]));
    const style = attr(el, 'style');
    if (style) for (const d of style.split(';').filter((d) => d.includes(':'))) out.set(d.slice(0, d.indexOf(':')).trim(), d.slice(d.indexOf(':') + 1).trim());
    return out;
  };
  const stage = find(parseHtml(html), (e) => classes(e).includes(exitCss.hero))!;
  const walk = (el: El, link: boolean, deco: boolean, svg: boolean): FNode => {
    const w = winners(el);
    const inLink = link || isLink(el);
    const td = w.get('text-decoration') ?? w.get('text-decoration-line') ?? (isLink(el) ? 'underline' : undefined);
    const decorated = deco || (td !== undefined && td !== 'none');
    const inSvg = svg || el.tag === 'svg';
    const exitInherit = EXIT_PROPS.map((p) => w.get(p) === 'inherit');
    expect(exitInherit[0]).toBe(exitInherit[1]);
    const f: Flags = {
      vars: [...w].some(([p, v]) => p.startsWith('--') || v.includes('var(')),
      slow: [...w.keys()].some((p) => p.startsWith('animation') || p.startsWith('transition')) || inLink || decorated || inSvg,
      hidden: w.get('display') === 'none' || attr(el, 'hidden') !== undefined,
      inh: exitInherit[0],
      explicit: [...w].some(([p, v]) => v === 'inherit' && !EXIT_PROPS.includes(p) && !INHERITED_PROPS.has(p)),
      reads: [...w].some(([p, v]) => !p.startsWith('--') && readsExit(v)),
    };
    return { name: nameOf(el), f, kids: el.kids.map((k) => walk(k, inLink, decorated, inSvg)) };
  };
  return { stage, tree: walk(stage, false, false, false) };
}

const LETTERS: [keyof Flags, string][] = [['vars', 'v'], ['slow', 's'], ['hidden', 'h'], ['inh', 'i'], ['explicit', 'x'], ['reads', 'r']];
const gnode = (n: FNode): GNode => {
  const letters = LETTERS.filter(([k]) => n.f[k]).map(([, l]) => l).join('');
  return n.kids.length === 0 ? [n.name, letters] : [n.name, letters, n.kids.map(gnode)];
};

function combined(faithful: FNode, scoped: FNode): FNode {
  expect(scoped.name).toBe(faithful.name);
  expect(faithful.f.inh).toBe(false);
  expect(scoped.f.vars).toBe(faithful.f.vars || scoped.f.inh);
  for (const k of ['slow', 'hidden', 'explicit', 'reads'] as const) expect(scoped.f[k]).toBe(faithful.f[k]);
  expect(scoped.kids.length).toBe(faithful.kids.length);
  return { name: faithful.name, f: { ...faithful.f, inh: scoped.f.inh }, kids: faithful.kids.map((k, i) => combined(k, scoped.kids[i])) };
}

const sum = (ks: FNode[], g: (k: FNode) => number): number => ks.reduce((a, k) => a + g(k), 0);
const crFull = (n: FNode): number => 1 + (n.f.hidden ? 0 : sum(n.kids, n.f.vars ? crFull : crClone));
const crClone = (n: FNode): number => (n.f.vars || n.f.slow || n.f.hidden ? crFull(n) : sum(n.kids, crClone));
const wkFull = (n: FNode): number => 1 + (n.f.hidden ? 0 : sum(n.kids, wkFull));
const crScoped = (n: FNode): number =>
  1 + (!n.f.hidden && n.kids.some((k) => k.f.inh || k.f.explicit) ? sum(n.kids, (k) => (k.f.inh ? crScoped(k) : 1)) : 0);
const wkScoped = (n: FNode): number => 1 + (n.f.hidden ? 0 : sum(n.kids, (k) => (k.f.inh ? wkScoped(k) : k.f.explicit ? 1 : 0)));

const PHONE = { reduced: false, hoverNone: true, coarse: true };
const DESKTOP = { reduced: false, hoverNone: false, coarse: false };
const ENVS: [keyof Golden['trees'], Env][] = [
  ...[320, 375, 400, 430, 600].map((width) => ['narrow', { width, ...PHONE }] as [keyof Golden['trees'], Env]),
  ...[601, 800, 1024, 1200].map((width) => ['wide', { width, ...PHONE }] as [keyof Golden['trees'], Env]),
  ...[601, 1000, 1280, 1440, 1512, 1920].map((width) => ['wide', { width, ...DESKTOP }] as [keyof Golden['trees'], Env]),
];

describe('hero.exit:scoped constants against the Lean golden', () => {
  it('variant, attribute and registrations', () => {
    expect(golden.variant).toBe(SCOPED);
    expect(golden.scopeAttr).toBe(SCOPE_ATTR);
    expect(SCOPED_PROPS).toEqual(golden.register);
    expect((part.variants as Record<string, { kind: string }>)[SCOPED].kind).toBe('optimized');
  });

  it('the stage rule and the reduced-motion rule declare the golden stage defaults', () => {
    const exit = fileRules.find((r) => r.rel === 'hero.exit/hero.module.css')!.rules.filter((r) => r.raw.includes('.hero'));
    const value = (media: (m: string[]) => boolean, p: string): (string | undefined)[] =>
      exit.filter((r) => media(r.media)).flatMap((r) => r.decls.filter(([q]) => q === p).map(([, v]) => v));
    const plain = (m: string[]): boolean => m.length === 0;
    const reduced = (m: string[]): boolean => m.length === 1 && m[0] === '@media (prefers-reduced-motion: reduce)';
    expect(value(plain, '--exit-opacity')).toEqual([golden.stageDefaults.opacity]);
    expect(value(plain, '--exit-scatter')).toEqual([golden.stageDefaults.scatter]);
    expect(value(reduced, '--exit-scatter')).toEqual([golden.stageDefaults.reducedScatter]);
    expect(value(reduced, '--exit-opacity')).toEqual([]);
  });
});

describe('readers and inherit rules from the CSS', () => {
  const isScopeRule = (r: Rule): boolean =>
    r.raw.every((s) => s.startsWith(`[${SCOPE_ATTR}] `)) &&
    r.decls.length === EXIT_PROPS.length &&
    r.decls.every(([p, v]) => EXIT_PROPS.includes(p) && v === 'inherit');
  const subjectClass = (selector: string): string | null => /\.([A-Za-z][\w-]*)/.exec(selector.split(/[\s>+~]+/).pop() ?? '')?.[1] ?? null;
  const partRules = fileRules.filter((r) => r.rel.startsWith('hero'));

  it('the scope rules declare inherit on exactly the golden chain classes', () => {
    const chain = new Set<string>();
    for (const { rel, rules } of partRules)
      for (const r of rules) if (isScopeRule(r)) for (const s of r.raw) chain.add(`${partOf(rel)}/${subjectClass(s)}`);
    expect([...chain].sort()).toEqual([...golden.inheritRules].sort());
  });

  it('no other rule names the scope attribute or declares an exit property outside hero.exit', () => {
    for (const { rel, rules } of fileRules)
      for (const r of rules) {
        if (isScopeRule(r)) continue;
        expect(r.raw.some((s) => s.includes(SCOPE_ATTR))).toBe(false);
        if (partOf(rel) !== 'hero.exit') expect(r.decls.some(([prop]) => EXIT_PROPS.includes(prop))).toBe(false);
      }
  });
});

describe('the cascade-derived hero stage against the golden trees', () => {
  it.each(ENVS)('%s tree at %o', (key, env) => {
    const f = flagTree({}, env);
    const s = flagTree({ 'hero.exit': SCOPED }, env);
    expect(s.stage.attrs).toContain(`${SCOPE_ATTR}=""`);
    expect(f.stage.attrs).not.toContain(SCOPE_ATTR);
    expect(gnode(combined(f.tree, s.tree))).toEqual(golden.trees[key]);
  });

  it.each(['narrow', 'wide'] as const)('%s: the TS recurrences over the golden tree give the golden units', (key) => {
    const fromG = (g: GNode): FNode => ({
      name: g[0],
      f: Object.fromEntries(LETTERS.map(([k, l]) => [k, g[1].includes(l)])) as unknown as Flags,
      kids: (g[2] ?? []).map(fromG),
    });
    const t = fromG(golden.trees[key]);
    expect({ chromiumFaithful: crFull(t), webkitFaithful: wkFull(t), chromiumScoped: crScoped(t), webkitScoped: wkScoped(t) }).toEqual(golden.units[key]);
  });

  it('the readers are the named reading elements of the trees', () => {
    const names = new Set<string>();
    const walk = (g: GNode): void => {
      if (g[1].includes('r')) names.add(g[0]);
      (g[2] ?? []).forEach(walk);
    };
    walk(golden.trees.narrow);
    walk(golden.trees.wide);
    expect([...names].sort()).toEqual([...golden.readers].sort());
  });
});

describe('registerScoped', () => {
  it('registers both properties once and tolerates an earlier registration', async () => {
    vi.resetModules();
    const { registerScoped } = await import('./scope');
    const seen: string[] = [];
    const registry = {
      registerProperty(def: { name: string }) {
        seen.push(def.name);
        if (def.name === '--exit-scatter') throw new DOMException('taken', 'InvalidModificationError');
      },
    };
    registerScoped(registry);
    registerScoped(registry);
    expect(seen).toEqual(EXIT_PROPS);
  });

  it('skips a document without CSS.registerProperty and rethrows other errors', async () => {
    vi.resetModules();
    const a = await import('./scope');
    a.registerScoped(undefined);
    expect(() =>
      a.registerScoped({
        registerProperty() {
          throw new TypeError('bad');
        },
      }),
    ).toThrow(TypeError);
  });
});

describe('inline writes on the readers (Lean inline_visSame)', () => {
  it('readerWrites matches the golden vectors', () => {
    for (const c of golden.readerWrites) expect(readerWrites(c.reduced, c.opacity)).toEqual(c.writes);
  });

  it('the frame writes are the stage and then each golden reader', () => {
    const per = golden.readers.flatMap((r) => EXIT_PROPS.map((property) => ({ element: r, property })));
    expect(golden.frameWrites).toEqual([{ element: 'hero.exit/hero', property: '--exit-opacity' }, ...per]);
  });

  it('the selector finds exactly the golden readers of the SSR stage', () => {
    const html = renderToString(createElement(Hero, { variants: { 'hero.exit': SCOPED } }));
    const stage = find(parseHtml(html), (e) => attr(e, SCOPE_ATTR) !== undefined)!;
    const readerClasses: Record<string, string> = { 'hero.orbit/card': cardCss.card, 'hero/copy': heroCss.copy, 'hero.cue/cue': cueCss.cue };
    expect(Object.keys(readerClasses).sort()).toEqual([...golden.readers].sort());
    const wanted = new Set(Object.values(readerClasses));
    const all = (el: El): El[] => [el, ...el.kids.flatMap(all)];
    const byClass = all(stage).filter((e) => classes(e).some((c) => wanted.has(c)));
    const bySelector = all(stage).filter((e) => READER_SELECTOR.split(',').some((s) => matchesComplex(e, s.trim())));
    expect(bySelector).toEqual(byClass);
    expect(byClass.length).toBe(golden.inline.narrow.touched - 1);
    expect(byClass.length).toBe(golden.inline.wide.touched - 1);
  });

  it('the writer writes the stage and then every reader, reads nothing more', () => {
    const log: string[] = [];
    const el = (n: string) => ({ style: { pointerEvents: '', setProperty: (p: string, v: string) => log.push(`${n} ${p} ${v}`) } });
    const d = createExitDriver({
      track: { getBoundingClientRect: () => ({ top: -400, height: 1600 }) },
      hero: el('stage'),
      reduced: () => false,
      readers: () => [el('a'), el('b')],
    });
    const w = d.read(800);
    expect(log).toEqual([]);
    w();
    expect(log).toEqual([
      'stage --exit-opacity 0.5',
      'a --exit-opacity 0.5',
      'a --exit-scatter calc(1 - 0.5)',
      'b --exit-opacity 0.5',
      'b --exit-scatter calc(1 - 0.5)',
    ]);
  });

  it('under reduced motion the readers get opacity 1 and scatter 0', () => {
    const log: string[] = [];
    const el = (n: string) => ({ style: { pointerEvents: '', setProperty: (p: string, v: string) => log.push(`${n} ${p} ${v}`) } });
    const d = createExitDriver({
      track: { getBoundingClientRect: () => ({ top: -400, height: 1600 }) },
      hero: el('stage'),
      reduced: () => true,
      readers: () => [el('a')],
    });
    d.read(800)();
    expect(log).toEqual(['stage --exit-opacity 1', 'a --exit-opacity 1', 'a --exit-scatter 0']);
  });
});
