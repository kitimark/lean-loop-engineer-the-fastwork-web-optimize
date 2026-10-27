import { readFileSync } from 'node:fs';
import { createElement } from 'react';
import { renderToString } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { App } from '../App';
import { MorphColumns } from '../parts/morph.columns';
import { parts, presets, resolveSearch } from './index';
import { resolve } from './resolve';

const golden = readFileSync(new URL('../../../../packages/contracts/golden/preset/probes.jsonl', import.meta.url), 'utf8')
  .trim()
  .split('\n')
  .map((l) => JSON.parse(l) as { flag: string; kind: string; member: boolean; lookCandidate: boolean });

const registered = parts
  .flatMap((p) => Object.entries(p.variants).map(([v, d]) => ({ key: `${p.id}:${v}`, kind: d.kind })))
  .filter((x) => x.kind === 'probe')
  .map((x) => x.key)
  .sort();

describe('probe class', () => {
  it('the golden lists exactly the registered probes, none a member or a look candidate', () => {
    expect(golden.map((g) => g.flag)).toEqual(registered);
    expect(registered).toEqual([
      'morph.columns:probe-off',
      'platform.entries:probe-off',
      'platform.glint:probe-off',
      'platform.marquee:probe-off',
      'platform.sweep:probe-off',
    ]);
    for (const g of golden) expect(g, g.flag).toMatchObject({ kind: 'probe', member: false, lookCandidate: false });
  });

  it('no shipped preset names a probe', () => {
    for (const p of Object.values(presets))
      for (const [id, v] of Object.entries(p.fw)) expect(registered, `${p.name}: ${id}:${v}`).not.toContain(`${id}:${v}`);
  });

  it('a probe resolves from ?fw= (a lane may measure it)', () => {
    for (const k of registered) expect(resolveSearch(`?fw=${k}`).ok, k).toBe(true);
  });

  it('a preset that names a probe is refused', () => {
    const bad = { ...presets, bad: { name: 'bad', fw: { 'platform.sweep': 'probe-off' } } };
    const r = resolve('?preset=bad', parts, bad);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.errors.join(';')).toContain('probe');
  });

  it('each probe changes the rendered section and leaves the other parts as they are', () => {
    const html = (search: string) => {
      const r = resolveSearch(search);
      if (!r.ok) throw new Error(r.errors.join('; '));
      return renderToString(createElement(App, { config: r.config }));
    };
    const base = html('');
    expect(html('?fw=platform.marquee:probe-off')).toContain('data-marquee="off"');
    expect(base).toContain('data-marquee="faithful"');
    const count = (h: string, s: string) => h.split(s).length - 1;
    const sw = html('?fw=platform.sweep:probe-off');
    expect(sw).not.toBe(base);
    expect(sw).toMatch(/_still_/);
    expect(base).not.toMatch(/_still_/);
    expect(count(sw, 'data-fw-sweep')).toBe(count(base, 'data-fw-sweep'));
    const cols = (v: string) => renderToString(createElement(MorphColumns, { variant: v }));
    expect(cols('probe-off')).toContain('data-fw-variant="probe-off"');
    expect(count(cols('probe-off'), '<img')).toBe(count(cols('faithful'), '<img'));
    expect(readFileSync(new URL('../parts/morph.columns/morph.module.css', import.meta.url), 'utf8')).toMatch(
      /data-fw-variant='probe-off'\] img \{\s*visibility: hidden;\s*\}/,
    );
    expect(html('?fw=platform.glint:probe-off')).toBeTypeOf('string');
    expect(html('?fw=platform.entries:probe-off')).toBeTypeOf('string');
  });

  it('a probe is a different config from the faithful page', () => {
    const a = resolveSearch('?fw=platform.sweep:probe-off');
    const b = resolveSearch('');
    if (!a.ok || !b.ok) throw new Error('resolve');
    expect(a.configHash).not.toBe(b.configHash);
  });
});
