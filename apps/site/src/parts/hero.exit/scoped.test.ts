import { readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { createElement } from 'react';
import { renderToString } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';
import { Hero } from '../hero';
import heroCss from '../hero/hero.module.css';
import cueCss from '../hero.cue/cue.module.css';
import deckCss from '../hero.deck/deck.module.css';
import cardCss from '../hero.orbit/card.module.css';
import orbitCss from '../hero.orbit/orbit.module.css';
import exitCss from './hero.module.css';
import part from './part.json';
import { SCOPE_ATTR, SCOPED, SCOPED_PROPS } from './scope';

interface TreeNode {
  name: string;
  extra: number;
  explicit: number;
  rest: number;
  chain: TreeNode[];
}
interface Golden {
  variant: string;
  scopeAttr: string;
  register: { name: string; syntax: string; inherits: boolean }[];
  readers: string[];
  inheritRules: string[];
  tree: TreeNode;
}

const root = resolve(__dirname, '../../../../..');
const golden = JSON.parse(readFileSync(resolve(root, 'packages/contracts/golden/parts/hero.exit.scoped.json'), 'utf8')) as Golden;
const partsDir = resolve(__dirname, '..');
const HERO_PARTS = ['hero', 'hero.accent', 'hero.countdown', 'hero.cue', 'hero.deck', 'hero.exit', 'hero.orbit'];
const EXIT_PROPS = ['--exit-opacity', '--exit-scatter'];
const INHERITED_PROPS = new Set(['color', 'font']);

const modules: Record<string, Record<string, string>> = {
  hero: heroCss,
  'hero.cue': cueCss,
  'hero.deck': deckCss,
  'hero.exit': exitCss,
  'hero.orbit': orbitCss,
};
const moduleClass = (p: string, c: string): string => (p === 'hero.orbit' && c === 'card' ? cardCss.card : modules[p][c]);

interface Rule {
  selectors: string[];
  decls: [string, string][];
}

function parseCss(src: string): Rule[] {
  const text = src.replace(/\/\*[\s\S]*?\*\//g, '');
  const rules: Rule[] = [];
  const stack: { prelude: string; body: string }[] = [];
  let buf = '';
  for (const ch of text) {
    if (ch === '{') {
      stack.push({ prelude: buf.trim(), body: '' });
      buf = '';
    } else if (ch === '}') {
      const top = stack.pop()!;
      top.body += buf;
      buf = '';
      if (!top.prelude.startsWith('@')) {
        const decls = top.body
          .split(';')
          .map((d) => d.trim())
          .filter((d) => d.includes(':'))
          .map((d) => [d.slice(0, d.indexOf(':')).trim(), d.slice(d.indexOf(':') + 1).trim()] as [string, string]);
        rules.push({ selectors: top.prelude.split(',').map((s) => s.trim().replace(/\s+/g, ' ')), decls });
      }
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
const partOf = (file: string): string => file.slice(partsDir.length + 1).split('/')[0];
const subjectClass = (selector: string): string | null => {
  const last = selector.split(/[\s>+~]+/).pop() ?? '';
  const m = /\.([A-Za-z][\w-]*)/.exec(last);
  return m ? m[1] : null;
};
const allRules = cssFiles(partsDir).map((f) => ({ part: partOf(f), rules: parseCss(readFileSync(f, 'utf8')) }));
const heroRules = allRules.filter((r) => HERO_PARTS.includes(r.part));
const readsExit = (v: string): boolean => EXIT_PROPS.some((p) => v.includes(`var(${p}`));
const isScopeRule = (r: Rule): boolean =>
  r.selectors.every((s) => s.startsWith(`[${SCOPE_ATTR}] `)) &&
  r.decls.length === EXIT_PROPS.length &&
  r.decls.every(([p, v]) => EXIT_PROPS.includes(p) && v === 'inherit');

describe('hero.exit:scoped constants against the Lean golden', () => {
  it('variant, attribute and registrations', () => {
    expect(golden.variant).toBe(SCOPED);
    expect(golden.scopeAttr).toBe(SCOPE_ATTR);
    expect(SCOPED_PROPS).toEqual(golden.register);
    expect((part.variants as Record<string, { kind: string }>)[SCOPED].kind).toBe('optimized');
  });
});

describe('readers and inherit rules from the CSS', () => {
  it('the classes whose rules read an exit property are the golden readers', () => {
    const readers = new Set<string>();
    for (const { part: p, rules } of allRules)
      for (const r of rules)
        if (r.decls.some(([prop, v]) => !prop.startsWith('--') && readsExit(v)))
          for (const s of r.selectors) readers.add(`${p}/${subjectClass(s)}`);
    expect([...readers].sort()).toEqual([...golden.readers].sort());
  });

  it('the scope rules declare inherit on exactly the golden chain classes', () => {
    const chain = new Set<string>();
    for (const { part: p, rules } of allRules)
      for (const r of rules) if (isScopeRule(r)) for (const s of r.selectors) chain.add(`${p}/${subjectClass(s)}`);
    expect([...chain].sort()).toEqual([...golden.inheritRules].sort());
  });

  it('no other rule names the scope attribute or declares an exit property outside hero.exit', () => {
    for (const { part: p, rules } of allRules)
      for (const r of rules) {
        if (isScopeRule(r)) continue;
        expect(r.selectors.some((s) => s.includes(SCOPE_ATTR))).toBe(false);
        if (p !== 'hero.exit') expect(r.decls.some(([prop]) => EXIT_PROPS.includes(prop))).toBe(false);
      }
  });

  it('every other inherit in the hero parts and the global styles is on an inherited property (explicit = 0)', () => {
    const global = cssFiles(resolve(__dirname, '../../styles')).map((f) => parseCss(readFileSync(f, 'utf8')));
    const rules = [...heroRules.flatMap((r) => r.rules), ...global.flat()].filter((r) => !isScopeRule(r));
    const inherits = rules.flatMap((r) => r.decls.filter(([, v]) => v === 'inherit').map(([p]) => p));
    expect(inherits.length).toBeGreaterThan(0);
    expect(inherits.filter((p) => !INHERITED_PROPS.has(p))).toEqual([]);
  });
});

interface El {
  attrs: string;
  kids: El[];
}

function parseHtml(html: string): El {
  const VOID = new Set(['area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'source', 'track', 'wbr']);
  const re = /<!--[\s\S]*?-->|<(\/?)([a-zA-Z][\w:-]*)([^>]*?)(\/?)>/g;
  const top: El & { tag: string } = { tag: '#root', attrs: '', kids: [] };
  const stack: (El & { tag: string })[] = [top];
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
    const el = { tag, attrs, kids: [] };
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
const size = (el: El): number => 1 + el.kids.reduce((a, k) => a + size(k), 0);
const find = (el: El, p: (e: El) => boolean): El | undefined =>
  p(el) ? el : el.kids.map((k) => find(k, p)).find(Boolean);
const nameIn = (list: string[], el: El): string | undefined =>
  list.find((n) => {
    const [p, c] = n.split('/');
    return classes(el).includes(moduleClass(p, c));
  });

function summary(el: El, name: string): TreeNode {
  const chain = el.kids.filter((k) => nameIn(golden.inheritRules, k));
  const other = el.kids.filter((k) => !nameIn(golden.inheritRules, k));
  return {
    name,
    extra: other.length,
    explicit: 0,
    rest: other.reduce((a, k) => a + size(k), 0),
    chain: chain.map((k) => summary(k, nameIn(golden.inheritRules, k)!)),
  };
}

const stageOf = (variants: Record<string, string>): El => {
  const dom = parseHtml(renderToString(createElement(Hero, { variants })));
  const stage = find(dom, (e) => classes(e).includes(exitCss.hero));
  expect(stage).toBeDefined();
  return stage!;
};

describe('the rendered hero stage against the golden tree', () => {
  it('scoped: the stage carries the scope attribute and summarises to the golden tree', () => {
    const stage = stageOf({ 'hero.exit': SCOPED });
    expect(stage.attrs).toContain(`${SCOPE_ATTR}=""`);
    expect(summary(stage, 'hero.exit/hero')).toEqual(golden.tree);
  });

  it('every element with a reader class sits on an all-chain path from the stage', () => {
    const stage = stageOf({ 'hero.exit': SCOPED });
    let seen = 0;
    const walk = (el: El, onChain: boolean): void => {
      for (const k of el.kids) {
        const chain = onChain && nameIn(golden.inheritRules, k) !== undefined;
        if (nameIn(golden.readers, k)) {
          seen += 1;
          expect(chain).toBe(true);
        }
        walk(k, chain);
      }
    };
    walk(stage, true);
    expect(seen).toBe(16);
  });

  it('faithful renders no scope attribute', () => {
    expect(stageOf({}).attrs).not.toContain(SCOPE_ATTR);
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
