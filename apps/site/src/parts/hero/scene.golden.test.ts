import { readdirSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import { HERO_SCENE_ATTR, bindHeroScene, heroSceneOf } from './scene';

const css = readFileSync(resolve(__dirname, 'hero.module.css'), 'utf8');
const shared = readFileSync(resolve(__dirname, '../people/shared.ts'), 'utf8');
const index = readFileSync(resolve(__dirname, 'index.tsx'), 'utf8');
const part = JSON.parse(readFileSync(resolve(__dirname, 'part.json'), 'utf8')) as { variants: Record<string, { kind: string }> };

const capture = (re: RegExp, text: string): string => {
  const m = re.exec(text);
  expect(m, `${re} not found`).not.toBeNull();
  return m![1]!;
};

const rule = /:global\(\[data-fw-hero-scene='paused'\]\),\s*:global\(\[data-fw-hero-scene='paused'\]\) :where\(\*\) \{([^}]*)\}/;

const partsDir = resolve(__dirname, '..');
const norm = (s: string): string => s.replace(/\s+/g, ' ').trim();

const splitTop = (s: string): string[] => {
  const out: string[] = [];
  let depth = 0;
  let cur = '';
  for (const c of s) {
    if (c === '(') depth++;
    if (c === ')') depth--;
    if (c === ',' && depth === 0) {
      out.push(cur);
      cur = '';
    } else cur += c;
  }
  out.push(cur);
  return out.map(norm).filter(Boolean);
};

interface CssRule {
  sels: string[];
  body: string;
  media: string[];
}

/** Innermost style rules outside `@keyframes`, each with its enclosing `@media` preludes. */
const cssRules = (css: string): CssRule[] => {
  const text = css.replace(/\/\*[\s\S]*?\*\//g, '');
  const rules: CssRule[] = [];
  const stack: { prelude: string; body: string; inner: boolean }[] = [];
  let buf = '';
  for (const c of text) {
    if (c === '{') {
      stack.push({ prelude: norm(buf), body: '', inner: false });
      buf = '';
    } else if (c === '}') {
      const b = stack.pop()!;
      if (stack.length) stack[stack.length - 1]!.inner = true;
      if (!b.inner && !stack.some((s) => s.prelude.startsWith('@keyframes')))
        rules.push({ sels: splitTop(b.prelude), body: buf, media: stack.map((s) => s.prelude).filter((p) => p.startsWith('@media')) });
      buf = '';
    } else buf += c;
  }
  return rules;
};

const decls = (body: string, prop: string): string[] =>
  [...body.matchAll(new RegExp(`(?:^|;)\\s*${prop}\\s*:([^;]*)`, 'g'))].map((m) => norm(m[1]!));

const cardSel = /(\.card|\[data-orbit-id\]|> article)$/;

/** A keyframes rule as the CSS writes it: the selectors naming it, each with its splash-end `animation: none` rule. */
const animOf = (file: string, name: string) => {
  const rules = cssRules(readFileSync(resolve(partsDir, file), 'utf8'));
  const word = new RegExp(`\\b${name}\\b`);
  const offOf = (sel: string, media: string[]): string | null =>
    rules
      .filter((r) => decls(r.body, 'animation').includes('none') && r.media.every((m) => media.includes(m)))
      .flatMap((r) => r.sels)
      .find((s) => s === `[data-splash='done'] ${sel}` || s === `[data-orbit][data-done] ${sel}`) ?? null;
  const uses: { sel: string; off: string | null }[] = [];
  for (const r of rules.filter((x) => [...decls(x.body, 'animation'), ...decls(x.body, 'animation-name')].some((v) => word.test(v))))
    for (const sel of r.sels) {
      const off = offOf(sel, r.media);
      if (!uses.some((u) => u.sel === sel && u.off === off)) uses.push({ sel, off });
    }
  const cards = uses.filter((u) => cardSel.test(u.sel)).length;
  const fam = cards === uses.length ? 'card' : cards === 0 ? 'copy' : 'mixed';
  return { fam, uses, afterSplash: uses.some((u) => u.off === null) };
};

const heroCss = readdirSync(partsDir)
  .filter((d) => d === 'hero' || d.startsWith('hero.'))
  .flatMap((d) => readdirSync(resolve(partsDir, d)).filter((f) => f.endsWith('.css')).map((f) => `${d}/${f}`));

goldenConformance('hero-scene-pause', {
  anim: (i) => animOf(i.file as string, i.name as string),
  scene: (i) => heroSceneOf({ top: i.top as number, bottom: i.bottom as number, vh: i.vh as number }),
  const: () => ({
    attr: HERO_SCENE_ATTR,
    active: heroSceneOf({ top: 0, bottom: 1, vh: 1 }),
    paused: heroSceneOf({ top: 3, bottom: 4, vh: 1 }),
    rootMargin: capture(/export function watchActive[\s\S]*?rootMargin: '([^']+)'/, shared),
    playState: capture(/animation-play-state: (\w+) !important/, capture(rule, css)),
    willChange: capture(/will-change: (\w+) !important/, capture(rule, css)),
  }),
});

describe('hero animations (Lean HeroScenePause.heroAnims)', () => {
  it('the golden names every @keyframes rule of the hero subtree CSS, and only those', () => {
    const golden = readFileSync(resolve(__dirname, '../../../../../packages/contracts/golden/parts/hero-scene-pause.jsonl'), 'utf8')
      .split('\n')
      .filter(Boolean)
      .map((l) => JSON.parse(l) as { fn: string; in: { file?: string; name?: string } })
      .filter((l) => l.fn === 'anim')
      .map((l) => `${l.in.file} ${l.in.name}`)
      .sort();
    const css = heroCss
      .flatMap((f) => [...readFileSync(resolve(partsDir, f), 'utf8').matchAll(/@keyframes\s+([\w-]+)/g)].map((m) => `${f} ${m[1]}`))
      .sort();
    expect(golden).toEqual(css);
  });
});

describe('hero scene-pause wiring (source level: the site tests have no DOM)', () => {
  it('the variant is registered and binds the hero-exit track to watchActive', () => {
    expect(part.variants['scene-pause']?.kind).toBe('optimized');
    expect(index).toMatch(/copy\.current\?\.closest\('\[data-fw="hero-exit"\]'\)/);
    expect(index).toMatch(/if \(variant !== SCENE_PAUSE \|\| !track\) return undefined;\s*return bindHeroScene\(track, watchActive\);/);
    expect(index).toMatch(/<header ref=\{copy\}[^>]*data-fw="hero"/);
  });
});

type Host = Element & { setAttribute(n: string, v: string): void; removeAttribute(n: string): void };

describe('hero scene attribute', () => {
  it('follows the observer and is removed on teardown', () => {
    const attrs = new Map<string, string>();
    const el = {
      setAttribute: (n: string, v: string) => void attrs.set(n, v),
      removeAttribute: (n: string) => void attrs.delete(n),
    } as unknown as Host;
    let push: (a: boolean) => void = () => undefined;
    let stopped = false;
    const off = bindHeroScene(el, (_e, cb) => {
      push = cb;
      cb(true);
      return () => {
        stopped = true;
      };
    });
    expect(attrs.get(HERO_SCENE_ATTR)).toBe('active');
    push(false);
    expect(attrs.get(HERO_SCENE_ATTR)).toBe('paused');
    push(true);
    expect(attrs.get(HERO_SCENE_ATTR)).toBe('active');
    off();
    expect(stopped).toBe(true);
    expect(attrs.has(HERO_SCENE_ATTR)).toBe(false);
  });
});
