import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { mediaText, MEDIA_IDS } from './media';

const blocks = (file: string) =>
  [...readFileSync(resolve(__dirname, file), 'utf8').matchAll(/@media\s+([^{]+)\{/g)].map((m) => m[1]!.trim().replace(/\s+/g, ' '));

describe('hero.deck media', () => {
  it('the @media blocks of deck.module.css and the shared card.module.css are byte-equal to the generated conditions', () => {
    const found = [...blocks('deck.module.css'), ...blocks('../hero.orbit/card.module.css')];
    expect([...found].sort()).toEqual(MEDIA_IDS.map((id) => mediaText(id)).sort());
  });
});
