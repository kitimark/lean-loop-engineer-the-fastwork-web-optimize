#!/usr/bin/env node
// changed-inputs: the guard job of every workflow (Lean Fw.Ci.Intent `start`, over Fw.Ci.Trigger `starts`).
//
// A run starts only when someone asked for it (task ci-own-trigger). On a push to ci/** the guard runs the workflow's
// jobs iff ALL of:
//   - the head commit wants the lane: it names it with a token `[ci:<lane>]` (case-insensitive), or it carries no
//     `[ci:` at all and the lane is a default lane (only `lean`, never a macOS lane). `[ci:none]` asks for nothing.
//     Lean `wanted`, `no_unrequested_start`, `default_no_macos`. The guard job's own `if:` (Lean `ifExpr`, written by
//     scripts/ci-paths.mjs) already skips the guard, so no runner starts, when the lane is not wanted.
//   - THIS push changed one of the lane's inputs to something other than main's content: before..HEAD (the whole branch
//     when `before` is unknown or a new branch) intersected with the files that differ from the base (Lean
//     Fw.Ci.Trigger `effective`, `starts_iff`). The inputs are the workflow's row of the Lean table
//     (packages/contracts/golden/ci/triggers.jsonl) with `@fwcore` / `@breakgen` expanded to the import cones of this
//     checkout; without a row, the workflow's own `on.push.paths` (a superset).
//   - no newer push on the branch changed one of those inputs (`superseded`; the tip is read with `git ls-remote`, so a
//     run that waited behind a newer push does not start its jobs). Lean `superseded_never_runs_heavy`.
//   - the commit is not already on main (`landed`: an ancestor of origin/main or of origin/ci/landed). Lean
//     `landed_never_runs_heavy`.
// Anything that is not a push to ci/** (main pushes, workflow_dispatch, schedules) always runs: a run there is a record
// (Lean `record_always_runs`). Any error fails open (run=true), never closed.
// Usage in a first job on ubuntu (checkout with fetch-depth: 0):
//   node .github/scripts/changed-inputs.mjs --workflow .github/workflows/<name>.yml
// Env: EVENT_NAME (github.event_name), REF (github.ref), BEFORE (github.event.before), GUARD_TOKEN (github.token, for
// ls-remote), PATHS_GUARD_BASE (default: origin/ci/landed when it contains origin/main, else origin/main).
// Output: `run=true|false` on stdout and in $GITHUB_OUTPUT, the reason and the files in $GITHUB_STEP_SUMMARY.
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

/** The Lean intent golden (Fw.Ci.Intent): the lanes (name, token, macOS and default flags, the guard `if:`) and the
 *  replay cases. */
