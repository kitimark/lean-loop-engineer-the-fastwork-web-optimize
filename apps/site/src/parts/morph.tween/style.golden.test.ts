import { readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { writes } from './style.logic';

const here = dirname(fileURLToPath(import.meta.url));
const parts = join(here, '..');
const golden = readFileSync(join(here, '../../../../../packages/contracts/golden/parts/morph-style.jsonl'), 'utf8')
  .trim()
  .split('\n')
  .map((l) => JSON.parse(l) as { fn: string; in: Record<string, unknown>; out: Record<string, unknown> });

const cssFiles = (dir: string): string[] =>
  readdirSync(dir).flatMap((f) => {
    const p = join(dir, f);
    return statSync(p).isDirectory() ? cssFiles(p) : p.endsWith('.css') ? [p] : [];
  });
const readers = (re: RegExp): string[] =>
  cssFiles(parts)
    .filter((p) => re.test(readFileSync(p, 'utf8')))
    .map((p) => p.slice(parts.length + 1))
    .sort();
const lean = (w: string, mode: string) =>
  golden.find((g) => g.fn === 'morph.style.consumers' && g.in.write === w && g.in.mode === mode)?.out.files as string[];

describe('Lean Fw.Parts.MorphStyle (golden morph-style.jsonl)', () => {
  it('writes: the skip is flip and m > 0', () => {
    const cases = golden.filter((g) => g.fn === 'morph.style.writes');
    expect(cases.length).toBe(12);
    for (const c of cases) expect(writes(c.in.flip as boolean, (c.in.mMilli as number) / 1000)).toBe(c.out.writes);
  });

  it('base-mode CSS readers of --morph and --morph-fade are the files the Lean table names', () => {
    expect(readers(/var\(--morph[,)]/)).toEqual(lean('nav.--morph', 'base'));
    expect(readers(/var\(--morph-fade/)).toEqual(lean('platform.--morph-fade', 'base'));
  });

  it('a skippable write has no flip-mode reader; the attribute keeps its three', () => {
    const rows = golden.filter((g) => g.fn === 'morph.style.consumers' && g.in.mode === 'flip');
    expect(rows.map((r) => [r.in.write, r.out.skippable, (r.out.files as string[]).length])).toEqual([
      ['nav.--morph', true, 0],
      ['nav.data-fw-morph', false, 3],
      ['platform.--morph-fade', true, 0],
    ]);
  });

  it('the attribute readers are the files that observe or read it', () => {
    const src = (f: string) => readFileSync(join(parts, f), 'utf8');
    for (const f of lean('nav.data-fw-morph', 'flip')) expect(src(f)).toMatch(/fwMorph/);
  });

  it('flip-mode override: the nav rule holds --morph at 1 and the platform tracks animate opacity and filter', () => {
    const css = readFileSync(join(parts, 'morph.geom/geom.css'), 'utf8');
    expect(css).toMatch(/\.is-flip \[data-fw='nav'\] \{\s*--morph: 1 !important;/);
    const tracks = readFileSync(join(parts, 'morph.geom/tracks.ts'), 'utf8');
    expect(tracks).toMatch(/one\('platform', 'opacity', 'fade'/);
    expect(tracks).toMatch(/one\('platform', 'filter', 'fade'/);
  });
});
