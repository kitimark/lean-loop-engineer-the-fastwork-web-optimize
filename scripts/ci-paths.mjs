#!/usr/bin/env node
// ci-paths: the push trigger of every workflow is decided in Lean (lean/Fw/Ci/Trigger.lean, task ci-trigger-lean) and
// written to packages/contracts/golden/ci/triggers.jsonl. This script expands that table against the checkout and
//   --check (default)  fails when a workflow's `on.push` (branches; no paths) differs from the Lean decision, when a workflow
//                      lacks the `guard` job, or when a job does not (transitively) wait for it;
//   --write            rewrites those parts of the workflow files.
// It also reads, for every job that uses setup-lean, its `save:` and the Lake targets it builds, into the generated Lean
// module lean/Fw/Ops/LakeJobsGen.lean (--check: equal to the workflows; --write: rewritten). Lean Fw.Ops.LakeCache decides
// the rules over those rows (one writer, every job covered by it), so the Lean build fails on a broken rule.
// `@fwcore` / `@breakgen` name the build files plus the import cone of Main.lean / BreakgenMain.lean. The coarse push
// globs (every cone the fixed `coneGlobs`, `lean/Fw/**`, `lean/*.lean`; Lean `pushPaths`) are read by the guard on a
// main push only. This check fails when a cone file falls outside `coneGlobs` (Lean `ConeWithin`, `coarse_sound`).
// Round 3 of task ci-own-trigger (Lean Fw.Ci.Intent, golden packages/contracts/golden/ci/intent.jsonl):
//   - no `on.push.paths`: every push creates a run of every lane, so the tip push always gets its guard, which decides
//     on the whole branch (.github/scripts/changed-inputs.mjs; Lean `decision`, `tip_starts`, `tip_lean_always`);
//   - the guard job's own `if:` is the Lean intent condition (`ifExpr`): on a ci/* push the guard, and so every job, is
//     skipped unless the head commit asks for the lane (`[ci:<lane>]`) or the lane is a default lane (lean);
//     --check fails when a guard's `if:`, its GUARD_TOKEN env or its decision steps (Lean `Fw.Ci.Verdict.decisionStep`,
//     read by `fw ci wait`) differ; --write sets them;
//   - no workflow-level `concurrency:` (Lean `Fw.Ci.Cancel.wf_level_loses`); every non-guard job carries the Lean
//     job-level group (`Intent.groupExpr`) without `cancel-in-progress`: on ci/** the group holds the run id, so nothing
//     is cancelled (`Fw.Ci.Cancel.ci_never_cancelled`); main pushes keep one queue per ref;
//   - the first steps of every non-guard job re-check the branch tip (`tip re-check`, then `stale: ...` fails the job
//     when a newer push moved the tip; Lean `stale_never_works`), and every step whose `if:` uses a status function
//     carries the conjunct `steps.stale.outcome == 'skipped'` (Lean `workConj`).
// Task ci-main-triggers: only rows with a Lean seeder list `main`; in such a workflow every job but the guard and the
// seeders carries the Lean `notMainPush` conjunct in its `if:` (--write adds it), so a main push runs only the seeders.
// --check also fails when the Lean macOS flag of a lane differs from its workflow (a job on `macos-*` / `xcode-*` whose
// `if:` is not dispatch-only), and when a job's `if:` uses a status function without a conjunct that is false when the
// guard skipped.
// Run:  node scripts/ci-paths.mjs [--write | --check] [--root <dir>]
import { existsSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join, normalize } from 'node:path';
import { pathToFileURL } from 'node:url';
import { coneOf, loadGolden, loadIntent, matches, setMapFor, setMapWith, expand } from '../.github/scripts/changed-inputs.mjs';

const WF_DIR = ['.git', 'hub/workflows'].join('');
export const GUARD_SCRIPT = ['.git', 'hub/scripts/changed-inputs.mjs'].join('');

// The cone reader and the Lean `setMap` / `expand` live in the guard script, which runs them at run time on CI.
export { coneOf, expand, loadGolden, setMapFor, setMapWith } from '../.github/scripts/changed-inputs.mjs';

const SETUP_LEAN = /^\s*- uses: \.\/\.github\/actions\/setup-lean\s*$/;

