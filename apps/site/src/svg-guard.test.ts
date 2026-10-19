// Allowlist guard: GenSvg/GenShape are the only way to draw snapshot artwork. Any JSX geometry element under
// src/parts/** must be listed in svg-allow.json with a reason; each listed entry must still match one.
import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import allow from './svg-allow.json';

const root = fileURLToPath(new URL('..', import.meta.url));
const GEOMETRY = new Set(['path', 'polygon', 'polyline', 'circle', 'ellipse', 'line', 'rect']);

function walk(dir: string): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? walk(`${dir}${e.name}/`) : [`${dir}${e.name}`]));
}

export function geometryElements(source: string): string[] {
  const code = source.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
  const names = [...GEOMETRY].join('|');
  const jsx = [...code.matchAll(new RegExp(`<(${names})(?=[\\s/>])`, 'g'))].map((m) => m[1]!);
  const calls = [...code.matchAll(new RegExp(`createElement\\(\\s*['"\`](${names})['"\`]`, 'g'))].map((m) => m[1]!);
  return [...jsx, ...calls];
}

describe('svg allowlist guard', () => {
  const files = walk(`${root}src/parts/`).filter((f) => f.endsWith('.tsx'));

  it('detects geometry elements', () => {
    expect(geometryElements('const a = <svg><circle r="1" /><path d="M0 0"></path></svg>;')).toEqual(['circle', 'path']);
    expect(geometryElements('const a = <svg><g /></svg>;')).toEqual([]);
  });

  it('no parts file draws a geometry element unless svg-allow.json lists it with a reason', () => {
    const found = new Map<string, number>();
    for (const f of files) {
      for (const el of geometryElements(readFileSync(f, 'utf8'))) {
        const key = `${f.slice(root.length)}\u0000${el}`;
        found.set(key, (found.get(key) ?? 0) + 1);
      }
    }
    const listed = new Set(allow.map((a) => `${a.file}\u0000${a.element}`));
    expect([...found.keys()].filter((k) => !listed.has(k)).map((k) => k.replace('\u0000', ' <') + '>')).toEqual([]);
    for (const a of allow) {
      expect(a.reason.trim().length, `${a.file} needs a reason`).toBeGreaterThan(20);
      expect(found.has(`${a.file}\u0000${a.element}`), `${a.file} <${a.element}> is stale`).toBe(true);
    }
  });
});
