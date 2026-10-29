import { readFileSync } from 'node:fs';
import { createElement } from 'react';
import { renderToString } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { App } from '../../App';
import { parts, presets, resolveSearch } from '../index';

const golden = (name: string) =>
  readFileSync(new URL(`../../../../../packages/contracts/golden/preset/${name}`, import.meta.url), 'utf8');

type Row = { flag: string; kind: string | null; visClass: string | null; member: boolean; route: string | null; blockers: string[]; userDecision: { decision: string; review: string } | null };
const rows: Row[] = golden('shipped.decisions.jsonl').trim().split('\n').map((l) => JSON.parse(l));

describe('shipped preset', () => {
  it('equals the Lean golden byte for byte', () => {
    expect(readFileSync(new URL('./shipped.json', import.meta.url), 'utf8')).toBe(golden('shipped.json'));
  });

  it('holds every v2-proved member with the same variant', () => {
    const s = presets['shipped']!;
    expect(s.extends).toBe('original');
    for (const [part, v] of Object.entries(presets['v2-proved']!.fw)) expect(s.fw[part], part).toBe(v);
  });

  it('every member outside v2-proved has an accepted, reviewed look decision and a shipping kind', () => {
    const v2 = presets['v2-proved']!.fw;
    for (const [part, v] of Object.entries(presets['shipped']!.fw)) {
      if (v2[part] === v) continue;
      const r = rows.find((x) => x.flag === `${part}:${v}`)!;
      expect(r.route).toBe('look-accepted');
      expect(r.userDecision).toMatchObject({ decision: 'accepted', review: 'done' });
      expect(['optimized', 'proposal']).toContain(parts.find((x) => x.id === part)?.variants[v]?.kind);
    }
  });

  it('the decision rows name exactly the members', () => {
    const fw = presets['shipped']!.fw;
    for (const r of rows) {
      const [part, v] = r.flag.split(':') as [string, string];
      expect(r.member, r.flag).toBe(fw[part] === v);
      if (r.member) expect(r.blockers, r.flag).toEqual([]);
    }
  });

  it('?preset=shipped resolves to the member variants and renders', () => {
    const r = resolveSearch('?preset=shipped');
    if (!r.ok) throw new Error(r.errors.join('; '));
    expect(r.source).toBe('url-preset');
    for (const [p, v] of Object.entries(presets['shipped']!.fw)) expect(r.config.variants[p]).toBe(v);
    expect(renderToString(createElement(App, { config: r.config }))).toContain('data-fw');
  });
});
