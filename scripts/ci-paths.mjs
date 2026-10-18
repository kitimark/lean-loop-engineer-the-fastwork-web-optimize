#!/usr/bin/env node
// ci-paths: the push trigger of every workflow is decided in Lean (lean/Fw/Ci/Trigger.lean, task ci-trigger-lean) and
// written to packages/contracts/golden/ci/triggers.jsonl. This script expands that table against the checkout and
//   --check (default)  fails when a workflow's `on.push` (branches, paths) differs from the Lean decision, when a workflow
//                      lacks the `guard` job, or when a job does not (transitively) wait for it;
//   --write            rewrites those parts of the workflow files.
// It also checks the Lake cache writer (lean/Fw/Ops/LakeCache.lean, golden packages/contracts/golden/ops/lake-cache.jsonl):
// every job that uses setup-lean is in the Lean table, and exactly the table's writer passes `save: 'true'` (fixed by hand).
// `@fwcore` / `@breakgen` expand to the build files plus the import cone of Main.lean / BreakgenMain.lean (the files that
// can change the built binary), found by scanning `import Fw...` and `include_str` in lean/. A new import in a cone moves
// the paths, so the check fails until `--write` is run: the list cannot go stale silently.
// Run:  node scripts/ci-paths.mjs [--write | --check] [--root <dir>]
import { existsSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join, normalize, relative } from 'node:path';
import { pathToFileURL } from 'node:url';

const WF_DIR = ['.git', 'hub/workflows'].join('');
export const GUARD_SCRIPT = ['.git', 'hub/scripts/changed-inputs.mjs'].join('');

