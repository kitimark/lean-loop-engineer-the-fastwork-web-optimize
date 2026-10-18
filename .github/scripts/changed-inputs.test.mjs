// node --test .github/scripts/changed-inputs.test.mjs
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, readdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { branchFiles, decide, evOf, globToRegExp, guardBase, isLanded, isTip, laneFor, lowerAscii, matches, outputLine, parsePaths, preciseInputs, pushFiles, pushInputs, remoteTip, wantedBy } from './changed-inputs.mjs';

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


const CI = { event: 'push', ref: 'refs/heads/ci/foo' };
const tagOf = (r) => (r.run ? 'run' : r.reason.split(':')[0]);

test('decide: a ci push runs iff a file that differs from main on the branch is an input', () => {
  const globs = parsePaths(WF);
  assert.equal(tagOf(decide({ ...CI, globs, files: ['docs/a.md', 'apps/site/x.ts'] })), 'unchanged');
  assert.equal(tagOf(decide({ ...CI, globs, files: [] })), 'unchanged');
  const hit = decide({ ...CI, globs, files: ['docs/a.md', 'lean/Fw.lean'] });
  assert.equal(hit.run, true);
  assert.deepEqual(hit.matched, ['lean/Fw.lean']);
});

test('decide: main pushes keep the coarse paths rule; dispatches, schedules and other events run', () => {
  const main = { event: 'push', ref: 'refs/heads/main', globs: ['lean/Fw/X.lean'], pushGlobs: ['lean/**'] };
  assert.equal(decide({ ...main, files: ['lean/Fw/Y.lean'] }).run, true); // coarse, not precise
  assert.equal(tagOf(decide({ ...main, files: ['docs/a.md'] })), 'unchanged');
  assert.equal(decide({ ...main, files: null }).run, true); // unknown before: fail open
  assert.equal(decide({ event: 'workflow_dispatch', ref: 'refs/heads/ci/foo', files: [], globs: [] }).run, true);
  assert.equal(decide({ event: 'schedule', ref: 'refs/heads/main', files: [], globs: [] }).run, true);
  assert.equal(evOf('push', 'refs/heads/ci/x'), 'ci');
  assert.equal(evOf('push', 'refs/heads/main'), 'main');
  assert.equal(evOf('workflow_dispatch', 'refs/heads/ci/x'), 'record');
});

