#!/usr/bin/env node
// changed-inputs: the "paths guard" for macOS lanes on ci/* pushes.
//
// Problem: an agent merges main into its ci/* branch and pushes. GitHub's push `paths:` filter compares against the
// push's before-sha, so main's merged changes match and every macOS lane starts. This script answers the question the
// filter should have asked: does THIS BRANCH (merge-base with main ... HEAD) touch an input of the workflow?
//
// The globs are the workflow's PRECISE inputs (task ci-cone-glob): its row of the Lean table
// (packages/contracts/golden/ci/triggers.jsonl) with `@fwcore` / `@breakgen` expanded to the import cones computed from
// this checkout. The static `on.push.paths` hold only the coarse cone globs (`lean/Fw/**`, `lean/*.lean`), so a new
// module changes no workflow file, while this guard keeps the exact decision (Lean Fw.Ci.Trigger: starts_iff,
// push_filter_passes). Without a Lean row (or an unreadable golden) it falls back to the workflow's own `on.push.paths`
// (a superset). Usage in a first job on ubuntu (checkout with fetch-depth: 0):
//   node .github/scripts/changed-inputs.mjs --workflow .github/workflows/<name>.yml
// Env: EVENT_NAME (github.event_name), REF (github.ref), BEFORE (github.event.before), PATHS_GUARD_BASE (default origin/main).
// Output: `run=true|false` on stdout and in $GITHUB_OUTPUT, the reason and the files in $GITHUB_STEP_SUMMARY.
//   - not a push to refs/heads/ci/**  -> run=true (main pushes, workflow_dispatch, anything else always run)
//   - a push to ci/**                 -> run=true iff a file THIS PUSH changed (before..HEAD; the whole branch when `before` is
//                                        unknown or a new branch) and that differs from main's content matches one of the globs
//                                        (Lean Fw.Ci.Trigger: starts_iff, merge_starts_nothing)
//   - any error (no merge-base, git failure, unreadable globs) -> run=true: the guard fails open, never closed.
//
// GitHub's filter glob (docs "Filter pattern cheat sheet"): `*` any chars but `/`, `**` any chars, `?`/`+` zero-or-one /
// one-or-more of the preceding character, `[...]` a class, a leading `!` excludes (later patterns win).
import { execFileSync } from 'node:child_process';
import { appendFileSync, existsSync, readFileSync } from 'node:fs';
import { basename, dirname, join, normalize, relative } from 'node:path';
import { pathToFileURL } from 'node:url';

