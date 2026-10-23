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
// seeders has the `if:` form Lean `carriesNotMain` accepts (--write gives it Lean `withNotMain`), so a main push runs only
// the seeders. The keys under `on:` are the row's Lean `onKeys` (push, workflow_dispatch; schedule only with a cron), and
// `on.schedule` equals the row's crons (none: a schedule is a main run). The jobs that save a cache, read
// from the workflows and their local actions, equal Lean `cacheWriters`.
// Run:  node scripts/ci-paths.mjs [--write | --check | --plan-time [--refresh <timings.jsonl>] [--check]] [--root <dir>]
import { execFileSync } from 'node:child_process';
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

/** The `- ` items between lines `from` and `to`, each as its lines. */
function stepItems(lines, from, to) {
  const out = [];
  for (let i = from; i < to; i++) {
    const m = /^(\s*)- /.exec(lines[i]);
    if (!m) continue;
    let e = i + 1;
    while (e < to && (isBlank(lines[e]) || indentOf(lines[e]) > m[1].length)) e++;
    out.push(lines.slice(i, e));
    i = e - 1;
  }
  return out;
}

/** The value of the first `key:` line of a step, unquoted, without a trailing comment. */
function stepField(step, key) {
  const re = new RegExp(`^\\s*(?:-\\s+)?${key}:\\s*(.*?)\\s*(?:#.*)?$`);
  for (const l of step) {
    const m = re.exec(l);
    if (m) return m[1].replace(/^'(.*)'$/, '$1');
  }
  return null;
}

const SAVES_CACHE = /^actions\/cache(?:\/save)?@/;

/** Every job that saves a cache, as `file/job/cache` (Lean `cacheWriters`): an `actions/cache` (or `/save`) step of the
 *  job, or of a local action it uses unless that step's `if:` asks for an input `== 'true'` the job does not pass. The
 *  cache is the last segment of the step's `path:`. */
export function cacheWriters(root) {
  const dir = join(root, WF_DIR);
  const out = new Set();
  const cacheOf = (step) => (stepField(step, 'path') ?? '').split('/').pop();
  for (const file of readdirSync(dir).filter((f) => f.endsWith('.yml')).sort()) {
    const lines = readFileSync(join(dir, file), 'utf8').split('\n');
    for (const j of readJobs(lines)) {
      for (const step of stepItems(lines, j.at + 1, j.end)) {
        const uses = stepField(step, 'uses') ?? '';
        if (SAVES_CACHE.test(uses)) out.add(`${file}/${j.name}/${cacheOf(step)}`);
        const a = /^\.\/(\.github\/actions\/[\w.-]+)$/.exec(uses);
        const p = a && join(root, a[1], 'action.yml');
        if (!p || !existsSync(p)) continue;
        const al = readFileSync(p, 'utf8').split('\n');
        for (const s of stepItems(al, 0, al.length)) {
          if (!SAVES_CACHE.test(stepField(s, 'uses') ?? '')) continue;
          const cond = /inputs\.([\w-]+) == 'true'/.exec(stepField(s, 'if') ?? '');
          if (cond && stepField(step, cond[1]) !== 'true') continue;
          out.add(`${file}/${j.name}/${cacheOf(s)}`);
        }
      }
    }
  }
  return [...out].sort();
}

