// Tests scripts/fwcore-build.sh and its record rule (task local-mem-budget, "no svc.unknown after a land / a clean check.sh").
// The table of `record_rule` equals the #guards of Fw.Obs.recordTree in lean/Fw/Obs/Stale.lean; the land test builds in a
// real merge (git merge --no-commit), commits it, and asks the consumer (build-base.ts) for the base: a commit, not unknown.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { chmodSync, copyFileSync, cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { after, describe, it } from 'node:test';
import { fileURLToPath } from 'node:url';
import { buildBase } from '../apps/console-api/src/core/build-base.ts';

const here = path.dirname(fileURLToPath(import.meta.url));
const dirs = [];
after(() => dirs.forEach((d) => rmSync(d, { recursive: true, force: true })));
const sh = (cwd, ...a) => execFileSync(a[0], a.slice(1), { cwd, encoding: 'utf8', env: { ...process.env, GIT_AUTHOR_NAME: 't', GIT_AUTHOR_EMAIL: 't@t', GIT_COMMITTER_NAME: 't', GIT_COMMITTER_EMAIL: 't@t' } }).trim();

describe('record_rule (Fw.Obs.recordTree)', () => {
  const rule = (...a) => execFileSync('sh', ['-c', '. "$1"; shift; record_rule "$@"', '_', path.join(here, 'fwcore-record-rule.sh'), ...a], { encoding: 'utf8' }).trim();
  for (const [name, a, want] of [
    ['both reads, clean both ends', ['T', 'T', '1', '1'], 'T'],
    ['dirty before', ['T', 'T', '0', '1'], ''],
    ['dirty after', ['T', 'T', '1', '0'], ''],
    ['the tree moved during the build', ['T', 'U', '1', '1'], ''],
    ['no tree before (unmerged paths)', ['', 'T', '1', '1'], ''],
    ['no tree after', ['T', '', '1', '1'], ''],
  ]) it(name, () => assert.equal(rule(...a), want));
});

/** A repo with the build script, a fake `lake` that "links" the binary, and a branch to merge. */
function fixture() {
  const d = mkdtempSync(path.join(tmpdir(), 'fwbuild-'));
  dirs.push(d);
  sh(d, 'git', 'init', '-q', '-b', 'main');
  mkdirSync(path.join(d, 'scripts'));
  for (const f of ['fwcore-build.sh', 'fwcore-record-rule.sh', 'lake-slot-lib.sh']) copyFileSync(path.join(here, f), path.join(d, 'scripts', f));
  mkdirSync(path.join(d, 'packages/contracts/golden/sched'), { recursive: true });
  copyFileSync(path.join(here, '../packages/contracts/golden/sched/lake-slot.gen.sh'), path.join(d, 'packages/contracts/golden/sched/lake-slot.gen.sh'));
  mkdirSync(path.join(d, 'lean/Fw'), { recursive: true });
  writeFileSync(path.join(d, 'lean/Fw/A.lean'), 'a\n');
  writeFileSync(path.join(d, '.gitignore'), 'lean/.lake\n');
  const bindir = path.join(d, 'fakebin');
  mkdirSync(bindir);
  writeFileSync(path.join(bindir, 'lake'), '#!/bin/sh\nmkdir -p .lake/build/bin && cat Fw/*.lean > .lake/build/bin/fwcore\n');
  chmodSync(path.join(bindir, 'lake'), 0o755);
  sh(d, 'git', 'add', '-A');
  sh(d, 'git', 'commit', '-qm', 'base');
  const build = () => execFileSync('sh', ['scripts/fwcore-build.sh'], { cwd: d, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], env: { ...process.env, PATH: `${bindir}:${process.env.PATH}`, LAKE_SLOT_DIR: path.join(d, '.slot'), FW_HEAVY_LOCK: 'off' } });
  const base = () => buildBase(d, path.join(d, 'lean/.lake/build/bin/fwcore'));
  return { d, build, base };
}

