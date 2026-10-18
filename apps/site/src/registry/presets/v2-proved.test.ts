// The v2-proved arm inside the site. Its files equal the Lean generator byte for byte (lean/Fw/Preset/Gen.lean, decision
// Fw.Preset.preset): the "preset v2-proved check" job of lean/scripts/check.sh regenerates them from the findings ledger
// and the parts and fails on any difference. Here: every flag is a registered optimized variant, and ?preset=v2-proved
// resolves and renders.
import { createElement } from 'react';
import { renderToString } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { App } from '../../App';
import { parts, presets, resolveSearch } from '../index';

describe('v2-proved preset', () => {
  it('every flag is a registered optimized variant', () => {
    const p = presets['v2-proved']!;
    expect(p.extends).toBe('original');
    const fw = Object.entries(p.fw);
    expect(fw.length).toBeGreaterThan(0);
    for (const [part, v] of fw)
      expect(parts.find((x) => x.id === part)?.variants[v]?.kind, `${part}:${v}`).toBe('optimized');
  });

  it('?preset=v2-proved resolves to the member variants and renders', () => {
    const r = resolveSearch('?preset=v2-proved');
    if (!r.ok) throw new Error(r.errors.join('; '));
    expect(r.source).toBe('url-preset');
    for (const [p, v] of Object.entries(presets['v2-proved']!.fw)) expect(r.config.variants[p]).toBe(v);
    expect(r.configHash).not.toBe((resolveSearch('') as { configHash: string }).configHash);
    expect(renderToString(createElement(App, { config: r.config }))).toContain('data-fw');
  });
});
