// Tests of scripts/ci-paths.mjs: the workflows equal the Lean decision, the Lean replay cases hold under GitHub's own glob
// reading (an independent matcher), and the lint fails on each way the trigger can drift.
import assert from 'node:assert/strict';
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { decide, loadIntent, matches, preciseInputs } from '../.github/scripts/changed-inputs.mjs';
import { capProblems, coarseMap, coneOf, coneProblems, loadCaps, dispatchOnly, expand, guardIf, jobConcurrency, LAKE_GEN, leanInputGaps, leanInputProblems, leanScriptPaths, recheckSteps, withConj, macosJobs, unsafeStatusIf, lakeGenProblems, lakeImportFacts, lakeJobs, lakeTargetsOf, loadGolden, portableGlob, withNotMain, notMainIf, carriesNotMain, cacheWriters, guardComment, readJobs, readLakefile, reconcile, renderPush, run, setMapFor, setupLeanJobs, unguarded, nodePinProblems, jobFacts, jobProblems, pinValueProblems, rowProblems, copyProblems, nodePinRefusal, runNameProblems } from './ci-paths.mjs';

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
  assert.deepEqual(setupLeanJobs(lean), [{ job: 'lean', save: 'true' }]);
  // `lake build` = the lakefile defaults; `lake test` runs `fwcore fwtest`, a default target (task lean-bin-slim)
  assert.deepEqual(by('lean.yml/lean').targets, readLakefile(root).defaults);
  // a site build reaches `lake exe breakgen` through pnpm -> package.json -> scripts/check-breakpoints.mjs (spawnSync)
  for (const k of ['webkit-sim.yml/site', 'visual-diff.yml/site', 'breakpoint-gate.yml/site']) assert.deepEqual(by(k)?.targets, ['breakgen'], k);
  assert.deepEqual(by('webkit-sim.yml/fwcore')?.targets, ['fwcore']);
  // mutants.sh: `lake build $LIBS fwcore` with LIBS="Fw FwTest.Mutants.Kill"; `$mod` (no literal) is skipped
  assert.ok(['Fw', 'FwTest.Mutants.Kill', 'fwcore'].every((t) => by('mutants.yml/shard').targets.includes(t)));
  assert.deepEqual(lakeImportFacts(root, rows), [['FwTest.Mutants.Kill', 'fwcore']]);
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

