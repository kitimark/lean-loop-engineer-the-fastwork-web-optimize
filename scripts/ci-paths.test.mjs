// Tests of scripts/ci-paths.mjs: the workflows equal the Lean decision, the Lean replay cases hold under GitHub's own glob
// reading (an independent matcher), and the lint fails on each way the trigger can drift.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { matches } from '../.github/scripts/changed-inputs.mjs';
import { coneOf, expand, lakeCacheProblems, loadGolden, loadLakeCache, portableGlob, readJobs, reconcile, renderPush, run, setMapFor, setupLeanJobs, unguarded } from './ci-paths.mjs';

const root = join(dirname(new URL(import.meta.url).pathname), '..');
const WF = ['.git', 'hub/workflows'].join('');
const { table, cases } = loadGolden(root);

test('every workflow in the repo equals the Lean decision', () => {
  const { problems } = run(root, false);
  assert.deepEqual(problems, []);
});

test('Lean replay cases: the started workflows equal the decision under GitHub glob semantics', () => {
  assert.ok(cases.length >= 10);
  for (const c of cases) {
    const S = (g) => (table.sets[g] ?? [g]).flatMap((h) => (h.startsWith('@cone:') ? (c.cones[h.slice(6)] ?? []) : [h]));
    const eff = c.diff.filter((f) => !c.merged.includes(f));
    const started = table.workflows.filter((w) => eff.some((f) => matches(expand(S, w.inputs), f))).map((w) => w.file);
    assert.deepEqual(started, c.started, c.name);
  }
});

test('every declared glob is read the same by GitHub and by Lean PathCheck', () => {
  const S = setMapFor(root, table);
  for (const w of table.workflows) for (const g of expand(S, w.inputs)) assert.ok(portableGlob(g), `${w.file}: ${g}`);
});

test('the fwcore cone is smaller than lean/** and holds the entry module and the build files', () => {
  const S = setMapFor(root, table);
  const core = S('@fwcore');
  assert.ok(core.includes('lean/Main.lean') && core.includes('lean/lakefile.toml') && core.includes('lean/lean-toolchain'));
  assert.ok(core.every((p) => p.startsWith('lean/') || p.startsWith('packages/')));
  assert.ok(!core.some((p) => p.startsWith('lean/FwTest/') || p.startsWith('lean/scripts/')));
  assert.ok(coneOf(root, 'Main').length > 20);
  // a Lean test file or script starts no fwcore-only lane
  const wktr = table.workflows.find((w) => w.file === 'wktr.yml');
  assert.equal(matches(expand(S, wktr.inputs), 'lean/FwTest/Lease.lean'), false);
  assert.equal(matches(expand(S, wktr.inputs), 'lean/scripts/check.sh'), false);
  assert.equal(matches(expand(S, wktr.inputs), 'lean/Main.lean'), true);
});

test('the breakgen cone (run by every site build) holds only the breakpoint generator (task site-build-cache)', () => {
  const cone = coneOf(root, 'BreakgenMain');
  assert.ok(cone.includes('lean/Fw/Site/BreakpointGen.lean'));
  assert.ok(cone.every((p) => p === 'lean/BreakgenMain.lean' || p.startsWith('lean/Fw/Site/')), cone.join(' '));
  assert.ok(cone.length <= 8, `breakgen cone grew to ${cone.length} files: ${cone.join(' ')}`);
  // the gate generators live in sweepsgen
  assert.ok(coneOf(root, 'SweepsgenMain').includes('lean/Fw/Gate/Scope.lean'));
});

test('Lake cache: exactly one writer, and every setup-lean job equals the Lean table', () => {
  const rows = loadLakeCache(root);
  assert.ok(rows && rows.length >= 10);
  assert.deepEqual(rows.filter((r) => r.saves).map((r) => `${r.file}/${r.job}`), ['lean.yml/lean']);
  assert.ok(rows.every((r) => r.covered));
  const lean = readFileSync(join(root, WF, 'lean.yml'), 'utf8').split('\n');
  assert.deepEqual(setupLeanJobs(lean), [{ job: 'lean', save: 'true' }, { job: 'mathview-differential', save: 'false' }]);
  assert.deepEqual(lakeCacheProblems('lean.yml', lean, rows), []);
  // a second writer, a missing writer and an unlisted job are each reported
  const gg = readFileSync(join(root, WF, 'gate-gaps.yml'), 'utf8');
  const twoWriters = gg.replace(/^( +)- uses: \.\/\.github\/actions\/setup-lean$/m, "$1- uses: ./.github/actions/setup-lean\n$1  with:\n$1    save: 'true'");
  assert.ok(lakeCacheProblems('gate-gaps.yml', twoWriters.split('\n'), rows).some((p) => /save: 'true'/.test(p)));
  const noWriter = lean.join('\n').replace("save: 'true'", "save: 'false'").split('\n');
  assert.ok(lakeCacheProblems('lean.yml', noWriter, rows).some((p) => /job lean passes save: 'false'/.test(p)));
  assert.ok(lakeCacheProblems('other.yml', gg.split('\n'), rows).some((p) => /not in lean\/Fw\/Ops\/LakeCache.lean/.test(p)));
});

const sample = readFileSync(join(root, WF, 'gate-gaps.yml'), 'utf8');
const row = table.workflows.find((w) => w.file === 'gate-gaps.yml');
const S = setMapFor(root, table);
const paths = expand(S, row.inputs);

test('lint: a changed paths list is reported', () => {
  const bad = sample.replace(/^( {6}- 'snapshot\/\*\*')$/m, "$1\n      - 'extra/**'");
  const r = reconcile('gate-gaps.yml', bad, row, paths);
  assert.ok(r.problems.some((p) => /on\.push differs/.test(p)), r.problems.join('\n'));
  assert.equal(reconcile('gate-gaps.yml', r.text, row, paths).problems.length, 0);
});

test('lint: a branches change is reported', () => {
  const bad = sample.replace("branches: ['ci/**', main]", "branches: ['**']");
  assert.ok(reconcile('gate-gaps.yml', bad, row, paths).problems.some((p) => /on\.push differs/.test(p)));
});

test('lint: a removed guard is reported and restored', () => {
  const lines = sample.split('\n');
  const jobs = readJobs(lines);
  const g = jobs.find((j) => j.name === 'guard');
  const noGuard = [...lines.slice(0, g.at), ...lines.slice(g.end)].join('\n').replace(/^ {4}needs: \[guard\]\n {4}if: .*\n/gm, '');
  const r = reconcile('gate-gaps.yml', noGuard, row, paths);
  assert.ok(r.problems.some((p) => /no `guard` job/.test(p)), r.problems.join('\n'));
  assert.deepEqual(unguarded(readJobs(r.text.split('\n'))), []);
});

test('lint: a new root job that does not wait for the guard is reported', () => {
  const bad = `${sample.trimEnd()}\n\n  extra:\n    runs-on: ubuntu-24.04-arm\n    steps:\n      - run: echo hi\n`;
  const r = reconcile('gate-gaps.yml', bad, row, paths);
  assert.ok(r.problems.some((p) => /job extra does not wait for guard/.test(p)), r.problems.join('\n'));
  assert.deepEqual(unguarded(readJobs(r.text.split('\n'))), []);
});

test('renderPush writes branches and quoted paths', () => {
  assert.deepEqual(renderPush(['ci/**', 'main'], ['a/**']), ['  push:', "    branches: ['ci/**', main]", '    paths:', "      - 'a/**'"]);
});
