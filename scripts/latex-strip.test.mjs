// Tests of scripts/latex-strip.mjs: fixture Lean sources and their expected output, one pass equals two passes, and
// --check exits 1 exactly when a doc comment still holds `$$`.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { docDollarBlocks, plainInline, split, strip } from './latex-strip.mjs';

const script = join(dirname(new URL(import.meta.url).pathname), 'latex-strip.mjs');

const cases = [
  ['block after prose', '/-- The plan commands.\n\n$$\\mathrm{Cmd} = a \\mid b$$\n-/\ninductive Cmd\n',
    '/-- The plan commands. -/\ninductive Cmd\n'],
  ['block between paragraphs', '/-- First.\n\n$$x = 1$$\n\nSecond line.\n-/\ndef x := 1\n',
    '/-- First.\n\nSecond line.\n-/\ndef x := 1\n'],
  ['inline name becomes a code span', '/-- A time $\\mathit{ts}$ in ms. -/\ndef ts := 0\n', '/-- A time `ts` in ms. -/\ndef ts := 0\n'],
  ['inline formula becomes plain text', '/-- For every $k \\ge 1$ and $\\tfrac12$. -/\ndef k := 1\n',
    '/-- For every `k ≥ 1` and `1/2`. -/\ndef k := 1\n'],
  ['mixed: lead-in colon, block, where clause with math', '/-- The bound:\n\n$$b \\le n$$\n\nwhere $b$ is the bound.\n-/\ndef b := 1\n',
    '/-- The bound. -/\ndef b := 1\n'],
  ['a where clause without math is kept', '/-- Reads the file.\n\n$$r = f$$\nwhere a missing file reads as empty. -/\ndef r := 1\n',
    '/-- Reads the file.\n\nHere a missing file reads as empty. -/\ndef r := 1\n'],
  ['a sentence that ran into the block ends at its last full sentence', '/-- It steps. A refused body is kept; otherwise\n\n$$s = t$$\n-/\ndef s := 1\n',
    '/-- It steps. A refused body is kept. -/\ndef s := 1\n'],
  ['math-only docstring is deleted with its line', 'def a := 1\n\n/-- $$a = 1$$ -/\ntheorem t : True := trivial\n',
    'def a := 1\n\ntheorem t : True := trivial\n'],
  ['math-only module doc is deleted', '/-! $$x$$ -/\n\ndef x := 1\n', '\ndef x := 1\n'],
  ['indented field doc', 'structure S where\n  /-- The width.\n\n  $$w \\ge 0$$\n  -/\n  w : Nat\n',
    'structure S where\n  /-- The width. -/\n  w : Nat\n'],
  ['code spans and fences keep their dollars', '/-- Shell `$$` and `$HOME`.\n\n```\necho $x$\n```\n\n$$y$$\n-/\ndef y := 1\n',
    '/-- Shell `$$` and `$HOME`.\n\n```\necho $x$\n```\n-/\ndef y := 1\n'],
  ['a -/ and /-- inside a string literal stay code', 'def s := "/-- $$x$$ -/"\n/-- Doc $$y$$ -/\ndef t := s\n',
    'def s := "/-- $$x$$ -/"\n/-- Doc. -/\ndef t := s\n'],
  ['a $ in a string literal and in a char', 'def u := "$$" ++ "$x$"\ndef c := \'$\'\ndef q := \'"\'\n/-- $$z$$ Kept. -/\ndef z := 1\n',
    'def u := "$$" ++ "$x$"\ndef c := \'$\'\ndef q := \'"\'\n/-- Kept. -/\ndef z := 1\n'],
  ['plain comments and line comments are not touched', '/- $$a$$ -/\n-- $$b$$\n/-- $$c$$ Doc. -/\ndef c := 1\n',
    '/- $$a$$ -/\n-- $$b$$\n/-- Doc. -/\ndef c := 1\n'],
  ['nested comment inside a doc comment', '/-- Doc /- inner -/ $$m$$ end. -/\ndef m := 1\n', '/-- Doc /- inner -/ end. -/\ndef m := 1\n'],
  ['interpolated string with a nested string', 'def i := s!"a {f "/-"} b"\n/-- $$k$$ K. -/\ndef k := 1\n',
    'def i := s!"a {f "/-"} b"\n/-- K. -/\ndef k := 1\n'],
  ['a prime in a name is not a char', "def x' := 1\ndef y'' := x'\n/-- $$v$$ V. -/\ndef v := 1\n", "def x' := 1\ndef y'' := x'\n/-- V. -/\ndef v := 1\n"],
  ['a doc without math is unchanged', '/-- Costs \\$5 or `$x$`. -/\ndef p := 1\n', '/-- Costs \\$5 or `$x$`. -/\ndef p := 1\n'],
];

for (const [name, src, want] of cases) {
  test(`strip: ${name}`, () => {
    const got = strip(src);
    assert.equal(got, want);
    assert.equal(strip(got), got, 'a second pass changes nothing');
  });
}

test('split: the parts concatenate to the source and doc parts are whole comments', () => {
  for (const [, src] of cases) {
    const parts = split(src);
    assert.equal(parts.map((p) => p.text).join(''), src);
    for (const p of parts.filter((q) => q.kind === 'doc')) assert.match(p.text, /^\/-[-!][\s\S]*-\/$/);
  }
});

test('plainInline: names, operators, fractions and binomials; null for an unknown command', () => {
  assert.equal(plainInline('\\mathrm{some}(x)'), 'some(x)');
  assert.equal(plainInline('(L, e) \\in \\mathbb N \\times \\mathbb N'), '(L, e) ∈ ℕ × ℕ');
  assert.equal(plainInline('C_{\\max} \\le \\sum_j d_j'), 'C_max ≤ Σ_j d_j');
  assert.equal(plainInline('\\binom{m+n}{n}'), 'choose(m+n, n)');
  assert.equal(plainInline('\\mathit{now} \\mathbin{\\dot-} t'), 'now ∸ t');
  assert.equal(plainInline('\\overbrace{x}'), null);
});

test('docDollarBlocks counts $$ in doc comments only', () => {
  assert.equal(docDollarBlocks('def s := "$$"\n-- $$\n/-- $$a$$ -/\ndef a := 1\n'), 2);
  assert.equal(docDollarBlocks('#guard f "$$" == none\n'), 0);
});

test('the CLI rewrites in place, skips generated files, and --check exits 1 only while a doc holds $$', () => {
  const dir = mkdtempSync(join(tmpdir(), 'latex-strip-'));
  const f = join(dir, 'A.lean');
  const g = join(dir, 'G.lean');
  writeFileSync(f, '/-- Doc.\n\n$$x$$\n-/\ndef x := "$$"\n');
  writeFileSync(g, '-- GENERATED by a generator: do not edit by hand\n/-- $$g$$ G. -/\ndef g := 1\n');
  const run = (...args) => spawnSync(process.execPath, [script, ...args], { encoding: 'utf8' });
  assert.equal(run('--check', f).status, 1);
  assert.equal(run(f, g).status, 0);
  assert.equal(readFileSync(f, 'utf8'), '/-- Doc. -/\ndef x := "$$"\n');
  assert.match(readFileSync(g, 'utf8'), /\$\$g\$\$/);
  assert.equal(run('--check', f).status, 0);
  assert.equal(run('--check', g).status, 1);
});
