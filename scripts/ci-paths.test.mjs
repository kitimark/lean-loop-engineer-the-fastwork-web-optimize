// Tests of scripts/ci-paths.mjs: the workflows equal the Lean decision, the Lean replay cases hold under GitHub's own glob
// reading (an independent matcher), and the lint fails on each way the trigger can drift.
import assert from 'node:assert/strict';
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { decide, loadIntent, matches, preciseInputs } from '../.github/scripts/changed-inputs.mjs';
import { coarseMap, coneOf, coneProblems, dispatchOnly, expand, guardIf, jobConcurrency, LAKE_GEN, macosJobs, unsafeStatusIf, lakeGenProblems, lakeImportFacts, lakeJobs, lakeTargetsOf, loadGolden, portableGlob, readJobs, readLakefile, reconcile, renderPush, run, setMapFor, setupLeanJobs, unguarded } from './ci-paths.mjs';

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

// ---- task ci-own-trigger: the Lean intent golden (lean/Fw/Ci/Intent.lean) ----
const intent = loadIntent(root);
const laneOf = (file) => ({ ...intent.lanes.lanes.find((l) => l.file === file), prefix: intent.lanes.prefix,
  cancel: intent.lanes.cancel, decision: intent.lanes.decision });

/** A mini evaluator of the guard `if:` (Lean `ifExpr`): `||` of four term shapes, GitHub's case-insensitive functions;
 *  no `if:` (the empty text) always runs. */
export function evalGuardIf(expr, { event, ref, msg }) {
  if (expr === '') return true;
  const m = /^\$\{\{ (.*) \}\}$/.exec(expr);
  assert.ok(m, expr);
  const low = (x) => x.toLowerCase();
  return m[1].split(' || ').some((t) => {
    if (t === "github.event_name != 'push'") return event !== 'push';
    if (t === "!startsWith(github.ref, 'refs/heads/ci/')") return !low(ref).startsWith('refs/heads/ci/');
    const c = /^(!?)contains\(github\.event\.head_commit\.message, '([^']*)'\)$/.exec(t);
    assert.ok(c, `unknown term ${t}`);
    const has = low(msg).includes(low(c[2]));
    return c[1] === '!' ? !has : has;
  });
}

test('intent golden: one lane per workflow of the Lean table; only lean is a default lane; no default lane is macOS', () => {
  assert.deepEqual(intent.lanes.lanes.map((l) => l.file).sort(), table.workflows.map((w) => w.file).sort());
  assert.deepEqual(intent.lanes.lanes.filter((l) => l.byDefault).map((l) => l.file), ['lean.yml']);
  for (const l of intent.lanes.lanes) {
    assert.equal(l.token, `${intent.lanes.prefix}${l.name}]`);
    assert.ok(!(l.byDefault && l.macos), l.file); // Lean default_lane_not_macos
  }
});

test('intent replay: JS decide over the Lean cases starts exactly the Lean `start` lanes, the generated if: gates exactly `gate`', () => {
  assert.ok(intent.cases.length >= 10);
  for (const c of intent.cases) {
    const S = (g) => (table.sets[g] ?? [g]).flatMap((h) => (h.startsWith('@cone:') ? (c.cones[h.slice(6)] ?? []) : [h]));
    const files = c.diff.filter((f) => !c.merged.includes(f));
    const ctx = { event: c.ci ? 'push' : 'workflow_dispatch', ref: c.ci ? 'refs/heads/ci/x' : 'refs/heads/main', msg: c.msg };
    const started = table.workflows.filter((w) => {
      const globs = expand(S, w.inputs);
      return decide({ ...ctx, files, globs, lane: laneOf(w.file), newer: c.newer, tipMsg: c.tipMsg, landed: c.landed }).run;
    }).map((w) => w.file);
    assert.deepEqual(started, c.started, c.name);
    const gated = table.workflows.filter((w) => evalGuardIf(laneOf(w.file).if, ctx)).map((w) => w.file);
    assert.deepEqual(gated, c.gated, c.name);
    // the if: never skips a lane the guard would start (Lean start_gate)
    for (const f of started) assert.ok(gated.includes(f), `${c.name}: ${f}`);
  }
});

