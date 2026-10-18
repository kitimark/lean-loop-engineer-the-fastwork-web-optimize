#!/usr/bin/env node
// Land lock: nothing else commits in the main checkout while `fw land` advances it (incident inc-commit-during-land). The
// pre-lock land holds the lock only for the `merge --ff-only` instant (checks run before, in a land worktree); the fallback
// protocol still holds it around an open merge. Two users:
//   * `fw land` (src/land.ts) takes `<git common dir>/fw-land.lock` around merge --no-commit .. commit and releases it;
//   * the git `pre-commit` hook (scripts/hooks/pre-commit runs this file) refuses a commit in the locked checkout unless
//     it is the land's own (env FW_LAND_TOKEN = the lock's token).
// The decisions are Lean (`fwcore`: console.landLock, console.landGuard, console.landCommit; proofs in
// lean/Fw/Console/Land.lean). This file only reads facts (lock file, pid liveness, MERGE_HEAD, HEAD) and writes the file.
// Dependency-free, sync. A stale lock (dead pid) is reported, never removed here.
import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, readFileSync, realpathSync, unlinkSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { randomBytes } from "node:crypto";
import { fileURLToPath } from "node:url";

const git = (cwd, args) => execFileSync("git", args, { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();

/** Where fwcore is: FW_CORE_BIN, else <repo of this file>/lean/.lake/build/bin/fwcore. */
export function coreBin() {
  if (process.env.FW_CORE_BIN) return process.env.FW_CORE_BIN;
  return join(dirname(fileURLToPath(import.meta.url)), "../../../lean/.lake/build/bin/fwcore");
}

/** Ask Lean one op. The reply fields, or null when fwcore is missing, slow or refuses the request. */
export function askCore(op, req, bin = coreBin()) {
  if (!existsSync(bin)) return null;
  const r = spawnSync(bin, [], { input: JSON.stringify({ id: 1, op, ...req }) + "\n", encoding: "utf8", timeout: 30_000 });
  try {
    const m = JSON.parse((r.stdout ?? "").split("\n")[0] ?? "");
    return m && m.id === 1 && !m.error ? m : null;
  } catch { return null; }
}

/** The lock file of the repo that contains `cwd` (shared by every worktree: it lives in the common git dir). */
export function lockFile(cwd) {
  return join(git(cwd, ["rev-parse", "--path-format=absolute", "--git-common-dir"]), "fw-land.lock");
}

export function pidAlive(pid) {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try { process.kill(pid, 0); return true; } catch (e) { return e.code === "EPERM"; }
}

/** The lock {pid, branch, pre, dir, token, at}, `null` when there is none, `{ unreadable: true, pid: 0 }` when it is not JSON. */
export function readLock(file) {
  let raw;
  try { raw = readFileSync(file, "utf8"); } catch { return null; }
  try { const j = JSON.parse(raw); return j && typeof j === "object" ? j : { unreadable: true, pid: 0 }; } catch { return { unreadable: true, pid: 0 }; }
}

/** The facts the lock decisions read. */
export function lockFacts(file) {
  const lk = readLock(file);
  return { lock: lk, held: lk !== null, alive: lk !== null && pidAlive(lk.pid) };
}

/** Create the lock file atomically (fails when it exists). Returns the lock, or null when it already exists. */
export function takeLock(file, info) {
  const lock = { pid: process.pid, token: randomBytes(12).toString("hex"), at: new Date().toISOString(), ...info };
  try { writeFileSync(file, JSON.stringify(lock) + "\n", { flag: "wx" }); } catch (e) { if (e.code === "EEXIST") return null; throw e; }
  return lock;
}

/** Remove the lock file when it is ours (same token). Idempotent. */
export function dropLock(file, token) {
  const lk = readLock(file);
  if (lk && lk.token === token) { try { unlinkSync(file); } catch { /* already gone */ } return true; }
  return false;
}

/** The pre-commit decision for a commit made in `cwd` by a process with environment `env`. {allow, message}. */
export function guard(cwd, env = process.env) {
  const file = lockFile(cwd);
  const f = lockFacts(file);
  // no lock file: nothing to decide (Lean: guard_allows_unlocked); no need to start fwcore for every commit
  if (!f.held) return { allow: true, message: "" };
  const top = realpathSync(git(cwd, ["rev-parse", "--show-toplevel"]));
  const here = f.lock.dir ? top === f.lock.dir : true;
  const own = typeof env.FW_LAND_TOKEN === "string" && env.FW_LAND_TOKEN === f.lock.token;
  const r = askCore("console.landGuard", { held: true, alive: f.alive, here, own });
  const who = `fw land (pid ${f.lock.pid}, branch ${f.lock.branch ?? "?"}, since ${f.lock.at ?? "?"})`;
  if (!r) {
    // fail closed while a lock exists in this checkout: the decision could not be asked
    return here ? { allow: false, message: `commit refused: ${who} holds ${file} and fwcore is not available to decide (build lean/.lake)` } : { allow: true, message: "" };
  }
  if (r.verdict === "allow") return { allow: true, message: "" };
  if (r.verdict === "held") {
    return { allow: false, message: `commit refused: ${who} is advancing this checkout (${file}): normally a sub-second fast-forward, or a fallback land with its merge open. Retry in a moment, or stop that pid if it hangs.` };
  }
  return { allow: false, message: `commit refused: stale land lock ${file}: ${who} is no longer running. Not removed. Look at \`git status\` (an open merge: \`git merge --abort\`), then delete the file.` };
}

// `node land-guard.mjs` = the git pre-commit entry: exit 1 with the reason on stderr, else 0
if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url))) {
  try {
    const r = guard(process.cwd());
    if (!r.allow) { process.stderr.write(r.message + "\n"); process.exitCode = 1; }
  } catch (e) {
    process.stderr.write(`land-guard: ${e instanceof Error ? e.message : String(e)} (commit allowed: not a git checkout?)\n`);
  }
}
