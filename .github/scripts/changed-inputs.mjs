#!/usr/bin/env node
// changed-inputs: the guard job of every workflow (Lean Fw.Ci.Intent `decision`, over Fw.Ci.Trigger `starts`).
//
// Round 3 of task ci-own-trigger. No workflow has a `paths` filter, so every push creates a run of every lane and this
// guard decides. On a push to ci/** it runs the workflow's jobs iff ALL of (else it skips with a tagged reason):
//   - `unwanted`: the head commit wants the lane: it names it with a token `[ci:<lane>]` (case-insensitive), or the
//     lane is a default lane (only `lean`, never a macOS lane). The guard job's own `if:` (Lean `ifExpr`, written by
//     scripts/ci-paths.mjs) already skips the guard, so no runner starts, when the lane is not wanted.
//   - `stale`: the commit is the branch tip (`git ls-remote`; a read error counts as the tip, fail open). An older push
//     never runs heavy work; the tip does (Lean `stale_guard_never_starts`, `tip_starts`).
//   - `landed`: the commit is not already on main (an ancestor of origin/main or origin/ci/landed).
//   - `unchanged`: some file that differs from main on the WHOLE branch (merge-base..HEAD, intersected with the files
//     whose content is not main's: Lean `effective`) is an input of the lane. Never this push's own diff, so a revert
//     in a later push cannot hide a change the branch still carries (Lean `tip_history_free`, `tip_lean_always`).
//     The inputs are the workflow's row of the Lean table (packages/contracts/golden/ci/triggers.jsonl) with
//     `@fwcore` / `@breakgen` expanded to the import cones of this checkout.
// Every heavy job then re-checks the tip in its first step and stops as `stale:` when a newer push moved it (Lean
// `stale_never_works`); no concurrency group is shared on ci/**, so nothing is cancelled (Lean Fw.Ci.Cancel).
// A push to main keeps the old rule: it runs iff its own diff (before..HEAD) passes the coarse paths globs (Lean
// `main_keeps_paths_rule`, `pushPaths`). Dispatches and schedules always run (`record_always_runs`). Any error fails
// open (run=true), never closed.
// Usage in a first job on ubuntu (checkout with fetch-depth: 0):
//   node .github/scripts/changed-inputs.mjs --workflow .github/workflows/<name>.yml
// Env: EVENT_NAME (github.event_name), REF (github.ref), BEFORE (github.event.before), GUARD_TOKEN (github.token, for
// ls-remote), PATHS_GUARD_BASE (default: origin/ci/landed when it contains origin/main, else origin/main).
// Output: `run=true|false` and `reason=<tag>: <one line>` in $GITHUB_OUTPUT (the guard's `decision: skip: <reason>`
// step shows the reason in the run's jobs, read by `fw ci wait`: Lean Fw.Ci.Verdict `skipOf`), the reason and the
// files on stdout and in $GITHUB_STEP_SUMMARY.
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

/** The Lean intent golden (Fw.Ci.Intent): the lanes (name, token, macOS and default flags, the guard `if:`), the
 *  replay cases, the gate vectors and the push vectors (`pushOk`). */
