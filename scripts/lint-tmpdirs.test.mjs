import assert from 'node:assert/strict';
import test from 'node:test';
import { cleansUp, finding, lint, makes, run } from './lint-tmpdirs.mjs';

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
