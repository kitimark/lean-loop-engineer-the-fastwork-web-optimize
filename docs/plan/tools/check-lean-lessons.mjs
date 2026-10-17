#!/usr/bin/env node
// Lint for the math-to-Lean study lessons (research/kickoff/12-math-to-lean/lessons.json) and the page that shows them
// (docs/plan/math-to-lean.html).
//   node docs/plan/tools/check-lean-lessons.mjs          (lint, then embed lessons.json into the page)
//   node docs/plan/tools/check-lean-lessons.mjs --check  (lint only; exit 1 on any drift)
// Checks:
//   1. every lesson's lean_excerpt is exactly lines lean_line_start..lean_line_end of lean_file;
//   2. every proof step's Lean text still appears in that excerpt;
//   3. math_latex, every pair's math and every notation row's math parse with KaTeX 0.16.11, if KaTeX is available
//      (FW_KATEX = path to katex.min.js, else `katex` resolvable from the repo); otherwise this check is skipped with a note;
//   4. the page embeds the current lessons.json (with --check: exit 1 if not).
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const lessonsPath = join(root, 'research/kickoff/12-math-to-lean/lessons.json');
const pagePath = join(root, 'docs/plan/math-to-lean.html');
const check = process.argv.includes('--check');
const BEGIN = '<script type="application/json" id="lessons-data">';
const END = '</script><!-- lessons:end -->';

const errors = [];
const data = JSON.parse(readFileSync(lessonsPath, 'utf8'));

for (const l of data.lessons) {
  const file = join(root, l.lean_file);
  if (!existsSync(file)) { errors.push(`${l.id}: ${l.lean_file} does not exist`); continue; }
  const lines = readFileSync(file, 'utf8').split('\n');
  const actual = lines.slice(l.lean_line_start - 1, l.lean_line_end).join('\n');
  if (actual !== l.lean_excerpt) {
    errors.push(`${l.id}: excerpt differs from ${l.lean_file}:${l.lean_line_start}-${l.lean_line_end}`);
    const i = l.lean_excerpt.split('\n').findIndex((x, k) => x !== actual.split('\n')[k]);
    errors.push(`  first differing line ${l.lean_line_start + i}:\n    lesson: ${l.lean_excerpt.split('\n')[i]}\n    file:   ${actual.split('\n')[i]}`);
  }
  for (const s of l.proof_steps) {
    if (!l.lean_excerpt.includes(s.lean)) errors.push(`${l.id}: proof step not in excerpt: ${s.lean.split('\n')[0]}`);
  }
}

const katex = (() => {
  const req = createRequire(join(root, 'package.json'));
  try { return req(process.env.FW_KATEX || 'katex'); } catch { return null; }
})();
let texCount = 0;
if (!katex) {
  console.log('note: KaTeX not found (set FW_KATEX to katex.min.js of 0.16.11); TeX parse check skipped');
} else {
  if (katex.version !== '0.16.11') errors.push(`KaTeX ${katex.version} found, 0.16.11 required (the page loads 0.16.11)`);
  const tex = (where, src) => {
    texCount++;
    try { katex.renderToString('\\displaystyle ' + src, { output: 'mathml', throwOnError: true, strict: 'ignore' }); }
    catch (e) { errors.push(`${where}: TeX does not parse: ${e.message}`); }
  };
  for (const l of data.lessons) {
    tex(`${l.id} math_latex`, l.math_latex);
    l.pairs.forEach((p, i) => tex(`${l.id} pair ${i + 1}`, p.math));
  }
  data.notation.forEach((n, i) => tex(`notation row ${i + 1}`, n.math));
}

// The page embeds the lessons as JSON; `<` is escaped so `</script>` can never close the tag early.
const embedded = JSON.stringify(data).replace(/</g, '\\u003c');
const page = readFileSync(pagePath, 'utf8');
const a = page.indexOf(BEGIN), b = page.indexOf(END);
if (a < 0 || b < a) errors.push(`page: markers not found in ${pagePath}`);
else {
  const current = page.slice(a + BEGIN.length, b);
  if (current !== embedded) {
    if (check) errors.push('page: embedded lessons differ from lessons.json (run without --check to update)');
    else writeFileSync(pagePath, page.slice(0, a + BEGIN.length) + embedded + page.slice(b));
  }
}

if (errors.length) { console.error(errors.join('\n')); process.exit(1); }
console.log(`lessons ok: ${data.lessons.length} lessons, excerpts match their Lean lines, ${texCount} TeX fragments parse${check ? ', page up to date' : ', page written'}`);
