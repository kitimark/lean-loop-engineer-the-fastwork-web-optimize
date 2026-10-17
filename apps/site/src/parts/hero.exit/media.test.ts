import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import gen from '../../breakpoints.gen.json';
import { MEDIA_IDS } from './media';

const conds = (gen as { conditions: Record<string, string> }).conditions;
const css = readFileSync(resolve(__dirname, 'hero.module.css'), 'utf8');
const norm = (s: string) => s.replace(/\s+/g, '').replace(/px/g, '');

describe('hero.exit media', () => {
  it('the CSS @media blocks restate the breakpoint conditions (compared once the gen file has them)', () => {
    const found = [...css.matchAll(/@media\s+([^{]+)\{/g)].map((m) => m[1]!.trim());
    expect(found.length).toBe(3);
    expect(MEDIA_IDS.length).toBe(3);
    for (const id of MEDIA_IDS) {
      const c = conds[id];
      if (c === undefined) continue; // placeholder breakpoints file
      expect(found.map(norm)).toContain(norm(c));
    }
  });
});
