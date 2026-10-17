import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { mediaCondition } from '../../breakpoints';
import { MEDIA_IDS } from './media';

describe('hero media', () => {
  it('the CSS @media blocks are byte-equal to the generated conditions', () => {
    const css = readFileSync(resolve(__dirname, 'hero.module.css'), 'utf8');
    const found = [...css.matchAll(/@media\s+([^{]+)\{/g)].map((m) => m[1]!.trim().replace(/\s+/g, ' '));
    expect([...found].sort()).toEqual(MEDIA_IDS.map((id) => mediaCondition(id)).sort());
  });
});
