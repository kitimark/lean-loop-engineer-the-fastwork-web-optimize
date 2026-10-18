#!/usr/bin/env node
// ci-push (task ci-own-trigger): the one way an agent asks CI for runs. A push to ci/** starts only the lanes its head
// commit names with `[ci:<lane>]` tokens (Lean lean/Fw/Ci/Intent.lean; the guard `if:` and
// .github/scripts/changed-inputs.mjs), plus the default lane `lean` whenever its inputs changed (round 2: whatever lanes
// are named, `[ci:none]` included). This helper
//   1. checks every lane name against the Lean intent golden (packages/contracts/golden/ci/intent.jsonl),
//   2. adds an empty commit `ci: request [ci:a] [ci:b]` when the head commit does not already ask for exactly those lanes,
//   3. previews, with the guard's own `decide` over this push (fresh origin/main, the branch's remote tip as `before`),
//      which requested lanes would start, and refuses (exit 2) when none would,
//   4. pushes HEAD to origin ci/<name> (never forced).
// Every decision is the guard's (Lean-replayed); this file is argument parsing, git calls and printing.
// Run:  pnpm fw ci push --branch ci/<task> --lanes <lane,lane | none> [--dry]
//       (or node scripts/ci-push.mjs ...)
import { execFileSync } from 'node:child_process';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { changedFiles, decide, guardBase, isLanded, loadIntent, preciseInputs, wantedBy } from '../.github/scripts/changed-inputs.mjs';

export const USAGE = 'usage: fw ci push --branch ci/<name> --lanes <lane,lane | none> [--dry]\n' +
  '  lanes: the workflow file stems (lean, wktr, webkit-sim, ...); `none` asks for no lane (lean still runs when its\n' +
  '  inputs changed: it is the default lane).';

/** Parse the arguments: { branch, lanes, dry }; throws with USAGE on a bad flag. */
export function parseArgs(argv) {
  const a = { branch: '', lanes: null, dry: false };
  for (let i = 0; i < argv.length; i++) {
    const f = argv[i];
    const val = () => { const v = argv[++i]; if (v === undefined || v.startsWith('--')) throw new Error(`flag ${f} needs a value\n${USAGE}`); return v; };
    if (f === '--branch') a.branch = val();
    else if (f === '--lanes') a.lanes = val().split(',').map((x) => x.trim()).filter(Boolean);
    else if (f === '--dry') a.dry = true;
    else throw new Error(`unknown argument ${f}\n${USAGE}`);
  }
  if (!/^ci\/[A-Za-z0-9._/-]+$/.test(a.branch)) throw new Error(`--branch must be ci/<name>\n${USAGE}`);
  if (!a.lanes || a.lanes.length === 0) throw new Error(`--lanes is required (a list, or none)\n${USAGE}`);
  return a;
}

/** The lanes of the golden for the requested names; throws on an unknown name. `none` alone asks for no lane. */
export function lanesFor(golden, names) {
  const all = golden.lanes.map((l) => ({ ...l, prefix: golden.prefix }));
  if (names.length === 1 && names[0] === 'none') return [];
  return names.map((n) => {
    const l = all.find((x) => x.name === n);
    if (!l) throw new Error(`unknown lane ${n}; lanes: ${all.map((x) => x.name).join(', ')}, none`);
    return l;
  });
}

/** The commit message that asks for exactly these lanes (`[ci:none]` for none). */
export function requestMessage(golden, lanes) {
  const toks = lanes.length ? lanes.map((l) => l.token) : [`${golden.prefix}none]`];
  return `ci: request ${toks.join(' ')}`;
}

/** Whether a message asks for exactly these lanes (Lean `wanted`, as the guard reads it); a default lane is always
 *  wanted, so it counts as asked for. */
export function asksExactly(golden, lanes, msg) {
  const want = new Set([...lanes.map((l) => l.name), ...golden.lanes.filter((l) => l.byDefault).map((l) => l.name)]);
  return golden.lanes.every((l) => wantedBy({ ...l, prefix: golden.prefix }, msg) === want.has(l.name));
}

/** The requested lanes, then the default lanes not requested (shown in the preview, never a reason to push). */
export function previewLanes(golden, lanes) {
  const names = new Set(lanes.map((l) => l.name));
  return [...lanes, ...golden.lanes.filter((l) => l.byDefault && !names.has(l.name)).map((l) => ({ ...l, prefix: golden.prefix, implicit: true }))];
}

const git = (cwd, ...a) => execFileSync('git', a, { cwd, encoding: 'utf8', maxBuffer: 64 << 20, stdio: ['ignore', 'pipe', 'pipe'] }).trim();

/** The guard's decision for each requested lane on a push of HEAD to `branch` (`before`: the branch's remote tip). */
export function preview(cwd, lanes, msg, before, branch) {
  const base = guardBase(cwd);
  const files = changedFiles(base, cwd, before);
  const landed = isLanded(cwd);
  return lanes.map((l) => {
    const globs = preciseInputs(cwd, l.file) ?? [];
    const r = decide({ event: 'push', ref: `refs/heads/${branch}`, files, globs, msg, lane: l, newer: [], landed });
    return { lane: l.implicit ? `${l.name} (default lane)` : l.name, run: r.run, reason: r.reason, implicit: l.implicit === true };
  });
}

export function main(argv, cwd = process.cwd()) {
  let a;
  try { a = parseArgs(argv); } catch (e) { console.error(e.message); return 64; }
  const root = git(cwd, 'rev-parse', '--show-toplevel');
  const golden = loadIntent(root).lanes;
  let lanes;
  try { lanes = lanesFor(golden, a.lanes); } catch (e) { console.error(e.message); return 64; }
  // fresh refs: the guard on CI compares with today's main, so the preview must too
  git(root, 'fetch', '-q', '--no-tags', 'origin', 'main');
  const remote = git(root, 'ls-remote', 'origin', `refs/heads/${a.branch}`).split(/\s+/)[0] ?? '';
  if (remote) git(root, 'fetch', '-q', '--no-tags', 'origin', `refs/heads/${a.branch}`);
  const head = git(root, 'log', '-1', '--format=%B', 'HEAD');
  const needCommit = !asksExactly(golden, lanes, head);
  const msg = needCommit ? requestMessage(golden, lanes) : head;
  const plan = preview(root, previewLanes(golden, lanes), msg, remote, a.branch);
  for (const p of plan) console.log(`${p.run ? 'START' : 'skip '} ${p.lane}: ${p.reason}`);
  if (lanes.length > 0 && !plan.some((p) => p.run && !p.implicit)) {
    console.log('ci-push: no requested lane would start (its inputs are unchanged by this push, or landed). Change an input, or');
    console.log(`  dispatch a record run instead: gh workflow run <lane>.yml --ref ${a.branch}`);
    return 2;
  }
  if (a.dry) { console.log(`ci-push: dry: would ${needCommit ? `commit "${msg}" and ` : ''}push HEAD to origin ${a.branch}`); return 0; }
  if (needCommit) git(root, 'commit', '--allow-empty', '-q', '-m', msg);
  git(root, 'push', '-q', 'origin', `HEAD:refs/heads/${a.branch}`);
  console.log(`ci-push: pushed ${git(root, 'rev-parse', '--short', 'HEAD')} to ${a.branch}; wait with: pnpm fw ci wait --branch ${a.branch}`);
  return 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) process.exitCode = main(process.argv.slice(2));
export const SCRIPT = join('scripts', 'ci-push.mjs');
