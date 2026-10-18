#!/usr/bin/env node
// ci-paths: the push trigger of every workflow is decided in Lean (lean/Fw/Ci/Trigger.lean, task ci-trigger-lean) and
// written to packages/contracts/golden/ci/triggers.jsonl. This script expands that table against the checkout and
//   --check (default)  fails when a workflow's `on.push` (branches, paths) differs from the Lean decision, when a workflow
//                      lacks the `guard` job, or when a job does not (transitively) wait for it;
//   --write            rewrites those parts of the workflow files.
// `@fwcore` / `@breakgen` name the build files plus the import cone of Main.lean / BreakgenMain.lean. In `on.push.paths`
// every cone is the fixed `coneGlobs` of the golden (`lean/Fw/**`, `lean/*.lean`; Lean `pushPaths`), so a new module
// changes no workflow file (task ci-cone-glob, `paths_stable_under_new_module`). The guard job computes the precise cone
// at run time (.github/scripts/changed-inputs.mjs). This check fails when a cone file falls outside `coneGlobs`
// (Lean `ConeWithin`, the hypothesis of `coarse_sound`).
// Run:  node scripts/ci-paths.mjs [--write | --check] [--root <dir>]
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { coneOf, loadGolden, matches, setMapWith, expand } from '../.github/scripts/changed-inputs.mjs';

const WF_DIR = ['.git', 'hub/workflows'].join('');
export const GUARD_SCRIPT = ['.git', 'hub/scripts/changed-inputs.mjs'].join('');

// The cone reader and the Lean `setMap` / `expand` live in the guard script, which runs them at run time on CI.
export { coneOf, expand, loadGolden, setMapFor, setMapWith } from '../.github/scripts/changed-inputs.mjs';

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
  const S = coarseMap(table);
  const dir = join(root, WF_DIR);
  const files = readdirSync(dir).filter((f) => f.endsWith('.yml')).sort();
  const problems = coneProblems(root, table);
  let wrote = 0;
  const rows = new Map(table.workflows.map((w) => [w.file, w]));
  for (const w of table.workflows) if (!files.includes(w.file)) problems.push(`${w.file}: in the Lean table but no such workflow file`);
  for (const f of files) {
    const row = rows.get(f);
    if (!row) { problems.push(`${f}: not in the Lean table (lean/Fw/Ci/Trigger.lean \`table\`)`); continue; }
    const paths = expand(S, row.inputs);
    for (const p of paths) if (!portableGlob(p)) problems.push(`${f}: glob ${p} is not read the same by GitHub and by Lean PathCheck`);
    const text = readFileSync(join(dir, f), 'utf8');
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
    const left = problems.filter((p) => /by hand|not in the Lean table|no such workflow|not read the same|outside coneGlobs/.test(p));
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