describe('fwcore-build.sh record', () => {
  it('a check.sh-style build on a clean tree names the tree of HEAD and resolves to HEAD (no svc.unknown)', () => {
    const { d, build, base } = fixture();
    build();
    const rec = readFileSync(path.join(d, 'lean/.lake/build/bin/fwcore.commit'), 'utf8').trim();
    assert.match(rec, new RegExp(`^tree ${sh(d, 'git', 'rev-parse', 'HEAD^{tree}')} [0-9a-f]{64}$`));
    assert.deepEqual(base(), { sha: sh(d, 'git', 'rev-parse', 'HEAD') });
  });

  it('a land: the build of the merged tree mid-merge is found again at the commit that lands it', () => {
    const { d, build, base } = fixture();
    sh(d, 'git', 'checkout', '-qb', 'feat');
    writeFileSync(path.join(d, 'lean/Fw/B.lean'), 'b\n');
    sh(d, 'git', 'add', '-A');
    sh(d, 'git', 'commit', '-qm', 'feat');
    sh(d, 'git', 'checkout', '-q', 'main');
    writeFileSync(path.join(d, 'lean/Fw/C.lean'), 'c\n');
    sh(d, 'git', 'add', '-A');
    sh(d, 'git', 'commit', '-qm', 'main moves');
    sh(d, 'git', 'merge', '--no-commit', '--no-ff', 'feat');
    assert.ok(existsSync(path.join(d, '.git/MERGE_HEAD')));
    // the land writes the task evidence into the merge before the checks (and so before the build): the committed tree is the built tree
    const wg = path.join(d, 'docs/team/work-graph.json');
    mkdirSync(path.dirname(wg), { recursive: true });
    writeFileSync(wg, '{"evidence":"abc1234"}\n');
    sh(d, 'git', 'add', 'docs/team/work-graph.json');
    const err = build();
    assert.doesNotMatch(err, /no build record/);
    // before the landing commit exists the tree is on no commit: unknown, with the reason, not a guess
    const mid = base();
    assert.ok('unknown' in mid && /on no commit of main/.test(mid.unknown), JSON.stringify(mid));
    sh(d, 'git', 'commit', '-qm', 'land feat');
    assert.deepEqual(base(), { sha: sh(d, 'git', 'rev-parse', 'HEAD') });
  });

  it('a land that writes the evidence after the build (the old fallback order): the built tree is not the committed tree, unknown', () => {
    const { d, build, base } = fixture();
    sh(d, 'git', 'checkout', '-qb', 'feat');
    writeFileSync(path.join(d, 'lean/Fw/B.lean'), 'b\n');
    sh(d, 'git', 'add', '-A');
    sh(d, 'git', 'commit', '-qm', 'feat');
    sh(d, 'git', 'checkout', '-q', 'main');
    writeFileSync(path.join(d, 'lean/Fw/C.lean'), 'c\n');
    sh(d, 'git', 'add', '-A');
    sh(d, 'git', 'commit', '-qm', 'main moves');
    sh(d, 'git', 'merge', '--no-commit', '--no-ff', 'feat');
    build();
    const wg = path.join(d, 'docs/team/work-graph.json');
    mkdirSync(path.dirname(wg), { recursive: true });
    writeFileSync(wg, '{"evidence":"abc1234"}\n');
    sh(d, 'git', 'add', 'docs/team/work-graph.json');
    sh(d, 'git', 'commit', '-qm', 'land feat');
    const b = base();
    assert.ok('unknown' in b, JSON.stringify(b));
  });

  it('a dirty tree writes no new record; the binary of the old record still resolves when nothing relinked', () => {
    const { d, build, base } = fixture();
    build();
    const head = sh(d, 'git', 'rev-parse', 'HEAD');
    writeFileSync(path.join(d, 'lean/Fw/A.lean'), 'edited\n');
    build();
    const b = base();
    assert.ok('unknown' in b && /does not match the binary/.test(b.unknown), JSON.stringify(b)); // the fake lake relinked: old record is another binary
    sh(d, 'git', 'checkout', '--', 'lean/Fw/A.lean');
    build();
    assert.deepEqual(base(), { sha: head });
  });

  it('a no-op build keeps the record (the old script removed it first, a watch tick then saw svc.unknown)', () => {
    const { d, build, base } = fixture();
    build();
    writeFileSync(path.join(d, 'untracked.txt'), 'x\n'); // outside lean/: still clean
    build();
    assert.deepEqual(base(), { sha: sh(d, 'git', 'rev-parse', 'HEAD') });
  });
});
