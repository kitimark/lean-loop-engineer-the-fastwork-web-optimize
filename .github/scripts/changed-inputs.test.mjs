// node --test .github/scripts/changed-inputs.test.mjs
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { changedFiles, decide, globToRegExp, matches, parsePaths } from './changed-inputs.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const WF = `name: x
on:
  push:
    branches: ['ci/**']
    paths:
      - 'packages/measure-wktr/**'   # a comment
      - "lean/**"
      - snapshot.lock.json
      - '!lean/docs/**'
  workflow_dispatch:
    inputs:
      jobs:
        type: string
jobs: {}
`;

test('parsePaths reads quoted, double-quoted and bare items, stops at the next key', () => {
  assert.deepEqual(parsePaths(WF), ['packages/measure-wktr/**', 'lean/**', 'snapshot.lock.json', '!lean/docs/**']);
});

test('parsePaths fails on a workflow without a push paths list', () => {
  assert.throws(() => parsePaths('name: x\non:\n  push:\n    branches: [main]\n'), /paths/);
  assert.throws(() => parsePaths('name: x\njobs: {}\n'), /on:/);
});

test('parsePaths reads every real workflow that has a push paths list', () => {
  const dir = join(here, '..', 'workflows');
  for (const f of readdirSync(dir).filter((n) => n.endsWith('.yml'))) {
    const text = readFileSync(join(dir, f), 'utf8');
    if (!/^ {4}paths:/m.test(text)) continue;
    const globs = parsePaths(text);
    assert.ok(globs.length > 0, f);
    assert.ok(globs.every((g) => g.length > 0 && !/['"]/.test(g)), `${f}: ${globs}`);
  }
});

test('globs: * stops at a slash, ** does not, dots are literal', () => {
  const m = (g, f) => globToRegExp(g).test(f);
  assert.ok(m('lean/**', 'lean/Fw/Measure.lean'));
  assert.ok(m('lean/**', 'lean/lakefile.toml'));
  assert.ok(!m('lean/**', 'leanx/a'));
  assert.ok(!m('lean/*', 'lean/a/b'));
  assert.ok(m('lean/*', 'lean/a'));
  assert.ok(m('snapshot.lock.json', 'snapshot.lock.json'));
  assert.ok(!m('snapshot.lock.json', 'snapshotXlockXjson'));
  assert.ok(m('a/**/c', 'a/c'));
  assert.ok(m('a/**/c', 'a/b/b/c'));
  assert.ok(m('**.md', 'docs/team/x.md'));
  assert.ok(m('.github/workflows/wktr.yml', '.github/workflows/wktr.yml'));
  assert.ok(m('file[0-9].txt', 'file7.txt'));
  assert.ok(m('colou?r.txt', 'color.txt') && m('colou?r.txt', 'colour.txt'));
  assert.ok(m('ab+c', 'abbbc') && !m('ab+c', 'ac'));
});

test('matches: a later ! pattern excludes, a later positive pattern re-includes', () => {
  const globs = ['lean/**', '!lean/docs/**', 'lean/docs/keep.md'];
  assert.ok(matches(globs, 'lean/Fw.lean'));
  assert.ok(!matches(globs, 'lean/docs/a.md'));
  assert.ok(matches(globs, 'lean/docs/keep.md'));
  assert.ok(!matches(globs, 'apps/site/a.ts'));
});

test('decide: ci push without an input skips; with an input runs', () => {
  const globs = parsePaths(WF);
  const ci = { event: 'push', ref: 'refs/heads/ci/foo', globs };
  assert.equal(decide({ ...ci, files: ['docs/a.md', 'apps/site/x.ts'] }).run, false);
  assert.equal(decide({ ...ci, files: [] }).run, false);
  const hit = decide({ ...ci, files: ['docs/a.md', 'lean/Fw.lean'] });
  assert.equal(hit.run, true);
  assert.deepEqual(hit.matched, ['lean/Fw.lean']);
});

test('decide: main pushes, dispatches and non-ci branches always run', () => {
  const globs = parsePaths(WF);
  assert.equal(decide({ event: 'push', ref: 'refs/heads/main', files: [], globs }).run, true);
  assert.equal(decide({ event: 'workflow_dispatch', ref: 'refs/heads/ci/foo', files: [], globs }).run, true);
  assert.equal(decide({ event: 'push', ref: 'refs/heads/feature/x', files: [], globs }).run, true);
});

// A throwaway repo: main moves on after the branch was cut, and the branch merges main in. The merge brings main's lean/
// change onto the branch, but the branch itself only touches docs: the guard must say skip.
test('changedFiles ignores what a merge of main brought in', () => {
  const dir = mkdtempSync(join(tmpdir(), 'changed-inputs-'));
  try {
    const git = (...a) => execFileSync('git', ['-c', 'user.name=t', '-c', 'user.email=t@example.com', '-c', 'commit.gpgsign=false', ...a], { cwd: dir, encoding: 'utf8' });
    const put = (f, text) => { mkdirSync(dirname(join(dir, f)), { recursive: true }); writeFileSync(join(dir, f), text); };
    git('init', '-q', '-b', 'main');
    put('README.md', '1');
    put('lean/Fw.lean', '1');
    git('add', '.');
    git('commit', '-q', '-m', 'root');
    git('checkout', '-q', '-b', 'ci/x');
    put('docs/a.md', 'branch');
    git('add', '.');
    git('commit', '-q', '-m', 'docs');
    git('checkout', '-q', 'main');
    put('lean/Fw.lean', '2');
    put('snapshot.lock.json', '{}');
    git('add', '.');
    git('commit', '-q', '-m', 'main moves on');
    git('checkout', '-q', 'ci/x');
    git('merge', '-q', '--no-ff', '-m', 'merge main', 'main');
    // `main` plays origin/main here
    const files = changedFiles('main', dir);
    assert.deepEqual(files, ['docs/a.md']);
    const globs = parsePaths(WF);
    assert.equal(decide({ event: 'push', ref: 'refs/heads/ci/x', files, globs }).run, false);
    // the branch now touches an input
    put('packages/measure-wktr/src/a.mjs', 'x');
    git('add', '.');
    git('commit', '-q', '-m', 'wktr input');
    const files2 = changedFiles('main', dir);
    assert.deepEqual(files2.sort(), ['docs/a.md', 'packages/measure-wktr/src/a.mjs']);
    assert.equal(decide({ event: 'push', ref: 'refs/heads/ci/x', files: files2, globs }).run, true);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