test('intent: every workflow guard carries the Lean `if:` and passes GUARD_TOKEN', () => {
  for (const w of table.workflows) {
    const lines = readFileSync(join(root, WF, w.file), 'utf8').split('\n');
    const g = readJobs(lines).find((j) => j.name === 'guard');
    const body = lines.slice(g.at, g.end);
    if (laneOf(w.file).if === '') assert.ok(!body.some((l) => /^ {4}if:/.test(l)), w.file); // a default lane: no if:
    else assert.equal(body[1], guardIf(laneOf(w.file)), w.file);
    assert.ok(body.some((l) => l.trim() === 'GUARD_TOKEN: ${{ github.token }}'), w.file);
  }
});

test('lint: a changed or removed guard if: and a missing GUARD_TOKEN are reported and restored', () => {
  const lane = laneOf('gate-gaps.yml');
  const changed = sample.replace(guardIf(lane), guardIf(laneOf('wktr.yml')));
  const r1 = reconcile('gate-gaps.yml', changed, row, paths, lane);
  assert.ok(r1.problems.some((p) => /guard's `if:` differs/.test(p)), r1.problems.join('\n'));
  assert.equal(reconcile('gate-gaps.yml', r1.text, row, paths, lane).problems.length, 0);
  const removed = sample.replace(`${guardIf(lane)}\n`, '').replace(/^ {10}GUARD_TOKEN: .*\n/m, '');
  const r2 = reconcile('gate-gaps.yml', removed, row, paths, lane);
  assert.ok(r2.problems.some((p) => /guard's `if:` differs/.test(p)), r2.problems.join('\n'));
  assert.ok(r2.problems.some((p) => /GUARD_TOKEN/.test(p)), r2.problems.join('\n'));
  assert.equal(r2.text, sample);
});

test('evalGuardIf: case-insensitive tokens; [ci:wktr-fixtures] does not request wktr; records always pass', () => {
  const wktr = laneOf('wktr.yml').if;
  const lean = laneOf('lean.yml').if;
  const ci = (msg) => ({ event: 'push', ref: 'refs/heads/ci/x', msg });
  assert.equal(evalGuardIf(wktr, ci('x [CI:WKTR]')), true);
  assert.equal(evalGuardIf(wktr, ci('x [ci:wktr-fixtures]')), false);
  assert.equal(evalGuardIf(wktr, ci('fix')), false);
  assert.equal(evalGuardIf(lean, ci('fix')), true);
  assert.equal(evalGuardIf(lean, ci('[ci:none]')), true); // round 2: lean is always wanted
  assert.equal(evalGuardIf(wktr, { event: 'push', ref: 'refs/heads/main', msg: '' }), true);
  assert.equal(evalGuardIf(wktr, { event: 'workflow_dispatch', ref: 'refs/heads/ci/x', msg: '' }), true);
});

// ---- ci-own-trigger round 2: gate vectors, job-level concurrency, decision steps, macOS flags ----
const gateLines = intent.gates ?? [];
const ifOf = (file) => {
  const lines = readFileSync(join(root, WF, file), 'utf8').split('\n');
  return readJobs(lines).find((j) => j.name === 'guard').ifText;
};

test('gate vectors: every workflow guard if:, as written, equals Lean `gate` on every event, ref and message', () => {
  assert.equal(gateLines.length, table.workflows.length);
  for (const gl of gateLines) {
    const expr = ifOf(gl.file);
    assert.ok(gl.rows.length >= 4 * 6, gl.file);
    for (const [event, ref, msg, want] of gl.rows) assert.equal(evalGuardIf(expr, { event, ref, msg }), want, `${gl.file} ${event} ${ref} ${msg}`);
  }
});

test('gate vectors: a changed if: text fails the vectors', () => {
  const gl = gateLines.find((g) => g.file === 'wktr.yml');
  const wrong = laneOf('wktr-fixtures.yml').if;
  assert.ok(gl.rows.some(([event, ref, msg, want]) => evalGuardIf(wrong, { event, ref, msg }) !== want));
});

test('job-level concurrency: no workflow-level group; every non-guard job carries the Lean group of its lane', () => {
  for (const w of table.workflows) {
    const lines = readFileSync(join(root, WF, w.file), 'utf8').split('\n');
    assert.ok(!lines.some((l) => /^concurrency:/.test(l)), w.file);
    for (const j of readJobs(lines).filter((x) => x.name !== 'guard')) {
      const want = jobConcurrency(laneOf(w.file), j.name);
      const k = lines.findIndex((l, i) => i > j.at && i < j.end && l === want[0]);
      assert.deepEqual(lines.slice(k, k + 3), want, `${w.file} ${j.name}`);
    }
    const g = readJobs(lines).find((x) => x.name === 'guard');
    assert.ok(!lines.slice(g.at, g.end).some((l) => /^ {4}concurrency:/.test(l)), `${w.file}: the guard never waits`);
  }
});

test('lint: a workflow-level concurrency block and a missing job group are reported and fixed', () => {
  const lane = laneOf('gate-gaps.yml');
  const bad = sample
    .replace('\njobs:\n', "\nconcurrency:\n  group: ${{ github.workflow }}-${{ github.ref }}\n  cancel-in-progress: true\n\njobs:\n")
    .replace(`${jobConcurrency(lane, 'judge').join('\n')}\n`, '');
  const r = reconcile('gate-gaps.yml', bad, row, paths, lane);
  assert.ok(r.problems.some((p) => /workflow-level `concurrency:`/.test(p)), r.problems.join('\n'));
  assert.ok(r.problems.some((p) => /job judge has no job-level concurrency/.test(p)), r.problems.join('\n'));
  assert.equal(r.text, sample);
});

test('decision steps: every guard shows decision: run / decision: skip right after the guard script (Lean decisionStep)', () => {
  assert.equal(intent.lanes.decision.run, 'decision: run');
  assert.equal(intent.lanes.decision.skip, 'decision: skip');
  for (const w of table.workflows) {
    const text = readFileSync(join(root, WF, w.file), 'utf8');
    assert.ok(text.includes(`.mjs --workflow ${WF}/${w.file}\n      - name: 'decision: run'\n`), w.file);
    assert.ok(text.includes("      - name: 'decision: skip: ${{ steps.g.outputs.reason }}'\n        if: steps.g.outputs.run != 'true'\n"), w.file);
  }
  const lane = laneOf('gate-gaps.yml');
  const r = reconcile('gate-gaps.yml', sample.replace("      - name: 'decision: run'\n        if: steps.g.outputs.run == 'true'\n        run: 'true'\n", ''), row, paths, lane);
  assert.ok(r.problems.some((p) => /decision steps differ/.test(p)), r.problems.join('\n'));
  assert.equal(r.text, sample);
});

test('macOS: the Lean flag of every lane equals "some push job runs on macos-* / xcode-*" in its workflow', () => {
  for (const w of table.workflows) {
    const lines = readFileSync(join(root, WF, w.file), 'utf8').split('\n');
    assert.equal(macosJobs(readJobs(lines)).length > 0, laneOf(w.file).macos === true, w.file);
  }
  assert.ok(dispatchOnly("${{ needs.guard.outputs.run == 'true' && github.event_name == 'workflow_dispatch' && inputs.macos }}"));
  assert.ok(!dispatchOnly("${{ github.event_name == 'workflow_dispatch' && inputs.x || true }}"));
});

test('lint: a macOS job in a lane Lean calls Linux-only fails the check (no --write fix)', () => {
  const lane = laneOf('gate-gaps.yml');
  assert.equal(lane.macos, false);
  const bad = sample.replace(/(\n  judge:\n(?: {4}.*\n)*? {4}runs-on: )ubuntu-24\.04-arm/, '$1macos-26');
  assert.notEqual(bad, sample);
  const r = reconcile('gate-gaps.yml', bad, row, paths, lane);
  assert.ok(r.problems.some((p) => /macos=false in Lean/.test(p)), r.problems.join('\n'));
});

test('status functions: a job that runs after skipped needs must keep a guard conjunct', () => {
  assert.ok(unsafeStatusIf('${{ always() }}'));
  assert.ok(!unsafeStatusIf("${{ always() && needs.fwcore.result == 'success' }}"));
  assert.ok(!unsafeStatusIf("${{ !cancelled() && needs.guard.outputs.run == 'true' }}"));
  assert.ok(!unsafeStatusIf("${{ needs.guard.outputs.run == 'true' }}"));
});
