// svg.gen.json is built from the snapshot and never committed; no tracked file under apps/ or packages/ may hold any
// 24-character run of a snapshot SVG path. No file is exempt, this test included.
import { execFileSync } from 'node:child_process';
import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import gen from './svg.gen.json';

const repo = fileURLToPath(new URL('../../../', import.meta.url));
const RUN = 24;

function walk(dir: string): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? walk(`${dir}${e.name}/`) : [`${dir}${e.name}`]));
}

/** Every SVG path string the snapshot carries: `d="..."` attributes in the page and its scripts, and path template strings in scripts. */
function snapshotPaths(): Set<string> {
  const out = new Set<string>();
  const site = `${repo}snapshot/site/`;
  const files = [`${site}index.html`, ...walk(`${site}_app/`).filter((f) => f.endsWith('.js'))];
  for (const f of files) {
    const text = readFileSync(f, 'utf8');
    for (const m of text.matchAll(/\sd="([^"]{24,})"/g)) out.add(m[1]!);
    for (const m of text.matchAll(/`([Mm][-\d\s.,A-Za-z]{23,})`/g)) out.add(m[1]!);
    for (const m of text.matchAll(/"([Mm][-\d.,]+[-\d\s.,A-Za-z]{22,})"/g)) out.add(m[1]!);
  }
  return out;
}

const IDENTITY: Record<string, { viewBox: string; kids: string[] }> = {
  'drawer.mark': { viewBox: '0 0 46 46', kids: ['path'] },
  'nav.chevron': { viewBox: '0 0 16 16', kids: ['path'] },
  'nav.langCheck': { viewBox: '0 0 24 24', kids: ['path'] },
  'platform.search': { viewBox: '0 0 24 24', kids: ['circle', 'path'] },
  'platform.check': { viewBox: '0 0 24 24', kids: ['circle', 'path'] },
  'platform.dashLeft': { viewBox: '0 0 94 3.2', kids: ['line'] },
  'platform.dashRight': { viewBox: '0 0 94 3.2', kids: ['line'] },
  'people.star': { viewBox: '0 0 24 24', kids: ['path'] },
  'people.mute': { viewBox: '0 0 24 24', kids: ['path'] },
  'people.play': { viewBox: '0 0 24 24', kids: ['path'] },
  'people.clock': { viewBox: '0 0 16 16', kids: ['circle', 'path'] },
  'review.bolt': { viewBox: '0 0 24 24', kids: ['path'] },
  'review.shield': { viewBox: '0 0 24 24', kids: ['path', 'path'] },
  'review.star': { viewBox: '0 0 24 24', kids: ['path'] },
  'review.tag': { viewBox: '0 0 24 24', kids: ['path', 'circle'] },
  'brand.mark': { viewBox: '0 0 74 66', kids: ['path'] },
};

describe('svg-extract', () => {
  it('each art id is the snapshot artwork it names: viewBox and child shapes', () => {
    const art = gen.art as unknown as Record<string, { svg: { viewBox: string }; kids: Array<{ tag: string }> }>;
    for (const [id, want] of Object.entries(IDENTITY)) {
      expect(art[id]!.svg.viewBox, id).toBe(want.viewBox);
      expect(art[id]!.kids.map((k) => k.tag), id).toEqual(want.kids);
    }
  });

  it('extracts the wordmark, every visible accent word and each moved artwork', () => {
    expect(gen.wordmark.paths.length).toBeGreaterThan(0);
    expect(gen.accent.base).toHaveLength(3);
    expect(gen.accent.words).toHaveLength(6);
    for (const w of gen.accent.words) expect(w.paths).toHaveLength(3);
    expect(gen.art['icon.calendar'].kids).toHaveLength(10);
    expect(gen.art['icon.bell'].kids).toHaveLength(2);
    expect(gen.art['commission.underline']).toHaveLength(3);
    expect(gen.art['commission.zero']).toHaveLength(3);
    for (const k of ['nav.globe', 'platform.star', 'platform.pin', 'platform.shield', 'brand.mark'] as const) {
      expect(gen.art[k].kids.length).toBeGreaterThan(0);
    }
    expect(gen.art['brand.mark'].svg.viewBox).toBe('0 0 74 66');
  });

  it(`no tracked file under apps/ or packages/ holds ${RUN} characters of a snapshot path`, () => {
    const paths = snapshotPaths();
    expect(paths.size).toBeGreaterThan(40);
    const runs = new Set<string>();
    for (const p of paths) for (let i = 0; i + RUN <= p.length; i++) runs.add(p.slice(i, i + RUN));
    const tracked = execFileSync('git', ['ls-files', '-z', '--', 'apps', 'packages'], { cwd: repo, encoding: 'utf8', maxBuffer: 1 << 28 })
      .split('\0')
      .filter(Boolean);
    const bad: string[] = [];
    for (const f of tracked) {
      let text: string;
      try {
        text = readFileSync(`${repo}${f}`, 'utf8');
      } catch {
        continue;
      }
      for (let i = 0; i + RUN <= text.length; i++) {
        if (runs.has(text.slice(i, i + RUN))) {
          bad.push(f);
          break;
        }
      }
    }
    expect(bad).toEqual([]);
  });
});
