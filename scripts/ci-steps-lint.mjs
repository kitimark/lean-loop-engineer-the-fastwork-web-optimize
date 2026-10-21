#!/usr/bin/env node
// ci-steps-lint: the steps after the measurement step of the five macOS jobs equal the Lean allowlist (Fw.Ci.Steps,
// golden packages/contracts/golden/ci/steps.jsonl). Rows, guard texts and the flagged jobs are READ from the golden; the
// functions below are TS stand-ins for Lean `labelOf`, `go`, `tailAfter`, `checkJob` and `coverage`, replayed against the
// golden cases by scripts/ci-steps-lint.test.mjs.
// Run:  node scripts/ci-steps-lint.mjs [--root <dir>]
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { readJobs } from './ci-paths.mjs';

export const GOLDEN = 'packages/contracts/golden/ci/steps.jsonl';
const WF_DIR = ['.git', 'hub/workflows'].join('');
const MACOS = /^(macos-|xcode-)/;

/** Lean `labelOf`: the step name, else its action without the ref. */
export function labelOf(name, uses) {
  if (name != null) return name;
  if (uses != null) return uses.split('@')[0];
  return '';
}

/** Lean `go`: problems of the observed steps against the allowed ones, walked in step. */
export function go(post, obs) {
  const out = [];
  let i = 0;
  let j = 0;
  while (i < post.length || j < obs.length) {
    if (j >= obs.length) { out.push(`missing:${post[i++].label}`); continue; }
    if (i >= post.length) { out.push(`unlisted:${obs[j++].label}`); continue; }
    const p = post[i];
    const o = obs[j];
    if (o.label === p.label) {
      if (o.ifText !== p.ifText) out.push(`cond:${o.label}`);
      if (o.timeout != null) out.push(`timeout:${o.label}`);
      i++;
      j++;
    } else if (obs.slice(j + 1).some((x) => x.label === p.label)) {
      out.push(`unlisted:${o.label}`);
      j++;
    } else {
      out.push(`missing:${p.label}`);
      i++;
    }
  }
  return out;
}

/** Lean `tailAfter`: the steps after the measurement step, or null unless it occurs exactly once. */
export function tailAfter(measure, steps) {
  const at = steps.findIndex((s) => s.label === measure);
  if (at < 0 || steps.slice(at + 1).some((s) => s.label === measure)) return null;
  return steps.slice(at + 1);
}

/** Lean `checkJob`. */
export function checkJob(row, steps) {
  const t = tailAfter(row.measure, steps);
  return t === null ? [`measure:${row.measure}`] : go(row.post, t);
}

/** Lean `coverage`: `rows` are the golden rows. */
export function coverage(rows, file, found) {
  const listed = rows.filter((r) => r.file === file).map((r) => r.job);
  return [...found.filter((j) => !listed.includes(j)).map((j) => `uncovered:${j}`),
    ...listed.filter((j) => !found.includes(j)).map((j) => `stale-row:${j}`)];
}

export function loadGolden(root) {
  const rows = readFileSync(join(root, GOLDEN), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
  return {
    rows: rows.filter((r) => r.kind === 'row'),
    flagged: rows.find((r) => r.kind === 'flagged').jobs,
    all: rows,
  };
}

const indentOf = (l) => l.length - l.trimStart().length;
const scalar = (v) => v.replace(/\s+#.*$/, '').trim().replace(/^'(.*)'$/, '$1');

/** The steps of one job as the lint sees them: label, `if:` text, `timeout-minutes` text. */
export function readSteps(lines, job) {
  const at = lines.findIndex((l, i) => i >= job.at && i < job.end && /^ {4}steps:\s*$/.test(l));
  if (at < 0) throw new Error(`job ${job.name}: no steps`);
  const steps = [];
  for (let i = at + 1; i < job.end; i++) {
    if (!/^ {6}- /.test(lines[i])) continue;
    let e = i + 1;
    while (e < job.end && (lines[e].trim() === '' || lines[e].trim().startsWith('#') || indentOf(lines[e]) > 6)) e++;
    const f = {};
    lines.slice(i, e).forEach((l, k) => {
      const m = /^ {8}([A-Za-z-]+):\s*(.*)$/.exec(k === 0 ? l.replace(/^( {6})- /, '$1  ') : l);
      if (m && !(m[1] in f)) f[m[1]] = m[2];
    });
    steps.push({
      label: labelOf(f.name != null ? scalar(f.name) : null, f.uses != null ? scalar(f.uses) : null),
      ifText: f.if != null ? f.if.replace(/\s+#.*$/, '').trim() : null,
      timeout: f['timeout-minutes'] != null ? scalar(f['timeout-minutes']) : null,
    });
    i = e - 1;
  }
  return steps;
}

/** Problems (`file/job: code`) and the flagged jobs of the tree under `root`. */
export function lint(root) {
  const g = loadGolden(root);
  const problems = [];
  for (const file of [...new Set(g.rows.map((r) => r.file))]) {
    const lines = readFileSync(join(root, WF_DIR, file), 'utf8').split('\n');
    const jobs = readJobs(lines);
    for (const p of coverage(g.rows, file, jobs.filter((j) => MACOS.test(j.runsOn)).map((j) => j.name))) problems.push(`${file}: ${p}`);
    for (const row of g.rows.filter((r) => r.file === file)) {
      const job = jobs.find((j) => j.name === row.job);
      if (!job) continue;
      for (const p of checkJob(row, readSteps(lines, job))) problems.push(`${file}/${row.job}: ${p}`);
    }
  }
  return { problems, flagged: g.flagged };
}

function main() {
  const i = process.argv.indexOf('--root');
  const root = i >= 0 ? process.argv[i + 1] : join(dirname(fileURLToPath(import.meta.url)), '..');
  const { problems, flagged } = lint(root);
  for (const f of flagged) console.log(`ci-steps-lint: follow-up, ${f} still shuts down a discarded Simulator`);
  if (problems.length) {
    for (const p of problems) console.error(`ci-steps-lint: ${p}`);
    process.exit(1);
  }
  console.log('ci-steps-lint: ok (the steps after the measurement step equal the Lean allowlist)');
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) main();
