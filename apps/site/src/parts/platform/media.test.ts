import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { mediaCondition } from '../../breakpoints';
import { MEDIA_IDS } from './media';

const FILES = ['platform.module.css', 'stage.module.css', 'sweep.module.css', 'visuals.module.css'];
const norm = (s: string) => s.trim().replace(/\s+/g, ' ');

describe('platform media', () => {
  const found = new Set(FILES.flatMap((f) => [...readFileSync(resolve(__dirname, f), 'utf8').matchAll(/@media\s+([^{]+)\{/g)].map((m) => norm(m[1]!))));
  it('the CSS @media blocks are byte-equal to the generated conditions, and every condition is used', () => {
    const want = new Set(MEDIA_IDS.map((id) => mediaCondition(id)));
    expect(found).toEqual(want);
  });
});
