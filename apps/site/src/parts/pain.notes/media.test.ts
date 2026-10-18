import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { mediaCondition } from '../../breakpoints';

const css = readFileSync(resolve(__dirname, 'notes.module.css'), 'utf8');
const norm = (s: string) => s.trim().replace(/\s+/g, ' ');

describe('pain.notes media', () => {
  it('the CSS @media blocks are byte-equal to the generated conditions', () => {
    const found = [...css.matchAll(/@media\s+([^{]+)\{/g)].map((m) => norm(m[1]!));
    expect(found).toEqual([mediaCondition('mq.rm-reduce'), mediaCondition('mq.w-le-860')]);
  });
});
