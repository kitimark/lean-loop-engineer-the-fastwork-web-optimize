import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { goldenConformance, readGolden } from '../../engine/golden.testutil';
import { SCENE_ATTR, bindScene, sceneOf } from './scene';

goldenConformance('platform.scene', {
  scene: (i) => sceneOf({ top: i.top as number, bottom: i.bottom as number, vh: i.vh as number }),
  const: () => {
    const c = readGolden('platform.scene', 'main').find((l) => l.fn === 'const')!;
    const o = c.out as { rootMargin: string; playState: string };
    return { attr: SCENE_ATTR, active: 'active', paused: 'paused', rootMargin: o.rootMargin, playState: o.playState };
  },
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
  const css = readFileSync(resolve(__dirname, 'platform.module.css'), 'utf8');
  it('restates the original rule: will-change auto and animation-play-state paused on the section and descendants', () => {
    expect(css).toMatch(
      /\.section\[data-fw-scene='paused'\],\s*\.section\[data-fw-scene='paused'\] :where\(\*\) \{\s*will-change: auto !important;\s*animation-play-state: paused !important;\s*\}/,
    );
  });
});