export function loadIntent(root) {
  const lines = readFileSync(join(root, 'packages/contracts/golden/ci/intent.jsonl'), 'utf8').trim().split('\n').map((l) => JSON.parse(l));
  return { lanes: lines.find((l) => l.kind === 'lanes'), cases: lines.filter((l) => l.kind === 'case'), gates: lines.filter((l) => l.kind === 'gate'),
    push: lines.find((l) => l.kind === 'push') };
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

/** Lean `wanted`: a default lane always, any other lane when the message names its token (case-insensitive). */
export function wantedBy(lane, msg) {
  return lane.byDefault === true || lowerAscii(msg).includes(lane.token);
}


/** The coarse push globs of a workflow (Lean `pushPaths`: every cone replaced by `coneGlobs`); null without a row. */
export function pushInputs(root, workflowFile) {
  const { table } = loadGolden(root);
  const row = table?.workflows.find((w) => w.file === basename(workflowFile));
  return row ? expand(setMapWith(table, () => table.coneGlobs), row.inputs) : null;
}

/** Lean `evOf`: `ci` for a push to refs/heads/ci/**, `main` for any other push, else `record`. */
export function evOf(event, ref) {
  if (event === 'push' && String(ref).startsWith('refs/heads/ci/')) return 'ci';
  return event === 'push' ? 'main' : 'record';
}

/** The decision, pure (Lean Fw.Ci.Intent `decision`): { run, reason, matched }; a skip reason starts with its tag
 *  (Lean `Skip.tag`). `files`: on a ci push the branch's effective files (merge-base..HEAD that differ from main); on a
 *  main push the push's own diff, or null when unknown (runs). `globs`: the lane's precise inputs; `pushGlobs`: its
 *  coarse push globs (main pushes). `lane` null: no Lean lane, so every push is wanted. `tip`: HEAD is the branch tip. */
export function decide({ event, ref, files, globs, pushGlobs = globs, msg = '', lane = null, tip = true, landed = false }) {
  const ev = evOf(event, ref);
  if (ev === 'record') return { run: true, reason: `${event} on ${ref}: always runs (a record)`, matched: [] };
  if (ev === 'main') {
    if (files == null) return { run: true, reason: 'main push with an unknown before commit: runs (fail open)', matched: [] };
    const matched = files.filter((f) => matches(pushGlobs, f));
    if (matched.length === 0) return { run: false, reason: `unchanged: none of the ${files.length} file(s) this main push changed match the paths globs`, matched };
    return { run: true, reason: `${matched.length} of ${files.length} file(s) this main push changed match the paths globs`, matched };
  }
  if (lane && !wantedBy(lane, msg)) {
    return { run: false, reason: `unwanted: the head commit does not name ${lane.token} and ${lane.name} is not a default lane`, matched: [] };
  }
  if (!tip) return { run: false, reason: 'stale: a newer push is the branch tip; its run decides', matched: [] };
  if (landed) return { run: false, reason: 'landed: this commit is already on main', matched: [] };
  const matched = files.filter((f) => matches(globs, f));
  if (matched.length === 0) {
    return { run: false, reason: `unchanged: none of the ${files.length} file(s) that differ from main on the branch match the inputs`, matched };
  }
  return { run: true, reason: `${matched.length} of ${files.length} file(s) that differ from main on the branch match the inputs${lane ? `; the head commit wants ${lane.name}` : ''}`, matched };
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

/** The branch tip on the remote (`git ls-remote`, with the job token when given): its sha, or '' when unreadable.
 *  actions/checkout points origin/<branch> at the pushed commit, so the remote is asked. */
export function remoteTip(ref, cwd = process.cwd(), token = '') {
  const auth = token ? ['-c', `http.extraheader=AUTHORIZATION: basic ${Buffer.from(`x-access-token:${token}`).toString('base64')}`] : [];
  const tip = (gitIn(cwd, ...auth, 'ls-remote', 'origin', ref).split(/\s+/)[0] ?? '').trim();
  return /^[0-9a-f]{40}$/.test(tip) ? tip : '';
}

/** Lean `tip`: HEAD is the branch tip; an unreadable tip counts as the tip (fail open). */
export function isTip(head, tip) {
  return tip === '' || tip === head;
}

/** The reason as one `$GITHUB_OUTPUT` value and step-name text: one line, no `\r`, at most 200 characters. */
export function outputLine(reason) {
  return String(reason).replace(/[\r\n]+/g, ' ').slice(0, 200);
}

/** Lean `effective` over the whole branch: files changed from the merge-base of `base` and HEAD to HEAD whose content
 *  at HEAD is not `base`'s (renames listed as delete + add). */
export function branchFiles(base, cwd = process.cwd()) {
  const mb = gitIn(cwd, 'merge-base', base, 'HEAD');
  const branch = linesOf(gitIn(cwd, 'diff', '--name-only', '--no-renames', mb, 'HEAD'));
  const differs = new Set(linesOf(gitIn(cwd, 'diff', '--name-only', '--no-renames', base, 'HEAD')));
  return branch.filter((f) => differs.has(f));
}

/** A main push's own diff (before..HEAD); null when `before` is not a commit we have (a new branch, a force push). */
export function pushFiles(before, cwd = process.cwd()) {
  if (!/^[0-9a-f]{7,40}$/.test(before) || /^0+$/.test(before)) return null;
  try { gitIn(cwd, 'cat-file', '-e', `${before}^{commit}`); } catch { return null; }
  return linesOf(gitIn(cwd, 'diff', '--name-only', '--no-renames', before, 'HEAD'));
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
    let pushGlobs = null;
    try { globs = preciseInputs(process.cwd(), workflow); pushGlobs = pushInputs(process.cwd(), workflow); } catch { globs = null; }
    try { lane = laneFor(process.cwd(), workflow); } catch { lane = null; }
    source = globs ? 'the Lean table, cones from this checkout' : 'no Lean row: every file';
    globs ??= ['**'];
    pushGlobs ??= ['**'];
    const ev = evOf(event, ref);
    let msg = '';
    let landed = false;
    let tip = true;
    if (ev === 'ci') {
      base ||= guardBase();
      files = branchFiles(base);
      msg = gitIn(process.cwd(), 'log', '-1', '--format=%B', 'HEAD');
      console.log(`head commit: ${msg.split('\n')[0]}`); // the intent the guard read
      landed = isLanded();
      try {
        const t = remoteTip(ref, process.cwd(), process.env.GUARD_TOKEN ?? '');
        tip = isTip(gitIn(process.cwd(), 'rev-parse', 'HEAD'), t);
        console.log(`branch tip: ${t || 'unreadable (counts as the tip)'}`);
      } catch (e) { console.log(`tip check skipped (counts as the tip): ${String(e.message).split('\n')[0]}`); }
    } else if (ev === 'main') {
      files = pushFiles(process.env.BEFORE ?? '');
    }
    result = decide({ event, ref, files, globs, pushGlobs, msg, lane, tip, landed });
  } catch (e) {
    result = { run: true, reason: `guard error, failing open: ${e.message}`, matched: [] };
  }
  const line = `run=${result.run}`;
  console.log(line);
  console.log(result.reason);
  if (source) console.log(`inputs: ${source}; lane: ${lane ? lane.name : 'none'}; base: ${base || 'n/a'}`);
  for (const f of files ?? []) console.log(`${result.matched.includes(f) ? '  input ' : '  other '}${f}`);
  if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, `${line}\nreason=${outputLine(result.reason)}\n`);
  if (process.env.GITHUB_STEP_SUMMARY) {
    const rows = (files ?? []).slice(0, 200).map((f) => `- ${result.matched.includes(f) ? '**input**' : 'other'} \`${f}\``).join('\n');
    appendFileSync(
      process.env.GITHUB_STEP_SUMMARY,
      `### guard: ${line}\n${result.reason} (workflow \`${workflow}\`, lane \`${lane ? lane.name : 'none'}\`, base \`${base || 'n/a'}\`, inputs: ${source})\n\n${rows}\n`,
    );
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
