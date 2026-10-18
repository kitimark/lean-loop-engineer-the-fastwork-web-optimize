// Tests of scripts/ci-paths.mjs: the workflows equal the Lean decision, the Lean replay cases hold under GitHub's own glob
// reading (an independent matcher), and the lint fails on each way the trigger can drift.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { matches, preciseInputs } from '../.github/scripts/changed-inputs.mjs';
import { coarseMap, coneOf, coneProblems, expand, loadGolden, portableGlob, readJobs, reconcile, renderPush, run, setMapFor, unguarded } from './ci-paths.mjs';

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

test('Lean replay cases: the static push filter (coarse cone globs) passes exactly `filtered`, a superset of `started`', () => {
  const S = coarseMap(table);
  for (const c of cases) {
    const passed = table.workflows.filter((w) => c.diff.some((f) => matches(expand(S, w.inputs), f))).map((w) => w.file);
    assert.deepEqual(passed, c.filtered, c.name);
    for (const f of c.started) assert.ok(c.filtered.includes(f), `${c.name}: ${f} started but filtered out`);
  }
});

test('coarse push paths: every cone of the checkout stays inside coneGlobs (Lean ConeWithin) and no path lists a cone file', () => {
  assert.deepEqual(coneProblems(root, table), []);
  assert.deepEqual(table.coneGlobs, ['lean/Fw/**', 'lean/*.lean']);
  const S = coarseMap(table);
  for (const w of table.workflows) {
    const coarse = expand(S, w.inputs);
    // a cone module is covered without being listed: the only modules listed are the row's own literal inputs
    for (const g of coarse) if (/^lean\/Fw\/.+\.lean$/.test(g)) assert.ok(w.inputs.includes(g), `${w.file} lists cone module ${g}`);
    // every precise input of the checkout passes the coarse filter (Lean coarse_sound)
    for (const g of preciseInputs(root, w.file)) if (!g.includes('*')) assert.ok(matches(coarse, g), `${w.file}: ${g}`);
  }
});

const sample = readFileSync(join(root, WF, 'gate-gaps.yml'), 'utf8');
const row = table.workflows.find((w) => w.file === 'gate-gaps.yml');
const paths = expand(coarseMap(table), row.inputs);

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