test('Lean replay cases: the coarse cone globs (a main push, read by the guard) pass exactly `filtered`, a superset of `started`', () => {
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
const pushLine = renderPush(row.branches)[1];

test('lint: a paths list under on.push is reported and removed (round 3: every push creates a run)', () => {
  assert.ok(!/^ {4}paths:/m.test(sample));
  const bad = sample.replace(`${pushLine}\n`, `${pushLine}\n    paths:\n      - 'extra/**'\n`);
  assert.notEqual(bad, sample);
  const r = reconcile('gate-gaps.yml', bad, row);
  assert.ok(r.problems.some((p) => /on\.push differs/.test(p)), r.problems.join('\n'));
  assert.equal(reconcile('gate-gaps.yml', r.text, row).problems.length, 0);
});

test('lint: a branches change is reported', () => {
  const bad = sample.replace(pushLine, "    branches: ['**']");
  assert.notEqual(bad, sample);
  assert.ok(reconcile('gate-gaps.yml', bad, row).problems.some((p) => /on\.push differs/.test(p)));
});

test('lint: a removed guard is reported and restored', () => {
  const lines = sample.split('\n');
  const jobs = readJobs(lines);
  const g = jobs.find((j) => j.name === 'guard');
  const noGuard = [...lines.slice(0, g.at), ...lines.slice(g.end)].join('\n').replace(/^ {4}needs: \[guard\]\n {4}if: .*\n/gm, '');
  const r = reconcile('gate-gaps.yml', noGuard, row);
  assert.ok(r.problems.some((p) => /no `guard` job/.test(p)), r.problems.join('\n'));
  assert.deepEqual(unguarded(readJobs(r.text.split('\n'))), []);
});

test('lint: a new root job that does not wait for the guard is reported', () => {
  const bad = `${sample.trimEnd()}\n\n  extra:\n    runs-on: ubuntu-24.04-arm\n    steps:\n      - run: echo hi\n`;
  const r = reconcile('gate-gaps.yml', bad, row);
  assert.ok(r.problems.some((p) => /job extra does not wait for guard/.test(p)), r.problems.join('\n'));
  assert.deepEqual(unguarded(readJobs(r.text.split('\n'))), []);
});

const goldenLines = readFileSync(join(root, 'packages/contracts/golden/ci/triggers.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));

test('main pushes: only the seeders\' workflows list main, and the cache writers equal Lean cacheWriters', () => {
  const seedFiles = [...new Set(table.seeders.map((s) => s.file))].sort();
  assert.deepEqual(table.workflows.filter((w) => w.branches.includes('main')).map((w) => w.file).sort(), seedFiles);
  assert.deepEqual(cacheWriters(root), table.cacheWriters.map((w) => `${w.file}/${w.job}/${w.cache}`).sort());
  for (const s of table.seeders) assert.ok(table.cacheWriters.some((w) => w.file === s.file && w.job === s.job), `${s.file}/${s.job} saves no cache`);
  for (const w of table.workflows) {
    assert.ok(w.branches.filter((b) => b !== 'main').every((b) => b.startsWith('ci/')), w.file);
    assert.deepEqual(w.crons, [], w.file);
  }
});

test('Lean golden if forms: notMainIf equals Lean withNotMain, carriesNotMain equals Lean carriesNotMain', () => {
  const forms = goldenLines.filter((l) => l.kind === 'ifForm');
  const checks = goldenLines.filter((l) => l.kind === 'ifCheck');
  assert.ok(forms.length >= 5 && checks.length >= 5);
  for (const f of forms) {
    assert.equal(notMainIf(f.orig, table.notMainPush), f.emitted, String(f.orig));
    assert.equal(carriesNotMain(f.emitted, table.notMainPush), f.carries, f.emitted);
  }
  for (const c of checks) assert.equal(carriesNotMain(c.text, table.notMainPush), c.carries, c.text);
});

test('withNotMain: `a || b` is grouped before the conjunct; `(x) || true` and a bare `&&` suffix are refused', () => {
  const x = 'x';
  assert.equal(withNotMain('${{ a || b }}', x), '${{ (a || b) && (x) }}');
  assert.ok(carriesNotMain(withNotMain('${{ a || b }}', x), x));
  assert.ok(!carriesNotMain('${{ (x) || true }}', x));
  assert.ok(!carriesNotMain('${{ a || b && (x) }}', x));
  assert.ok(!carriesNotMain('${{ (a) || (b) && (x) }}', x));
  assert.equal(withNotMain('${{ (x) || true }}', x), '${{ ((x) || true) && (x) }}');
  assert.equal(withNotMain('${{ (a) && (x) }}', x), '${{ (a) && (x) }}');
  assert.equal(withNotMain('', x), '${{ (x) }}');
});

test('lint: a non-seeder job of a main workflow without the notMainPush form is reported and fixed', () => {
  const pt = readFileSync(join(root, WF, 'premise-tests.yml'), 'utf8');
  const ptRow = table.workflows.find((w) => w.file === 'premise-tests.yml');
  const intent = loadIntent(root).lanes;
  const lane = { ...intent.lanes.find((l) => l.file === 'premise-tests.yml'), decision: intent.decision, recheck: intent.recheck };
  const main = { jobs: ['engine'], conj: table.notMainPush };
  const good = `  verdict:\n    if: \${{ (${table.notMainPush}) }}\n`;
  assert.ok(pt.includes(good));
  for (const bad of ['  verdict:\n', `  verdict:\n    if: \${{ true || (${table.notMainPush}) }}\n`]) {
    const r = reconcile('premise-tests.yml', pt.replace(good, bad), ptRow, lane, main);
    assert.ok(r.problems.some((p) => /verdict would run on a main push/.test(p)), r.problems.join('\n'));
    assert.ok(reconcile('premise-tests.yml', r.text, ptRow, lane, main).problems.length === 0);
  }
  assert.equal(reconcile('premise-tests.yml', pt.replace(good, '  verdict:\n'), ptRow, lane, main).text, pt);
  assert.deepEqual(reconcile('premise-tests.yml', pt, ptRow, lane, main).problems, []);
  const seederSkips = reconcile('premise-tests.yml', pt, ptRow, lane, { ...main, jobs: ['engine', 'verdict'] });
  assert.ok(seederSkips.problems.some((p) => /is a seeder .* skips a main push/.test(p)), seederSkips.problems.join('\n'));
});

test('lint: a schedule is reported and removed (Lean no_crons: a schedule runs on main)', () => {
  const bad = sample.replace(`${pushLine}\n`, `${pushLine}\n  schedule:\n    - cron: '23 4 * * *'\n`);
  assert.notEqual(bad, sample);
  const r = reconcile('gate-gaps.yml', bad, row);
  assert.ok(r.problems.some((p) => /on\.schedule differs/.test(p)), r.problems.join('\n'));
  assert.equal(r.text, sample);
});

test('lint: every on: key outside the Lean onKeys allowlist is reported (schedule in any spelling, workflow_run)', () => {
  assert.deepEqual(row.onKeys, ['push', 'workflow_dispatch']);
  const variants = {
    flow: `  schedule: [{cron: '0 0 * * *'}]\n`,
    comment: `  schedule: # nightly\n    - cron: '0 0 * * *'\n`,
    spaced: `  schedule :\n    - cron: '0 0 * * *'\n`,
    quoted: `  "schedule":\n    - cron: '0 0 * * *'\n`,
    workflowRun: `  workflow_run: {workflows: [lean]}\n`,
    pullRequest: `  pull_request:\n`,
  };
  for (const [name, add] of Object.entries(variants)) {
    const bad = sample.replace(`${pushLine}\n`, `${pushLine}\n${add}`);
    assert.notEqual(bad, sample, name);
    const key = name === 'workflowRun' ? 'workflow_run' : name === 'pullRequest' ? 'pull_request' : 'schedule';
    const r = reconcile('gate-gaps.yml', bad, row);
    assert.ok(r.problems.some((p) => p.includes(`on.${key} is not an allowed trigger`)), `${name}: ${r.problems.join('\n')}`);
  }
  const odd = reconcile('gate-gaps.yml', sample.replace(`${pushLine}\n`, `${pushLine}\n  <<: *triggers\n`), row);
  assert.ok(odd.problems.some((p) => /is no key at indent 2/.test(p)), odd.problems.join('\n'));
  assert.deepEqual(reconcile('gate-gaps.yml', sample, row).problems, []);
  assert.deepEqual(reconcile('gate-gaps.yml', sample, { ...row, onKeys: undefined }).problems.length, 1);
});

test('lint: schedule is allowed only when the Lean row has a cron', () => {
  const cron = '23 4 * * *';
  const withCron = { ...row, crons: [cron], onKeys: ['push', 'workflow_dispatch', 'schedule'] };
  const scheduled = sample.replace(`${pushLine}\n`, `${pushLine}\n  schedule:\n    - cron: '${cron}'\n`);
  assert.deepEqual(reconcile('gate-gaps.yml', scheduled, withCron).problems, []);
});

test('the guard comment names main only where the row lists main', () => {
  assert.ok(guardComment({ branches: ['ci/**', 'main'] }).join('\n').includes('only the cache seeders'));
  assert.ok(guardComment({ branches: ['ci/**'] }).join('\n').includes('A main push starts no run'));
  assert.ok(!guardComment({ branches: ['ci/**'] }).join('\n').includes('schedule'));
});

test('renderPush writes the branches and no paths', () => {
  assert.deepEqual(renderPush(['ci/**', 'main']), ['  push:', "    branches: ['ci/**', main]"]);
});

// ---- task ci-own-trigger: the Lean intent golden (lean/Fw/Ci/Intent.lean) ----
const intent = loadIntent(root);
const laneOf = (file) => ({ ...intent.lanes.lanes.find((l) => l.file === file), prefix: intent.lanes.prefix,
  decision: intent.lanes.decision, recheck: intent.lanes.recheck });

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

test('intent replay: JS decide over the Lean cases gives every Lean decision tag, the generated if: gates exactly `gate`', () => {
  assert.ok(intent.cases.length >= 20);
  assert.deepEqual(intent.lanes.skips, ['unwanted', 'stale', 'landed', 'unchanged']);
  const coarse = coarseMap(table);
  for (const c of intent.cases) {
    const S = (g) => (table.sets[g] ?? [g]).flatMap((h) => (h.startsWith('@cone:') ? (c.cones[h.slice(6)] ?? []) : [h]));
    // a ci push decides on the branch files that differ from main (Lean `effective`); a main push on its own diff
    const files = c.event === 'ci' ? c.diff.filter((f) => !c.merged.includes(f)) : c.diff;
    const ctx = {
      event: c.event === 'record' ? 'workflow_dispatch' : 'push',
      ref: c.event === 'ci' ? 'refs/heads/ci/x' : 'refs/heads/main',
      msg: c.msg,
    };
    const tags = {};
    for (const w of table.workflows) {
      const r = decide({ ...ctx, files, globs: expand(S, w.inputs), pushGlobs: expand(coarse, w.inputs), lane: laneOf(w.file), tip: c.tip, landed: c.landed });
      tags[w.file] = r.run ? 'run' : r.reason.split(':')[0];
    }
    assert.deepEqual(tags, c.decisions, c.name);
    const started = table.workflows.filter((w) => tags[w.file] === 'run').map((w) => w.file);
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
  const r1 = reconcile('gate-gaps.yml', changed, row, lane);
  assert.ok(r1.problems.some((p) => /guard's `if:` differs/.test(p)), r1.problems.join('\n'));
  assert.equal(reconcile('gate-gaps.yml', r1.text, row, lane).problems.length, 0);
  const removed = sample.replace(`${guardIf(lane)}\n`, '').replace(/^ {10}GUARD_TOKEN: .*\n/m, '');
  const r2 = reconcile('gate-gaps.yml', removed, row, lane);
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
      assert.deepEqual(lines.slice(k, k + want.length), want, `${w.file} ${j.name}`);
      assert.ok(!lines.slice(j.at, j.end).some((l) => /cancel-in-progress/.test(l)), `${w.file} ${j.name}: no cancel (Lean ci_never_cancelled)`);
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
  const r = reconcile('gate-gaps.yml', bad, row, lane);
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
  const r = reconcile('gate-gaps.yml', sample.replace("      - name: 'decision: run'\n        if: steps.g.outputs.run == 'true'\n        run: 'true'\n", ''), row, lane);
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
  const r = reconcile('gate-gaps.yml', bad, row, lane);
  assert.ok(r.problems.some((p) => /macos=false in Lean/.test(p)), r.problems.join('\n'));
});

// ---- ci-own-trigger round 3: the tip re-check of every heavy job (Lean stale_never_works) ----
test('tip re-check: every non-guard job with steps starts with the Lean re-check; every status-function step has the conjunct', () => {
  const rc = intent.lanes.recheck;
  assert.equal(rc.tipName, 'tip re-check');
  assert.ok(rc.staleName.startsWith('stale:'));
  assert.equal(rc.conj, "steps.stale.outcome == 'skipped'");
  let jobs = 0;
  for (const w of table.workflows) {
    const lines = readFileSync(join(root, WF, w.file), 'utf8').split('\n');
    for (const j of readJobs(lines).filter((x) => x.name !== 'guard')) {
      const k = lines.findIndex((l, i) => i > j.at && i < j.end && l === '    steps:');
      if (k < 0) continue;
      jobs++;
      const want = recheckSteps(rc);
      assert.deepEqual(lines.slice(k + 1, k + 1 + want.length), want, `${w.file} ${j.name}`);
      for (const l of lines.slice(j.at, j.end)) {
        if (/^ {8}if:.*(always|cancelled|failure)\(\)/.test(l)) assert.ok(l.includes(rc.conj), `${w.file} ${j.name}: ${l}`);
      }
    }
    const g = readJobs(lines).find((x) => x.name === 'guard');
    assert.ok(!lines.slice(g.at, g.end).some((l) => l.includes(rc.tipName)), `${w.file}: the guard checks the tip in its script`);
  }
  assert.ok(jobs >= table.workflows.length, `${jobs} jobs`);
});

test('lint: a removed tip re-check and a status step without the conjunct are reported and restored', () => {
  const lane = laneOf('gate-gaps.yml');
  const want = recheckSteps(lane.recheck).join('\n');
  assert.ok(sample.includes(want));
  const conjIf = `if: \${{ (always()) && ${lane.recheck.conj} }}`;
  assert.ok(sample.includes(conjIf));
  const bad = sample.replace(`${want}\n`, '').replace(conjIf, 'if: ${{ always() }}');
  const r = reconcile('gate-gaps.yml', bad, row, lane);
  assert.ok(r.problems.some((p) => /first steps differ from the Lean tip re-check/.test(p)), r.problems.join('\n'));
  assert.ok(r.problems.some((p) => /lacks `steps\.stale\.outcome/.test(p)), r.problems.join('\n'));
  assert.equal(r.text, sample);
  assert.equal(withConj('${{ !cancelled() }}', 'C'), '${{ (!cancelled()) && C }}');
  assert.equal(withConj('failure()', 'C'), '${{ (failure()) && C }}');
  assert.equal(withConj("${{ inputs.x == 'y' }}", 'C'), "${{ inputs.x == 'y' }}");
  assert.equal(withConj('${{ (always()) && C }}', 'C'), '${{ (always()) && C }}');
});

test('status functions: a job that runs after skipped needs must keep a guard conjunct', () => {
  assert.ok(unsafeStatusIf('${{ always() }}'));
  assert.ok(!unsafeStatusIf("${{ always() && needs.fwcore.result == 'success' }}"));
  assert.ok(!unsafeStatusIf("${{ !cancelled() && needs.guard.outputs.run == 'true' }}"));
  assert.ok(!unsafeStatusIf("${{ needs.guard.outputs.run == 'true' }}"));
});

test('lean inputs: every ../ path a lean/scripts/*.sh reads is an input of the lean.yml row (round 4)', () => {
  assert.deepEqual(leanInputProblems(root, table), []);
  assert.deepEqual(leanInputGaps(root, table), []);
  assert.deepEqual(leanScriptPaths(". ../scripts/span.sh\nsh -c 'sh ../scripts/fwcore-build.sh && x' ../a/$b ../\n"),
    ['scripts/span.sh', 'scripts/fwcore-build.sh', null, null]);
});

test('lint: a lean script reading a file outside the lean.yml row fails the check', () => {
  const dir = mkdtempSync(join(tmpdir(), 'ci-paths-lean-'));
  try {
    mkdirSync(join(dir, 'lean', 'scripts'), { recursive: true });
    writeFileSync(join(dir, 'lean', 'scripts', 'check.sh'), '. ../scripts/span.sh\nx --check ../apps/site/src/new.gen.json\n');
    const t = { sets: {}, workflows: [{ file: 'lean.yml', inputs: ['lean/**', 'scripts/span.sh'] }] };
    const ps = leanInputProblems(dir, t);
    assert.equal(ps.length, 1);
    assert.match(ps[0], /reads \.\.\/apps\/site\/src\/new\.gen\.json, which is not an input/);
    assert.deepEqual(leanInputGaps(dir, t), [{ script: 'lean/scripts/check.sh', path: 'apps/site/src/new.gen.json' }]);
    assert.deepEqual(leanInputProblems(dir, { sets: {}, workflows: [] }).length, 1);
    assert.equal(leanInputGaps(dir, { sets: {}, workflows: [] }).length, 2);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('preview-e2e.yml: a change inside its read set selects it, a change outside does not (task preview-e2e)', () => {
  const inputs = preciseInputs(root, 'preview-e2e.yml');
  assert.ok(inputs, 'the workflow has a Lean row');
  for (const f of ['packages/e2e-preview/src/suite.mjs', 'packages/e2e-preview/fixture/site/index.html', 'apps/console-api/src/preview/proxy.ts',
    'apps/console-api/src/app.ts', 'apps/console-api/src/cap/cap.ts', 'apps/console-api/src/ops/routes.ts', 'packages/contracts/src/index.ts', 'packages/contracts/package.json',
    'lean/Fw/Console/PreviewOwner.lean', 'lean/Fw/Console/Preview.lean', 'lean/Fw/Wire/Console.lean',
    'packages/contracts/golden/console/preview-owner.jsonl', '.github/workflows/preview-e2e.yml']) {
    assert.ok(matches(inputs, f), `${f} selects the lane`);
  }
  for (const f of ['apps/console-web/src/main.tsx', 'apps/site/src/index.ts', 'packages/measure-chromium/src/a.mjs', 'docs/team/handoffs/x.md',
    'apps/console-api/test/app.test.ts', 'lean/FwTest/Lease.lean', '.github/workflows/premise-tests.yml']) {
    assert.ok(!matches(inputs, f), `${f} does not select the lane`);
  }
});

// ---- pool-caps: macOS job timeouts equal the Lean caps (Fw.Ci.Pool.Caps, golden/ci/pool-caps.jsonl) ----

const capTable = loadCaps(root);
const capRows = readFileSync(join(root, 'packages/contracts/golden/ci/pool-caps.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));

test('pool caps: each listed macOS job has timeout-minutes equal to its Lean cap; webkit-sim is excluded', () => {
  assert.deepEqual([...capTable.caps], [['wktr.yml wktr', 16], ['wktr-fixtures.yml fixtures', 21], ['sim-speed.yml probe', 17],
    ['engine-premises.yml webkit', 8], ['gate-gaps.yml collect-macos', 26], ['trajectory-probe.yml probe-apple', 15],
    ['smoothness.yml webkit-mac', 15], ['smoothness.yml webkit-sim', 45]]);
  assert.deepEqual([...capTable.excluded], ['path-pix.yml', 'toolbar-throttle.yml', 'webkit-sim.yml', 'chrome-crash-probe.yml', 'font-fidelity.yml']);
  for (const [key, cap] of capTable.caps) {
    const [file, job] = key.split(' ');
    const lines = readFileSync(join(root, WF, file), 'utf8').split('\n');
    const j = readJobs(lines).find((x) => x.name === job);
    assert.ok(j && /^(macos-|xcode-)/.test(j.runsOn), key);
    assert.ok(lines.slice(j.at, j.end).includes(`    timeout-minutes: ${cap}`), key);
  }
});

test('pool caps: every cap is at least 1.3 x its p90 and the least such minute; the golden holds capMin 289 = 38', () => {
  for (const r of capRows.filter((x) => x.kind !== 'excluded')) {
    assert.ok(13 * r.p90dm <= 100 * r.capMin && 100 * r.capMin < 13 * r.p90dm + 100, JSON.stringify(r));
    assert.ok(r.p90dm <= 10 * r.capMin);
  }
  assert.ok(capRows.some((r) => r.kind === 'vector' && r.p90dm === 289 && r.capMin === 38));
  assert.deepEqual(capRows.filter((r) => r.kind === 'cap' && r.thin).map((r) => [r.lane, r.n]), [['gate-gaps', 3], ['trajectory-probe', 4], ['smoothness-webkit-mac', 3], ['smoothness-webkit-sim', 3]]);
});

test('lint: a drifted or missing cap timeout is reported and set back by --write', () => {
  const text = readFileSync(join(root, WF, 'wktr.yml'), 'utf8');
  const drift = text.replace(/(\n {2}wktr:\n(?: {4}.*\n)*? {4}timeout-minutes: )16\n/, '$160\n');
  assert.notEqual(drift, text);
  const r = capProblems('wktr.yml', drift, capTable);
  assert.deepEqual(r.problems, ['wktr.yml: macOS job wktr has timeout-minutes 60; the Lean cap is 16']);
  assert.equal(r.text, text);
  const gone = text.replace(/(\n {2}wktr:\n(?: {4}.*\n)*?) {4}timeout-minutes: 16\n/, '$1');
  assert.notEqual(gone, text);
  const g = capProblems('wktr.yml', gone, capTable);
  assert.deepEqual(g.problems, ['wktr.yml: macOS job wktr has no timeout-minutes; the Lean cap is 16']);
  assert.equal(g.text, text);
  assert.deepEqual(capProblems('wktr.yml', text, capTable).problems, []);
});

test('lint: a macOS job without a Lean cap, a cap on a Linux job and a cap on a missing job fail with no --write fix', () => {
  const mac = sample.replace(/(\n {2}judge:\n(?: {4}.*\n)*? {4}runs-on: )ubuntu-24\.04-arm/, '$1macos-26');
  assert.notEqual(mac, sample);
  assert.ok(capProblems('gate-gaps.yml', mac, capTable).problems.some((p) => /macOS job judge has no Lean cap/.test(p)));
  const linux = sample.replace(/(\n {2}collect-macos:\n(?: {4}.*\n)*? {4}runs-on: )xcode-27/, '$1ubuntu-24.04-arm');
  assert.notEqual(linux, sample);
  assert.ok(capProblems('gate-gaps.yml', linux, capTable).problems.some((p) => /collect-macos has a Lean cap but does not run on macOS/.test(p)));
  const renamed = sample.replace('\n  collect-macos:\n', '\n  collect-mac:\n');
  assert.ok(capProblems('gate-gaps.yml', renamed, capTable).problems.some((p) => /Lean cap for job collect-macos, but the workflow has no such job/.test(p)));
  const sim = readFileSync(join(root, WF, 'webkit-sim.yml'), 'utf8');
  assert.deepEqual(capProblems('webkit-sim.yml', sim, capTable).problems, []);
});

test('node pin: the repo pins one exact Node >= 24.22.0 and every Node lane lists it (task node-pin)', () => {
  assert.deepEqual(nodePinProblems(root, table), []);
  assert.match(readFileSync(join(root, '.node-version'), 'utf8').trim(), /^24\.(2[2-9]|[3-9]\d)\.\d+$/);
});

test('node pin golden: the TS twins decide exactly as Lean (Fw.Ci.Trigger pinValueProblems, jobProblems, rowProblems, copyProblems)', () => {
  const g = (k) => goldenLines.filter((l) => l.kind === k);
  assert.ok(g('pinValue').length >= 10 && g('pinJob').length >= 6 && g('pinRow').length >= 4 && g('pinCopies').length >= 3);
  for (const l of g('pinValue')) assert.deepEqual(pinValueProblems(l.pin), l.problems, `pin ${JSON.stringify(l.pin)}`);
  for (const l of g('pinJob')) assert.deepEqual(jobProblems(l), l.problems, JSON.stringify(l));
  assert.ok(g('pinGuard').length >= 8 && g('pinJob').some((l) => l.nodeBeforeSetup));
  for (const l of g('pinGuard')) assert.equal(nodePinRefusal(l.running, l.pinned), l.refusal, JSON.stringify(l));
  for (const l of g('pinRow')) assert.deepEqual(rowProblems(l.usesNode, l.row), l.problems, JSON.stringify(l));
  for (const l of g('pinCopies')) assert.deepEqual(copyProblems(l.pin, l.copies.map((c) => [c.name, c.value])), l.problems, JSON.stringify(l));
});

test('node pin facts: the reader sees block, quoted and flow-map setup-node steps and the commands a job runs', () => {
  const f = (text) => jobFacts(text.split('\n'));
  const block = f('  a:\n    steps:\n      - uses: actions/setup-node@abc # v7\n        with:\n          node-version-file: .node-version\n      - run: node x.mjs');
  assert.deepEqual([block.setups, block.versionKey, block.runsNode], [['.node-version'], false, true]);
  assert.deepEqual(f("  a:\n    steps:\n      - uses: 'actions/setup-node@abc'\n        with:\n          node-version-file: '.node-version'").setups, ['.node-version']);
  assert.deepEqual(f('  a:\n    steps:\n      - { uses: actions/setup-node@abc, with: { node-version-file: .node-version } }').setups, ['.node-version']);
  assert.deepEqual(f('  a:\n    steps:\n      - { uses: "actions/setup-node@abc", with: { node-version: 24 } }').setups, ['']);
  assert.equal(f('  a:\n    steps:\n      - { uses: "actions/setup-node@abc", with: { "node-version": 24 } }').versionKey, true);
  assert.deepEqual(f("  a:\n    steps:\n      - uses: actions/setup-node@abc\n        with:\n          node-version-file: 'package.json'").setups, ['package.json']);
  assert.deepEqual(f("  a:\n    steps:\n      - with:\n          node-version-file: package.json\n        uses: actions/setup-node@abc").setups, ['package.json'], 'uses after with');
  assert.equal(f('  a:\n    steps:\n      - run: |\n          echo hi\n          pnpm install').runsNode, true);
  assert.equal(f('  a:\n    steps:\n      - run: "cd x && node y"').runsNode, true);
  assert.equal(f('  a:\n    steps:\n      - run: echo node is fine\n      # run: node x').runsNode, false);
  assert.equal(f('  a:\n    steps:\n      - uses: ./.github/actions/setup-pnpm\n      - run: pnpm test').pnpmAction, true);
  const order = (a, b) => f(`  a:\n    steps:\n      - ${a}\n      - ${b}`).nodeBeforeSetup;
  assert.equal(order('run: node x.mjs', 'uses: actions/setup-node@abc'), true, 'node before setup-node');
  assert.equal(order('run: pnpm test', 'uses: ./.github/actions/setup-pnpm'), true, 'pnpm before setup-pnpm');
  assert.equal(order('uses: actions/setup-node@abc', 'run: node x.mjs'), false, 'setup first');
  assert.equal(order('run: echo hi', 'uses: actions/setup-node@abc'), false, 'no node before setup');
  assert.equal(jobFacts('  a:\n    steps:\n      - uses: ./.github/actions/telemetry\n      - uses: actions/setup-node@abc'.split('\n'), ['telemetry']).nodeBeforeSetup, true, 'telemetry before setup is not exempt');
  assert.equal(jobFacts('  a:\n    steps:\n      - uses: ./.github/actions/gate-engine\n      - uses: actions/setup-node@abc'.split('\n'), ['gate-engine']).nodeBeforeSetup, true, 'another node action is not');
});

test('node pin lint: floating version, wrong file, old pin, a copy that differs, no setup, and a row missing or without the file each fail', () => {
  const dir = mkdtempSync(join(tmpdir(), 'ci-paths-node-'));
  const put = (rel, text) => { mkdirSync(dirname(join(dir, rel)), { recursive: true }); writeFileSync(join(dir, rel), text); };
  const wf = (w) => `jobs:\n  a:\n    steps:\n      - uses: actions/setup-node@abc # v7\n        with:\n          ${w}\n`;
  const t = (inputs, file = 'x.yml') => ({ sets: {}, workflows: inputs === null ? [] : [{ file, inputs }] });
  const ACT = WF.replace('workflows', 'actions');
  const problems = (tbl) => nodePinProblems(dir, tbl);
  try {
    put('.node-version', '24.22.0\n');
    put('.nvmrc', '24.22.0\n');
    put('.npmrc', 'engine-strict=true\n');
    put('package.json', JSON.stringify({ engines: { node: '24.22.0' } }));
    put('pnpm-workspace.yaml', 'packages:\n  - "apps/*"\nuseNodeVersion: 24.22.0\n');
    put(`${WF}/x.yml`, wf('node-version-file: .node-version'));
    assert.deepEqual(problems(t(['.node-version'])), []);
    assert.equal(problems(t(['apps/**'])).length, 1, 'row without the file');
    assert.ok(problems(t(null)).some((p) => /has no row in the Lean table/.test(p)), 'a workflow with no Lean row is a problem');
    put(`${WF}/x.yml`, wf("node-version: '24'"));
    assert.ok(problems(t(['.node-version'])).some((p) => /sets node-version/.test(p)), 'floating');
    put(`${WF}/x.yml`, wf('node-version-file: package.json'));
    assert.ok(problems(t(['.node-version'])).some((p) => /is not \.node-version/.test(p)), 'other file');
    put(`${WF}/x.yml`, "jobs:\n  a:\n    steps:\n      - { uses: 'actions/setup-node@abc', with: { node-version-file: package.json } }\n");
    assert.ok(problems(t(['.node-version'])).some((p) => /is not \.node-version/.test(p)), 'flow-map form');
    put(`${WF}/x.yml`, 'jobs:\n  a:\n    steps:\n      - run: node x.mjs\n');
    assert.ok(problems(t(['.node-version'])).some((p) => /job a: runs node.*no setup-node/.test(p)), 'node without setup');
    put(`${WF}/x.yml`, 'jobs:\n  a:\n    steps:\n      - uses: ./.github/actions/setup-pnpm\n      - run: pnpm test\n');
    assert.deepEqual(problems(t(['.node-version'])), [], 'the setup-pnpm action counts as the setup');
    put(`${WF}/x.yml`, wf('node-version-file: .node-version'));
    put(`${ACT}/y/action.yml`, 'runs:\n  steps:\n    - uses: actions/setup-node@abc\n      with:\n        node-version: 24.22.0\n');
    assert.ok(problems(t(['.node-version'])).some((p) => /actions\/y/.test(p)), 'action drift');
    rmSync(join(dir, ACT), { recursive: true });
    put('.nvmrc', '24.21.0\n');
    assert.ok(problems(t(['.node-version'])).some((p) => /^\.nvmrc: must equal/.test(p)), '.nvmrc differs');
    put('.nvmrc', '24.22.0\n');
    put('package.json', JSON.stringify({ engines: { node: '>=24' } }));
    assert.ok(problems(t(['.node-version'])).some((p) => /engines\.node: must equal/.test(p)), 'engines differs');
    put('package.json', JSON.stringify({ engines: { node: '24.22.0' } }));
    put('pnpm-workspace.yaml', 'packages: []\n');
    assert.ok(problems(t(['.node-version'])).some((p) => /useNodeVersion: must equal/.test(p)), 'pnpm setting missing');
    put('pnpm-workspace.yaml', 'useNodeVersion: 24.22.0\n');
    put('.npmrc', '');
    assert.ok(problems(t(['.node-version'])).some((p) => /engine-strict/.test(p)), 'engine-strict');
    put('.npmrc', 'engine-strict=true\n');
    put('.node-version', '24.21.0\n');
    assert.ok(problems(t(['.node-version'])).some((p) => /older than/.test(p)), 'old');
    put('.node-version', '24\n');
    assert.ok(problems(t(['.node-version'])).some((p) => /exact version/.test(p)), 'floating file');
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

/** A line without its trailing comment: a `#` at the line start or after whitespace, outside single and double quotes.
 *  Limit: the quote state restarts on each line, so a lone apostrophe (shell text such as `don't`) hides a later comment,
 *  which then still counts its paths: the scan errs towards naming too many scripts, never too few. */
export function stripComment(line) {
  let q = '';
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (q) { if (c === q) q = ''; continue; }
    if (c === '"' || c === "'") q = c;
    else if (c === '#' && (i === 0 || /\s/.test(line[i - 1]))) return line.slice(0, i);
  }
  return line;
}

/** The `.github/scripts/*` paths a workflow text runs or reads (comment text left out). */
export function scriptsNamed(text) {
  const code = text.split('\n').map(stripComment).join('\n');
  return [...new Set(code.match(/\.github\/scripts\/[A-Za-z0-9._-]+/g) ?? [])].sort();
}

test('scripts a workflow runs: every .github/scripts/* path named in a workflow is an input of its Lean row', () => {
  const S = setMapFor(root, table);
  let seen = 0;
  for (const w of table.workflows) {
    const named = scriptsNamed(readFileSync(join(root, WF, w.file), 'utf8'));
    seen += named.length;
    const globs = expand(S, w.inputs);
    for (const f of named) assert.ok(matches(globs, f), `${w.file} runs ${f}, which is not in its Lean inputs (lean/Fw/Ci/Trigger.lean): a push changing only it would skip the lane`);
  }
  assert.ok(seen >= 10);
});

test('scripts a workflow runs: a script missing from a row is reported (trajectory-probe without trajectory-line.mjs)', () => {
  const S = setMapFor(root, table);
  const w = table.workflows.find((x) => x.file === 'trajectory-probe.yml');
  const globs = expand(S, w.inputs).filter((g) => g !== '.github/scripts/trajectory-line.mjs');
  assert.ok(scriptsNamed(readFileSync(join(root, WF, w.file), 'utf8')).includes('.github/scripts/trajectory-line.mjs'));
  assert.equal(matches(globs, '.github/scripts/trajectory-line.mjs'), false);
});

test('scripts a workflow runs: a " #" inside a quoted string is not a comment (the script after it is named)', () => {
  assert.deepEqual(scriptsNamed(`run: echo "a #b" && node .github/scripts/q.mjs`), ['.github/scripts/q.mjs']);
  assert.deepEqual(scriptsNamed(`run: echo 'x #y' && node .github/scripts/r.mjs # .github/scripts/s.mjs`), ['.github/scripts/r.mjs']);
  assert.equal(stripComment('  # whole line'), '  ');
  assert.equal(stripComment('a#b c'), 'a#b c');
  assert.equal(stripComment(`don't # x`), `don't # x`); // the stated limit: a lone apostrophe keeps the comment text
});

test('scripts a workflow runs: the scanner reads run and env lines, not comments', () => {
  assert.deepEqual(scriptsNamed('run: node .github/scripts/a.mjs --x\n  SMOKE: ${{ github.workspace }}/.github/scripts/b.mjs\n# .github/scripts/c.mjs\n  run: x  # .github/scripts/d.mjs'), ['.github/scripts/a.mjs', '.github/scripts/b.mjs']);
});

test('run names: name and run-name of each dispatch workflow equal Lean titleFor; each drift is a problem', () => {
  assert.deepEqual(runNameProblems(root), []);
  const dir = mkdtempSync(join(tmpdir(), 'runname-'));
  try {
    mkdirSync(join(dir, WF), { recursive: true });
    mkdirSync(join(dir, 'packages', 'contracts', 'golden', 'ci'), { recursive: true });
    copyFileSync(join(root, 'packages', 'contracts', 'golden', 'ci', 'dispatch.jsonl'), join(dir, 'packages', 'contracts', 'golden', 'ci', 'dispatch.jsonl'));
    const list = readFileSync(join(dir, 'packages', 'contracts', 'golden', 'ci', 'dispatch.jsonl'), 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l)).find((l) => l.kind === 'workflows').list;
    assert.ok(list.length >= 4);
    for (const w of list) copyFileSync(join(root, WF, `${w}.yml`), join(dir, WF, `${w}.yml`));
    assert.deepEqual(runNameProblems(dir), []);
    const f = join(dir, WF, `${list[1]}.yml`);
    const text = readFileSync(f, 'utf8');
    writeFileSync(f, text.replace(/^run-name:.*$/m, "run-name: ${{ format('x {0}', inputs.nonce) }}"));
    assert.equal(runNameProblems(dir).filter((p) => p.includes('run-name')).length, 1);
    writeFileSync(f, text.replace(/^name:.*$/m, 'name: other'));
    assert.equal(runNameProblems(dir).filter((p) => p.includes('`name:`')).length, 1);
    writeFileSync(f, text.replace(/^run-name:.*\n/m, ''));
    assert.equal(runNameProblems(dir).length, 1);
    rmSync(f);
    assert.match(runNameProblems(dir)[0], /no such workflow file/);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
