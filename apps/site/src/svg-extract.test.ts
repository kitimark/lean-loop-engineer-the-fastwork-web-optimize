// svg.gen.json is built from the snapshot and never committed; no tracked file under apps/ may hold a snapshot path string.
import { execFileSync } from 'node:child_process';
import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const repo = fileURLToPath(new URL('../../../', import.meta.url));
const gen = JSON.parse(readFileSync(new URL('./svg.gen.json', import.meta.url), 'utf8')) as {
  wordmark: { paths: string[] };
  accent: { base: string[]; words: { paths: string[] }[] };
};

// Inline paths already on main, moved to svg.gen.json by task snapshot-paths-cleanup; the list only shrinks.
const PENDING_CLEANUP = new Set([
  'apps/site/src/parts/hero/index.tsx',
  'apps/site/src/parts/morph.panel/index.tsx',
  'apps/site/src/parts/overlays.drawer/index.tsx',
  'apps/site/src/parts/overlays.signup/index.tsx',
  'apps/site/src/parts/platform/Visuals.tsx',
  'apps/site/src/parts/commission/data.ts',
  'apps/site/src/parts/commission/index.tsx',
]);

describe('svg-extract', () => {
  it('extracts the wordmark and every visible accent word with three boil frames', () => {
    expect(gen.wordmark.paths.length).toBeGreaterThan(0);
    expect(gen.accent.base).toHaveLength(3);
    expect(gen.accent.words).toHaveLength(6);
    for (const w of gen.accent.words) expect(w.paths).toHaveLength(3);
  });

  it('no tracked file under apps/ holds a snapshot path string of >= 40 chars', () => {
    const html = readFileSync(`${repo}snapshot/site/index.html`, 'utf8');
    const nodes = `${repo}snapshot/site/_app/immutable/nodes/`;
    const js = readFileSync(nodes + readdirSync(nodes).find((f) => /^2\..*\.js$/.test(f))!, 'utf8');
    const strings = new Set<string>();
    for (const m of html.matchAll(/ d="([^"]{40,})"/g)) strings.add(m[1]!);
    for (const m of js.matchAll(/`(M[^`]{39,})`/g)) strings.add(m[1]!);
    expect(strings.size).toBeGreaterThan(0);
    const tracked = execFileSync('git', ['ls-files', '--', 'apps'], { cwd: repo, encoding: 'utf8' }).split('\n').filter(Boolean);
    const bad = new Set<string>();
    for (const f of tracked) {
      if (f === 'apps/site/src/svg-extract.test.ts' || PENDING_CLEANUP.has(f)) continue;
      let text: string;
      try {
        text = readFileSync(`${repo}${f}`, 'utf8');
      } catch {
        continue;
      }
      for (const s of strings) if (text.includes(s)) bad.add(f);
    }
    expect([...bad]).toEqual([]);
  });
});