/** Problems when the cache writers of the workflows differ from Lean `cacheWriters`. */
export function cacheWriterProblems(root, table) {
  const lean = (table.cacheWriters ?? []).map((w) => `${w.file}/${w.job}/${w.cache}`).sort();
  const got = cacheWriters(root);
  const add = got.filter((x) => !lean.includes(x));
  const gone = lean.filter((x) => !got.includes(x));
  return [...add.map((x) => `cache writer ${x} is not in Lean Fw.Ci.Trigger.cacheWriters (add it, then cd lean && lake test -- --write-ci-trigger-golden)`),
    ...gone.map((x) => `cache writer ${x} of Lean Fw.Ci.Trigger.cacheWriters saves no such cache in the workflows`)];
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

const leanStr = (s) => JSON.stringify(s);

/** The text of lean/Fw/Ops/LakeJobsGen.lean. */
export function renderLakeGen(rows, facts) {
  return [
    '-- GENERATED by node scripts/ci-paths.mjs --write from .github/workflows/*.yml: do not edit by hand',
    'namespace Fw.Ops.LakeJobsGen',
    '',
    "/-- Every CI job that uses setup-lean: (workflow, job id, saves the cache, Lake targets), by workflow then job order. -/",
    'def rows : List (String × String × Bool × List String) := [',
    `${rows.map((r) => `  (${leanStr(r.file)}, ${leanStr(r.job)}, ${r.saves}, [${r.targets.map(leanStr).join(', ')}])`).join(',\n')}]`,
    '',
    '/-- (module, Lake target): a job target that is a module, and a target whose root imports it. -/',
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

/** [start, end) line range of the `  <key>:` block under the top-level `on:`; empty, at the end of `on:`, when absent. */
export function onKeyRange(lines, key) {
  const on = lines.findIndex((l) => l === 'on:');
  if (on < 0) throw new Error('no top-level `on:`');
  let i = on + 1;
  let last = on + 1;
  for (; i < lines.length; i++) {
    if (!isBlank(lines[i]) && indentOf(lines[i]) === 0) break;
    if (lines[i] === `  ${key}:`) break;
    if (!isBlank(lines[i])) last = i + 1;
  }
  if (i >= lines.length || lines[i] !== `  ${key}:`) return [last, last];
  let end = i + 1;
  while (end < lines.length && (isBlank(lines[end]) || indentOf(lines[end]) > 2)) end++;
  while (end > i + 1 && isBlank(lines[end - 1])) end--;
  return [i, end];
}

const ON_KEY = /^ {2}(['"]?)([\w-]+)\1\s*:/;

/** The keys under the top-level `on:`, as { key, text }; key null for a line at indent 2 that is no key, or at indent 1. */
export function onKeys(lines) {
  const on = lines.findIndex((l) => l === 'on:');
  if (on < 0) throw new Error('no top-level `on:`');
  const keys = [];
  let seen = false;
  for (let i = on + 1; i < lines.length; i++) {
    if (isBlank(lines[i])) continue;
    const d = indentOf(lines[i]);
    if (d === 0) break;
    if (d === 2 || d === 1 || !seen) {
      const m = d === 2 ? ON_KEY.exec(lines[i]) : null;
      keys.push({ key: m ? m[2] : null, text: lines[i] });
      seen = true;
    }
  }
  return keys;
}

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

/** The comment above the guard job of a row: the main sentence only where the row lists `main`. */
export function guardComment(row) {
  return [
    '  # Guard (Lean Fw.Ci.Intent + Fw.Ci.Trigger, scripts/ci-paths.mjs). On a ci/* push it, and so every job, is skipped unless',
    '  # the head commit asks for this lane (`[ci:<lane>]`; the default lane lean always); then it runs the workflow only if',
    "  # the commit is the branch tip, is not on main yet, and (lean: always) some file that differs from main on the whole",
    ...(row?.branches?.includes('main')
      ? ['  # branch is an input. A main push runs when its own diff passes the coarse paths, and then only the cache seeders',
        '  # (Lean Fw.Ci.Trigger.seeders); dispatches always run. Fails open.']
      : ['  # branch is an input. A main push starts no run; dispatches always run. Fails open.']),
    '  # Every other job re-checks the tip first (`stale:` fails it) and has its own group, never cancelled on ci/*.',
  ];
}

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

export const POOL_CAPS = 'packages/contracts/golden/ci/pool-caps.jsonl';

/** The Lean cap table (Fw.Ci.Pool.Caps): `caps` maps `<file> <job>` to its `timeout-minutes`; `excluded` holds the
 *  workflows whose macOS jobs another task times. */
export function loadCaps(root) {
  const rows = readFileSync(join(root, POOL_CAPS), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
  return {
    caps: new Map(rows.filter((r) => r.kind === 'cap').map((r) => [`${r.file} ${r.job}`, r.capMin])),
    excluded: new Set(rows.filter((r) => r.kind === 'excluded').map((r) => r.file)),
  };
}

const TIMEOUT = /^ {4}timeout-minutes:\s*(.*?)\s*(?:#.*)?$/;

/** Every macOS job (runs-on macos-* / xcode-*, dispatch-only included) of a workflow outside `excluded` has a Lean cap,
 *  and its job-level `timeout-minutes` equals it; a cap row names a macOS job of the file. Returns { problems, text }
 *  with the timeouts set to the caps. */
export function capProblems(file, text, capTable) {
  const problems = [];
  const lines = text.split('\n');
  const jobs = readJobs(lines);
  for (const key of capTable.caps.keys()) {
    const [f, job] = key.split(' ');
    if (f === file && !jobs.some((j) => j.name === job)) problems.push(`${file}: Lean cap for job ${job}, but the workflow has no such job`);
  }
  if (capTable.excluded.has(file)) return { problems, text };
  for (const j of [...jobs].reverse()) {
    if (j.runsOn.includes('${{')) problems.push(`${file}: job ${j.name}: runs-on is an expression, so the cap check cannot read its runner (write the label)`);
    const cap = capTable.caps.get(`${file} ${j.name}`);
    if (!/^(macos-|xcode-)/.test(j.runsOn)) {
      if (cap !== undefined) problems.push(`${file}: job ${j.name} has a Lean cap but does not run on macOS`);
      continue;
    }
    if (cap === undefined) {
      problems.push(`${file}: macOS job ${j.name} has no Lean cap (lean/Fw/Ci/Pool/Caps.lean \`rows\` or \`excluded\`)`);
      continue;
    }
    const want = `    timeout-minutes: ${cap}`;
    const at = lines.findIndex((l, i) => i > j.at && i < j.end && TIMEOUT.test(l));
    if (at < 0) {
      problems.push(`${file}: macOS job ${j.name} has no timeout-minutes; the Lean cap is ${cap}`);
      const ro = lines.findIndex((l, i) => i > j.at && i < j.end && /^ {4}runs-on:/.test(l));
      lines.splice(ro + 1, 0, want);
    } else if (TIMEOUT.exec(lines[at])[1] !== String(cap)) {
      problems.push(`${file}: macOS job ${j.name} has timeout-minutes ${TIMEOUT.exec(lines[at])[1]}; the Lean cap is ${cap}`);
      lines[at] = want;
    }
  }
  return { problems, text: lines.join('\n') };
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
export function guardJob(file, lane, row = null) {
  return [
    ...guardComment(row),
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
    '      - uses: actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1 # v7.1.0',
    '        with:',
    `          node-version-file: ${NODE_FILE}`,
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

/** Lean `withNotMain`: the `if:` of a non-seeder job with condition `orig` (null: the job had no `if:`). */
export function notMainIf(orig, conj) {
  return orig === null ? `\${{ (${conj}) }}` : `\${{ (${orig}) && (${conj}) }}`;
}

/** Lean `inner 1 false`: from depth 1 outside a string, the parentheses of `m` never close the outer group and end at
 *  depth 1 outside a string. */
function innerGroup(m) {
  let d = 1;
  let q = false;
  for (const ch of m) {
    if (q) { if (ch === "'") q = false; continue; }
    if (ch === "'") q = true;
    else if (ch === '(') d++;
    else if (ch === ')') { if (d <= 1) return false; d--; }
  }
  return d === 1 && !q;
}

/** Lean `carriesNotMain`: `text` is `${{ (conj) }}`, or `${{ (m) && (conj) }}` with `m` closing only at its end. */
export function carriesNotMain(text, conj) {
  if (text === notMainIf(null, conj)) return true;
  const pre = '${{ (';
  const post = `) && (${conj}) }}`;
  if (!text.startsWith(pre) || !text.endsWith(post) || text.length < pre.length + post.length) return false;
  return innerGroup(text.slice(pre.length, text.length - post.length));
}

/** A job `if:` text with the Lean form that skips a main push; a text Lean `carriesNotMain` accepts is unchanged. */
export function withNotMain(ifText, conj) {
  const t = ifText.trim();
  if (carriesNotMain(t, conj)) return t;
  if (t === '') return notMainIf(null, conj);
  const m = /^\$\{\{\s*(.*?)\s*\}\}$/.exec(t);
  return notMainIf(m ? m[1] : t, conj);
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
    lines = [...lines.slice(0, at + 1), ...guardJob(file, lane, row), ...lines.slice(at + 1)];
    jobs = readJobs(lines);
  }
  let g = jobs.find((j) => j.name === 'guard');
  // the comment above the guard
  let c = g.at;
  while (c > 0 && /^ {2}#/.test(lines[c - 1])) c--;
  if (lines.slice(c, g.at).join('\n') !== guardComment(row).join('\n')) {
    problems.push(`${file}: the comment above the guard job differs`);
    lines = [...lines.slice(0, c), ...guardComment(row), ...lines.slice(g.at)];
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
    for (const name of readJobs(lines).map((j) => j.name).filter((n) => n !== 'guard')) {
      const j = readJobs(lines).find((x) => x.name === name);
      const k = lines.findIndex((l, i) => i > j.at && i < j.end && /^ {4}if:/.test(l));
      const carries = carriesNotMain(j.ifText.trim(), main.conj);
      if (main.jobs.includes(name)) {
        if (j.ifText.includes(main.conj)) problems.push(`${file}: job ${name} is a seeder (Lean Fw.Ci.Trigger.seeders) but its \`if:\` skips a main push (edit by hand)`);
        continue;
      }
      if (carries) continue;
      problems.push(`${file}: job ${name} would run on a main push but is no seeder (Lean Fw.Ci.Trigger.seeders); its \`if:\` is not \`\${{ (<condition>) && (${main.conj}) }}\` (Lean carriesNotMain)`);
      if (k >= 0) lines[k] = `    if: ${withNotMain(j.ifText, main.conj)}`;
      else lines.splice(j.at + 1, 0, `    if: ${notMainIf(null, main.conj)}`);
    }
  }
  // 9. on.schedule: the row's crons (Lean `no_crons`: none, since a schedule runs on main)
  {
    const want = (row.crons ?? []).length ? ['  schedule:', ...row.crons.map((c) => `    - cron: '${c}'`)] : [];
    const [a, b] = onKeyRange(lines, 'schedule');
    if (lines.slice(a, b).join('\n') !== want.join('\n')) {
      problems.push(`${file}: on.schedule differs from the Lean row's crons (Lean Fw.Ci.Trigger.no_crons)`);
      lines = [...lines.slice(0, a), ...want, ...lines.slice(b)];
    }
  }
  // 10. on: holds only the Lean row's keys (Lean Fw.Ci.Trigger.onKeys_iff)
  if (!Array.isArray(row.onKeys)) problems.push(`${file}: the Lean row has no onKeys (lake test -- --write-ci-trigger-golden)`);
  else {
    for (const { key, text } of onKeys(lines)) {
      if (key === null) problems.push(`${file}: \`${text.trim()}\` under \`on:\` is no key at indent 2 (edit by hand)`);
      else if (!row.onKeys.includes(key)) problems.push(`${file}: on.${key} is not an allowed trigger [${row.onKeys.join(', ')}] (Lean Fw.Ci.Trigger.onKeys_iff; edit by hand)`);
    }
  }
  return { problems, text: lines.join('\n') };
}

/** Globs a GitHub `paths` filter and Lean `PathCheck.inScope` read the same way: literals, `*` inside a segment, `**` as a segment. */
export function portableGlob(g) {
  return !/[?+\[\]!{}]/.test(g) && !g.split('/').some((seg) => seg.includes('**') && seg !== '**') && !g.startsWith('/');
}

const READ = /(?<![^\s'"`;)|&<>])\.\.\/([^\s'"`;)|&<>]*)|\.\.\/[^\s'"`;)|&<>]*/g;

/** Lean `readsOf`: the repo paths a shell script under lean/scripts reads relative to lean/ (a `../<path>` at a word
 *  start); a path that is not a literal (empty, or with `$`, `*`, `?`, `{`) and a `../` inside a word are null, so the
 *  lint fails closed on them. */
export function leanScriptPaths(text) {
  return [...text.matchAll(READ)].map((m) => (m[1] === undefined || m[1] === '' || /[$*?{}]/.test(m[1]) ? null : m[1]));
}

export const normRead = (p) => p.split('/').filter((x) => x !== '' && x !== '.').join('/');

export const readPath = (p) => (p.split('/').includes('..') ? null : normRead(p));

export const rowGlob = (g) => /^[A-Za-z0-9._\-/*]+$/.test(g.startsWith('!') ? g.slice(1) : g);

export function gapsFrom(scripts, globs) {
  return scripts.flatMap(({ script, text }) => leanScriptPaths(text).map((p) => ({ script, path: p === null ? null : readPath(p) })))
    .filter((r) => r.path === null || !matches(globs, r.path));
}

export function leanRowGlobs(root, table) {
  const row = table.workflows.find((w) => w.file === 'lean.yml');
  return row ? expand(setMapFor(root, table), row.inputs) : [];
}

export function leanInputGaps(root, table) {
  const globs = leanRowGlobs(root, table);
  const dir = join(root, 'lean', 'scripts');
  const scripts = readdirSync(dir).filter((x) => x.endsWith('.sh')).sort().map((f) => ({ script: `lean/scripts/${f}`, text: readFileSync(join(dir, f), 'utf8') }));
  return gapsFrom(scripts, globs);
}

export function leanInputProblems(root, table) {
  if (!table.workflows.some((w) => w.file === 'lean.yml')) return ['lean.yml: no row in the Lean table (lean/Fw/Ci/Trigger.lean `table`)'];
  const bad = leanRowGlobs(root, table).filter((g) => !rowGlob(g))
    .map((g) => `lean.yml: row glob ${JSON.stringify(g)} is outside the plain subset (Lean Fw.Plan.WritesClosure.rowGlob: letters, digits, ._-/*), where the writes-closure matcher and GitHub agree`);
  if (bad.length) return bad;
  return leanInputGaps(root, table).map(({ script, path }) => path === null
    ? `${script}: reads a ../ path that is not at a word start, is not a literal file path, or has a .. segment (write it out as its own word, so the lean row can name it)`
    : `${script}: reads ../${path}, which is not an input of the lean.yml row (add it to lean/Fw/Ci/Trigger.lean \`table\`, then cd lean && lake test -- --write-ci-trigger-golden)`);
}

// ---- Node pin (tasks node-pin, node-pin-local) -----------------------------------------------------------------------
// One canonical Node version: the repo-root `.node-version` (exact x.y.z, at least NODE_MIN). Every `actions/setup-node`
// step takes it through `node-version-file: .node-version`, no workflow or action sets `node-version:`, a job that runs
// node/pnpm/npm/npx has such a step (or the setup-pnpm action), and every workflow that runs Node has a Lean row that lists
// `.node-version`, so a change of the pin starts the lanes that use Node. The pin is repeated in `.nvmrc`, `engines.node`
// and pnpm's `useNodeVersion` (pnpm-workspace.yaml); each copy must equal it.
// The decisions (pinValueProblems, jobProblems, rowProblems, copyProblems) are Lean (Fw.Ci.Trigger, section "The Node pin
// rule"); the functions below are their TS twins, checked against the golden `pin*` lines in ci-paths.test.mjs. The YAML
// reader (jobFacts) and the `.npmrc` engine-strict line are glue with no Lean twin (TS stand-in).
export const NODE_FILE = '.node-version';
export const NODE_MIN = [24, 22, 0];

/** Twin of Lean `pinValueProblems`. */
export function pinValueProblems(pin) {
  if (pin === null || pin === undefined) return ['noFile'];
  const m = /^(\d+)\.(\d+)\.(\d+)$/.exec(pin);
  if (!m) return ['notExact'];
  const v = m.slice(1).map(Number);
  for (let k = 0; k < 3; k++) if (v[k] !== NODE_MIN[k]) return v[k] > NODE_MIN[k] ? [] : ['tooOld'];
  return [];
}

/** Twin of Lean `jobProblems`. */
export function jobProblems(j) {
  const out = [];
  if (j.versionKey) out.push('versionKey');
  if (j.setups.some((s) => s !== NODE_FILE)) out.push('otherFile');
  if (j.runsNode && j.setups.length === 0 && !j.pnpmAction) out.push('unpinnedNode');
  if (j.nodeBeforeSetup) out.push('nodeBeforeSetup');
  return out;
}

/** The one trim of a pin file's content: ASCII space, tab, CR, LF only, as Lean `trimAscii` (Init/Data/Char/Basic.lean:97-98@v4.35.0). Not `String.trim`, which also strips U+FEFF, U+00A0, \f and \v. */
export const trimPin = (s) => s.replace(/^[ \t\r\n]+|[ \t\r\n]+$/g, '');

/** Twin of Lean `nodePinRefusal`: the refusal line when the running Node is not the pin, else null. */
export function nodePinRefusal(running, pinned) {
  if (pinned === null || pinned === undefined) return null;
  const want = trimPin(pinned);
  const seen = running.startsWith('v') ? running.slice(1) : running;
  if (seen === want) return null;
  return `refusing to start: running Node ${seen} but ${NODE_FILE} pins ${want}; run \`nvm install && nvm use\` (or start through \`pnpm\`, which uses the pinned Node) and retry`;
}

/** Twin of Lean `rowProblems`. */
export function rowProblems(usesNode, row) {
  if (!usesNode) return [];
  if (row === null || row === undefined) return ['noRow'];
  return row.includes(NODE_FILE) ? [] : ['rowLacksPin'];
}

/** Twin of Lean `copyProblems`: copies is [[name, value|null]]. */
export function copyProblems(pin, copies) {
  return copies.filter(([, v]) => (v ?? null) !== (pin ?? null)).map(([n]) => `differs:${n}`);
}

const SETUP_NODE = /\buses['"]?\s*:\s*['"]?actions\/setup-node@/;
const SETUP_PNPM = /\buses['"]?\s*:\s*['"]?\.\/\.github\/actions\/setup-pnpm['"]?\s*(?:[,}]|$)/;
const VERSION_KEY = /(^|[\s{,-])['"]?node-version['"]?\s*:/;
const FILE_KEY = /(^|[\s{,-])['"]?node-version-file['"]?\s*:\s*['"]?([^'"\s,}]*)/;
const NODE_CMD = /(^|[;&|(`]\s*|\$\(\s*|\bthen\s+|\bdo\s+|\bxargs\s+|\bexec\s+)(node|pnpm|npm|npx)(\s|$)/;

/** The lines of the step that holds line `i` (block or flow-map form): from its `- ` item line to the next item. */
function stepLines(lines, i) {
  let a = i;
  if (!/^\s*-\s/.test(lines[i])) { // `uses` is not the first key: walk up to the `- ` item line
    const k = indentOf(lines[i]);
    for (let n = i - 1; n >= 0; n--) if (!isBlank(lines[n]) && indentOf(lines[n]) < k) { a = n; break; }
  }
  const sk = indentOf(lines[a]);
  let b = a + 1;
  while (b < lines.length && (isBlank(lines[b]) || indentOf(lines[b]) > sk || (indentOf(lines[b]) === sk && !/^\s*-\s/.test(lines[b])))) b++;
  return lines.slice(a, b);
}

/** What the scanner reads off the lines of one job (or of a whole composite action): the facts of Lean `PinJob`.
 *  Reads the block form and the quoted and flow-map forms (`- { uses: 'actions/setup-node@x', with: { node-version-file: .node-version } }`). */
export function jobFacts(lines, nodeActions = []) {
  const f = { setups: [], versionKey: false, pnpmAction: false, runsNode: false, nodeBeforeSetup: false };
  let runIndent = -1;
  let firstSetup = -1; // line of the first setup-node / setup-pnpm step
  let firstNode = -1; // line of the first step that runs Node (a run: line or a node action other than telemetry)
  lines.forEach((l, i) => {
    if (isBlank(l)) return;
    const code = l.replace(/\s+#.*$/, '');
    if (VERSION_KEY.test(code.replace(/node-version-file/g, 'x'))) f.versionKey = true;
    if (SETUP_NODE.test(code)) {
      const m = stepLines(lines, i).map((x) => FILE_KEY.exec(x)).find(Boolean);
      f.setups.push(m ? m[2] : '');
    }
    if (SETUP_PNPM.test(code)) f.pnpmAction = true;
    if ((SETUP_NODE.test(code) || SETUP_PNPM.test(code)) && firstSetup < 0) firstSetup = i;
    if (nodeActions.some((a) => code.includes(`./.github/actions/${a}`))) { // a composite action that runs node
      f.runsNode = true;
      if (firstNode < 0) firstNode = i; // no exemption (Lean PinJob)
    }
    let run = null;
    if (runIndent >= 0) {
      if (indentOf(l) > runIndent) run = code.trim();
      else runIndent = -1;
    }
    if (run === null) {
      const m = /^\s*(?:-\s+)?['"]?run['"]?\s*:\s*(.*)$/.exec(code);
      if (m) {
        if (/^[|>][-+]?\d*$/.test(m[1].trim())) runIndent = indentOf(l.replace(/^(\s*)-\s+/, '$1  '));
        else run = m[1].trim().replace(/^['"]/, '');
      }
    }
    if (run !== null && NODE_CMD.test(run)) { f.runsNode = true; if (firstNode < 0) firstNode = i; }
  });
  f.nodeBeforeSetup = firstNode >= 0 && firstSetup >= 0 && firstNode < firstSetup;
  return f;
}

/** Problems of the Node pin: file shape, the copies of the pin, drift in workflows and actions, and Lean rows that miss the file. */
export function nodePinProblems(root, table) {
  const out = [];
  const read = (rel) => (existsSync(join(root, rel)) ? readFileSync(join(root, rel), 'utf8') : null);
  const raw = read(NODE_FILE);
  const pin = raw === null ? null : trimPin(raw);
  for (const c of pinValueProblems(pin)) {
    out.push(`${NODE_FILE}: ${c === 'tooOld' ? `${pin} is older than ${NODE_MIN.join('.')}` : `must hold one exact version x.y.z (got ${pin === null ? 'no file' : JSON.stringify(pin)})`}`);
  }
  const pkg = read('package.json');
  const ws = read('pnpm-workspace.yaml');
  const nvmrc = read('.nvmrc');
  const copies = [
    ['.nvmrc', nvmrc === null ? null : trimPin(nvmrc)],
    ['package.json engines.node', pkg === null ? null : (JSON.parse(pkg).engines?.node ?? null)],
    ['pnpm-workspace.yaml useNodeVersion', ws === null ? null : (/^useNodeVersion:\s*['"]?([^'"\s#]+)/m.exec(ws)?.[1] ?? null)],
  ];
  for (const p of copyProblems(pin, copies)) out.push(`${p.replace('differs:', '')}: must equal ${NODE_FILE} (${pin})`);
  const npmrc = read('.npmrc');
  if (npmrc === null || !/^engine-strict\s*=\s*true\s*$/m.test(npmrc)) out.push('.npmrc: must set engine-strict=true');
  const files = [];
  for (const f of readdirSync(join(root, WF_DIR)).filter((n) => n.endsWith('.yml'))) files.push({ rel: `${WF_DIR}/${f}`, wf: f });
  const actDir = join(root, '.github/actions');
  if (existsSync(actDir)) for (const d of readdirSync(actDir)) if (existsSync(join(actDir, d, 'action.yml'))) files.push({ rel: `.github/actions/${d}/action.yml`, wf: null });
  const rows = new Map(table.workflows.map((w) => [w.file, w]));
  const text = {
    versionKey: `sets node-version; use node-version-file: ${NODE_FILE}`,
    otherFile: `a setup-node step whose node-version-file is not ${NODE_FILE}`,
    nodeBeforeSetup: 'a step runs node before the job sets up the pinned Node (move actions/setup-node or the setup-pnpm action directly after actions/checkout)',
    unpinnedNode: `runs node/pnpm/npm/npx with no setup-node step (add actions/setup-node with node-version-file: ${NODE_FILE}, or the setup-pnpm action)`,
  };
  // composite actions that run node without setting it up: the job that uses one needs the pin, the action itself is judged through its callers
  const nodeActions = files.filter((x) => !x.wf).filter((x) => { const f = jobFacts(readFileSync(join(root, x.rel), 'utf8').split('\n')); return f.runsNode && !f.setups.length; }).map((x) => x.rel.split('/')[2]);
  for (const { rel, wf } of files) {
    const lines = readFileSync(join(root, rel), 'utf8').split('\n');
    let units;
    if (wf) {
      let jobs = [];
      try { jobs = readJobs(lines); } catch { out.push(`${rel}: jobs unreadable by the pin scanner`); }
      units = jobs.map((j) => ({ name: j.name, lines: lines.slice(j.at, j.end), at: j.at }));
    } else units = [{ name: 'action', lines, at: 0 }];
    let usesNode = false;
    for (const u of units) {
      const facts = jobFacts(u.lines, nodeActions);
      if (!wf && !facts.setups.length) facts.runsNode = false;
      if (facts.setups.length || facts.pnpmAction || facts.runsNode) usesNode = true;
      for (const c of jobProblems(facts)) out.push(`${rel}:${u.at + 1}: job ${u.name}: ${text[c]}`);
    }
    if (wf) {
      for (const c of rowProblems(usesNode, rows.has(wf) ? rows.get(wf).inputs : null)) {
        out.push(c === 'noRow' ? `${wf}: runs Node but has no row in the Lean table (lean/Fw/Ci/Trigger.lean \`table\`)` : `${wf}: runs Node but its Lean row (lean/Fw/Ci/Trigger.lean \`table\`) lacks "${NODE_FILE}"`);
      }
    }
  }
  return out;
}

/** The `name:` and `run-name:` of every workflow in Lean `Fw.Ci.Dispatch.dispatchWorkflows` equal what Lean says (the `workflows` line of
 *  packages/contracts/golden/ci/dispatch.jsonl: `list` and `runNames`, from `titleFor`). A run-name that drifts makes every identity
 *  wait (`fw ci wait --nonce`, `fw run`) find no run, so a difference is a problem here, not a timeout later. */
export function runNameProblems(root) {
  const out = [];
  let line;
  try {
    line = readFileSync(join(root, 'packages', 'contracts', 'golden', 'ci', 'dispatch.jsonl'), 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l)).find((l) => l.kind === 'workflows');
  } catch (e) { return [`dispatch golden unreadable: ${e.message}`]; }
  if (!line || !Array.isArray(line.list) || !Array.isArray(line.runNames) || line.list.length !== line.runNames.length) return ['the dispatch golden has no workflows line with list and runNames (lake test -- --write-ci-trigger-golden)'];
  line.list.forEach((w, i) => {
    const file = `${w}.yml`;
    let text;
    try { text = readFileSync(join(root, WF_DIR, file), 'utf8'); } catch { out.push(`${file}: in Lean dispatchWorkflows but no such workflow file`); return; }
    const lines = text.split('\n');
    const name = lines.find((l) => /^name:/.test(l));
    if (name?.slice(5).trim() !== w) out.push(`${file}: \`name:\` is \`${name?.slice(5).trim() ?? ''}\`, Lean dispatchWorkflows says \`${w}\` (the identity waits match the run title)`);
    const rn = lines.find((l) => /^run-name:/.test(l));
    if (rn?.slice(9).trim() !== line.runNames[i]) out.push(`${file}: \`run-name:\` is \`${rn?.slice(9).trim() ?? ''}\`, Lean titleFor says \`${line.runNames[i]}\``);
  });
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
  const problems = [...coneProblems(root, table), ...leanInputProblems(root, table), ...cacheWriterProblems(root, table), ...nodePinProblems(root, table), ...runNameProblems(root)];
  const caps = loadCaps(root);
  for (const k of caps.caps.keys()) if (!files.includes(k.split(' ')[0])) problems.push(`${k.split(' ')[0]}: Lean cap row but no such workflow file`);
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
    const c = capProblems(f, r.text, caps);
    problems.push(...c.problems);
    if (write && c.text !== text) { writeFileSync(join(dir, f), c.text); wrote++; }
  }
  return { problems, wrote };
}

export const CLOSURE_COMMIT = '9a09d8066';
export const PLAN_DOC = 'docs/team/tools/plan.md';
const CLOSURE_GOLDEN = 'packages/contracts/golden/plan/writes-closure.jsonl';
const ROOT = join(dirname(new URL(import.meta.url).pathname), '..');
const TIME_BEGIN = '<!-- plan-time begin: node scripts/ci-paths.mjs --plan-time -->';
const TIME_END = '<!-- plan-time end -->';

const ord = (xs, rank) => (rank === 0 ? 0 : [...xs].sort((a, b) => a - b)[rank - 1]);
export const p50 = (xs) => ord(xs, Math.floor((xs.length + 1) / 2));
export const p90 = (xs) => ord(xs, Math.floor((9 * xs.length + 9) / 10));
const maxL = (xs) => xs.reduce((a, b) => Math.max(a, b), 0);
const timeRow = (label, xs) => `| ${label} | ${xs.length} | ${p50(xs)} ms | ${p90(xs)} ms | ${maxL(xs)} ms |\n`;

/** Lean `timeParams` row of the writes-closure golden: `calmLoad` (Fw.Obs.Timing.calmLoad) and the before `window`. */
export function timeParams(root = ROOT) {
  const rows = readFileSync(join(root, CLOSURE_GOLDEN), 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
  const r = rows.find((x) => x.type === 'timeParams');
  if (!r) throw new Error(`${CLOSURE_GOLDEN}: no timeParams row (cd lean && lake env lean --run scripts/WritesClosureGolden.lean)`);
  return { calmLoad: r.calmLoad, window: r.window };
}

const calmDurs = (xs, calmLoad) => xs.filter(([, l]) => l <= calmLoad).map(([d]) => d);

/** Lean `timeTable` over `[durMs, load floor]` pairs: only calm runs (load floor at most `calmLoad`) enter the table. */
export function timeTable(before, after, { calmLoad, window }) {
  const cb = calmDurs(before, calmLoad);
  const b = cb.slice(Math.max(0, cb.length - window));
  const a = calmDurs(after, calmLoad);
  return `Calm runs only: load floor at most ${calmLoad} (Fw.Obs.Timing.calmLoad); ${cb.length + a.length} of ` +
    `${before.length + after.length} samples are calm.\n\n` +
    '| Window | n | p50 | p90 | max |\n|---|---|---|---|---|\n' + timeRow(`last ${b.length} calm runs before the closure check`, b) +
    timeRow('every calm run with it', a) + `\nINFERRED: the closure check adds about ${p50(a) - p50(b)} ms to a calm sync (p50 with it minus p50 before).\n`;
}

const day = (ms) => new Date(ms).toISOString().slice(0, 10);

export const loadFloor = (load) => Math.floor(Math.max(0, load));

export function planTimeBlock(samples, params = timeParams()) {
  const dur = (closure) => samples.filter((s) => s.closure === closure).map((s) => [s.durMs, loadFloor(s.load)]);
  const span = samples.length ? `${day(samples[0].startMs)} to ${day(samples.at(-1).startMs)}` : 'none';
  return `${TIME_BEGIN}\nMEASURED (the samples below, ${span}: every exit-0 \`plan sync\` span of the tool \`fw\` in the main ` +
    `checkout's\n\`.fw-console/timings.jsonl\` with a load; a run is "with it" when its commit contains ${CLOSURE_COMMIT}).\n\n` +
    `${timeTable(dur(false), dur(true), params)}\n<details><summary>Samples (node scripts/ci-paths.mjs --plan-time --refresh &lt;timings.jsonl&gt;)</summary>\n\n` +
    '```jsonl\n' + samples.map((s) => JSON.stringify(s) + '\n').join('') + '```\n\n</details>\n' + TIME_END;
}

function timeSpan(doc) {
  const i = doc.indexOf(TIME_BEGIN), j = doc.indexOf(TIME_END);
  if (i < 0 || j < i) throw new Error(`${PLAN_DOC}: no ${TIME_BEGIN} ... ${TIME_END} block`);
  return [i, j + TIME_END.length];
}

export function planTimeSamples(doc) {
  const [i, j] = timeSpan(doc);
  const m = doc.slice(i, j).match(/```jsonl\n([\s\S]*?)```/);
  return m ? m[1].split('\n').filter(Boolean).map((l) => JSON.parse(l)) : [];
}

export function planTimeRender(doc, samples = planTimeSamples(doc), params = timeParams()) {
  const [i, j] = timeSpan(doc);
  return doc.slice(0, i) + planTimeBlock(samples, params) + doc.slice(j);
}

function hasClosure(root, commit) {
  try { execFileSync('git', ['merge-base', '--is-ancestor', CLOSURE_COMMIT, commit], { cwd: root, stdio: 'ignore' }); return true; }
  catch (e) { return e.status === 1 ? false : null; }
}

export function planTimeRefresh(root, timingsFile) {
  const spans = readFileSync(timingsFile, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l))
    .filter((s) => s.tool === 'fw' && s.step === 'plan sync' && s.exit === 0 && s.host === 'local' && typeof s.commit === 'string')
    .sort((a, b) => a.startMs - b.startMs);
  const noLoad = spans.filter((s) => !Number.isFinite(s.load)).length;
  const known = new Map();
  const out = [];
  for (const s of spans) {
    if (!Number.isFinite(s.load)) continue;
    if (!known.has(s.commit)) known.set(s.commit, hasClosure(root, s.commit));
    const closure = known.get(s.commit);
    if (closure !== null) out.push({ commit: s.commit, startMs: s.startMs, durMs: s.durMs, load: s.load, closure });
  }
  return { samples: out, dropped: spans.length - out.length - noLoad, noLoad };
}

function planTimeMain(root, args) {
  const file = join(root, PLAN_DOC);
  const doc = readFileSync(file, 'utf8');
  const r = args.indexOf('--refresh');
  let samples = planTimeSamples(doc);
  if (r >= 0) {
    const got = planTimeRefresh(root, args[r + 1]);
    samples = got.samples;
    console.log(`ci-paths --plan-time: ${samples.length} samples, ${got.dropped} dropped (commit not in this repo), ${got.noLoad} without a load`);
  }
  const next = planTimeRender(doc, samples, timeParams(root));
  if (args.includes('--check')) {
    console.log(next === doc ? `ci-paths --plan-time: ${PLAN_DOC} is up to date` : `ci-paths --plan-time: ${PLAN_DOC} is stale (node scripts/ci-paths.mjs --plan-time)`);
    process.exit(next === doc ? 0 : 1);
  }
  writeFileSync(file, next);
  console.log(`ci-paths --plan-time: ${PLAN_DOC} written`);
}

function main() {
  const i = process.argv.indexOf('--root');
  const root = i >= 0 ? process.argv[i + 1] : join(dirname(new URL(import.meta.url).pathname), '..');
  if (process.argv.includes('--plan-time')) return planTimeMain(root, process.argv.slice(2));
  const write = process.argv.includes('--write');
  const { problems, wrote } = run(root, write);
  if (write) {
    console.log(`ci-paths: wrote ${wrote} workflow file(s)`);
    const left = problems.filter((p) => /by hand|not in the Lean table|no such workflow|not read the same|outside coneGlobs|no lane in the Lean intent|lean\/scripts\/|Lean cap row|run-name|dispatchWorkflows|Lean cap for job|has no Lean cap|does not run on macOS|runs-on is an expression/.test(p));
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
