// Census assertion: every @media in the built static CSS (mui.*.css and linked app CSS) must be a condition from
// src/breakpoints.gen.json (`conditions`); the `neutral` set of the same file is reported apart.
import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';

// The generator's strings are canonical (range syntax, single spaces). The CSS minifier drops the space after ':' and
// after ',' (and around parens), so both sides are compared with whitespace around ':', ',' and parens removed.
const norm = (s) =>
  s.trim().toLowerCase().replace(/\s+/g, ' ').replace(/\s*([:,()])\s*/g, '$1').replace(/\)and\(/g, ') and (');

export async function checkMedia(root, engine) {
  const gen = JSON.parse(await readFile(path.join(root, 'src/breakpoints.gen.json'), 'utf8'));
  const allowed = new Set(gen.conditions.map((c) => norm(c.css)));
  const internalSet = new Set(gen.neutral.map((c) => norm(c.css)));

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
      // a whole query list may itself be a generated condition (c860 etc. contain commas); otherwise each alternative is checked
      const whole = norm(m[1]);
      if (allowed.has(whole)) {
        fromGen[whole] = (fromGen[whole] ?? 0) + 1;
        continue;
      }
      for (const part of m[1].split(',')) {
        const c = norm(part);
        const bucket = allowed.has(c) ? fromGen : internalSet.has(c) ? fromInternal : unknown;
        bucket[c] = (bucket[c] ?? 0) + 1;
      }
    }
  }
  return { ok: Object.keys(unknown).length === 0, fromGen, fromInternal, unknown };
}
