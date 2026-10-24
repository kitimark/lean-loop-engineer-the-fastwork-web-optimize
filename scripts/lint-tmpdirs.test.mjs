import assert from 'node:assert/strict';
import test from 'node:test';
import { bindingOf, cleansUp, finding, lint, makes, removesName, run } from './lint-tmpdirs.mjs';

const leak = `import { mkdtempSync } from 'node:fs';\nconst d = mkdtempSync(join(tmpdir(), 'fw-x-'));\ntest('a', () => {});\n`;
const clean = `const d = mkdtempSync(join(tmpdir(), 'fw-x-'));\nafterAll(() => { rmSync(d, { recursive: true, force: true }); });\n`;
const tryFinally = `const d = mkdtempSync(p);\ntry { go(d); } finally { rmSync(d, { recursive: true }); }\n`;
const rmFar = `const d = mkdtempSync(p);\nrmSync(d);\n`;
const tAfter = `test('a', (t) => { const d = mkdtempSync(p); t.after(() => rmSync(d, { recursive: true })); });\n`;

test('makes: the lines of each mkdtemp call', () => {
  assert.deepEqual(makes(leak), [2]);
  assert.deepEqual(makes('const x = 1;\n'), []);
});

test('a file that creates a temp dir and has no cleanup context is flagged', () => {
  assert.deepEqual(finding(leak), [2]);
});

test('afterAll, finally and t.after with a removal are clean', () => {
  for (const t of [clean, tryFinally, tAfter]) assert.deepEqual(finding(t), []);
});

test('a removal outside any cleanup context is not enough', () => {
  assert.equal(cleansUp(rmFar), false);
  assert.deepEqual(finding(rmFar), [1]);
});

test('a cleanup keyword with no removal near it is not enough', () => {
  assert.equal(cleansUp(`afterAll(() => { close(); });\n${'x'.repeat(700)}\nrmSync(d);\n`), false);
});

test('a file with no temp dir is never flagged', () => {
  assert.deepEqual(finding(`afterAll(() => rmSync(d));\n`), []);
});

test('run: findings exit 0, and 1 only with --strict', () => {
  const lines = [];
  const read = () => leak;
  assert.equal(run([], (l) => lines.push(l), ['a.test.ts'], read), 0);
  assert.equal(run(['--strict'], () => {}, ['a.test.ts'], read), 1);
  assert.equal(run(['--strict'], () => {}, ['a.test.ts'], () => clean), 0);
  assert.match(lines.join('\n'), /a\.test\.ts:2 creates a temp dir/);
});

test('lint reports the flagged files only', () => {
  const texts = { 'a.test.ts': leak, 'b.test.ts': clean };
  assert.deepEqual(lint(['a.test.ts', 'b.test.ts', 'gone.ts'], (f) => { if (!(f in texts)) throw new Error('x'); return texts[f]; }),
    [{ file: 'a.test.ts', lines: [2] }]);
});

test('each binding needs an rm of its own name in a cleanup window', () => {
  const two = `const a = mkdtempSync(p);\nconst b = mkdtempSync(p);\nafterAll(() => { rmSync(a, { recursive: true }); });\n`;
  assert.deepEqual(finding(two), [2]);
  const both = `const a = mkdtempSync(p);\nconst b = realpathSync(mkdtempSync(p));\nafterAll(() => { rmSync(a); rmSync(join(b, 'x')); });\n`;
  assert.deepEqual(finding(both), []);
  const prefix = `const d = mkdtempSync(p);\nafterAll(() => { rmSync(dd); rmSync(d2); });\n`;
  assert.deepEqual(finding(prefix), [1]);
});

test('bindingOf: const, let, assignment; null for a factory, a destructuring or a bare call', () => {
  const at = (src) => bindingOf(src, src.indexOf('mkdtemp'));
  assert.equal(at('const d = mkdtempSync(p)'), 'd');
  assert.equal(at('let $t: string = realpathSync(mkdtempSync(p))'), '$t');
  assert.equal(at('  base = mkdtempSync(p)'), 'base');
  assert.equal(at('const tmp = (p) => mkdtempSync(p)'), null);
  assert.equal(at('const { a } = mkdtempSync(p)'), null);
  assert.equal(at('use(mkdtempSync(p))'), null);
});

test('removesName only counts removals inside a cleanup window', () => {
  assert.equal(removesName('afterAll(() => rmSync(d))', 'd'), true);
  assert.equal(removesName('rmSync(d);\n', 'd'), false);
  assert.equal(removesName('afterAll(() => rmSync(other))', 'd'), false);
});

test('an unbound factory falls back to the file-level cleanup rule', () => {
  const factory = `const tmp = (p) => mkdtempSync(join(tmpdir(), p));\nafterAll(() => { for (const d of dirs) rmSync(d); });\n`;
  assert.deepEqual(finding(factory), []);
  assert.deepEqual(finding(`const tmp = (p) => mkdtempSync(p);\n`), [1]);
});
