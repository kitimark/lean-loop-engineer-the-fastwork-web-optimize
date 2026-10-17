import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { mediaCondition } from '../../breakpoints';
import { MEDIA_IDS } from './media';

const norm = (s: string) => s.trim().replace(/\s+/g, ' ');
const blocks = (file: string) =>
  [...readFileSync(resolve(__dirname, file), 'utf8').matchAll(/@media\s+([^{]+)\{/g)].map((m) => norm(m[1]!));

describe('hero.orbit media', () => {
  it('the @media blocks of orbit.module.css and card.module.css are byte-equal to the generated conditions', () => {
    const found = [...blocks('orbit.module.css'), ...blocks('card.module.css')];
    expect([...new Set(found)].sort()).toEqual(MEDIA_IDS.map((id) => mediaCondition(id)).sort());
  });
});