/** The Lean golden: the table line and the replay cases. */
export function loadGolden(root) {
  const lines = readFileSync(join(root, 'packages/contracts/golden/ci/triggers.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
  return { table: lines.find((l) => l.kind === 'table'), cases: lines.filter((l) => l.kind === 'case') };
}

/** The Lean Lake-cache table (one line per job that uses setup-lean), or null when the golden is absent (a fixture root). */
export function loadLakeCache(root) {
  const p = join(root, 'packages/contracts/golden/ops/lake-cache.jsonl');
  if (!existsSync(p)) return null;
  return readFileSync(p, 'utf8').trim().split('\n').map((l) => JSON.parse(l)).filter((l) => l.kind === 'job');
}

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

/** Problems of one workflow against the Lean Lake-cache table (fixed by hand: the Lean table decides). */
export function lakeCacheProblems(file, lines, rows) {
  const problems = [];
  const used = setupLeanJobs(lines);
  for (const u of used) {
    const r = rows.find((x) => x.file === file && x.job === u.job);
    if (!r) { problems.push(`${file}: job ${u.job} uses setup-lean but is not in lean/Fw/Ops/LakeCache.lean \`jobs\` (edit by hand)`); continue; }
    if ((u.save === 'true') !== r.saves) problems.push(`${file}: job ${u.job} passes save: '${u.save}' to setup-lean, the Lean table says ${r.saves} (edit by hand)`);
  }
  for (const r of rows.filter((x) => x.file === file)) {
    if (!used.some((u) => u.job === r.job)) problems.push(`${file}: lean/Fw/Ops/LakeCache.lean lists job ${r.job}, which does not use setup-lean (edit by hand)`);
  }
  return problems;
}

/** Repo paths (under lean/) of the import cone of a root module: its file, every `import Fw...` module file, and the files
 *  they `include_str`. */
export function coneOf(root, rootModule) {
  const leanDir = join(root, 'lean');
  const modFile = (m) => `${m.replace(/\./g, '/')}.lean`; // a root such as Main or BreakgenMain is lean/<Root>.lean
  const seen = new Set();
  const files = new Set();
  const queue = [rootModule];
  while (queue.length) {
    const m = queue.pop();
    if (seen.has(m)) continue;
    seen.add(m);
    const f = modFile(m);
    const abs = join(leanDir, f);
    if (!existsSync(abs)) continue;
    files.add(`lean/${f}`);
    const text = readFileSync(abs, 'utf8');
    for (const l of text.split('\n')) {
      const r = /^import\s+(\S+)/.exec(l);
      if (r && (r[1] === 'Fw' || r[1].startsWith('Fw.'))) queue.push(r[1]);
    }
    for (const r of text.matchAll(/include_str\s+"([^"]+)"/g)) {
      const inc = normalize(join(dirname(abs), r[1]));
      files.add(relative(root, inc));
    }
  }
  return [...files].sort();
}

/** The Lean `setMap` for the real checkout. */
export function setMapFor(root, table) {
  const cones = new Map();
  const cone = (m) => { if (!cones.has(m)) cones.set(m, coneOf(root, m)); return cones.get(m); };
  return (g) => {
    const xs = table.sets[g];
    if (!xs) return [g];
    return xs.flatMap((h) => (h.startsWith('@cone:') ? cone(h.slice(6)) : [h]));
  };
}

/** Lean `expand`: `@set` globs replaced by the set's contents (deduplicated, first occurrence wins). */
export function expand(S, inputs) {
  const out = [];
  for (const g of inputs.flatMap((x) => (x.startsWith('@') ? S(x) : [x]))) if (!out.includes(g)) out.push(g);
  return out;
}

const quote = (s) => `'${s}'`;
const branchItem = (b) => (/[*\[\]{}:,&!#|>%@`'"?\s]/.test(b) ? quote(b) : b);

/** The `push:` block the Lean decision gives, as lines. */
export function renderPush(branches, paths) {
  return ['  push:', `    branches: [${branches.map(branchItem).join(', ')}]`, '    paths:', ...paths.map((p) => `      - ${quote(p)}`)];
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
    for (let i = h.at + 1; i < end; i++) {
      if (indentOf(lines[i]) !== 4) continue;
      const n = /^ {4}needs:\s*(.*?)\s*(?:#.*)?$/.exec(lines[i]);
      if (n) {
        const v = n[1];
        if (v === '' || v.startsWith('-')) throw new Error(`job ${h.name}: write \`needs\` inline ([a, b]) so the reader can see it`);
        needs = v.replace(/^\[|\]$/g, '').split(',').map((x) => x.trim()).filter(Boolean);
      }
      if (/^ {4}if:/.test(lines[i])) hasIf = true;
    }
    return { name: h.name, at: h.at, end, needs, hasIf };
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

/** The text of the guard job for a workflow file. */
export function guardJob(file) {
  return [
    '  # Paths guard (Lean Fw.Ci.Trigger, scripts/ci-paths.mjs): on a ci/* push, runs the workflow only if THIS push changed one of',
    "  # its inputs (the paths list under `on.push`) to something other than main's content; main pushes, dispatches and",
    '  # schedules always run. Fails open on error.',
    '  guard:',
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
    `        run: node ${GUARD_SCRIPT} --workflow ${WF_DIR}/${file}`,
    '',
  ];
}

/** Everything wrong with one workflow's text, and the fixed text. */
export function reconcile(file, text, row, paths) {
  const problems = [];
  let lines = text.split('\n');
  // 1. on.push
  const [s, e] = pushRange(lines);
  const want = renderPush(row.branches, paths);
  if (lines.slice(s, e).join('\n') !== want.join('\n')) problems.push(`${file}: on.push differs from the Lean decision`);
  lines = [...lines.slice(0, s), ...want, ...lines.slice(e)];
  // 2. the guard job
  let jobs = readJobs(lines);
  if (!jobs.some((j) => j.name === 'guard')) {
    problems.push(`${file}: no \`guard\` job`);
    const at = lines.indexOf('jobs:');
    lines = [...lines.slice(0, at + 1), ...guardJob(file), ...lines.slice(at + 1)];
    jobs = readJobs(lines);
  }
  const g = jobs.find((j) => j.name === 'guard');
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
  return { problems, text: lines.join('\n') };
}

/** Globs a GitHub `paths` filter and Lean `PathCheck.inScope` read the same way: literals, `*` inside a segment, `**` as a segment. */
export function portableGlob(g) {
  return !/[?+\[\]!{}]/.test(g) && !g.split('/').some((seg) => seg.includes('**') && seg !== '**') && !g.startsWith('/');
}

/** Check (or write) every workflow. Returns { problems, wrote }. */
export function run(root, write) {
  const { table } = loadGolden(root);
  const S = setMapFor(root, table);
  const dir = join(root, WF_DIR);
  const files = readdirSync(dir).filter((f) => f.endsWith('.yml')).sort();
  const problems = [];
  let wrote = 0;
  const rows = new Map(table.workflows.map((w) => [w.file, w]));
  const lake = loadLakeCache(root);
  if (lake) for (const r of lake) if (!files.includes(r.file)) problems.push(`${r.file}: in lean/Fw/Ops/LakeCache.lean but no such workflow file (edit by hand)`);
  for (const w of table.workflows) if (!files.includes(w.file)) problems.push(`${w.file}: in the Lean table but no such workflow file`);
  for (const f of files) {
    const row = rows.get(f);
    if (!row) { problems.push(`${f}: not in the Lean table (lean/Fw/Ci/Trigger.lean \`table\`)`); continue; }
    const paths = expand(S, row.inputs);
    for (const p of paths) if (!portableGlob(p)) problems.push(`${f}: glob ${p} is not read the same by GitHub and by Lean PathCheck`);
    const text = readFileSync(join(dir, f), 'utf8');
    if (lake) { try { problems.push(...lakeCacheProblems(f, text.split('\n'), lake)); } catch (e) { problems.push(`${f}: ${e.message}`); } }
    let r;
    try { r = reconcile(f, text, row, paths); } catch (e) { problems.push(`${f}: ${e.message}`); continue; }
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
    const left = problems.filter((p) => /by hand|not in the Lean table|no such workflow|not read the same/.test(p));
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
