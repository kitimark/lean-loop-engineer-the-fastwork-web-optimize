import { describe, expect, it } from 'vitest';
import { resolve } from './resolve';
import type { PartDef, PresetDef } from './types';

const mk = (id: string, extra: Partial<PartDef> = {}): PartDef => ({
  id,
  slot: id.split('.')[0]!,
  anchors: [],
  experiment: true,
  impls: ['mui', 'plain'],
  muiStates: [],
  variants: { faithful: { kind: 'faithful' }, strip: { kind: 'optimized' }, frozen: { kind: 'ablation' } },
  requires: {},
  conflicts: {},
  ...extra,
});

const parts = [mk('hero.countdown'), mk('morph.countdown', { requires: { 'morph.countdown:strip': ['hero.countdown:strip'] } })];
const presets: Record<string, PresetDef> = {
  original: { name: 'original', fw: {} },
  stripped: { name: 'stripped', extends: 'original', fw: { 'hero.countdown': 'strip' } },
  loop1: { name: 'loop1', extends: 'loop2', fw: {} },
  loop2: { name: 'loop2', extends: 'loop1', fw: {} },
  bad: { name: 'bad', fw: { 'hero.countdown': 'nope' } },
};

const ok = (s: string) => {
  const r = resolve(s, parts, presets);
  if (!r.ok) throw new Error(r.errors.join('; '));
  return r;
};
const errs = (s: string) => {
  const r = resolve(s, parts, presets);
  if (r.ok) throw new Error('expected errors');
  return r.errors;
};

describe('resolve', () => {
  it('defaults every part to faithful / mui', () => {
    const r = ok('');
    expect(r.source).toBe('default');
    expect(r.config.variants).toEqual({ 'hero.countdown': 'faithful', 'morph.countdown': 'faithful' });
    expect(r.config.impl['hero.countdown']).toBe('mui');
  });

  it('?fw= swaps one part, others stay faithful', () => {
    const r = ok('?fw=hero.countdown:strip');
    expect(r.source).toBe('url-fw');
    expect(r.config.variants['hero.countdown']).toBe('strip');
    expect(r.config.variants['morph.countdown']).toBe('faithful');
  });

  it('accepts comma lists and repeated ?fw=', () => {
    const a = ok('?fw=hero.countdown:strip,morph.countdown:strip');
    const b = ok('?fw=hero.countdown:strip&fw=morph.countdown:strip');
    expect(a.configHash).toBe(b.configHash);
  });

  it('?preset= applies, extends chain included', () => {
    const r = ok('?preset=stripped');
    expect(r.source).toBe('url-preset');
    expect(r.config.variants['hero.countdown']).toBe('strip');
  });

  it('?fw= wins over ?preset=', () => {
    const r = ok('?preset=stripped&fw=hero.countdown:frozen');
    expect(r.config.variants['hero.countdown']).toBe('frozen');
  });

  it('impl axis via variant@impl', () => {
    const r = ok('?fw=hero.countdown:strip@plain');
    expect(r.config.impl['hero.countdown']).toBe('plain');
  });

  it('hash is order independent and changes with the config', () => {
    const a = ok('?fw=hero.countdown:strip,morph.countdown:strip').configHash;
    const b = ok('?fw=morph.countdown:strip,hero.countdown:strip').configHash;
    expect(a).toBe(b);
    expect(a).not.toBe(ok('').configHash);
    expect(a).toMatch(/^[0-9a-f]{16}$/);
  });

  it('?preset=original equals the default config hash', () => {
    expect(ok('?preset=original').configHash).toBe(ok('').configHash);
  });

  it('errors, never fallbacks', () => {
    expect(errs('?fw=nope:strip')[0]).toMatch(/unknown part/);
    expect(errs('?fw=hero.countdown:nope')[0]).toMatch(/no variant/);
    expect(errs('?fw=hero.countdown:strip@zzz')[0]).toMatch(/no impl/);
    expect(errs('?fw=garbage')[0]).toMatch(/cannot parse/);
    expect(errs('?preset=missing')[0]).toMatch(/unknown preset/);
    expect(errs('?preset=bad')[0]).toMatch(/no variant/);
    expect(errs('?preset=loop1').join()).toMatch(/cycle/);
    expect(errs('?preset=original&preset=stripped')[0]).toMatch(/only one/);
  });

  it('violated requires is an error; satisfied is fine', () => {
    expect(errs('?fw=morph.countdown:strip')[0]).toMatch(/requires hero.countdown:strip/);
    expect(() => ok('?fw=morph.countdown:strip,hero.countdown:strip')).not.toThrow();
  });

  it('conflicts are errors', () => {
    const p = [mk('a', { conflicts: { 'a:faithful': ['b:strip'] } }), mk('b')];
    const r = resolve('?fw=b:strip', p, presets);
    expect(r.ok).toBe(false);
    expect(resolve('?fw=a:strip,b:strip', p, presets).ok).toBe(true);
  });

  it('last request wins; default is the head variant', () => {
    expect(ok('?fw=hero.countdown:strip,hero.countdown:frozen').config.variants['hero.countdown']).toBe('frozen');
    const p = [mk('x', { variants: { zed: { kind: 'faithful' }, b: { kind: 'optimized' } } })];
    const r = resolve('', p, presets);
    expect(r.ok && r.config.variants.x).toBe('zed');
  });
});
