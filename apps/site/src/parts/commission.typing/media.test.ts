import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { mediaCondition } from '../../breakpoints';
import { MEDIA_IDS } from './media';

const css = readFileSync(resolve(__dirname, 'typing.module.css'), 'utf8');
const norm = (s: string) => s.trim().replace(/\s+/g, ' ');

describe('commission.typing media', () => {
  it('the CSS @media blocks are byte-equal to the generated conditions', () => {
    const found = [...css.matchAll(/@media\s+([^{]+)\{/g)].map((m) => norm(m[1]!));
    expect(found.length).toBe(MEDIA_IDS.length);
    for (const id of MEDIA_IDS) expect(found).toContain(mediaCondition(id));
  });
});
