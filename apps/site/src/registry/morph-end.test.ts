import { describe, expect, it } from 'vitest';
import { cfgOf, CLAMP_ID, FLIP_ID, hooksOf, RELEASE_ID } from '../parts/morph.tween/end.hooks';
import { resolveSearch } from './index';

const ids = [CLAMP_ID, FLIP_ID, RELEASE_ID];
const picks = [0, 1, 2, 3, 4, 5, 6, 7].map((n) => ids.map((id, i) => `${id}:${n & (1 << i) ? 'on' : 'faithful'}`));

describe('morph.end bricks in the registry (Lean MorphEnd.all_combinations, bricks_no_rules)', () => {
  for (const p of picks) {
    it(`?fw=${p.join(',')} resolves and the driver reads the same picks`, () => {
      const r = resolveSearch(`?fw=${p.join(',')}`);
      if (!r.ok) throw new Error(r.errors.join('; '));
      const cfg = cfgOf(r.config.variants);
      expect([cfg.clamp, cfg.flip, cfg.release]).toEqual(p.map((x) => x.endsWith(':on')));
      expect(hooksOf(cfg).release).toBe(cfg.release);
    });
  }
  it('adds no refusal next to engine.scroll:unthrottle', () => {
    const r = resolveSearch('?fw=morph.end.clamp:on,morph.end.flip:on,morph.end.release:on,engine.scroll:unthrottle');
    expect(r.ok).toBe(true);
  });
  it('the preset morph-end-all (what the breakpoint gate prerenders) turns all three on', () => {
    const r = resolveSearch('?preset=morph-end-all');
    if (!r.ok) throw new Error(r.errors.join('; '));
    expect(cfgOf(r.config.variants)).toEqual({ clamp: true, flip: true, release: true });
  });
  it('an unlisted default is faithful', () => {
    const r = resolveSearch('');
    if (!r.ok) throw new Error(r.errors.join('; '));
    expect(ids.map((id) => r.config.variants[id])).toEqual(['faithful', 'faithful', 'faithful']);
  });
});
