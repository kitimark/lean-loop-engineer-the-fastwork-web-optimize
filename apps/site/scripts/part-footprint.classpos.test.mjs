import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { parseSync } from 'vite';
import { CLASS_HELPERS, CLASS_LIST_METHODS, CLASS_SEPARATORS, classListReport, classReport, collectClassTokens, literalClasses } from './part-footprint.mjs';

const golden = new URL('../../../packages/contracts/golden/parts/footprint.classpos.jsonl', import.meta.url);
const [head, ...all] = readFileSync(fileURLToPath(golden), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const rows = all.filter((r) => r.src !== undefined);
const listRows = all.filter((r) => r.method !== undefined);

const memberClass = (x) => {
  if (x.object.type !== 'Identifier' || x.object.name !== 'css') return null;
  return x.computed ? { key: 'css' } : { mod: `css#${x.property.name}` };
};
const exprOf = (src) => parseSync('case.js', `const x = ${src};`).program.body[0].declarations[0].init;
const tokensOf = (src) => collectClassTokens(exprOf(src), memberClass);
const named = (toks, op) => toks.filter((t) => t.op === op).map((t) => t.name);

test('the helpers, separators and classList methods are the Lean sets', () => {
  assert.deepEqual(CLASS_HELPERS, head.helpers);
  assert.deepEqual(CLASS_SEPARATORS, head.separators);
  assert.deepEqual(CLASS_LIST_METHODS, head.listMethods);
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
    const e = exprOf(r.src);
    if (e.type === 'Literal') assert.deepEqual(literalClasses(e.value), r.classes);
  });
}

for (const r of listRows) {
  test(`classList.${r.method} of ${JSON.stringify(r.args)}`, () => {
    assert.deepEqual(classListReport(r.method, r.args), { writes: r.writes, findings: r.findings });
  });
}

test('the golden has literal rows with non-ASCII whitespace and a classList row per method', () => {
  assert.ok(rows.some((r) => exprOf(r.src).type === 'Literal' && r.classes.some((c) => /\s/.test(c))));
  for (const m of CLASS_LIST_METHODS) assert.ok(listRows.some((r) => r.method === m), m);
});

test('a class in an unmodelled call is reported and opens the site', () => {
  const { writes, findings } = classReport(tokensOf("getClass('primary', css.m)"));
  assert.deepEqual(findings, [['unmodelled-class', 'call getClass'], ['unmodelled-class', 'primary'], ['unmodelled-class', 'css#m']]);
  assert.deepEqual(writes, [['setClass', '?']]);
});

test('an unmodelled position without literals still opens the site', () => {
  const forms = { 'getClass(variant)': 'call getClass', 'cls.trim()': 'method trim', "items.map((i) => i.c).join(' ')": 'method join', 'clsx(...xs)': 'spread', "[a, b].join('-')": 'join separator', 'new Cls()': 'other' };
  for (const [src, form] of Object.entries(forms)) {
    const { writes, findings } = classReport(tokensOf(src));
    assert.deepEqual(findings[0], ['unmodelled-class', form], src);
    assert.deepEqual(writes, [['setClass', '?']], src);
  }
});

test('a glued class keeps its literal part, is reported and opens the site', () => {
  const { writes, findings } = classReport(tokensOf('`${box}is-pill`'));
  assert.deepEqual(findings, [['glued-class', '*is-pill'], ['unmodelled-class', 'id box']]);
  assert.deepEqual(writes, [['setClass', 'is-pill'], ['setClass', '?']]);
});
