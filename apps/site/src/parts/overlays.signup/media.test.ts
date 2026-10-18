import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { mediaCondition } from '../../breakpoints';
import { MEDIA_IDS } from './media';

const css = readFileSync(resolve(__dirname, 'signup.module.css'), 'utf8');
const norm = (s: string) => s.trim().replace(/\s+/g, ' ');

describe('overlays.signup media', () => {
  it('the CSS @media blocks are byte-equal to the generated conditions', () => {
    const found = [...css.matchAll(/@media\s+([^{]+)\{/g)].map((m) => norm(m[1]!));
    expect(found.length).toBe(MEDIA_IDS.length);
    for (const id of MEDIA_IDS) expect(found).toContain(mediaCondition(id));
  });
  it('the enter animation in the CSS is the Lean one: 0.4 s, --ease-standard, scale from 0.95', () => {
    expect(css).toContain('animation: enter 0.4s cubic-bezier(0.24, 1, 0.4, 1) backwards');
    expect(css).toContain('scale(0.95)');
  });
});
