import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { parts, presets, resolveSearch } from './index';
import { installLayerStyle, layerStyle } from './layer-opts';
import { layerOptsTable } from './layer-opts.gen';
import { resolve } from './resolve';
import type { LayerOptEntry, PartDef } from './types';

const files = {
  'layer-opts': new URL('../../../../packages/contracts/golden/console/layer-opts.jsonl', import.meta.url),
  'layers-search': new URL('../../../../packages/contracts/golden/console/layers-search.jsonl', import.meta.url),
};
const rows = (name: keyof typeof files) =>
  readFileSync(fileURLToPath(files[name]), 'utf8')
    .split('\n')
    .filter((l) => l !== '')
    .map((l) => JSON.parse(l) as Record<string, any>);

describe('layer-opts golden (Fw.Site.LayerOpts)', () => {
  const golden = rows('layer-opts');

  it('replays every row: the entries give the Lean style text', () => {
    expect(golden.length).toBeGreaterThan(30);
    for (const g of golden) {
      const entries = (g.entries as { layer: string; opts: string }[]).map((e) => ({ layer: e.layer, opts: e.opts }));
      expect(layerStyle(entries), g.name).toBe(g.style);
    }
  });

  it('the table has every layer the registry declares, with c, cs and s', () => {
    const declared = parts.flatMap((p) => (p.layers ?? []).map((l) => l.id));
    expect(Object.keys(layerOptsTable).sort()).toEqual(declared.slice().sort());
    for (const id of declared) expect(Object.keys(layerOptsTable[id]!).sort()).toEqual(['c', 'cs', 's']);
  });

  it('snap adds no rule today: the s text is empty for every layer', () => {
    for (const id of Object.keys(layerOptsTable)) expect(layerOptsTable[id]!.s).toBe('');
  });
});

describe('?fwl= against the console search golden (Fw.Console.BuildsOpen)', () => {
  for (const g of rows('layers-search')) {
    it(g.name as string, () => {
      const reg = g.request.registry as { parts: { id: string; variants: string[]; impls: string[]; layers?: string[] }[] };
      const defs: PartDef[] = reg.parts.map((p) => ({
        id: p.id,
        slot: p.id.split('.')[0]!,
        anchors: [],
        experiment: true,
        impls: p.impls as PartDef['impls'],
        muiStates: [],
        variants: Object.fromEntries(p.variants.map((v, i) => [v, { kind: i === 0 ? 'faithful' : 'optimized' }])) as PartDef['variants'],
        layers: (p.layers ?? []).map((id) => ({ id, label: id, text: true })),
        requires: {},
        conflicts: {},
      }));
      const r = resolve(g.request.search as string, defs, {});
      const want = g.response as { ok: boolean; canonical: string | null; reasons: string[] };
      const fwlReasons = want.reasons.filter((x) => x.startsWith('?fwl='));
      if (want.ok) {
        expect(r.ok).toBe(true);
        const canon = new URLSearchParams(want.canonical!).get('fwl') ?? '';
        const got = r.ok ? r.layerOpts.map((e) => `${e.layer}:${e.opts}`) : [];
        expect(got).toEqual(canon.split(',').filter((x) => x !== ''));
      } else {
        expect(r.ok).toBe(false);
        if (fwlReasons.length > 0 || want.reasons.some((x) => x.startsWith('search '))) expect(r.ok ? [] : r.errors).toEqual(want.reasons);
      }
    });
  }
});

describe('?fwl= without and with the option', () => {
  it('no fwl: no entries, no style, the same result as before', () => {
    const r = resolveSearch('?fw=hero:scene-pause');
    expect(r.ok && r.layerOpts).toEqual([]);
    expect(layerStyle([])).toBe('');
  });

  it('fwl does not change the config or its hash (the markup is the same)', () => {
    const a = resolveSearch('?fw=hero:scene-pause');
    const b = resolveSearch('?fw=hero:scene-pause&fwl=hero_copy:c');
    expect(a.ok && b.ok).toBe(true);
    if (a.ok && b.ok) {
      expect(b.configHash).toBe(a.configHash);
      expect(b.source).toBe(a.source);
      expect(b.layerOpts).toEqual([{ layer: 'hero_copy', opts: 'c' }]);
    }
  });

  it('refuses a layer twice, an unknown layer and a bad option string', () => {
    for (const s of ['?fwl=hero_copy:c,hero_copy:s', '?fwl=nope:c', '?fwl=hero_copy:x', '?fwl=hero_copy'])
      expect(resolveSearch(s).ok, s).toBe(false);
  });

  it('presets resolve as before', () => {
    expect(Object.keys(presets).length).toBeGreaterThan(0);
    for (const name of Object.keys(presets)) expect(resolveSearch(`?preset=${name}`).ok, name).toBe(true);
  });
});

describe('installLayerStyle', () => {
  const fakeDoc = () => {
    const appended: { id: string; textContent: string }[] = [];
    const doc = {
      createElement: () => ({ id: '', textContent: '' }),
      head: { appendChild: (el: { id: string; textContent: string }) => void appended.push(el) },
    };
    return { doc: doc as unknown as Document, appended };
  };

  it('adds nothing for no entries or a snap-only entry', () => {
    for (const es of [[], [{ layer: 'hero_copy', opts: 's' }]] as LayerOptEntry[][]) {
      const { doc, appended } = fakeDoc();
      expect(installLayerStyle(doc, es)).toBeNull();
      expect(appended).toHaveLength(0);
    }
  });

  it('adds one style element holding the Lean text', () => {
    const { doc, appended } = fakeDoc();
    const es: LayerOptEntry[] = [{ layer: 'hero_copy', opts: 'c' }, { layer: 'hero.cue_cue', opts: 'cs' }];
    installLayerStyle(doc, es);
    expect(appended).toHaveLength(1);
    expect(appended[0]!.id).toBe('fw-layer-opts');
    expect(appended[0]!.textContent).toBe(layerStyle(es));
    expect(appended[0]!.textContent).toContain('[data-fw-layer="hero_copy"] { will-change: opacity, filter, transform }');
  });
});
