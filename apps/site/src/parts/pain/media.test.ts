import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { MEDIA_IDS, mediaTexts } from './media';

const css = readFileSync(resolve(__dirname, 'pain.module.css'), 'utf8');
const norm = (s: string) => s.trim().replace(/\s+/g, ' ');

describe('pain media', () => {
  it('the CSS @media blocks are byte-equal to the generated conditions', () => {
    const found = [...css.matchAll(/@media\s+([^{]+)\{/g)].map((m) => norm(m[1]!));
    expect(found).toEqual(mediaTexts());
    expect(found.length).toBe(MEDIA_IDS.length);
  });
  it('restates the geometry the Lean spec proves facts about (Fw.Parts.Pain)', () => {
    const flat = css.replace(/\s+/g, ' ');
    expect(flat).toContain('padding: 96px 56px 80px');
    expect(flat).toContain('max-width: 780px');
    expect(flat).toContain('height: 200svh');
    expect(flat).toContain('min-height: 100svh');
    expect(flat).toContain('margin-top: -100svh');
  });
});
