// @vitest-environment jsdom
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { act, createElement } from 'react';
import { createRoot } from 'react-dom/client';
import { renderToString } from 'react-dom/server';
import { afterEach, describe, expect, it } from 'vitest';
import { Hero } from '../parts/hero';
import { HeroCountdown } from '../parts/hero.countdown';
import { MorphPanel } from '../parts/morph.panel';
import { Nav } from '../parts/nav';
import type { PartDef } from './types';

(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

const partsDir = resolve(__dirname, '../parts');
const leanSrc = resolve(__dirname, '../../../../lean/Fw/Console/BuildsOpen.lean');

/** The seven parts whose boxes are declared (layer-decl); other parts declare none yet. */
const DECLARED = ['hero', 'hero.cue', 'hero.orbit', 'hero.deck', 'hero.countdown', 'nav', 'morph.panel'];

const load = (id: string) => JSON.parse(readFileSync(resolve(partsDir, id, 'part.json'), 'utf8')) as PartDef;
const parts = DECLARED.map(load);
const allLayers = parts.flatMap((p) => (p.layers ?? []).map((l) => ({ part: p, layer: l })));

/**
 * The console's search charset, read from the Lean definition `BuildsOpen.okChar` (the one source): alphanumerics
 * plus the characters of its `c == '…'` terms.
 */
function okChars(): (c: string) => boolean {
  const src = readFileSync(leanSrc, 'utf8');
  const def = /def okChar \(c : Char\) : Bool :=\n([^\n]*)/.exec(src)?.[1] ?? '';
  const punct = new Set([...def.matchAll(/c == '(.)'/g)].map((m) => m[1]!));
  expect(def).toContain('c.isAlphanum');
  expect(punct.size).toBeGreaterThanOrEqual(8);
  return (c) => /^[A-Za-z0-9]$/.test(c) || punct.has(c);
}

describe('part.json layers (schema)', () => {
  const ok = okChars();

  it('declares layers for exactly the named parts it owns', () => {
    for (const p of parts) expect(p.layers?.length, p.id).toBeGreaterThan(0);
  });

  it('every layer is {id, label, text} with a part_box id of okChar characters, unique in the part and the registry', () => {
    const seen = new Set<string>();
    for (const { part, layer } of allLayers) {
      expect(Object.keys(layer).sort(), layer.id).toEqual(['id', 'label', 'text']);
      expect(typeof layer.text, layer.id).toBe('boolean');
      expect(layer.label.trim(), layer.id).not.toBe('');
      expect([...layer.id].every(ok), layer.id).toBe(true);
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

describe('data-fw-layer in the rendered DOM', () => {
  const found: { id: string; text: string }[] = [];
  const collect = (root: ParentNode) =>
    root.querySelectorAll('[data-fw-layer]').forEach((el) => found.push({ id: el.getAttribute('data-fw-layer')!, text: el.textContent!.trim() }));
  const mounted: (() => void)[] = [];
  afterEach(() => mounted.splice(0).forEach((f) => f()));

  const ssr = (el: Parameters<typeof renderToString>[0]) => {
    const host = document.createElement('div');
    host.innerHTML = renderToString(el);
    collect(host);
  };
  const client = async (el: Parameters<typeof renderToString>[0]) => {
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
    collect(host);
    mounted.push(() => {
      act(() => root.unmount());
      host.remove();
    });
    return host;
  };

  it('each layer box in the DOM is declared, each declared layer is found, and a box holding text has the text flag', async () => {
    ssr(createElement(Hero, { variants: {} }));
    ssr(createElement(Nav, { variant: 'faithful' }, createElement(MorphPanel, { variant: 'faithful', impl: 'plain' })));
    ssr(createElement(MorphPanel, { variant: 'faithful', impl: 'mui' }));
    await client(createElement(HeroCountdown, { variant: 'faithful', impl: 'plain' }));
    await client(createElement(HeroCountdown, { variant: 'strip', impl: 'plain' }));

    const declared = new Map(allLayers.map((x) => [x.layer.id, x.layer]));
    for (const f of found) {
      const d = declared.get(f.id);
      expect(d, `undeclared data-fw-layer ${f.id}`).toBeDefined();
      if (f.text !== '') expect(d!.text, `${f.id} holds text`).toBe(true);
    }
    const ids = new Set(found.map((f) => f.id));
    for (const id of declared.keys()) expect(ids.has(id), `${id} is on no box`).toBe(true);
    for (const d of declared.values()) {
      if (d.text) expect(found.some((f) => f.id === d.id && f.text !== ''), `${d.id} flagged text but holds none`).toBe(true);
    }
  });

  it('a second countdown instance (morph.countdown) carries no layer attribute', async () => {
    const host = await client(createElement(HeroCountdown, { variant: 'faithful', impl: 'plain', fwId: 'morph-countdown' }));
    expect(host.querySelectorAll('[data-face]').length).toBeGreaterThan(0);
    expect(host.querySelectorAll('[data-fw-layer]').length).toBe(0);
  });
});
