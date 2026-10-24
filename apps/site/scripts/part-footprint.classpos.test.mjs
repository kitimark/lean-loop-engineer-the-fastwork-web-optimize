import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { parseSync } from 'vite';
import { CLASS_HELPERS, CLASS_SEPARATORS, classReport, collectClassTokens } from './part-footprint.mjs';

const golden = new URL('../../../packages/contracts/golden/parts/footprint.classpos.jsonl', import.meta.url);
const [head, ...rows] = readFileSync(fileURLToPath(golden), 'utf8').trim().split('\n').map((l) => JSON.parse(l));

const memberClass = (x) => (!x.computed && x.object.type === 'Identifier' && x.object.name === 'css' ? `css#${x.property.name}` : null);
const tokensOf = (src) => {
  const { program } = parseSync('case.js', `const x = ${src};`);
  return collectClassTokens(program.body[0].declarations[0].init, memberClass);
};
const named = (toks, op) => toks.filter((t) => t.op === op).map((t) => t.name);

test('the helpers and separators are the Lean sets', () => {
  assert.deepEqual(CLASS_HELPERS, head.helpers);
  assert.deepEqual(CLASS_SEPARATORS, head.separators);
});

test('the golden has a row for every helper and every report kind', () => {
  for (const h of CLASS_HELPERS) assert.ok(rows.some((r) => r.src.startsWith(`${h}(`) && r.classes.length > 0), h);
  for (const k of ['unmodelled-class', 'glued-class']) assert.ok(rows.some((r) => r.findings.some((f) => f[0] === k)), k);
});

for (const r of rows) {
  test(`class tokens of ${r.src}`, () => {
    const toks = tokensOf(r.src);
    assert.deepEqual(named(toks, 'setClass'), r.classes);
    assert.deepEqual(named(toks, 'setModuleClass'), r.modules);
    assert.deepEqual(classReport(toks), { writes: r.writes, findings: r.findings });
  });
}

test('a class in an unmodelled call is reported and opens the site', () => {
  const { writes, findings } = classReport(tokensOf("getClass('primary', css.m)"));
  assert.deepEqual(findings, [['unmodelled-class', 'primary'], ['unmodelled-class', 'css#m']]);
  assert.deepEqual(writes, [['setClass', '?']]);
});

test('a glued class keeps its literal part and is reported', () => {
  const { writes, findings } = classReport(tokensOf('`${box}is-pill`'));
  assert.deepEqual(findings, [['glued-class', '*is-pill']]);
  assert.deepEqual(writes, [['setClass', 'is-pill']]);
});
