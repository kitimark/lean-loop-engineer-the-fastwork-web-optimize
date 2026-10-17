#!/usr/bin/env node
// changed-inputs: the "paths guard" for macOS lanes on ci/* pushes.
//
// Problem: an agent merges main into its ci/* branch and pushes. GitHub's push `paths:` filter compares against the
// push's before-sha, so main's merged changes match and every macOS lane starts. This script answers the question the
// filter should have asked: does THIS BRANCH (merge-base with main ... HEAD) touch an input of the workflow?
//
// The globs are the workflow's own `on.push.paths` list (read from the workflow file, so there is one place to keep
// them). Usage in a first job on ubuntu (checkout with fetch-depth: 0):
//   node .github/scripts/changed-inputs.mjs --workflow .github/workflows/<name>.yml
// Env: EVENT_NAME (github.event_name), REF (github.ref), PATHS_GUARD_BASE (default origin/main).
// Output: `run=true|false` on stdout and in $GITHUB_OUTPUT, the reason and the files in $GITHUB_STEP_SUMMARY.
//   - not a push to refs/heads/ci/**  -> run=true (main pushes, workflow_dispatch, anything else always run)
//   - a push to ci/**                 -> run=true iff a file changed since the merge-base matches one of the globs
//   - any error (no merge-base, git failure, unreadable globs) -> run=true: the guard fails open, never closed.
//
// GitHub's filter glob (docs "Filter pattern cheat sheet"): `*` any chars but `/`, `**` any chars, `?`/`+` zero-or-one /
// one-or-more of the preceding character, `[...]` a class, a leading `!` excludes (later patterns win).
import { execFileSync } from 'node:child_process';
import { appendFileSync, readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

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
export function changedFiles(base, cwd = process.cwd()) {
  const git = (...a) => execFileSync('git', a, { cwd, encoding: 'utf8', maxBuffer: 64 << 20 }).trim();
  const mb = git('merge-base', base, 'HEAD');
  const out = git('diff', '--name-only', '--no-renames', mb, 'HEAD');
  return out === '' ? [] : out.split('\n');
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
  try {
    const globs = parsePaths(readFileSync(workflow, 'utf8'));
    const guarded = event === 'push' && ref.startsWith('refs/heads/ci/');
    if (guarded) files = changedFiles(base);
    result = decide({ event, ref, files, globs });
  } catch (e) {
    result = { run: true, reason: `guard error, failing open: ${e.message}`, matched: [] };
  }
  const line = `run=${result.run}`;
  console.log(line);
  console.log(result.reason);
  for (const f of files) console.log(`${result.matched.includes(f) ? '  input ' : '  other '}${f}`);
  if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, `${line}\n`);
  if (process.env.GITHUB_STEP_SUMMARY) {
    const rows = files.slice(0, 200).map((f) => `- ${result.matched.includes(f) ? '**input**' : 'other'} \`${f}\``).join('\n');
    appendFileSync(
      process.env.GITHUB_STEP_SUMMARY,
      `### paths guard: ${line}\n${result.reason} (workflow \`${workflow}\`, base \`${base}\`)\n\n${rows}\n`,
    );
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
