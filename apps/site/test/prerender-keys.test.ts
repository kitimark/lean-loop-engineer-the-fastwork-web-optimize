// The canonical flag-set key (lean/Fw/Wire/FlagKey.lean): the golden of keys is replayed, the prerender stores every
// enumerated page under its key, and every order of the same flag set finds that page.
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { canonSearch, keyOf } from '../../../packages/contracts/src/flag-key.mjs';
import { enumerateSearches } from '../src/entry-server';
import { parts, resolveSearch } from '../src/registry';

const golden = readFileSync(new URL('../../../packages/contracts/golden/wire/flag-key.jsonl', import.meta.url), 'utf8')
  .trim()
  .split('\n')
  .map((l) => JSON.parse(l) as { in: string[]; key: string | null });

function perms<T>(xs: T[]): T[][] {
  if (xs.length <= 1) return [xs];
  return xs.flatMap((x, i) => perms([...xs.slice(0, i), ...xs.slice(i + 1)]).map((r) => [x, ...r]));
}

describe('golden flag-key.jsonl', () => {
  it('has rows', () => expect(golden.length).toBeGreaterThan(5));
  it.each(golden.map((r, i) => [i, r] as const))('row %i', (_i, r) => {
    expect(keyOf(r.in)).toBe(r.key);
  });
});

describe('prerender keys', () => {
  const searches = enumerateSearches(['presets', 'single']);
  const flagged = searches.filter((s) => s.startsWith('?fw='));

  it('every enumerated search is already canonical', () => {
    for (const s of searches) expect(canonSearch(s)).toBe(s);
  });

  it('a variant with requires is enumerated with them, and some variant has a chain', () => {
    const chained = parts.flatMap((p) => Object.entries(p.requires).filter(([, rs]) => rs.length > 0));
    expect(chained.length).toBeGreaterThan(0);
  });

  it('every order of every enumerated flag set canonicalizes to the enumerated search and resolves to its page', () => {
    for (const s of flagged) {
      const list = s.slice('?fw='.length).split(',');
      const want = resolveSearch(s);
      expect(want.ok, s).toBe(true);
      for (const p of perms(list)) {
        const typed = `?fw=${p.join(',')}`;
        expect(canonSearch(typed), typed).toBe(s);
        const got = resolveSearch(typed);
        expect(got.ok && want.ok && got.configHash === want.configHash, typed).toBe(true);
      }
    }
  });
});

describe('canonSearch', () => {
  it('reorders fw, keeps the other params in place', () => {
    expect(canonSearch('?fw=morph.countdown:strip,hero.countdown:strip')).toBe('?fw=hero.countdown:strip,morph.countdown:strip');
    expect(canonSearch('?x=1&fw=b:y&fw=a:x&y=2')).toBe('?x=1&fw=a:x,b:y&y=2');
    expect(canonSearch('?fw=b%3Ay,a%3Ax')).toBe('?fw=a:x,b:y');
  });
  it('leaves other searches unchanged', () => {
    for (const s of ['', '?preset=original', '?fw=nocolon', '?fw=', '?fw=a:b:c'])
      expect(canonSearch(s)).toBe(s);
  });
});
