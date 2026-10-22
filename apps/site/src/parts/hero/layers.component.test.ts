// @vitest-environment jsdom
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { act, createElement, type ReactElement } from 'react';
import { createRoot } from 'react-dom/client';
import { renderToString } from 'react-dom/server';
import { afterEach, describe, expect, it } from 'vitest';
import { Hero } from './index';
import { HeroCountdown } from '../hero.countdown';
import { MorphPanel } from '../morph.panel';
import { Nav } from '../nav';
import type { Impl, PartDef } from '../../registry/types';

(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

const partsDir = resolve(__dirname, '..');

const DECLARED = ['hero', 'hero.cue', 'hero.orbit', 'hero.deck', 'hero.countdown', 'nav', 'morph.panel'];

const load = (id: string) => JSON.parse(readFileSync(resolve(partsDir, id, 'part.json'), 'utf8')) as PartDef;
const parts = DECLARED.map(load);
const allLayers = parts.flatMap((p) => (p.layers ?? []).map((l) => ({ part: p, layer: l })));

describe('part.json layers (schema)', () => {
  it('declares layers for exactly the named parts it owns', () => {
    for (const p of parts) expect(p.layers?.length, p.id).toBeGreaterThan(0);
  });

  it('every layer is {id, label, text} with a part_box id, unique in the part and the registry', () => {
    const seen = new Set<string>();
    for (const { part, layer } of allLayers) {
      expect(Object.keys(layer).sort(), layer.id).toEqual(['id', 'label', 'text']);
      expect(typeof layer.text, layer.id).toBe('boolean');
      expect(layer.label.trim(), layer.id).not.toBe('');
      const cut = layer.id.indexOf('_');
      expect(layer.id.slice(0, cut), layer.id).toBe(part.id);
      expect(layer.id.slice(cut + 1), layer.id).not.toBe('');
      expect(seen.has(layer.id), `duplicate ${layer.id}`).toBe(false);
      seen.add(layer.id);
    }
  });

  it('every variant lists existing source files, and every source file of the part is listed by some variant', () => {
    for (const p of parts) {
      const onDisk = readdirSync(resolve(partsDir, p.id)).filter((f) => /\.(tsx?|css)$/.test(f) && !/\.test\.tsx?$/.test(f));
      const listed = new Set<string>();
      for (const [name, v] of Object.entries(p.variants)) {
        expect(v.files, `${p.id}:${name}`).toBeDefined();
        expect(new Set(v.files).size, `${p.id}:${name}`).toBe(v.files!.length);
        for (const f of v.files!) {
          expect(onDisk, `${p.id}:${name} lists ${f}`).toContain(f);
          listed.add(f);
        }
      }
      expect([...listed].sort(), p.id).toEqual([...onDisk].sort());
    }
  });
});

/** How a declared part renders one of its variants with one impl; `client` parts mount, the others render on the server. */
const RENDER: Record<string, { client: boolean; el: (variant: string, impl: Impl) => ReactElement }> = {
  hero: { client: false, el: (v) => createElement(Hero, { variants: { hero: v } }) },
  'hero.cue': { client: false, el: (v) => createElement(Hero, { variants: { 'hero.cue': v } }) },
  'hero.orbit': { client: false, el: (v) => createElement(Hero, { variants: { 'hero.orbit': v } }) },
  'hero.deck': { client: false, el: (v) => createElement(Hero, { variants: { 'hero.deck': v } }) },
  'hero.countdown': { client: true, el: (v, impl) => createElement(HeroCountdown, { variant: v, impl }) },
  nav: { client: false, el: (v, impl) => createElement(Nav, { variant: v, impl }) },
  'morph.panel': { client: false, el: (v, impl) => createElement(MorphPanel, { variant: v, impl }) },
};

describe('data-fw-layer in the rendered DOM', () => {
  const mounted: (() => void)[] = [];
  afterEach(() => mounted.splice(0).forEach((f) => f()));

  const boxes = (root: ParentNode) =>
    [...root.querySelectorAll('[data-fw-layer]')].map((el) => ({ id: el.getAttribute('data-fw-layer')!, text: el.textContent!.trim() }));
  const ssr = (el: ReactElement) => {
    const host = document.createElement('div');
    host.innerHTML = renderToString(el);
    return host;
  };
  const client = async (el: ReactElement) => {
    (globalThis as { ResizeObserver?: unknown }).ResizeObserver = class {
      observe() {}
      disconnect() {}
      unobserve() {}
    };
    const host = document.createElement('div');
    document.body.appendChild(host);
    const root = createRoot(host);
    await act(async () => root.render(el));
    await act(async () => {
      await Promise.resolve();
    });
    mounted.push(() => {
      act(() => root.unmount());
      host.remove();
    });
    return host;
  };

  it('has a renderer for every declared part', () => {
    expect(Object.keys(RENDER).sort()).toEqual([...DECLARED].sort());
  });

  it('every listed variant with every impl renders only declared boxes; over all of them each declared layer is found, and text boxes have the text flag', async () => {
    const declared = new Map(allLayers.map((x) => [x.layer.id, x.layer]));
    const found: { id: string; text: string }[] = [];
    for (const p of parts) {
      const r = RENDER[p.id]!;
      for (const variant of Object.keys(p.variants)) {
        for (const impl of p.impls) {
          const host = r.client ? await client(r.el(variant, impl)) : ssr(r.el(variant, impl));
          const own = boxes(host);
          const at = `${p.id}:${variant}@${impl}`;
          for (const b of own) expect(declared.has(b.id), `${at}: undeclared data-fw-layer ${b.id}`).toBe(true);
          expect(own.some((b) => b.id.startsWith(`${p.id}_`)), `${at} renders no box of its part`).toBe(true);
          found.push(...own);
        }
      }
    }
    for (const f of found) if (f.text !== '') expect(declared.get(f.id)!.text, `${f.id} holds text`).toBe(true);
    const ids = new Set(found.map((f) => f.id));
    for (const id of declared.keys()) expect(ids.has(id), `${id} is on no box`).toBe(true);
    for (const d of declared.values()) {
      if (d.text) expect(found.some((f) => f.id === d.id && f.text !== ''), `${d.id} flagged text but holds none`).toBe(true);
    }
  });

  it('the morph.countdown instance (inverse, fwId morph-countdown-clock) carries no layer attribute in any variant or impl', async () => {
    const p = load('hero.countdown');
    for (const variant of Object.keys(p.variants)) {
      for (const impl of p.impls) {
        const host = await client(createElement(HeroCountdown, { variant, impl, inverse: true, fwId: 'morph-countdown-clock' }));
        const at = `hero.countdown:${variant}@${impl} in morph.countdown`;
        expect(host.querySelectorAll('[data-face]').length, `${at} renders no face`).toBeGreaterThan(0);
        expect(host.querySelectorAll('[data-fw-layer]').length, `${at} carries a layer attribute`).toBe(0);
      }
    }
  });
});
