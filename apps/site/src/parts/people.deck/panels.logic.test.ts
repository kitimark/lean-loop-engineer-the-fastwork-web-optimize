import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import { PROFILES } from '../people/data';
import { PANELS } from '../people/panels.data';
import * as L from './panels.logic';

goldenConformance('people.deck.panels', {
  tabOf: (i) => L.tabOf({ id: i.id as string }),
  filterIds: (i) => L.filterIds({ services: i.services as Array<{ id: string; reviewCount: number }> }),
  shown: (i) => L.shown({ filter: i.filter as string, reviews: i.reviews as string[] }),
  faces: (i) => L.faces({ avatars: i.avatars as string[] }),
  more: (i) => L.more({ total: i.total as number, avatars: i.avatars as string[] }),
  verdict: (i) => L.verdict({ score: i.score as number }),
  filled: (i) => L.filled({ score: i.score as number, i: i.i as number }),
  flip: (i) => L.flip({ b: i.b as boolean }),
  sections: (i) => L.sections({ education: i.education as number, certificates: i.certificates as number, languages: i.languages as number, awards: i.awards as number }),
  initials: (i) => L.initials({ name: i.name as string }),
});

describe('people.deck panels content', () => {
  it('every about name has the same monogram under the Lean ASCII spec and the unicode rule of the original', () => {
    const uni = (n: string) =>
      n
        .split(/\s+/)
        .filter((w) => /^[\p{L}\p{N}]/u.test(w))
        .slice(0, 2)
        .map((w) => w[0]!.toUpperCase())
        .join('');
    const names: string[] = [];
    for (const p of Object.values(PANELS)) {
      for (const e of p.about.experience) names.push(e.company);
      for (const e of p.about.education) names.push(e.school);
      for (const e of p.about.certificates) names.push(e.issuer);
    }
    for (const n of names) {
      expect(L.initials({ name: n }), n).toBe(uni(n));
    }
  });
  it('dates read like the original (English)', () => {
    expect(L.formatMonth('2024-03')).toBe('Mar 2024');
    expect(L.formatDay('2026-09-04')).toBe('Sep 4, 2026');
    expect(L.range('2024-01', null)).toBe('Jan 2024 – Present');
  });
  it('every review names a service of its profile and the data covers every profession', () => {
    for (const p of PROFILES) {
      const ids = new Set(p.services.map((s) => s.id));
      for (const r of PANELS[p.id]!.reviews.items) expect(ids.has(r.serviceId), `${p.id}/${r.id}`).toBe(true);
    }
  });
});
