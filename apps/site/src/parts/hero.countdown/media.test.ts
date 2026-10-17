import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { mediaCondition } from '../../breakpoints';
import { MEDIA_IDS } from './media';

const css = readFileSync(resolve(__dirname, 'hero.module.css'), 'utf8');
const norm = (s: string) => s.trim().replace(/\s+/g, ' ');

describe('hero.countdown media', () => {
  it('the CSS @media blocks are byte-equal to the generated conditions', () => {
    const found = [...css.matchAll(/@media\s+([^{]+)\{/g)].map((m) => norm(m[1]!));
    expect(found.length).toBe(2); // C1000-nodw and <=400; reduced motion is read in JS only for this part
    expect(MEDIA_IDS).toContain('mq.rm-reduce');
    for (const id of ['mq.c1000-nodw', 'mq.w-le-400']) expect(found).toContain(mediaCondition(id));
  });
});
