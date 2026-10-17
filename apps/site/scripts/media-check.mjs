// Census assertion: every @media in the built static CSS (mui.*.css and linked app CSS) must be a condition from
// src/breakpoints.gen.json; MUI feature queries are allowed only via src/mui-internal-media.json and reported apart.
import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';

const norm = (s) =>
  s.trim().toLowerCase().replace(/\s+/g, ' ').replace(/\(\s+/g, '(').replace(/\s+\)/g, ')').replace(/\s*:\s*/g, ':');

export async function checkMedia(root, engine) {
  const gen = JSON.parse(await readFile(path.join(root, 'src/breakpoints.gen.json'), 'utf8'));
  const internal = JSON.parse(await readFile(path.join(root, 'src/mui-internal-media.json'), 'utf8'));
  const allowed = new Set(Object.values(gen.conditions).map(norm));
  const internalSet = new Set(internal.conditions.map(norm));

  const dir = path.join(root, 'dist', engine);
  const files = [];
  for (const f of await readdir(dir)) if (f.endsWith('.css')) files.push(path.join(dir, f));
  for (const f of await readdir(path.join(dir, 'assets'))) if (f.endsWith('.css')) files.push(path.join(dir, 'assets', f));

  const fromGen = {};
  const fromInternal = {};
  const unknown = {};
  for (const file of files) {
    const css = await readFile(file, 'utf8');
    for (const m of css.matchAll(/@media([^{]+)\{/g)) {
      // "a, b" is a list of alternatives: each must be allowed
      for (const part of m[1].split(',')) {
        const c = norm(part);
        const bucket = allowed.has(c) ? fromGen : internalSet.has(c) ? fromInternal : unknown;
        bucket[c] = (bucket[c] ?? 0) + 1;
      }
    }
  }
  return { ok: Object.keys(unknown).length === 0, fromGen, fromInternal, unknown };
}
