import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import { SCENE_ATTR, bindScene, sceneOf } from './scene';

const css = readFileSync(resolve(__dirname, 'platform.module.css'), 'utf8');
const shared = readFileSync(resolve(__dirname, '../people/shared.ts'), 'utf8');
const index = readFileSync(resolve(__dirname, 'index.tsx'), 'utf8');

/** The capture of `re` in `text`, failing the test when absent. */
const capture = (re: RegExp, text: string): string => {
  const m = re.exec(text);
  expect(m, `${re} not found`).not.toBeNull();
  return m![1]!;
};

goldenConformance('platform.scene', {
  scene: (i) => sceneOf({ top: i.top as number, bottom: i.bottom as number, vh: i.vh as number }),
  const: () => ({
    attr: SCENE_ATTR,
    active: sceneOf({ top: 0, bottom: 1, vh: 1 }),
    paused: sceneOf({ top: 3, bottom: 4, vh: 1 }),
    rootMargin: capture(/export function watchActive[\s\S]*?rootMargin: '([^']+)'/, shared),
    playState: capture(/\.section\[data-fw-scene='paused'\] :where\(\*\) \{[^}]*animation-play-state: (\w+) !important/, css),
  }),
});

describe('platform section wiring (source level: the site tests have no DOM)', () => {
  it('the section root is the scene host, bound to watchActive, and its cleanup stops the scene', () => {
    expect(index).toMatch(/<section ref=\{section\}[^>]*data-fw="platform"/);
    expect(index).toMatch(/const sec = section\.current;/);
    expect(index).toMatch(/const stopScene = bindScene\(sec, watchActive, writer\);/);
    expect(index).toMatch(/return \(\) => \{[^}]*stopScene\(\);/);
  });
});

type Host = Element & { setAttribute(n: string, v: string): void; removeAttribute(n: string): void };

describe('platform scene attribute', () => {
  it('follows the observer and is removed on teardown', () => {
    const attrs = new Map<string, string>();
    const el = {
      setAttribute: (n: string, v: string) => void attrs.set(n, v),
      removeAttribute: (n: string) => void attrs.delete(n),
    } as unknown as Host;
    let push: (a: boolean) => void = () => undefined;
    let stopped = false;
    const off = bindScene(el, (_e, cb) => {
      push = cb;
      cb(false);
      return () => {
        stopped = true;
      };
    });
    expect(attrs.get(SCENE_ATTR)).toBe('paused');
    push(true);
    expect(attrs.get(SCENE_ATTR)).toBe('active');
    push(false);
    expect(attrs.get(SCENE_ATTR)).toBe('paused');
    off();
    expect(stopped).toBe(true);
    expect(attrs.has(SCENE_ATTR)).toBe(false);
  });
});

describe('platform paused rule', () => {
  it('restates the original rule: will-change auto and animation-play-state paused on the section and descendants', () => {
    expect(css).toMatch(
      /\.section\[data-fw-scene='paused'\],\s*\.section\[data-fw-scene='paused'\] :where\(\*\) \{\s*will-change: auto !important;\s*animation-play-state: paused !important;\s*\}/,
    );
  });
});