/** The Lean golden: the table line and the replay cases. */
export function loadGolden(root) {
  const lines = readFileSync(join(root, 'packages/contracts/golden/ci/triggers.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
  return { table: lines.find((l) => l.kind === 'table'), cases: lines.filter((l) => l.kind === 'case') };
}

/** Repo paths (under lean/) of the import cone of a root module: its file, every `import Fw...` module file, and the files
 *  they `include_str`. */
export function coneOf(root, rootModule) {
  const leanDir = join(root, 'lean');
  const modFile = (m) => (m === 'Main' || m === 'BreakgenMain' ? `${m}.lean` : `${m.replace(/\./g, '/')}.lean`);
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

/** Lean `setMap`: a named set's entries with `@cone:<Root>` replaced by `cone(<Root>)`; an unknown name stays as it is. */
export function setMapWith(table, cone) {
  return (g) => {
    const xs = table.sets[g];
    if (!xs) return [g];
    return xs.flatMap((h) => (h.startsWith('@cone:') ? cone(h.slice(6)) : [h]));
  };
}

/** The Lean `setMap` for the real checkout (cones computed from its files). */
export function setMapFor(root, table) {
  const cones = new Map();
  return setMapWith(table, (m) => { if (!cones.has(m)) cones.set(m, coneOf(root, m)); return cones.get(m); });
}

/** Lean `expand`: `@set` globs replaced by the set's contents (deduplicated, first occurrence wins). */
export function expand(S, inputs) {
  const out = [];
  for (const g of inputs.flatMap((x) => (x.startsWith('@') ? S(x) : [x]))) if (!out.includes(g)) out.push(g);
  return out;
}

/** The precise inputs of a workflow: its Lean row with the cones of the checkout at `root`; null when it has no row. */
export function preciseInputs(root, workflowFile) {
  const { table } = loadGolden(root);
  const row = table?.workflows.find((w) => w.file === basename(workflowFile));
  return row ? expand(setMapFor(root, table), row.inputs) : null;
}

/** The `paths:` list under `on: push:` of a workflow file (a restricted reader: block lists of scalars). */
export function parsePaths(yamlText) {
  const lines = yamlText.split(/\r?\n/);
  const indentOf = (l) => l.length - l.trimStart().length;
  const blank = (l) => l.trim() === '' || l.trim().startsWith('#');
  const find = (from, to, indent, key) => {
    for (let i = from; i < to; i++) {
      if (!blank(lines[i]) && indentOf(lines[i]) === indent && lines[i].trim().replace(/\s*#.*$/, '') === key) return i;
    }
    return -1;
  };
  // the end (exclusive) of the block that starts at line `at`: the next non-blank line at the same or a lower indent
  const endOf = (at) => {
    const ind = indentOf(lines[at]);
    for (let i = at + 1; i < lines.length; i++) if (!blank(lines[i]) && indentOf(lines[i]) <= ind) return i;
    return lines.length;
  };
  const on = find(0, lines.length, 0, 'on:');
  if (on < 0) throw new Error('no top-level `on:` in the workflow');
  const onEnd = endOf(on);
  const pushIndent = indentOf(lines.slice(on + 1, onEnd).find((l) => !blank(l)) ?? '  ');
  const push = find(on + 1, onEnd, pushIndent, 'push:');
  if (push < 0) throw new Error('no `push:` under `on:`');
  const pushEnd = Math.min(endOf(push), onEnd);
  const keyIndent = indentOf(lines.slice(push + 1, pushEnd).find((l) => !blank(l)) ?? '    ');
  const paths = find(push + 1, pushEnd, keyIndent, 'paths:');
  if (paths < 0) throw new Error('no `paths:` under `on: push:`');
  const out = [];
  for (let i = paths + 1; i < pushEnd; i++) {
    if (blank(lines[i])) continue;
    if (indentOf(lines[i]) <= keyIndent) break;
    const m = /^\s*-\s+(?:'([^']*)'|"([^"]*)"|([^#\s][^#]*?))\s*(?:#.*)?$/.exec(lines[i]);
    if (!m) throw new Error(`cannot read the paths item: ${lines[i]}`);
    out.push(m[1] ?? m[2] ?? m[3]);
  }
  if (out.length === 0) throw new Error('empty `paths:` list');
  return out;
}

/** A GitHub filter glob as a RegExp over a whole repo-relative path. */
export function globToRegExp(glob) {
  const tokens = []; // one regexp source per glob token, so ? and + can wrap the preceding one
  for (let i = 0; i < glob.length; i++) {
    const c = glob[i];
    if (c === '*') {
      if (glob[i + 1] === '*') {
        i++;
        if (glob[i + 1] === '/') { i++; tokens.push('(?:.*/)?'); } else tokens.push('.*');
      } else tokens.push('[^/]*');
    } else if (c === '?' || c === '+') {
      if (tokens.length === 0) throw new Error(`glob ${glob}: ${c} has nothing before it`);
      const prev = tokens.pop();
      tokens.push(`(?:${prev})${c}`);
    } else if (c === '[') {
      const end = glob.indexOf(']', i + 1);
      if (end < 0) throw new Error(`glob ${glob}: unclosed [`);
      tokens.push(glob.slice(i, end + 1).replace(/^\[!/, '[^'));
      i = end;
    } else tokens.push(c.replace(/[.\\^$|(){}]/g, '\\$&'));
  }
  return new RegExp(`^${tokens.join('')}$`);
}

/** Does `file` pass the glob list (a leading `!` excludes; later patterns win)? */
export function matches(globs, file) {
  let hit = false;
  for (const g of globs) {
    if (g.startsWith('!')) { if (globToRegExp(g.slice(1)).test(file)) hit = false; }
    else if (globToRegExp(g).test(file)) hit = true;
  }
  return hit;
}

/** The decision, pure: { run, reason, matched }. */
export function decide({ event, ref, files, globs }) {
  if (event !== 'push' || !String(ref).startsWith('refs/heads/ci/')) {
    return { run: true, reason: `${event} on ${ref}: always runs`, matched: [] };
  }
  const matched = files.filter((f) => matches(globs, f));
  return matched.length > 0
    ? { run: true, reason: `${matched.length} of ${files.length} changed file(s) since the merge-base with main match the inputs`, matched }
    : { run: false, reason: `none of the ${files.length} file(s) changed since the merge-base with main match the inputs`, matched };
}

/** Files changed from the merge-base of `base` and HEAD to HEAD (renames listed as delete + add). */
export function changedFiles(base, cwd = process.cwd(), before = '') {
  const git = (...a) => execFileSync('git', a, { cwd, encoding: 'utf8', maxBuffer: 64 << 20 }).trim();
  const lines = (t) => (t === '' ? [] : t.split('\n'));
  const mb = git('merge-base', base, 'HEAD');
  // the push's own diff: before..HEAD when `before` is a commit we have, else the whole branch (merge-base..HEAD)
  let lo = mb;
  if (/^[0-9a-f]{7,40}$/.test(before) && !/^0+$/.test(before)) {
    try { git('cat-file', '-e', `${before}^{commit}`); lo = before; } catch { /* not fetched: use the whole branch */ }
  }
  const pushed = lines(git('diff', '--name-only', '--no-renames', lo, 'HEAD'));
  // Lean `Fw.Ci.Trigger.effective`: keep the files whose new content is not already main's (a merge of main brings none)
  const differs = new Set(lines(git('diff', '--name-only', '--no-renames', base, 'HEAD')));
  return pushed.filter((f) => differs.has(f));
}

function arg(name) {
  const i = process.argv.indexOf(name);
  return i < 0 ? undefined : process.argv[i + 1];
}

function main() {
  const workflow = arg('--workflow');
  if (!workflow) throw new Error('usage: changed-inputs.mjs --workflow <file>');
  const event = process.env.EVENT_NAME ?? 'push';
  const ref = process.env.REF ?? '';
  const base = process.env.PATHS_GUARD_BASE || 'origin/main';
  let result;
  let files = [];
  let source = '';
  try {
    let globs = null;
    try { globs = preciseInputs(process.cwd(), workflow); } catch { globs = null; }
    source = globs ? 'the Lean table, cones from this checkout' : 'the workflow on.push.paths (no Lean row)';
    globs ??= parsePaths(readFileSync(workflow, 'utf8'));
    const guarded = event === 'push' && ref.startsWith('refs/heads/ci/');
    if (guarded) files = changedFiles(base, process.cwd(), process.env.BEFORE ?? '');
    result = decide({ event, ref, files, globs });
  } catch (e) {
    result = { run: true, reason: `guard error, failing open: ${e.message}`, matched: [] };
  }
  const line = `run=${result.run}`;
  console.log(line);
  console.log(result.reason);
  if (source) console.log(`inputs: ${source}`);
  for (const f of files) console.log(`${result.matched.includes(f) ? '  input ' : '  other '}${f}`);
  if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, `${line}\n`);
  if (process.env.GITHUB_STEP_SUMMARY) {
    const rows = files.slice(0, 200).map((f) => `- ${result.matched.includes(f) ? '**input**' : 'other'} \`${f}\``).join('\n');
    appendFileSync(
      process.env.GITHUB_STEP_SUMMARY,
      `### paths guard: ${line}\n${result.reason} (workflow \`${workflow}\`, base \`${base}\`, inputs: ${source})\n\n${rows}\n`,
    );
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
