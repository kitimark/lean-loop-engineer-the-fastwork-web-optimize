import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { parseSync } from 'vite';
import {
  CLASS_LIST_METHODS,
  CLASS_SEPARATORS,
  JOIN_HELPERS,
  LIST_HELPERS,
  classAssign,
  classListReport,
  classMatch,
  classReport,
  classStrength,
  classUnion,
  collectClassTokens,
  isOpenClass,
  literalClasses,
  pickOwners,
} from './part-footprint.mjs';

const golden = new URL('../../../packages/contracts/golden/parts/footprint.classpos.jsonl', import.meta.url);
const [head, ...all] = readFileSync(fileURLToPath(golden), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
const rows = all.filter((r) => r.src !== undefined);
const listRows = all.filter((r) => r.method !== undefined);
const unionRows = all.filter((r) => r.union !== undefined);
const matchRows = all.filter((r) => r.sel !== undefined);
const strengthRows = all.filter((r) => r.classMatch !== undefined);
const pickRows = all.filter((r) => r.candidates !== undefined);

const memberClass = (x) => {
  if (x.object.type !== 'Identifier' || x.object.name !== 'css') return null;
  return x.computed ? { key: 'css' } : { mod: `css#${x.property.name}` };
};
const exprOf = (src) => parseSync('case.js', `const x = ${src};`).program.body[0].declarations[0].init;
const envOf = (consts = []) => {
  const inits = new Map(consts.map(([n, src]) => [n, exprOf(src)]));
  const env = { memberClass, constInit: (name) => (inits.has(name) ? { init: inits.get(name), env } : null) };
  return env;
};
const tokensOf = (src, consts, ctx) => collectClassTokens(exprOf(src), envOf(consts), ctx);
const named = (toks, op) => toks.filter((t) => t.op === op).map((t) => t.name);

test('the helpers, separators and classList methods are the Lean sets', () => {
  assert.deepEqual(LIST_HELPERS, head.listHelpers);
  assert.deepEqual(JOIN_HELPERS, head.joinHelpers);
  assert.deepEqual(CLASS_SEPARATORS, head.separators);
  assert.deepEqual(CLASS_LIST_METHODS, head.listMethods);
});

test('the golden has a row for every helper and every report kind', () => {
  for (const h of [...LIST_HELPERS, ...JOIN_HELPERS]) assert.ok(rows.some((r) => r.src.startsWith(`${h}(`) && r.classes.length > 0), h);
  for (const k of ['unmodelled-class', 'glued-class']) assert.ok(rows.some((r) => r.findings.some((f) => f[0] === k)), k);
  for (const m of ['none', 'weak', 'strong']) assert.ok(matchRows.some((r) => r.match === m), m);
});

for (const r of rows) {
  test(`class tokens of ${r.src}`, () => {
    const toks = tokensOf(r.src, r.consts);
    assert.deepEqual(named(toks, 'setClass'), r.classes);
    assert.deepEqual(named(toks, 'setModuleClass'), r.modules);
    assert.equal(isOpenClass(toks), r.open);
    assert.deepEqual(classReport(toks), { writes: r.writes, findings: r.findings });
    assert.deepEqual(classAssign(tokensOf(r.src, r.consts, 'text')), r.assign);
    const e = exprOf(r.src);
    if (e.type === 'Literal' && typeof e.value === 'string') assert.deepEqual(literalClasses(e.value), r.classes);
  });
}

for (const r of listRows) {
  test(`classList.${r.method} of ${JSON.stringify(r.args)}`, () => {
    assert.deepEqual(classListReport(r.method, r.args), { writes: r.writes, findings: r.findings });
  });
}

for (const r of unionRows) {
  test(`union of ${JSON.stringify(r.union)}`, () => {
    assert.deepEqual(classUnion(r.union[0], r.union[1]), r.value);
  });
}

for (const r of matchRows) {
  test(`class match of ${r.sel} on ${r.classes}${r.open ? ' (open)' : ''}`, () => {
    assert.equal(classMatch((c) => r.classes.includes(c), r.sel, r.open), r.match);
  });
}

for (const r of strengthRows) {
  test(`strength of ${r.classMatch} spread=${r.spread} literal=${r.literalAttrs}`, () => {
    assert.equal(classStrength(r.spread, r.literalAttrs, r.classMatch), r.strength);
  });
}

for (const r of pickRows) {
  test(`owners of ${JSON.stringify(r.candidates)}`, () => {
    assert.deepEqual(pickOwners(r.candidates), { owners: r.owners, weak: r.weak });
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

test('a const cycle stays lost', () => {
  assert.deepEqual(classReport(tokensOf('a', [['a', 'b'], ['b', 'a']])).findings, [['unmodelled-class', 'id a']]);
});
