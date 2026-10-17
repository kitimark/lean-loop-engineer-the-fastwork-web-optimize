import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { mediaCondition } from '../../breakpoints';
import { CSS_IDS } from './media';

const css = readFileSync(resolve(__dirname, 'nav.module.css'), 'utf8');
const norm = (s: string) => s.trim().replace(/\s+/g, ' ');

describe('nav media', () => {
  it('the CSS @media blocks are byte-equal to the generated conditions', () => {
    const found = [...css.matchAll(/@media\s+([^{]+)\{/g)].map((m) => norm(m[1]!));
    expect(found.sort()).toEqual(CSS_IDS.map((id) => mediaCondition(id)).sort());
  });
});