// A throwaway repo: main moves on after the branch was cut, and the branch merges main in. The merge brings main's lean/
// change onto the branch, but the branch itself only touches docs: the guard must say skip.
test('branchFiles ignores what a merge of main brought in and what the branch reverted', () => {
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
    const globs = parsePaths(WF);
    assert.deepEqual(branchFiles('main', dir), ['docs/a.md']);
    assert.equal(tagOf(decide({ ...CI, files: branchFiles('main', dir), globs })), 'unchanged');
    // the reviewer's sequence: push A changes X (an input) and Y; push B reverts X; the branch still carries Y
    const leanGlobs = ['lean/**'];
    put('lean/Fw.lean', 'A'); // X
    put('lean/Fw/Y.lean', 'A'); // Y
    git('add', '.');
    git('commit', '-q', '-m', 'push A');
    assert.deepEqual(branchFiles('main', dir).sort(), ['docs/a.md', 'lean/Fw.lean', 'lean/Fw/Y.lean']);
    put('lean/Fw.lean', '2'); // B reverts X to main's content
    git('add', '.');
    git('commit', '-q', '-m', 'push B');
    const filesB = branchFiles('main', dir);
    assert.deepEqual(filesB.sort(), ['docs/a.md', 'lean/Fw/Y.lean']);
    // B's own diff is lean/Fw.lean only; the tip decides on the branch, so lean runs on B (Lean tip_history_free)
    assert.equal(decide({ ...CI, files: filesB, globs: leanGlobs, msg: 'push B' }).run, true);
    // push C reverts Y too: nothing lean differs from main any more
    rmSync(join(dir, 'lean/Fw/Y.lean'));
    git('add', '-A');
    git('commit', '-q', '-m', 'push C');
    assert.deepEqual(branchFiles('main', dir), ['docs/a.md']);
    assert.equal(tagOf(decide({ ...CI, files: branchFiles('main', dir), globs: leanGlobs })), 'unchanged');
    // pushFiles: a main push's own diff; an unknown or all-zero before is null (runs)
    const before = git('rev-parse', 'HEAD~1').trim();
    assert.deepEqual(pushFiles(before, dir), ['lean/Fw/Y.lean']);
    assert.equal(pushFiles('0'.repeat(40), dir), null);
    assert.equal(pushFiles('f'.repeat(40), dir), null);
    assert.equal(pushFiles('', dir), null);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('preciseInputs: the Lean row with the cones of the checkout; pushInputs: the coarse globs', () => {
  const root = join(here, '..', '..');
  const precise = preciseInputs(root, '.github/workflows/wktr.yml');
  assert.ok(precise.includes('lean/Main.lean') && precise.includes('packages/measure-wktr/**'));
  assert.ok(!precise.includes('lean/Fw/**'), 'no coarse glob in the precise inputs');
  const coneFile = precise.find((g) => /^lean\/Fw\/.+\.lean$/.test(g));
  assert.ok(coneFile, 'the cone files are listed');
  // the guard decides on the precise list: a module outside the cone skips, a cone module runs
  assert.equal(decide({ ...CI, files: ['lean/Fw/NotImported.lean'], globs: precise }).run, false);
  assert.equal(decide({ ...CI, files: [coneFile], globs: precise }).run, true);
  const coarse = pushInputs(root, '.github/workflows/wktr.yml');
  assert.ok(coarse.includes('lean/Fw/**') && !coarse.includes(coneFile));
  assert.equal(preciseInputs(root, '.github/workflows/no-such.yml'), null);
  assert.equal(pushInputs(root, '.github/workflows/no-such.yml'), null);
});

// ---- task ci-own-trigger (Lean Fw.Ci.Intent `decision`) ----
const repoRoot = join(here, '..', '..');

test('decide with a lane: unwanted, stale, landed, unchanged, in the Lean order; records run', () => {
  const globs = parsePaths(WF);
  const wktr = laneFor(repoRoot, 'wktr.yml');
  const lean = laneFor(repoRoot, '.github/workflows/lean.yml');
  const files = ['packages/measure-wktr/src/a.mjs'];
  const ci = { ...CI, files, globs };
  assert.equal(tagOf(decide({ ...ci, lane: wktr, msg: 'fix' })), 'unwanted'); // no intent, not a default lane
  assert.equal(decide({ ...ci, lane: wktr, msg: 'fix [ci:wktr]' }).run, true);
  assert.equal(decide({ ...ci, lane: wktr, msg: 'fix [CI:Wktr]' }).run, true); // case-insensitive
  assert.equal(tagOf(decide({ ...ci, lane: wktr, msg: 'fix [ci:wktr-fixtures]' })), 'unwanted'); // tokens do not confuse
  assert.equal(tagOf(decide({ ...ci, lane: wktr, msg: '[ci:wktr]', tip: false })), 'stale');
  assert.equal(tagOf(decide({ ...ci, lane: wktr, msg: '[ci:wktr]', landed: true })), 'landed');
  assert.equal(tagOf(decide({ ...ci, lane: wktr, msg: '[ci:wktr]', tip: false, landed: true })), 'stale'); // first match
  assert.equal(tagOf(decide({ ...ci, lane: wktr, msg: 'x', tip: false })), 'unwanted'); // first match
  assert.equal(tagOf(decide({ ...ci, lane: wktr, msg: '[ci:wktr]', files: ['docs/a.md'] })), 'unchanged');
  // lean is the default lane: the tip runs it whatever differs from main, never `unchanged` (Lean tip_lean_always,
  // lean_never_unchanged, round 5)
  const leanFiles = ['lean/Fw.lean'];
  for (const msg of ['fix', '[ci:none]', '[ci:wktr]']) {
    for (const files of [leanFiles, ['docs/a.md'], []]) {
      assert.equal(decide({ ...ci, files, globs: ['lean/**'], lane: lean, msg }).run, true, `${msg} ${files}`);
    }
  }
  assert.equal(tagOf(decide({ ...ci, files: leanFiles, globs: ['lean/**'], lane: lean, msg: 'a', tip: false })), 'stale');
  assert.equal(tagOf(decide({ ...ci, files: [], globs: ['lean/**'], lane: lean, msg: 'a', landed: true })), 'landed');
  // a main push keeps the coarse paths rule for lean too
  assert.equal(tagOf(decide({ ...ci, ref: 'refs/heads/main', files: ['docs/a.md'], globs: ['lean/**'], lane: lean })), 'unchanged');
  assert.equal(decide({ ...ci, event: 'workflow_dispatch', lane: wktr, msg: '', landed: true, tip: false }).run, true);
  assert.equal(decide({ ...ci, ref: 'refs/heads/main', lane: wktr, msg: '' }).run, true); // main: the paths rule only
  assert.equal(lowerAscii('[CI:ÄB]'), '[ci:Äb]'); // Lean Char.toLower lowers ASCII only
  assert.equal(wantedBy(wktr, ''), false);
  assert.equal(wantedBy(lean, '[ci:none]'), true);
  assert.equal(outputLine('a\r\nb\nc'), 'a b c');
  assert.equal(outputLine('x'.repeat(300)).length, 200);
  assert.equal(isTip('a'.repeat(40), ''), true); // unreadable tip: fail open
  assert.equal(isTip('a'.repeat(40), 'a'.repeat(40)), true);
  assert.equal(isTip('a'.repeat(40), 'b'.repeat(40)), false);
});

test('isLanded, guardBase and remoteTip read the remote of a checkout', () => {
  const dir = mkdtempSync(join(tmpdir(), 'ci-intent-'));
  try {
    const cfg = ['-c', 'user.name=t', '-c', 'user.email=t@example.com', '-c', 'commit.gpgsign=false'];
    const at = (cwd) => (...a) => execFileSync('git', [...cfg, ...a], { cwd, encoding: 'utf8' }).trim();
    const up = join(dir, 'up.git');
    const work = join(dir, 'work');
    const other = join(dir, 'other');
    mkdirSync(work);
    at(dir)('init', '-q', '--bare', '-b', 'main', up);
    const w = at(work);
    const put = (f, text) => { mkdirSync(dirname(join(work, f)), { recursive: true }); writeFileSync(join(work, f), text); };
    w('init', '-q', '-b', 'main');
    w('remote', 'add', 'origin', up);
    put('README.md', '1');
    w('add', '.');
    w('commit', '-q', '-m', 'root');
    w('push', '-q', 'origin', 'main');
    w('checkout', '-q', '-b', 'ci/x');
    put('lean/Fw.lean', 'a');
    w('add', '.');
    w('commit', '-q', '-m', 'change [ci:lean]');
    w('push', '-q', 'origin', 'ci/x');
    w('fetch', '-q', 'origin');
    assert.equal(isLanded(work), false);
    assert.equal(guardBase(work), 'origin/main');
    const head = w('rev-parse', 'HEAD');
    assert.equal(remoteTip('refs/heads/ci/x', work), head);
    assert.equal(isTip(head, remoteTip('refs/heads/ci/x', work)), true); // HEAD is the tip
    assert.equal(remoteTip('refs/heads/ci/none', work), ''); // no such branch: unreadable
    // a newer push from another clone moves the tip: HEAD is stale
    at(dir)('clone', '-q', '-b', 'ci/x', up, other);
    const o = at(other);
    writeFileSync(join(other, 'docs.md'), 'x');
    o('add', '.');
    o('commit', '-q', '-m', 'newer');
    o('push', '-q', 'origin', 'ci/x');
    assert.equal(isTip(head, remoteTip('refs/heads/ci/x', work)), false);
    // the branch lands: main moves to the commit; the mirror ci/landed takes over as the base
    o('push', '-q', 'origin', 'HEAD:main');
    o('push', '-q', 'origin', 'HEAD:ci/landed');
    w('fetch', '-q', 'origin');
    assert.equal(isLanded(work), true);
    assert.equal(guardBase(work), 'origin/ci/landed');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
