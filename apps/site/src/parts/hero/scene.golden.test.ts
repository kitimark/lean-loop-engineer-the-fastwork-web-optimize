import { readFileSync } from 'node:fs';
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

goldenConformance('hero-scene-pause', {
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