export function loadIntent(root) {
  const lines = readFileSync(join(root, 'packages/contracts/golden/ci/intent.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
  return { lanes: lines.find((l) => l.kind === 'lanes'), cases: lines.filter((l) => l.kind === 'case') };
}

/** The lane of a workflow file (Lean `laneOf`), with the token prefix; null when it has none. */
export function laneFor(root, workflowFile) {
  const { lanes } = loadIntent(root);
  const l = lanes?.lanes.find((x) => x.file === basename(workflowFile));
  return l ? { ...l, prefix: lanes.prefix } : null;
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

/** Lean `lower`: only ASCII A-Z lowered (Lean `Char.toLower`). */
export function lowerAscii(m) {
  return String(m).replace(/[A-Z]/g, (c) => c.toLowerCase());
}

/** Lean `wanted`: with intent (some `[ci:`) exactly the named lanes, without intent the default lanes. */
export function wantedBy(lane, msg) {
  const low = lowerAscii(msg);
  return low.includes(lane.prefix ?? '[ci:') ? low.includes(lane.token) : lane.byDefault === true;
}

/** The decision, pure (Lean Fw.Ci.Intent `start`): { run, reason, matched }. `lane` null: no Lean lane, so every
 *  push is wanted (the old path-only guard). `newer`: files changed between this commit and the branch tip. */
export function decide({ event, ref, files, globs, msg = '', lane = null, newer = [], landed = false }) {
  if (event !== 'push' || !String(ref).startsWith('refs/heads/ci/')) {
    return { run: true, reason: `${event} on ${ref}: always runs (a record)`, matched: [] };
  }
  if (lane && !wantedBy(lane, msg)) {
    const why = lowerAscii(msg).includes(lane.prefix ?? '[ci:')
      ? `the head commit asks for other lanes, not ${lane.token}`
      : `the head commit has no [ci:<lane>] request and ${lane.name} is not a default lane`;
    return { run: false, reason: why, matched: [] };
  }
  const matched = files.filter((f) => matches(globs, f));
  if (matched.length === 0) {
    return { run: false, reason: `none of the ${files.length} file(s) this push changed (and that differ from main) match the inputs`, matched };
  }
  if (landed) return { run: false, reason: 'this commit is already on main (landed)', matched };
  const sup = newer.filter((f) => matches(globs, f));
  if (sup.length > 0) return { run: false, reason: `superseded: a newer push on the branch changed ${sup.length} input file(s)`, matched };
  return { run: true, reason: `${matched.length} of ${files.length} changed file(s) match the inputs${lane ? `; the head commit wants ${lane.name}` : ''}`, matched };
}

const gitIn = (cwd, ...a) => execFileSync('git', a, { cwd, encoding: 'utf8', maxBuffer: 64 << 20, stdio: ['ignore', 'pipe', 'pipe'] }).trim();
const linesOf = (t) => (t === '' ? [] : t.split('\n'));

/** The guard's base for "differs from main": origin/ci/landed (a mirror of the landed main, when the lead keeps one)
 *  when it exists and contains origin/main, else origin/main. */
export function guardBase(cwd = process.cwd()) {
  try {
    gitIn(cwd, 'rev-parse', '--verify', '-q', 'refs/remotes/origin/ci/landed');
    gitIn(cwd, 'merge-base', '--is-ancestor', 'refs/remotes/origin/main', 'refs/remotes/origin/ci/landed');
    return 'origin/ci/landed';
  } catch {
    return 'origin/main';
  }
}

/** Lean `landed`: HEAD is an ancestor of one of the main refs. */
export function isLanded(cwd = process.cwd(), refs = ['origin/main', 'origin/ci/landed']) {
  for (const r of refs) {
    try { gitIn(cwd, 'rev-parse', '--verify', '-q', `refs/remotes/${r}`); } catch { continue; }
    try { gitIn(cwd, 'merge-base', '--is-ancestor', 'HEAD', `refs/remotes/${r}`); return true; } catch { /* not an ancestor */ }
  }
  return false;
}

/** Lean `newer`: the files changed between HEAD and the branch's current tip on the remote ([] when HEAD is the tip).
 *  actions/checkout points origin/<branch> at the pushed commit, so the tip is read with ls-remote. */
export function newerFiles(ref, cwd = process.cwd(), token = '') {
  const auth = token ? ['-c', `http.extraheader=AUTHORIZATION: basic ${Buffer.from(`x-access-token:${token}`).toString('base64')}`] : [];
  const tip = (gitIn(cwd, ...auth, 'ls-remote', 'origin', ref).split(/\s+/)[0] ?? '').trim();
  if (!/^[0-9a-f]{40}$/.test(tip) || tip === gitIn(cwd, 'rev-parse', 'HEAD')) return [];
  try { gitIn(cwd, 'cat-file', '-e', `${tip}^{commit}`); } catch { gitIn(cwd, ...auth, 'fetch', '-q', '--no-tags', '--filter=blob:none', 'origin', tip); }
  return linesOf(gitIn(cwd, 'diff', '--name-only', '--no-renames', 'HEAD', tip));
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
  let base = process.env.PATHS_GUARD_BASE || '';
  let result;
  let files = [];
  let source = '';
  let lane = null;
  try {
    let globs = null;
    try { globs = preciseInputs(process.cwd(), workflow); } catch { globs = null; }
    try { lane = laneFor(process.cwd(), workflow); } catch { lane = null; }
    source = globs ? 'the Lean table, cones from this checkout' : 'the workflow on.push.paths (no Lean row)';
    globs ??= parsePaths(readFileSync(workflow, 'utf8'));
    const guarded = event === 'push' && ref.startsWith('refs/heads/ci/');
    let msg = '';
    let landed = false;
    let newer = [];
    if (guarded) {
      base ||= guardBase();
      files = changedFiles(base, process.cwd(), process.env.BEFORE ?? '');
      msg = gitIn(process.cwd(), 'log', '-1', '--format=%B', 'HEAD');
      console.log(`head commit: ${msg.split('\n')[0]}`); // the intent the guard read
      landed = isLanded();
      // superseded is best effort: on a read error the run counts as not superseded (fail open)
      try { newer = newerFiles(ref, process.cwd(), process.env.GUARD_TOKEN ?? ''); } catch (e) { console.log(`superseded check skipped: ${String(e.message).split('\n')[0]}`); }
    }
    result = decide({ event, ref, files, globs, msg, lane, newer, landed });
  } catch (e) {
    result = { run: true, reason: `guard error, failing open: ${e.message}`, matched: [] };
  }
  const line = `run=${result.run}`;
  console.log(line);
  console.log(result.reason);
  if (source) console.log(`inputs: ${source}; lane: ${lane ? lane.name : 'none'}; base: ${base || 'n/a'}`);
  for (const f of files) console.log(`${result.matched.includes(f) ? '  input ' : '  other '}${f}`);
  if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, `${line}\n`);
  if (process.env.GITHUB_STEP_SUMMARY) {
    const rows = files.slice(0, 200).map((f) => `- ${result.matched.includes(f) ? '**input**' : 'other'} \`${f}\``).join('\n');
    appendFileSync(
      process.env.GITHUB_STEP_SUMMARY,
      `### guard: ${line}\n${result.reason} (workflow \`${workflow}\`, lane \`${lane ? lane.name : 'none'}\`, base \`${base || 'n/a'}\`, inputs: ${source})\n\n${rows}\n`,
    );
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
