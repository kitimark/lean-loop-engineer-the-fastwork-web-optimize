import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { mediaCondition } from '../../breakpoints';
import { MEDIA_IDS } from './media';

const css = readFileSync(resolve(__dirname, 'card.module.css'), 'utf8');
const norm = (s: string) => s.trim().replace(/\s+/g, ' ');

describe('people.card media', () => {
  it('every CSS @media block is a generated condition', () => {
    const found = new Set([...css.matchAll(/@media\s+([^{]+)\{/g)].map((m) => norm(m[1]!)));
    const known = new Set(MEDIA_IDS.map((id) => mediaCondition(id)));
    for (const f of found) expect(known, f).toContain(f);
  });
});
