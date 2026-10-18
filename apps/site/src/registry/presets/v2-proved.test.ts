// The v2-proved arm against its Lean generator (lean/Fw/Preset/Gen.lean, decision Fw.Preset.preset):
// the registered preset is the golden byte for byte, the ledger and registry inputs the golden recorded are the current
// ones (a ledger edit without regenerating fails here), and ?preset=v2-proved resolves and renders.
import { readFileSync } from 'node:fs';
import { createElement } from 'react';
import { renderToString } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { App } from '../../App';
import { parts, presets, resolveSearch } from '../index';

const repo = new URL('../../../../../', import.meta.url);
const text = (p: string) => readFileSync(new URL(p, repo), 'utf8');

interface Found {
  status: string;
  fResult: string | null;
}
interface Decision {
  flag: string;
  registered: boolean;
  member: boolean;
  rows: { part: string; candidate: string; found: Found[] }[];
  flagRows: Found[];
}
interface LedgerRow {
  part: string;
  candidate: string;
  status: string;
  flag?: string;
  fResult?: string | null;
}

const decisions = text('packages/contracts/golden/preset/v2-proved.decisions.jsonl')
  .split('\n')
  .filter((l) => l !== '')
  .map((l) => JSON.parse(l) as Decision);
const ledger = (JSON.parse(text('research/findings/ledger.json')) as { findings: LedgerRow[] }).findings;
const found = (r: LedgerRow): Found => ({ status: r.status, fResult: r.fResult ?? null });

describe('v2-proved preset', () => {
  it('the site preset is the Lean golden byte for byte', () => {
    expect(text('apps/site/src/registry/presets/v2-proved.json')).toBe(
      text('packages/contracts/golden/preset/v2-proved.json'),
    );
  });

  it('every ledger input the golden read is unchanged', () => {
    for (const d of decisions) {
      for (const k of d.rows)
        expect(ledger.filter((r) => r.part === k.part && r.candidate === k.candidate).map(found), d.flag).toEqual(k.found);
      expect(ledger.filter((r) => r.flag === d.flag).map(found), d.flag).toEqual(d.flagRows);
    }
    const decided = new Set(decisions.map((d) => d.flag));
    for (const r of ledger) if (r.flag !== undefined) expect(decided, r.flag).toContain(r.flag);
  });

  it('the registered optimized flags are exactly the decided registered ones', () => {
    const registered = parts.flatMap((p) =>
      Object.entries(p.variants)
        .filter(([, v]) => v.kind === 'optimized')
        .map(([v]) => `${p.id}:${v}`),
    );
    expect(decisions.filter((d) => d.registered).map((d) => d.flag).sort()).toEqual(registered.sort());
  });

  it('the preset holds exactly the member flags', () => {
    const fw = presets['v2-proved']!.fw;
    expect(Object.entries(fw).map(([p, v]) => `${p}:${v}`).sort()).toEqual(
      decisions.filter((d) => d.member).map((d) => d.flag).sort(),
    );
  });

  it('?preset=v2-proved resolves to the member variants and renders', () => {
    const r = resolveSearch('?preset=v2-proved');
    if (!r.ok) throw new Error(r.errors.join('; '));
    expect(r.source).toBe('url-preset');
    for (const [p, v] of Object.entries(presets['v2-proved']!.fw)) expect(r.config.variants[p]).toBe(v);
    expect(r.configHash).not.toBe((resolveSearch('') as { configHash: string }).configHash);
    expect(renderToString(createElement(App, { config: r.config }))).toContain('data-fw');
  });

  it('?fw=preset:v2-proved is not the preset syntax (PLAN 6.3 uses ?preset=)', () => {
    const r = resolveSearch('?fw=preset:v2-proved');
    expect(r.ok).toBe(false);
  });
});
