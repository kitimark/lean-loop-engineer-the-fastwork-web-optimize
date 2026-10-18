// Tests of scripts/ci-paths.mjs: the workflows equal the Lean decision, the Lean replay cases hold under GitHub's own glob
// reading (an independent matcher), and the lint fails on each way the trigger can drift.
import assert from 'node:assert/strict';
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { matches, preciseInputs } from '../.github/scripts/changed-inputs.mjs';
import { coarseMap, coneOf, coneProblems, expand, LAKE_GEN, lakeGenProblems, lakeImportFacts, lakeJobs, lakeTargetsOf, loadGolden, portableGlob, readJobs, readLakefile, reconcile, renderPush, run, setMapFor, setupLeanJobs, unguarded } from './ci-paths.mjs';

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

test('Lake cache jobs are read from the workflows: one writer, every setup-lean job, its targets', () => {
  const rows = lakeJobs(root);
  const by = (k) => rows.find((r) => `${r.file}/${r.job}` === k);
  assert.deepEqual(rows.filter((r) => r.saves).map((r) => `${r.file}/${r.job}`), ['lean.yml/lean']);
  const lean = readFileSync(join(root, WF, 'lean.yml'), 'utf8').split('\n');
  assert.deepEqual(setupLeanJobs(lean), [{ job: 'lean', save: 'true' }, { job: 'mathview-differential', save: 'false' }]);
  // `lake build` = the lakefile defaults; check.sh adds fwtest
  assert.deepEqual(by('lean.yml/lean').targets, [...readLakefile(root).defaults, 'fwtest']);
  // a site build reaches `lake exe breakgen` through pnpm -> package.json -> scripts/check-breakpoints.mjs (spawnSync)
  for (const k of ['webkit-sim.yml/site', 'visual-diff.yml/site', 'breakpoint-gate.yml/site']) assert.deepEqual(by(k)?.targets, ['breakgen'], k);
  assert.deepEqual(by('webkit-sim.yml/fwcore')?.targets, ['fwcore']);
  // mutants.sh: `lake build $LIBS fwtest fwcore` with LIBS="Fw FwTest.Mutants.Kill"; `$mod` (no literal) is skipped
  assert.ok(['Fw', 'FwTest.Mutants.Kill', 'fwtest', 'fwcore'].every((t) => by('mutants.yml/shard').targets.includes(t)));
  assert.deepEqual(lakeImportFacts(root, rows), [['FwTest.Mutants.Kill', 'fwtest']]);
  assert.deepEqual(lakeGenProblems(root, false), []);
});

test('Lake targets: the scanner reads lake build / exe / test, variables, sh and pnpm', () => {
  const ctx = { root, lake: { defaults: ['D'], testDriver: 'T' }, pkgs: new Map(), seen: new Set() };
  assert.deepEqual(lakeTargetsOf(ctx, 'lake build && lake build a b:olean >log; lake exe e --x; lake test', [root]), ['D', 'a', 'b', 'e', 'T']);
  assert.deepEqual(lakeTargetsOf(ctx, 'L="x y"\nlake build $L z $u\n# lake build c', [root]), ['x', 'y', 'z']);
  assert.deepEqual(lakeTargetsOf(ctx, "spawnSync('lake', ['exe', 'g', '--check', file])", [root]), ['g']);
});

test('Lake cache: a new setup-lean job needs no hand edit (--write adds its row; --check then passes)', () => {
  const dir = mkdtempSync(join(tmpdir(), 'fw-lakegen-'));
  try {
    mkdirSync(join(dir, WF), { recursive: true });
    mkdirSync(join(dir, 'lean/Fw/Ops'), { recursive: true });
    copyFileSync(join(root, 'lean/lakefile.toml'), join(dir, 'lean/lakefile.toml'));
    const job = (name, extra) => [`  ${name}:`, '    runs-on: ubuntu-24.04-arm', '    steps:', '      - uses: ./.github/actions/setup-lean', ...extra];
    writeFileSync(join(dir, WF, 'lean.yml'), ['on:', 'jobs:', ...job('lean', ['        with:', "          save: 'true'", '      - run: lake build']), ''].join('\n'));
    assert.deepEqual(lakeGenProblems(dir, true), []);
    assert.deepEqual(lakeGenProblems(dir, false), []);
    writeFileSync(join(dir, WF, 'new.yml'), ['on:', 'jobs:', ...job('extra', ['      - working-directory: lean', '        run: |', '          lake build fwcore']), ''].join('\n'));
    assert.match(lakeGenProblems(dir, false)[0], /regenerate: node scripts\/ci-paths.mjs --write/);
    assert.deepEqual(lakeJobs(dir).map((r) => [r.file, r.job, r.saves, r.targets.join(' ')]),
      [['lean.yml', 'lean', true, readLakefile(root).defaults.join(' ')], ['new.yml', 'extra', false, 'fwcore']]);
    assert.deepEqual(lakeGenProblems(dir, true), []);
    assert.match(readFileSync(join(dir, LAKE_GEN), 'utf8'), /\("new\.yml", "extra", false, \["fwcore"\]\)/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
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