/** The jobs of a workflow that use setup-lean, with the `save:` they pass ('true' or 'false', the default). */
export function setupLeanJobs(lines) {
  const out = [];
  for (const j of readJobs(lines)) {
    for (let i = j.at + 1; i < j.end; i++) {
      if (!SETUP_LEAN.test(lines[i])) continue;
      const k = indentOf(lines[i]);
      let save = 'false';
      for (let n = i + 1; n < j.end && (isBlank(lines[n]) || indentOf(lines[n]) > k); n++) {
        const m = /^\s*save:\s*'?(true|false)'?\s*(?:#.*)?$/.exec(lines[n]);
        if (m) save = m[1];
      }
      out.push({ job: j.name, save });
    }
  }
  return out;
}

// ---- Lake cache jobs (task site-build-cache) -------------------------------------------------------------------------
// The facts lean/Fw/Ops/LakeCache.lean decides over are read here from the workflows and written to the generated module
// lean/Fw/Ops/LakeJobsGen.lean: for every job that uses setup-lean, whether it passes `save: 'true'` and the Lake targets
// it builds. A new setup-lean job needs no hand edit: `--write` adds its row, and the Lean build fails only when a row
// breaks a rule (Fw.Ops.LakeCache.violations). The targets are the Lake invocations this scanner reads, following
//   the `run:` blocks of the job and of the local actions it uses (./.github/actions/<x>/action.yml);
//   `sh|bash|node <file>` (when the file exists); `pnpm --filter <pkg> [run] <script>` (that package.json script);
//   `lake build [t...]` (no target: lakefile defaultTargets), `lake exe <t>`, `lake test` (lakefile testDriver), and
//   JS `spawnSync('lake', ['build'|'exe'|'test', ...])`. `$VAR` reads a literal `VAR=...` of the same file, else it is skipped.
export const LAKE_GEN = 'lean/Fw/Ops/LakeJobsGen.lean';

/** lean/lakefile.toml: default targets, test driver, executables (name, root module), libraries (name, globs). */
export function readLakefile(root) {
  const strs = (s) => [...s.matchAll(/"([^"]*)"/g)].map((m) => m[1]);
  const out = { defaults: [], testDriver: null, exes: [], libs: [] };
  let cur = null;
  for (const l of readFileSync(join(root, 'lean/lakefile.toml'), 'utf8').split('\n')) {
    if (/^\s*#/.test(l)) continue;
    const sec = /^\[\[(lean_exe|lean_lib)\]\]/.exec(l);
    if (sec) { cur = { name: null, root: null, globs: [] }; (sec[1] === 'lean_exe' ? out.exes : out.libs).push(cur); continue; }
    if (/^\[/.test(l)) { cur = null; continue; }
    const kv = /^\s*(\w+)\s*=\s*(.*)$/.exec(l);
    if (!kv) continue;
    if (!cur) {
      if (kv[1] === 'defaultTargets') out.defaults = strs(kv[2]);
      if (kv[1] === 'testDriver') out.testDriver = strs(kv[2])[0] ?? null;
    } else if (kv[1] === 'name') cur.name = strs(kv[2])[0];
    else if (kv[1] === 'root') cur.root = strs(kv[2])[0];
    else if (kv[1] === 'globs') cur.globs = strs(kv[2]);
  }
  for (const e of out.exes) e.root ??= e.name;
  return out;
}

/** The shell text of the `run:` blocks of YAML lines (inline values and `|` / `>` blocks), comment lines dropped. */
export function runBlocks(lines) {
  const out = [];
  for (let i = 0; i < lines.length; i++) {
    const m = /^\s*(?:-\s+)?run:\s*(.*)$/.exec(lines[i]);
    if (!m) continue;
    if (/^[|>]/.test(m[1])) {
      const k = indentOf(lines[i]);
      for (let n = i + 1; n < lines.length && (lines[n].trim() === '' || indentOf(lines[n]) > k); n++) out.push(lines[n]);
    } else out.push(m[1]);
  }
  return out.filter((l) => !/^\s*#/.test(l)).join('\n');
}

/** Workspace package name -> directory (apps/*, packages/*). */
function packageDirs(root) {
  const out = new Map();
  for (const top of ['apps', 'packages']) {
    const d = join(root, top);
    if (!existsSync(d)) continue;
    for (const n of readdirSync(d)) {
      const p = join(d, n, 'package.json');
      if (existsSync(p)) { try { out.set(JSON.parse(readFileSync(p, 'utf8')).name, join(d, n)); } catch { /* not a package */ } }
    }
  }
  return out;
}

/** Lake targets a piece of shell or JS text builds (see the header of this section). `ctx`: { root, lake, pkgs, seen }. */
export function lakeTargetsOf(ctx, text, bases) {
  const src = text.split('\n').filter((l) => !/^\s*(#|\/\/)/.test(l)).join('\n');
  const vars = new Map();
  for (const m of src.matchAll(/^\s*([A-Za-z_]\w*)=(?:"([^"$`(]*)"|'([^']*)'|([^\s$`('"]*))\s*$/gm)) if (!vars.has(m[1])) vars.set(m[1], m[2] ?? m[3] ?? m[4]);
  const words = (s) => s.trim().split(/\s+/).filter(Boolean).flatMap((w) => {
    const v = /^\$\{?([A-Za-z_]\w*)\}?$/.exec(w);
    if (v) return vars.has(v[1]) ? vars.get(v[1]).split(/\s+/).filter(Boolean) : [];
    return w.includes('$') ? [] : [w];
  });
  const out = [];
  const lakeCmd = (verb, rest) => {
    const ws = words(rest).filter((w) => !w.startsWith('-'));
    if (verb === 'build') out.push(...(ws.length ? ws.map((w) => w.replace(/^[+@]/, '').replace(/:.*$/, '')) : ctx.lake.defaults));
    if (verb === 'exe' && ws.length) out.push(ws[0]);
    if (verb === 'test' && ctx.lake.testDriver) out.push(ctx.lake.testDriver);
  };
  for (const m of src.matchAll(/\blake\s+(build|exe|test)\b([^\n&|;><)"'`#]*)/g)) lakeCmd(m[1], m[2]);
  for (const m of src.matchAll(/\(\s*['"]lake['"]\s*,\s*\[([^\]]*)\]/g)) {
    const lits = [];
    for (const x of m[1].split(',').map((s) => s.trim())) { const q = /^['"]([^'"]*)['"]$/.exec(x); if (!q) break; lits.push(q[1]); }
    if (lits.length) lakeCmd(lits[0], lits.slice(1).join(' '));
  }
  const follow = (key, nextBases, read) => {
    if (ctx.seen.has(key)) return;
    ctx.seen.add(key);
    out.push(...lakeTargetsOf(ctx, read(), nextBases));
  };
  for (const m of src.matchAll(/(?:^|[\s;&|(`'"])(?:sh|bash|node)\s+([\w./-]+\.(?:sh|mjs|js))\b/gm)) {
    const abs = [...bases, ctx.root, join(ctx.root, 'lean')].map((b) => normalize(join(b, m[1]))).find((p) => existsSync(p));
    if (abs) follow(abs, [dirname(abs), dirname(dirname(abs)), ctx.root], () => readFileSync(abs, 'utf8'));
  }
  for (const m of src.matchAll(/\bpnpm\s+(?:--filter[= ]|-F\s*)['"]?([@\w/.-]+?)(?:\.\.\.)?['"]?\s+(?:run\s+)?([\w:.-]+)/g)) {
    const dir = ctx.pkgs.get(m[1]);
    const script = dir && JSON.parse(readFileSync(join(dir, 'package.json'), 'utf8')).scripts?.[m[2]];
    if (script) follow(`${dir}#${m[2]}`, [dir], () => script);
  }
  return out;
}

/** One row per job that uses setup-lean: { file, job, saves, targets } (targets deduplicated, in reading order). */
export function lakeJobs(root) {
  const ctx0 = { root, lake: readLakefile(root), pkgs: packageDirs(root) };
  const dir = join(root, WF_DIR);
  const rows = [];
  for (const file of readdirSync(dir).filter((f) => f.endsWith('.yml')).sort()) {
    const lines = readFileSync(join(dir, file), 'utf8').split('\n');
    const used = setupLeanJobs(lines);
    for (const j of readJobs(lines)) {
      const uses = used.filter((u) => u.job === j.name);
      if (!uses.length) continue;
      const body = lines.slice(j.at, j.end);
      let text = runBlocks(body);
      for (const l of body) {
        const a = /^\s*(?:-\s+)?uses:\s*\.\/(\.github\/actions\/[\w.-]+)\s*$/.exec(l);
        const p = a && join(root, a[1], 'action.yml');
        if (p && existsSync(p)) text += `\n${runBlocks(readFileSync(p, 'utf8').split('\n'))}`;
      }
      const targets = [...new Set(lakeTargetsOf({ ...ctx0, seen: new Set() }, text, [root]))];
      rows.push({ file, job: j.name, saves: uses.some((u) => u.save === 'true'), targets });
    }
  }
  return rows;
}

/** Modules under lean/ reachable from a root module by `import` (every import whose file exists). */
function modulesOf(root, rootModule) {
  const seen = new Set();
  const queue = [rootModule];
  while (queue.length) {
    const m = queue.pop();
    const abs = join(root, 'lean', `${m.replace(/\./g, '/')}.lean`);
    if (seen.has(m) || !existsSync(abs)) continue;
    seen.add(m);
    for (const l of readFileSync(abs, 'utf8').split('\n')) { const r = /^import\s+(\S+)/.exec(l); if (r) queue.push(r[1]); }
  }
  return seen;
}

/** Import facts [module, target]: a job target that is a module (no Lake target name) and an executable whose root imports
 *  it, or a library whose `X.*` glob holds it. */
export function lakeImportFacts(root, rows) {
  const lake = readLakefile(root);
  const names = new Set([...lake.exes.map((e) => e.name), ...lake.libs.map((l) => l.name)]);
  const out = [];
  for (const t of [...new Set(rows.flatMap((r) => r.targets))].filter((t) => !names.has(t)).sort()) {
    for (const e of lake.exes) if (modulesOf(root, e.root).has(t)) out.push([t, e.name]);
    for (const l of lake.libs) if (l.globs.some((g) => g.endsWith('.*') && t.startsWith(g.slice(0, -1)))) out.push([t, l.name]);
  }
  return out;
}

const tex = (s) => `\\texttt{${s.replace(/_/g, '\\_')}}`;
const leanStr = (s) => JSON.stringify(s);

/** The text of lean/Fw/Ops/LakeJobsGen.lean. */
export function renderLakeGen(rows, facts) {
  const rowTex = (r) => `(${tex(r.file)},\\ ${tex(r.job)},\\ ${r.saves ? '\\top' : '\\bot'},\\ [${r.targets.map(tex).join(',\\ ')}])`;
  return [
    '/-!',
    '# The CI jobs that use setup-lean (generated, do not edit)',
    '',
    'Written by `node scripts/ci-paths.mjs --write` from `.github/workflows/*.yml` and the scripts their `run:` blocks call;',
    '`node scripts/ci-paths.mjs --check` fails when this file differs from what the workflows give. The rules and proofs over',
    'these rows are in `Fw.Ops.LakeCache`.',
    '-/',
    'namespace Fw.Ops.LakeJobsGen',
    '',
    "/-- Every CI job that uses `.github/actions/setup-lean`, as (workflow file, job id, passes `save: 'true'`, Lake targets",
    'it builds), workflow files sorted by name, jobs in file order.',
    `$$R = [\\,${rows.map(rowTex).join(',\\ ')}\\,]$$ -/`,
    'def rows : List (String × String × Bool × List String) := [',
    `${rows.map((r) => `  (${leanStr(r.file)}, ${leanStr(r.job)}, ${r.saves}, [${r.targets.map(leanStr).join(', ')}])`).join(',\n')}]`,
    '',
    '/-- Import facts (module, Lake target): a job target that is a module, not a target name, and a target whose root module',
    'imports it (or whose library glob holds it), read from the `import` lines under `lean/`.',
    `$$F = [\\,${facts.map(([m, t]) => `(${tex(m)},\\ ${tex(t)})`).join(',\\ ')}\\,]$$ -/`,
    `def importFacts : List (String × String) := [${facts.map(([m, t]) => `(${leanStr(m)}, ${leanStr(t)})`).join(', ')}]`,
    '',
    'end Fw.Ops.LakeJobsGen',
    '',
  ].join('\n');
}

/** Check (or write) the generated Lake jobs module. Returns the problems, or null when the root has no lean/lakefile.toml. */
export function lakeGenProblems(root, write) {
  if (!existsSync(join(root, 'lean/lakefile.toml'))) return null;
  const rows = lakeJobs(root);
  const want = renderLakeGen(rows, lakeImportFacts(root, rows));
  const p = join(root, LAKE_GEN);
  const cur = existsSync(p) ? readFileSync(p, 'utf8') : '';
  if (cur === want) return [];
  if (write) { writeFileSync(p, want); return []; }
  return [`${LAKE_GEN} differs from the setup-lean jobs of the workflows (regenerate: node scripts/ci-paths.mjs --write)`];
}

/** The set map of the generated push paths (Lean `pushPaths`): every cone replaced by the fixed `coneGlobs`. */
export const coarseMap = (table) => setMapWith(table, () => table.coneGlobs);

/** Lean `ConeWithin`, checked on the checkout: every file of every cone a set names is literal (no `*`) and in the
 *  scope of `coneGlobs`, so the coarse push paths stay sound (`coarse_sound`). Returns the problems. */
export function coneProblems(root, table) {
  const roots = [...new Set(Object.values(table.sets).flat().filter((h) => h.startsWith('@cone:')).map((h) => h.slice(6)))];
  const out = [];
  for (const r of roots) {
    for (const f of coneOf(root, r)) {
      if (f.includes('*') || !matches(table.coneGlobs, f)) out.push(`cone ${r}: ${f} is outside coneGlobs ${table.coneGlobs.join(', ')} (lean/Fw/Ci/Trigger.lean)`);
    }
  }
  return out;
}

const quote = (s) => `'${s}'`;
const branchItem = (b) => (/[*\[\]{}:,&!#|>%@`'"?\s]/.test(b) ? quote(b) : b);

/** The `push:` block the Lean decision gives, as lines: the branches, no `paths` (round 3: the guard decides). */
export function renderPush(branches) {
  return ['  push:', `    branches: [${branches.map(branchItem).join(', ')}]`];
}

const indentOf = (l) => l.length - l.trimStart().length;
const isBlank = (l) => l.trim() === '' || l.trim().startsWith('#');

/** [start, end) line range of the `  push:` block under the top-level `on:`. */
export function pushRange(lines) {
  const on = lines.findIndex((l) => l === 'on:');
  if (on < 0) throw new Error('no top-level `on:`');
  let start = -1;
  for (let i = on + 1; i < lines.length; i++) {
    if (!isBlank(lines[i]) && indentOf(lines[i]) === 0) break;
    if (lines[i] === '  push:') { start = i; break; }
  }
  if (start < 0) throw new Error('no `push:` under `on:`');
  let end = start + 1;
  while (end < lines.length && (isBlank(lines[end]) || indentOf(lines[end]) > 2)) end++;
  while (end > start + 1 && isBlank(lines[end - 1])) end--; // trailing blanks and comments belong to the next key
  return [start, end];
}

/** The jobs of a workflow: name, line range, `needs`, whether it has an `if:`. A restricted reader (inline `needs`). */
export function readJobs(lines) {
  const jobsAt = lines.findIndex((l) => l === 'jobs:');
  if (jobsAt < 0) throw new Error('no `jobs:`');
  const heads = [];
  for (let i = jobsAt + 1; i < lines.length; i++) {
    const m = /^ {2}([A-Za-z0-9_-]+):\s*$/.exec(lines[i]);
    if (m) heads.push({ name: m[1], at: i });
    else if (!isBlank(lines[i]) && indentOf(lines[i]) === 0) break;
  }
  return heads.map((h, k) => {
    const end = k + 1 < heads.length ? heads[k + 1].at : lines.length;
    let needs = [];
    let hasIf = false;
    let ifText = '';
    let runsOn = '';
    for (let i = h.at + 1; i < end; i++) {
      if (indentOf(lines[i]) !== 4) continue;
      const ro = /^ {4}runs-on:\s*(.*?)\s*(?:#.*)?$/.exec(lines[i]);
      if (ro) runsOn = ro[1];
      const n = /^ {4}needs:\s*(.*?)\s*(?:#.*)?$/.exec(lines[i]);
      if (n) {
        const v = n[1];
        if (v === '' || v.startsWith('-')) throw new Error(`job ${h.name}: write \`needs\` inline ([a, b]) so the reader can see it`);
        needs = v.replace(/^\[|\]$/g, '').split(',').map((x) => x.trim()).filter(Boolean);
      }
      if (/^ {4}if:/.test(lines[i])) { hasIf = true; ifText = lines[i].replace(/^ {4}if:\s*/, ''); }
    }
    return { name: h.name, at: h.at, end, needs, hasIf, ifText, runsOn };
  });
}

/** Names of the jobs that do not (transitively) wait for `guard`. */
export function unguarded(jobs) {
  const by = new Map(jobs.map((j) => [j.name, j]));
  const reaches = (j, seen = new Set()) => {
    if (seen.has(j.name)) return false;
    seen.add(j.name);
    return j.needs.some((n) => n === 'guard' || (by.has(n) && reaches(by.get(n), seen)));
  };
  return jobs.filter((j) => j.name !== 'guard' && !reaches(j)).map((j) => j.name);
}

/** The comment above the guard job. */
export const GUARD_COMMENT = [
  '  # Guard (Lean Fw.Ci.Intent + Fw.Ci.Trigger, scripts/ci-paths.mjs). On a ci/* push it, and so every job, is skipped unless',
  '  # the head commit asks for this lane (`[ci:<lane>]`; the default lane lean always); then it runs the workflow only if',
  "  # the commit is the branch tip, is not on main yet, and (lean: always) some file that differs from main on the whole",
  '  # branch is an input. A main push runs when its own diff passes the coarse paths; dispatches, schedules always run.',
  '  # Fails open.',
  '  # Every other job re-checks the tip first (`stale:` fails it) and has its own group, never cancelled on ci/*.',
];

/** The guard's decision steps (Lean `Fw.Ci.Verdict.decisionStep`): `fw ci wait` reads which one ran from the jobs. */
export function decisionSteps(lane) {
  return [
    `      - name: '${lane.decision.run}'`,
    "        if: steps.g.outputs.run == 'true'",
    "        run: 'true'",
    `      - name: '${lane.decision.skip}: \${{ steps.g.outputs.reason }}'`,
    "        if: steps.g.outputs.run != 'true'",
    "        run: 'true'",
  ];
}

/** A job's job-level concurrency (Lean `Intent.groupExpr`): the group only, no `cancel-in-progress`. */
export function jobConcurrency(lane, job) {
  return ['    concurrency:', `      group: ${lane.group.replace('<job>', job)}`];
}

/** The first steps of every non-guard job (Lean `tipName`/`tipIf`, `staleName`/`staleIf`): read the branch tip with
 *  `git ls-remote` (no checkout needed; an unreadable tip counts as the tip, fail open, Lean `isTip`), then fail the
 *  job as `stale:` when the tip is not this commit, so no later step without a status function runs. */
export function recheckSteps(rc) {
  return [
    `      - name: '${rc.tipName}'`,
    '        id: tip',
    `        if: \${{ ${rc.tipIf} }}`,
    '        shell: bash',
    '        env:',
    '          GH_TOKEN: ${{ github.token }}',
    '        run: |',
    `          auth="AUTHORIZATION: basic $(printf 'x-access-token:%s' "$GH_TOKEN" | base64 | tr -d '\\n')"`,
    '          t=$(git -c "http.extraheader=$auth" ls-remote "$GITHUB_SERVER_URL/$GITHUB_REPOSITORY" "$GITHUB_REF" 2>/dev/null | cut -f1) || t=""',
    '          if [ -n "$t" ] && [ "$t" != "$GITHUB_SHA" ]; then echo "tip=false" >> "$GITHUB_OUTPUT"; echo "branch tip $t is not $GITHUB_SHA"; else echo "tip=true" >> "$GITHUB_OUTPUT"; echo "branch tip: ${t:-unreadable, counts as the tip}"; fi',
    `      - name: '${rc.staleName}'`,
    '        id: stale',
    `        if: \${{ ${rc.staleIf} }}`,
    '        shell: bash',
    '        run: exit 1',
  ];
}

const STATUS_FN = /always\(\)|cancelled\(\)|failure\(\)/;

/** A step `if:` with a status function, with the Lean `workConj` added (`(e) && conj`); other texts unchanged. */
export function withConj(ifText, conj) {
  if (!STATUS_FN.test(ifText) || ifText.includes(conj)) return ifText;
  const m = /^\$\{\{\s*(.*?)\s*\}\}$/.exec(ifText.trim());
  return `\${{ (${m ? m[1] : ifText.trim()}) && ${conj} }}`;
}

/** A job that runs only on a dispatch: its `if:` is a conjunction with `github.event_name == 'workflow_dispatch'`. */
export function dispatchOnly(ifText) {
  return ifText.includes("github.event_name == 'workflow_dispatch' &&") && !ifText.includes('||');
}

/** The jobs of a workflow that may run on a macOS runner on a push (Lean `Lane.macos` must equal "some"). */
export function macosJobs(jobs) {
  return jobs.filter((j) => /^(macos-|xcode-)/.test(j.runsOn) && !dispatchOnly(j.ifText)).map((j) => j.name);
}

/** A status function (`always()`, `cancelled()`, `failure()`) lets a job run after its needs were skipped; its `if:` must
 *  then hold a conjunct that is false when the guard skipped (a needed job's success, or the guard's run=true). */
export function unsafeStatusIf(ifText) {
  return /always\(\)|cancelled\(\)|failure\(\)/.test(ifText) &&
    !/needs\.[A-Za-z0-9_-]+\.result == 'success'|needs\.guard\.outputs\.run == 'true'/.test(ifText);
}

/** The guard job's `if:` line for a lane (Lean `ifExpr`). */
export const guardIf = (lane) => `    if: ${lane.if}`;

/** The text of the guard job for a workflow file and its lane. */
export function guardJob(file, lane) {
  return [
    ...GUARD_COMMENT,
    '  guard:',
    ...(lane && lane.if ? [guardIf(lane)] : []),
    '    runs-on: ubuntu-24.04-arm',
    '    timeout-minutes: 5',
    '    outputs:',
    '      run: ${{ steps.g.outputs.run }}',
    '    steps:',
    '      - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803 # v6.1.0',
    '        with:',
    '          fetch-depth: 0',
    '          filter: blob:none',
    '          persist-credentials: false',
    '      - id: g',
    '        env:',
    '          EVENT_NAME: ${{ github.event_name }}',
    '          REF: ${{ github.ref }}',
    '          BEFORE: ${{ github.event.before }}',
    '          GUARD_TOKEN: ${{ github.token }}',
    `        run: node ${GUARD_SCRIPT} --workflow ${WF_DIR}/${file}`,
    ...(lane?.decision ? decisionSteps(lane) : []),
    '',
  ];
}

/** A job `if:` with the Lean `notMainPush` conjunct added (`${{ e && (conj) }}`); a text that has it is unchanged. */
export function withNotMain(ifText, conj) {
  const c = `(${conj})`;
  if (ifText.includes(c)) return ifText;
  const m = /^\$\{\{\s*(.*?)\s*\}\}$/.exec(ifText.trim());
  return `\${{ ${m ? m[1] : ifText.trim()} && ${c} }}`;
}

/** Everything wrong with one workflow's text, and the fixed text. `main` (Lean `seeders`, `notMainPush`): the jobs of
 *  this file a `main` push runs besides the guard, and the conjunct every other job carries when the row lists `main`. */
export function reconcile(file, text, row, lane = null, main = null) {
  const problems = [];
  let lines = text.split('\n');
  // 1. on.push: the branches, no paths (a docs-only tip push must still create the run whose guard decides)
  const [s, e] = pushRange(lines);
  const want = renderPush(row.branches);
  if (lines.slice(s, e).join('\n') !== want.join('\n')) problems.push(`${file}: on.push differs from the Lean decision`);
  lines = [...lines.slice(0, s), ...want, ...lines.slice(e)];
  // 2. the guard job
  let jobs = readJobs(lines);
  if (!jobs.some((j) => j.name === 'guard')) {
    problems.push(`${file}: no \`guard\` job`);
    const at = lines.indexOf('jobs:');
    lines = [...lines.slice(0, at + 1), ...guardJob(file, lane), ...lines.slice(at + 1)];
    jobs = readJobs(lines);
  }
  let g = jobs.find((j) => j.name === 'guard');
  // the comment above the guard
  let c = g.at;
  while (c > 0 && /^ {2}#/.test(lines[c - 1])) c--;
  if (lines.slice(c, g.at).join('\n') !== GUARD_COMMENT.join('\n')) {
    problems.push(`${file}: the comment above the guard job differs`);
    lines = [...lines.slice(0, c), ...GUARD_COMMENT, ...lines.slice(g.at)];
    jobs = readJobs(lines);
    g = jobs.find((j) => j.name === 'guard');
  }
  // the intent condition (Lean `ifExpr`) on the guard job itself
  if (lane && lane.if === '') {
    // a default lane: no `if:` (Lean `ifExpr` is empty), the guard runs on every push
    const k = lines.findIndex((l, i) => i > g.at && i < g.end && /^ {4}if:/.test(l));
    if (k >= 0) {
      problems.push(`${file}: the guard of default lane ${lane.name} has an \`if:\`; Lean \`ifExpr\` gives none`);
      lines.splice(k, 1);
      jobs = readJobs(lines);
      g = jobs.find((j) => j.name === 'guard');
    }
  } else if (lane) {
    const k = lines.findIndex((l, i) => i > g.at && i < g.end && /^ {4}if:/.test(l));
    if (k < 0 || lines[k] !== guardIf(lane)) {
      problems.push(`${file}: the guard's \`if:\` differs from the Lean intent condition (lane ${lane.name})`);
      if (k < 0) lines.splice(g.at + 1, 0, guardIf(lane));
      else lines[k] = guardIf(lane);
      jobs = readJobs(lines);
      g = jobs.find((j) => j.name === 'guard');
    }
  }
  if (!lines.slice(g.at, g.end).some((l) => l.trim() === 'GUARD_TOKEN: ${{ github.token }}')) {
    problems.push(`${file}: the guard job does not pass GUARD_TOKEN: github.token`);
    const k = lines.findIndex((l, i) => i >= g.at && i < g.end && l.trim() === 'BEFORE: ${{ github.event.before }}');
    if (k >= 0) { lines.splice(k + 1, 0, `${lines[k].slice(0, indentOf(lines[k]))}GUARD_TOKEN: \${{ github.token }}`); jobs = readJobs(lines); g = jobs.find((j) => j.name === 'guard'); }
  }
  const body = lines.slice(g.at, g.end).join('\n');
  const callee = `node ${GUARD_SCRIPT} --workflow ${WF_DIR}/${file}`;
  if (!body.includes(callee)) problems.push(`${file}: the guard job does not run \`${callee}\``);
  if (!/BEFORE: \$\{\{ github\.event\.before \}\}/.test(body)) {
    problems.push(`${file}: the guard job does not pass BEFORE: github.event.before`);
    const k = lines.findIndex((l, i) => i >= g.at && i < g.end && l.trim() === 'REF: ${{ github.ref }}');
    if (k >= 0) { lines.splice(k + 1, 0, `${lines[k].slice(0, indentOf(lines[k]))}BEFORE: \${{ github.event.before }}`); jobs = readJobs(lines); }
  }
  // 3. every job waits for the guard: root jobs get needs + if; an inner job is left to its upstream
  for (const name of unguarded(readJobs(lines))) {
    const j = readJobs(lines).find((x) => x.name === name);
    if (j.needs.length > 0) continue;
    if (j.hasIf) { problems.push(`${file}: root job ${name} has an \`if:\`; add \`needs: [guard]\` and the guard condition by hand`); continue; }
    problems.push(`${file}: job ${name} does not wait for guard`);
    lines.splice(j.at + 1, 0, '    needs: [guard]', "    if: ${{ needs.guard.outputs.run == 'true' }}");
  }
  for (const name of unguarded(readJobs(lines))) problems.push(`${file}: job ${name} has needs but none leads to guard (edit by hand)`);
  // 4. the guard's decision steps, right after the guard script (Lean Fw.Ci.Verdict.decisionStep)
  if (lane?.decision) {
    g = readJobs(lines).find((j) => j.name === 'guard');
    const k = lines.findIndex((l, i) => i > g.at && i < g.end && l.trim() === `run: ${callee}`);
    if (k >= 0) {
      let e = k + 1;
      while (e < g.end && lines[e].startsWith("      - name: 'decision:")) { e++; while (e < g.end && !isBlank(lines[e]) && indentOf(lines[e]) >= 8) e++; }
      const want = decisionSteps(lane);
      if (lines.slice(k + 1, e).join('\n') !== want.join('\n')) {
        problems.push(`${file}: the guard's decision steps differ (Lean Fw.Ci.Verdict.decisionStep)`);
        lines.splice(k + 1, e - k - 1, ...want);
      }
    }
  }
  // 5. no workflow-level concurrency (Lean Fw.Ci.Cancel.wf_level_loses); its comment goes with it
  const wc = lines.findIndex((l) => /^concurrency:/.test(l));
  if (wc >= 0) {
    problems.push(`${file}: workflow-level \`concurrency:\` (a push that does not ask for the lane would cancel a requested run; Lean Fw.Ci.Cancel.wf_level_loses)`);
    let e = wc + 1;
    while (e < lines.length && /^\s+\S/.test(lines[e])) e++;
    let c = wc;
    while (c > 0 && /^#/.test(lines[c - 1])) c--;
    if (e < lines.length && isBlank(lines[e]) && c > 0 && isBlank(lines[c - 1])) e++;
    lines.splice(c, e - c);
  }
  // 6. every non-guard job: the Lean job-level group (Intent.groupExpr), before its runs-on
  if (lane?.group) {
    for (const name of readJobs(lines).map((j) => j.name).filter((n) => n !== 'guard')) {
      const j = readJobs(lines).find((x) => x.name === name);
      const want = jobConcurrency(lane, name);
      const k = lines.findIndex((l, i) => i > j.at && i < j.end && l === '    concurrency:');
      if (k >= 0) {
        let e = k + 1;
        while (e < j.end && !isBlank(lines[e]) && indentOf(lines[e]) > 4) e++;
        if (lines.slice(k, e).join('\n') !== want.join('\n')) {
          problems.push(`${file}: job ${name}: concurrency differs from the Lean group (lane ${lane.name})`);
          lines.splice(k, e - k, ...want);
        }
      } else {
        problems.push(`${file}: job ${name} has no job-level concurrency group (lane ${lane.name})`);
        const r = lines.findIndex((l, i) => i > j.at && i < j.end && /^ {4}runs-on:/.test(l));
        lines.splice(r >= 0 ? r : j.at + 1, 0, ...want);
      }
    }
  }
  // 6b. every non-guard job with steps: the tip re-check first (Lean tipName/staleName), and every step `if:` with a
  // status function carries the Lean workConj, so a stale run does no work (Lean `stale_never_works`)
  const rc = lane?.recheck;
  if (rc) {
    const named = (l) => l === `      - name: '${rc.tipName}'` || l === `      - name: '${rc.staleName}'`;
    for (const name of readJobs(lines).map((j) => j.name).filter((n) => n !== 'guard')) {
      const j = readJobs(lines).find((x) => x.name === name);
      const k = lines.findIndex((l, i) => i > j.at && i < j.end && l === '    steps:');
      if (k < 0) continue; // a reusable-workflow job: no steps of its own
      const want = recheckSteps(rc);
      let e = k + 1;
      while (e < j.end && named(lines[e])) { e++; while (e < j.end && !isBlank(lines[e]) && indentOf(lines[e]) >= 8) e++; }
      if (lines.slice(k + 1, e).join('\n') !== want.join('\n')) {
        problems.push(`${file}: job ${name}: the first steps differ from the Lean tip re-check (lane ${lane.name})`);
        lines.splice(k + 1, e - k - 1, ...want);
      }
      const j2 = readJobs(lines).find((x) => x.name === name);
      for (let i = j2.at + 1; i < j2.end; i++) {
        const m = /^( {8})if:\s*(.*)$/.exec(lines[i]);
        if (!m) continue;
        const fixed = withConj(m[2], rc.conj);
        if (fixed !== m[2]) {
          problems.push(`${file}: job ${name}: a step \`if:\` with a status function lacks \`${rc.conj}\` (Lean workConj)`);
          lines[i] = `${m[1]}if: ${fixed}`;
        }
      }
    }
  }
  // 7. the Lean macOS flag equals the workflow (Fw.Ci.Intent macosFiles); a status function keeps a guard conjunct
  const jobs7 = readJobs(lines);
  if (lane) {
    const mac = macosJobs(jobs7);
    if ((mac.length > 0) !== (lane.macos === true)) {
      problems.push(`${file}: lane ${lane.name} has macos=${lane.macos === true} in Lean (Fw.Ci.Intent macosFiles) but its push macOS jobs are [${mac.join(', ')}] (edit by hand)`);
    }
  }
  for (const j of jobs7) {
    if (j.name !== 'guard' && unsafeStatusIf(j.ifText)) problems.push(`${file}: job ${j.name}: its \`if:\` uses a status function without a needs success or guard run conjunct, so it would run (and enter its group) after the guard skipped (edit by hand)`);
  }
  // 8. a row that lists `main`: a main push runs the guard and the seeders only (Lean Fw.Ci.Trigger.mainRuns_iff), so
  // every other job carries the `notMainPush` conjunct and no seeder does
  if (main && row.branches.includes('main')) {
    const c = `(${main.conj})`;
    for (const name of readJobs(lines).map((j) => j.name).filter((n) => n !== 'guard')) {
      const j = readJobs(lines).find((x) => x.name === name);
      const k = lines.findIndex((l, i) => i > j.at && i < j.end && /^ {4}if:/.test(l));
      const seeds = main.jobs.includes(name);
      if (seeds) {
        if (j.ifText.includes(c)) problems.push(`${file}: job ${name} is a seeder (Lean Fw.Ci.Trigger.seeders) but its \`if:\` skips a main push (edit by hand)`);
        continue;
      }
      if (j.ifText.includes(c)) continue;
      problems.push(`${file}: job ${name} would run on a main push but is no seeder (Lean Fw.Ci.Trigger.seeders); its \`if:\` lacks \`${c}\``);
      if (k >= 0) lines[k] = `    if: ${withNotMain(j.ifText, main.conj)}`;
      else lines.splice(j.at + 1, 0, `    if: \${{ ${c} }}`);
    }
  }
  return { problems, text: lines.join('\n') };
}

/** Globs a GitHub `paths` filter and Lean `PathCheck.inScope` read the same way: literals, `*` inside a segment, `**` as a segment. */
export function portableGlob(g) {
  return !/[?+\[\]!{}]/.test(g) && !g.split('/').some((seg) => seg.includes('**') && seg !== '**') && !g.startsWith('/');
}

/** The repo paths a shell script under lean/scripts reads relative to lean/ (every `../<path>`); a path that is not a
 *  literal (empty, or with `$`, `*`, `?`, `{`) is returned as null so the lint fails closed on it. */
export function leanScriptPaths(text) {
  return [...text.matchAll(/\.\.\/([^\s'"`;)|&<>]*)/g)].map((m) => (m[1] === '' || /[$*?{}]/.test(m[1]) ? null : m[1]));
}

/** Round 4 of task ci-own-trigger: every repo path a lean/scripts/*.sh reads (`../<path>`) must be an input of the
 *  lean row of the Lean table. Since round 5 lean never skips as `unchanged` on ci/** (Lean `lean_never_unchanged`), so
 *  this is no safety input of a branch wait; it keeps a main push that changes only such a file running lean (the
 *  coarse paths rule, Lean `main_keeps_paths_rule`). Returns the problems. */
export function leanInputProblems(root, table) {
  const row = table.workflows.find((w) => w.file === 'lean.yml');
  if (!row) return ['lean.yml: no row in the Lean table (lean/Fw/Ci/Trigger.lean `table`)'];
  const globs = expand(setMapFor(root, table), row.inputs);
  const dir = join(root, 'lean', 'scripts');
  const out = [];
  for (const f of readdirSync(dir).filter((x) => x.endsWith('.sh')).sort()) {
    for (const p of leanScriptPaths(readFileSync(join(dir, f), 'utf8'))) {
      if (p === null) out.push(`lean/scripts/${f}: reads a ../ path that is not a literal file path (write it out, so the lean row can name it)`);
      else if (!matches(globs, normalize(p))) out.push(`lean/scripts/${f}: reads ../${p}, which is not an input of the lean.yml row (add it to lean/Fw/Ci/Trigger.lean \`table\`, then cd lean && lake test -- --write-ci-trigger-golden)`);
    }
  }
  return out;
}

/** Check (or write) every workflow. Returns { problems, wrote }. */
export function run(root, write) {
  const { table } = loadGolden(root);
  const intent = loadIntent(root).lanes;
  const lanes = new Map((intent?.lanes ?? []).map((l) => [l.file, { ...l, decision: intent.decision, recheck: intent.recheck }]));
  const S = coarseMap(table);
  const dir = join(root, WF_DIR);
  const files = readdirSync(dir).filter((f) => f.endsWith('.yml')).sort();
  const problems = [...coneProblems(root, table), ...leanInputProblems(root, table)];
  let wrote = 0;
  const rows = new Map(table.workflows.map((w) => [w.file, w]));
  try { problems.push(...(lakeGenProblems(root, write) ?? [])); } catch (e) { problems.push(`${LAKE_GEN}: ${e.message}`); }
  for (const w of table.workflows) if (!files.includes(w.file)) problems.push(`${w.file}: in the Lean table but no such workflow file`);
  for (const f of files) {
    const row = rows.get(f);
    if (!row) { problems.push(`${f}: not in the Lean table (lean/Fw/Ci/Trigger.lean \`table\`)`); continue; }
    const lane = lanes.get(f);
    if (!lane) problems.push(`${f}: no lane in the Lean intent golden (lean/Fw/Ci/Intent.lean \`lanes\`; lake test -- --write-ci-trigger-golden)`);
    const paths = expand(S, row.inputs); // the coarse globs the guard reads on a main push
    for (const p of paths) if (!portableGlob(p)) problems.push(`${f}: glob ${p} is not read the same by GitHub and by Lean PathCheck`);
    const text = readFileSync(join(dir, f), 'utf8');
    let r;
    if (row.branches.includes('main') && !table.notMainPush) problems.push(`${f}: lists main but the Lean golden has no notMainPush (lake test -- --write-ci-trigger-golden)`);
    const main = table.notMainPush ? { jobs: (table.seeders ?? []).filter((s) => s.file === f).map((s) => s.job), conj: table.notMainPush } : null;
    try { r = reconcile(f, text, row, lane ?? null, main); } catch (e) { problems.push(`${f}: ${e.message}`); continue; }
    problems.push(...r.problems);
    if (write && r.text !== text) { writeFileSync(join(dir, f), r.text); wrote++; }
  }
  return { problems, wrote };
}

function main() {
  const i = process.argv.indexOf('--root');
  const root = i >= 0 ? process.argv[i + 1] : join(dirname(new URL(import.meta.url).pathname), '..');
  const write = process.argv.includes('--write');
  const { problems, wrote } = run(root, write);
  if (write) {
    console.log(`ci-paths: wrote ${wrote} workflow file(s)`);
    const left = problems.filter((p) => /by hand|not in the Lean table|no such workflow|not read the same|outside coneGlobs|no lane in the Lean intent|lean\/scripts\//.test(p));
    for (const p of left) console.log(`  ${p}`);
    process.exit(left.length ? 1 : 0);
  }
  if (problems.length) {
    console.log('ci-paths: a workflow trigger differs from the Lean decision (lean/Fw/Ci/Trigger.lean). Fix: node scripts/ci-paths.mjs --write');
    for (const p of problems) console.log(`  ${p}`);
    process.exit(1);
  }
  console.log('ci-paths: every workflow trigger equals the Lean decision');
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
