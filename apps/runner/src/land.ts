// `fw land <branch> [--task <id>] [--allow <glob>]...`: the only way to main. Every decision is made by console-api
// (Lean: card readiness; `Fw.Console.Land.landVerdict` for the file scope); this file runs git and the checks, sends
// typed commands, and prints a digest. It merges (never rebases), never pushes, never forces, and touches only the
// lead's main checkout (plus removing a finished, clean, unlocked worktree of the landed branch).
import { execFileSync, spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { appendFileSync, existsSync, mkdirSync, readdirSync, readFileSync, realpathSync, rmSync, unlinkSync, writeFileSync } from "node:fs";
import { availableParallelism, loadavg } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { Command } from "@fw/contracts";
import { branchCard } from "../../console-api/src/reconcile/naming.ts";
import { begin, record, span } from "./timing.ts";
import { cachedLaneView, circleciAdapter, DEFAULT_ALLOW, githubAdapter, makePusher, BUILD_ARGV, runTiered, spawnWait, type Adapter, type OverflowPlan, type Provider } from "./land-remote.ts";
import { ccStatusFrom, forceFullFromEnv, ghStatusOnce, overflowFor, readSlots, realCircle } from "./land-overflow.ts";
import { askCore, dropLock, lockFacts, lockFile, readLock, takeLock } from "../hooks/land-guard.mjs";
import { FWCORE_STALE_REASON, checkFailKind, failedStages, fwcoreStale, lintPlan, outcome, outcomeKind, type Kind, type Outcome } from "./land-verdict.ts";
import { consoleSecret } from "./lib.ts";
import { ConsoleUnreachable } from "./land-queue.ts";
import { chargedGh, fwcoreCall, ghCost } from "./run.ts";
import { chargedOnce, realEnv, type Env } from "@fw/gh-budget";

export type Http = {
  get(path: string): Promise<{ status: number; body: any }>;
  post(path: string, body: unknown): Promise<{ status: number; body: any }>;
};

/** `localhost` may resolve to ::1 first while console-api listens on 127.0.0.1 only: always dial the IPv4 loopback. */
export const loopback = (base: string) => base.replace(/^(https?:\/\/)localhost(?=[:/]|$)/, "$1127.0.0.1");
/** Own deadline per request, shorter than undici's 300 s headers timeout; the land step's retry takes it from there. */
export const HTTP_DEADLINE_MS = 90_000;
export const httpFor = (base0: string): Http => { const base = loopback(base0); let secret: string | undefined;
  // a refused or reset connection (undici: TypeError "fetch failed") is a console that is not listening: ConsoleUnreachable, which the queue retries after a bounded health wait
  const dial = async (p: string, init: RequestInit): Promise<Response> => {
    // `connection: close`: one socket per request, never a pooled keep-alive socket the console already closed while this process sat in
    // a synchronous call (worktree cleanup, fwcore rebuild: 4-9 s, past the console's 5 s keepAliveTimeout); that reuse is an ECONNRESET
    try { return await fetch(base + p, { ...init, headers: { ...(init.headers as Record<string, string> | undefined), connection: "close" }, signal: AbortSignal.timeout(HTTP_DEADLINE_MS) }); }
    catch (e) { throw e instanceof TypeError ? new ConsoleUnreachable(base, (e as { cause?: unknown }).cause ?? e) : e; }
  };
  return {
    get: async (p) => { const r = await dial(p, {}); return { status: r.status, body: await r.json() }; },
    post: async (p, b) => {
      const r = await dial(p, { method: "POST", headers: { "content-type": "application/json", "x-fw-secret": (secret ??= consoleSecret()) }, body: JSON.stringify(b) });
      return { status: r.status, body: await r.json() };
    },
  }; };

export type LandOptions = {
  http: Http;
  /** any directory of the repo (main checkout or a worktree) */
  cwd: string;
  mainRef?: string;
  /** how to send the land request: default is the capability door `/api/agent/commands` with `argv` */
  argv?: string[];
  submit?: (cmd: Command) => Promise<{ status: number; body: any }>;
  /** checks run in the main checkout after the merge, before it is committed; default: derived from the changed files */
  checks?: string[][];
  /** the remote tier waits on the land lane of these providers (task land-wait); `false` runs every check on this Mac. Default: GitHub only. */
  remote?: false | { allow?: Provider[]; adapters?: Partial<Record<Provider, Adapter>>; sliceS?: number; deadlineS?: number; waitsLeft?: number };
  /** Max checks running at once (default: the number of cores). */
  concurrency?: number;
  env?: Record<string, string | undefined>;
  /** work-graph task this landing completes: merged with --no-ff and a `Task: <id>` trailer; the reconciler then
   *  derives task.done from that trailer (the only evidence route) */
  task?: string;
  /** explicit extra scope globs (`--allow`), recorded in the merge message */
  allow?: string[];
  /** advisory CI conclusions of the task's ci/* ref; default: one `gh run list` call; `false` skips it */
  ci?: false | ((ref: string) => string[]);
  /** attribution lines of the merge commit; default: the lead's */
  attribution?: string[];
  /** run after a successful landing, in the main checkout (plan sync); its lines are printed; it throws when it failed */
  after?: (mainDir: string) => Promise<string[]>;
  /** run after a worktree removal: stops the processes Lean selects (TERM, grace, KILL of unchanged survivors; `reapStopLines`) and returns the report lines; tests inject a stub */
  reap?: (mainDir: string) => Promise<string[]>;
  /** console-api base URL, only used to print the commands for steps that failed after the commit */
  base?: string;
  /** pause between the two attempts of a post-commit step (ms); default 700 */
  retryMs?: number;
  /** check the merge in a dedicated land worktree before the lock and fast-forward under it (default true); false = the locked protocol only */
  prelock?: boolean;
  /** re-checks after main moved before the fallback to the locked protocol (default PRELOCK_RETRIES) */
  retries?: number;
  /** how long to wait for another land's (sub-second) lock before refusing (ms); default 10000 */
  lockWaitMs?: number;
  /** `--dry` (needs `task`): only the cheap stages (stale base, scope, merge-tree, the static reads test on the merge tree); no lock, no
   *  full check, main untouched. Lean `Fw.Console.LandDry` decides the kind (`Outcome.kind`). */
  dry?: boolean;
  /** the dry land's reads test: its argv and whether the change selects it; default: the land-inputs test, selected when the change
   *  selects the reads-scan check (`LandSpeed.scan_selected`; tests inject both) */
  dryReads?: { argv: string[]; selected?: boolean };
  /** the dry land's fast lints (argv list, run in the merge-tree worktree); default: `dryLintArgv` (ci-paths --check, and the math-view
   *  lint when the change touches `lean/`) */
  dryLints?: string[][];
};
/** `ok` = main was changed (or, on a refusal, left as it was). Post-commit trouble never turns it false: it is in `warnings`
 *  (also printed as lines) with the commands that finish the job. */
export type LandResult = { ok: boolean; lines: string[]; warnings?: string[];
  /** the verdict kind (Lean `Fw.Console.LandVerdict.Kind`): `done` after a landing, `dry` after a passing dry land, else the refusal's kind */
  kind?: Kind;
  /** a dry land: the stage outcomes; `fw.ts` prints `dryRun(outcome, task)` (Lean `Fw.Console.LandDry.dryRun`) and `kind` is `outcomeKind(outcome)` */
  outcome?: Outcome };

export const ATTRIBUTION = [
  "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>",
  "Claude-Session: https://claude.ai/code/session_01R3GWpzaWka38ev9uPDctoA",
];
/** a leftover conflict marker at the start of a line */
export const MARKER_RE = "^(<<<<<<<|>>>>>>>)";

const git = (cwd: string, args: string[]) => execFileSync("git", args, { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
/** Personal-data scan (scripts/scrub.mjs --range) of what a ci/land push adds to origin, run from the main checkout so a branch cannot set its own gate: null when clean, else the hits (rule and place, never values). */
const scanRange = (dir: string, mainDir: string, mergeSha: string): string | null => {
  try { execFileSync("node", [join(mainDir, "scripts/scrub.mjs"), "--range", "origin/main", mergeSha], { cwd: mainDir, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }); return null; }
  catch (e) { return String((e as { stderr?: string }).stderr ?? e).replace(/\s+/g, " ").slice(0, 300); }
};
const tryGit = (cwd: string, args: string[]) => { try { git(cwd, args); return true; } catch { return false; } };
const tryGitEnv = (cwd: string, args: string[], env: Record<string, string>) => {
  try { execFileSync("git", args, { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], env: { ...process.env, ...env } }); return true; } catch { return false; }
};
const tryHead = (cwd: string) => { try { return git(cwd, ["rev-parse", "--short", "HEAD"]); } catch { return "?"; } };

type Wt = { dir: string; branch: string | null; locked: string | null };
/** All worktrees with their branch and lock reason (`""` = locked without a reason). */
export function worktrees(cwd: string): Wt[] {
  const out: Wt[] = [];
  let cur: Wt | null = null;
  for (const l of git(cwd, ["worktree", "list", "--porcelain"]).split("\n")) {
    if (l.startsWith("worktree ")) { cur = { dir: l.slice(9), branch: null, locked: null }; out.push(cur); }
    else if (cur && l.startsWith("branch refs/heads/")) cur.branch = l.slice(18);
    else if (cur && (l === "locked" || l.startsWith("locked "))) cur.locked = l.slice(7);
  }
  return out;
}

/** Directory where `ref` is checked out, or null. */
export function worktreeOf(cwd: string, ref: string): string | null {
  return worktrees(cwd).find((w) => w.branch === ref)?.dir ?? null;
}

const alive = (pid: number) => { try { process.kill(pid, 0); return true; } catch (e) { return (e as NodeJS.ErrnoException).code === "EPERM"; } };

/** A check with its declared input set: path globs in the `Fw.Ops.PathCheck` syntax (`!` excludes). The premise
 *  `land.readsOnly` says the check's verdict depends only on the files these globs select. */
export type Check = { id: string; argv: string[]; reads: string[] };

// --- TS stand-in for Lean `Fw.Ops.PathCheck.inScope` (lean/Fw/Ops/PathCheck.lean:26-82); marked for Lean replacement
// (an `fwcore` op); checked against the `landSpeed.select` golden (test/land-inputs.test.ts).
const segs = (s: string) => s.split("/").filter((x) => x !== "" && x !== ".");
const segMatch = (g: string, s: string): boolean => {
  if (g === "") return s === "";
  if (g[0] === "*") return segMatch(g.slice(1), s) || (s !== "" && segMatch(g, s.slice(1)));
  return s !== "" && g[0] === s[0] && segMatch(g.slice(1), s.slice(1));
};
const globMatch = (g: string[], p: string[]): boolean => {
  if (g.length === 0) return p.length === 0;
  if (g[0] === "**") return globMatch(g.slice(1), p) || (p.length > 0 && globMatch(g, p.slice(1)));
  return p.length > 0 && segMatch(g[0]!, p[0]!) && globMatch(g.slice(1), p.slice(1));
};
const matchesPath = (g: string[], p: string[]) => p.some((_, k) => globMatch(g, p.slice(0, k + 1)));
/** `inScope(parseScope(globs), path)` */
export function inScope(globs: string[], path: string): boolean {
  const p = segs(path);
  const incl = globs.filter((g) => !g.startsWith("!")).map(segs);
  const excl = globs.filter((g) => g.startsWith("!")).map((g) => segs(g.slice(1)));
  return p.length > 0 && !p.includes("..") && incl.some((g) => matchesPath(g, p)) && !excl.some((g) => matchesPath(g, p));
}
/** `selectChecks`: ids of the checks one of whose declared globs covers a changed path, in table order. */
export const selectChecks = (ds: { id: string; reads: string[] }[], changed: string[]) =>
  ds.filter((d) => changed.some((c) => inScope(d.reads, c))).map((d) => d.id);

/** What `lean/scripts/check.sh` reads: Lean `Fw.Console.LandSpeed.checkShReads` (equal to the golden's declaration). */
export const CHECK_SH_READS = ["lean/**", "packages/contracts/golden/**", "apps/site/src/breakpoints.gen.json", "apps/site/src/sweeps.gen.json", "apps/site/src/head.gen.json", "packages/gate-breakpoints/src/scope.gen.json", ".github/workflows/**", "scripts/span.sh", "scripts/fwcore-build.sh", "scripts/fwcore-record-rule.sh", "scripts/lake-slot.sh", "scripts/lake-slot-lib.sh", "scripts/heavy-lock.mjs", "docs/team/incidents/ledger.json",
  "research/findings/ledger.json", "apps/site/src/parts/**", "apps/site/src/registry/presets/v2-proved.json", "packages/measure-chromium/scenarios.gen.json"];
export const INSTALL_READS = ["pnpm-lock.yaml", "**/package.json"];
/** apps/site reads of snapshot assets, derived from the one source apps/site/assets.manifest.json (listed <=> copied <=> read). */
export function siteAssetReads(manifestPath = join(new URL(import.meta.url).pathname, "../../../site/assets.manifest.json")): string[] {
  const m = JSON.parse(readFileSync(manifestPath, "utf8")) as { files: { src: string }[]; bundled?: string[] };
  return [...new Set([...m.files.map((f) => f.src), ...(m.bundled ?? [])])].sort();
}
const WALLCLOCK_LINT_FILES = ["scripts/lint-wallclock.mjs", "scripts/wallclock-allow.json", "scripts/lint-wallclock-cases/**"];
// land-wallclock-off-gate: test/wallclock-lint.test.ts (runner and console-api) runs scripts/lint-wallclock.mjs, which reads
// the three files above and every tracked test file in its SCOPE. The runner wrapper also declares those test files, so a
// changed or new test file anywhere selects the runner and with it the lint; console-api declares only the lint's own files.
const WALLCLOCK_LINT_TESTS = ["scripts/*.test.mjs", "apps/*/test/**", "packages/*/test/**", ".github/scripts/*.test.mjs", "apps/site/src/**/*.test.*", "apps/site/scripts/*.test.*"];

/** Files a package's tests read outside their own directory and outside their `workspace:` dependencies, found by the
 *  static scan in test/land-inputs.test.ts (which fails on any it finds that is not covered here). Dynamic reads the scan
 *  cannot see are listed in docs/team/handoffs/checksfor-inputs.md. */
export const PACKAGE_EXTRA_READS: Record<string, string[]> = {
  "apps/console-api": ["lean/Fw/Console/PreviewFacts.lean", "snapshot/site/index.html", "apps/console-web/**", "apps/runner/hooks/lib.mjs", "apps/runner/src/plan.ts", "packages/contracts/golden/**", "apps/site/src/registry/resolve.ts", "apps/site/src/registry/types.ts", ...WALLCLOCK_LINT_FILES],
  "apps/runner": ["lean/**", ...WALLCLOCK_LINT_FILES, ...WALLCLOCK_LINT_TESTS, "apps/console-api/**", "docs/team/work-graph.json", "docs/team/incidents/ledger.json", "lean/scripts/check-imports.mjs",
    "packages/contracts/golden/**", "packages/gh-budget/test/util.ts", "scripts/span.sh",
    // ci-trigger-lean: test/ci-triggers.test.ts reads every workflow, the guard script and the lint
    ".github/workflows/**", ".github/scripts/changed-inputs.mjs", ".github/scripts/changed-inputs.test.mjs", "scripts/ci-paths.mjs", "scripts/ci-paths.test.mjs",
    // ci-own-trigger: the intent helper and its test (run by test/ci-triggers.test.ts; fw ci push spawns it)
    "scripts/ci-push.mjs", "scripts/ci-push.test.mjs", "scripts/hooks/**",
    // circleci-pilot: the glue, its fixtures and the pilot config (test/ci-triggers.test.ts runs scripts/circleci.test.mjs; fw ci circleci spawns the glue)
    "scripts/circleci.mjs", "scripts/circleci.test.mjs", "scripts/circleci-fixtures/**", ".circleci/**",
    // macos-telemetry: test/ci-telemetry-mac.test.ts checks that the note embeds the tables Lean renders from the committed dataset
    "research/notes/2026/10-2x-macos-telemetry.md",
    // lake-build-slots: test/ci-triggers.test.ts runs the build-slot wrapper's tests (they also read golden/** above)
    "scripts/lake-slot.sh", "scripts/lake-slot-lib.sh", "scripts/lake-slot.test.mjs",
    // sup-baseline: test/watch-collect-sup.test.ts runs scripts/sim-lock.sh in a scratch repo to check its lock events
    "scripts/sim-lock.sh",
    // scrub-session-paths: test/scrub.test.ts runs the privacy scrub's tests (test-scrub.mjs is outside the scripts/*.test.mjs glob)
    "scripts/scrub.mjs", "scripts/test-scrub.mjs", "scripts/scrub.test.mjs", "scripts/scrub-allow.json",
    // ci-telemetry: test/ci-telemetry.test.ts runs the producer's own tests and replays golden/ci/telemetry.jsonl (golden/** above)
    "scripts/ci-telemetry/**",
    // site-build-cache: ci-paths reads each setup-lean job's Lake targets (lakefile, the scripts its run: blocks call) into
    // the generated lean/Fw/Ops/LakeJobsGen.lean and compares
    "lean/lakefile.toml", "lean/scripts/**", "apps/site/scripts/**", "lean/Fw/Ops/LakeJobsGen.lean"],
  // svg-extract: scripts/svg-extract.mjs (build, test, typecheck) and src/svg-extract.test.ts read the snapshot page and its scripts
  "apps/site": ["lean/Fw/Parts/HiddenPause.lean", "lean/Fw/Parts/HeroCountdownHidden.lean", "packages/gate-breakpoints/src/serve.mjs", "packages/gate-breakpoints/src/anchors.json", "packages/contracts/golden/parts/**",
    // earn-transition-retarget: src/parts/nav/look-change.test.ts reads the look-change list
    "packages/contracts/golden/preset/look-change.candidates.jsonl",
    "packages/contracts/golden/port/**", "scripts/port/**", "packages/visual-diff/src/engines.mjs", "packages/visual-diff/src/fonts.mjs", "snapshot/site/index.html", "snapshot/site/_app/**", ...siteAssetReads()],
  "packages/measure-wktr": ["packages/measure-chromium/src/fwcore.mjs", "packages/measure-webkit/src/page.mjs", "packages/measure-webkit/src/serve.mjs"],
  "packages/measure-chromium": ["lean/Fw/Store/Layout.lean", "lean/Fw/Faithful/Measured.lean", "packages/contracts/golden/measure/**", "packages/contracts/golden/faithful/**", "packages/contracts/golden/parts/stage-mode.jsonl", ".github/workflows/chromium-counts.yml", "results/baselines/chromium/**",
    // device-lag-recorder: test/profile.test.mjs reads golden/device/session.jsonl loader lines
    "packages/contracts/golden/device/**"],
  "packages/gate-breakpoints": ["lean/**", "packages/measure-webkit/src/device.mjs", "scripts/sim-lock.sh", "apps/site/src/breakpoints.gen.json", "apps/site/src/parts/**",
    "packages/contracts/golden/gate/**", "packages/contracts/golden/parts/**",
    // image-audit: the test compares the byte copy of arm.mjs that packages/measure-webkit keeps (visual-diff is a workspace
    // dependency, so workspaceDeps already reads packages/visual-diff/**)
    "packages/measure-webkit/src/images/arm.mjs", "apps/site/src/flags/images/drawn.json",
    // smoothness-webkit-cadence: src/smooth/webkit-cadence.mjs imports the WebKit profile recorder, its Lean twin, the raw-window writer and the arm plan
    "packages/measure-webkit/src/profile/recorder.mjs", "packages/measure-webkit/src/profile/reduce.mjs", "packages/measure-webkit/src/profile/raw.mjs", "packages/measure-webkit/src/device-arms.mjs"],
  "packages/premise-tests": ["packages/gate-breakpoints/src/align-equiv.mjs"],
  // preview-e2e: the rig starts console-api's server files (imported by file URL) and the preview servers over the snapshot
  "packages/e2e-preview": ["apps/console-api/src/**", "apps/console-api/package.json", "packages/contracts/src/**", "packages/contracts/package.json", "packages/contracts/golden/console/**", "snapshot/site/**"],
  "packages/engine-check": ["packages/contracts/golden/measure/**"],
  "packages/difftest": ["apps/console-api/src/cap/cap.ts", "apps/runner/hooks/cap.mjs", "packages/measure-chromium/src/n0.mjs",
    "packages/measure-chromium/src/trace.mjs", "packages/measure-webkit/src/quietsteps.mjs", "packages/measure-webkit/src/reduce.mjs"],
  "packages/measure-webkit": ["packages/contracts/golden/measure/**", "apps/site/src/flags/images/drawn.json",
    // device-lag-recorder: the session twin reads golden/device/session.jsonl and imports the CI profile loader that checks an exported replay
    "packages/contracts/golden/device/**", "packages/measure-chromium/src/profile.mjs", "packages/measure-chromium/profiles/**",
    // device-lag-recorder: device-arms.mjs resolves the arms' URLs from the site's presets and part files at record time
    "apps/site/src/registry/presets/**", "apps/site/src/parts/**",
    // webkit-lag-probe: test/lag-findings.test.mjs reads the note whose Findings it checks against the generated block
    "research/notes/2026/10-21-webkit-lag-probe.md",
    // smoothness-webkit-cadence: the profile report classifies with fwcore, the sim leg reuses the Chromium lane's schedule, hitch rule and arm-identity check
    "packages/measure-chromium/src/fwcore.mjs", "packages/gate-breakpoints/src/smooth/schedule.mjs", "packages/gate-breakpoints/src/smooth/reduce.mjs",
    "packages/gate-breakpoints/src/trajectory/reduce.mjs"],
  "packages/snapshot-extract": ["packages/gate-breakpoints/src/**"],
  "packages/visual-diff": ["packages/gate-breakpoints/src/**", "apps/site/src/breakpoints.gen.json", "packages/contracts/golden/gate/**", "scripts/port/**", "packages/contracts/golden/port/**"],
};

/** Directories of the `workspace:` dependencies of a package (`@fw/x` is `packages/x` or `apps/x`). */
function workspaceDeps(root: string, pkg: any): string[] {
  const out: string[] = [];
  for (const [n, v] of Object.entries({ ...pkg.dependencies, ...pkg.devDependencies, ...pkg.peerDependencies } as Record<string, string>)) {
    if (!String(v).startsWith("workspace:")) continue;
    const base = n.replace(/^@[^/]+\//, "");
    const d = ["packages", "apps"].map((t) => `${t}/${base}`).find((x) => existsSync(join(root, x, "package.json")));
    if (d) out.push(d);
  }
  return out;
}

/** Every check that can run in `root`, with its declared reads, in the order they run: install, the Lean gates, then the
 *  packages that have a `test` script (sorted). Which of them a change selects is `selectChecks` (Lean `landSpeed.select`). */
/** Packages whose tests run the `fwcore` binary. Found by the scan in test/land-inputs.test.ts. Each declares `FWCORE_BIN`;
 *  which of them a Lean change selects is `selectTwoPhase` (the binary digest). */
export const FWCORE_USERS = ["apps/console-api", "apps/runner", "packages/difftest", "packages/e2e-preview", "packages/engine-check", "packages/gate-breakpoints", "packages/gh-budget", "packages/measure-chromium", "packages/measure-webkit", "packages/measure-wktr"];
/** Lean `fwcoreBin`: the stripped binary as a declared read. */
export const FWCORE_BIN = "lean/.lake/build/bin/fwcore";
/** Lean `fwcoreBuildReads`. */
export const FWCORE_BUILD_READS = ["lean/**", "scripts/fwcore-build.sh", "scripts/fwcore-record-rule.sh"];
/** sha256 hex of a binary, or null when unknown. */
export type Digest = string | null;
/** Lean `binMoved`, checked against the `landSpeed.select2` golden. */
export const binMoved = (changed: string[], d0: Digest, d1: Digest): boolean =>
  changed.some((c) => inScope(FWCORE_BUILD_READS, c)) && (d0 === null || d1 === null || d0 !== d1);
/** Lean `LandTier.buildFree`: the `lean/` paths no default Lake target reads (checked against the import closure by test/land-phase1.test.ts). */
export const BUILD_FREE = ["lean/scripts/**", "lean/golden/**", "lean/README.md", "lean/land-filter.txt", "lean/land-legs.txt"];
/** Lean `LandTier.binaryChange`, checked against the `land-phase1.jsonl` golden. */
export const binaryChange = (changed: string[]): string[] => changed.filter((p) => !inScope(BUILD_FREE, p));
/** Lean `LandTier.phase1Build`: does phase 1 build `fwcore` (a changed build input that is not build-free)? */
export const phase1Build = (changed: string[]): boolean => binaryChange(changed).some((p) => inScope(FWCORE_BUILD_READS, p));
/** Lean `LandTier.selectBin`: `selectTwoPhase` with the binary-moved test over the binary change. */
export const selectBin = (ds: { id: string; reads: string[] }[], changed: string[], d0: Digest, d1: Digest) =>
  selectChecks(ds, binMoved(binaryChange(changed), d0, d1) ? [...changed, FWCORE_BIN] : changed);
/** Lean `selectTwoPhase`, checked against the `landSpeed.select2` golden. */
export const selectTwoPhase = (ds: { id: string; reads: string[] }[], changed: string[], d0: Digest, d1: Digest) =>
  selectChecks(ds, binMoved(changed, d0, d1) ? [...changed, FWCORE_BIN] : changed);

/** For each check of `list`, the indices it must wait for: `pnpm install` first; the fwcore users (FWCORE_USERS) after
 *  `sh lean/scripts/check.sh`, whose `lake build` writes the binary they run, or after the plan's `sh scripts/fwcore-build.sh` (Lean `LandTier.localPlan`). Everything else is independent. */
export function checkDeps(list: string[][]): number[][] {
  const isInstall = (a: string[]) => a[0] === "pnpm" && a[1] === "install";
  const isCheckSh = (a: string[]) => a[0] === "sh" && (a[1] === "lean/scripts/check.sh" || a[1] === BUILD_ARGV[1]);
  const usesCore = (a: string[]) => a[0] === "pnpm" && a[1] === "--filter" && FWCORE_USERS.some((p) => a[2] === `./${p}`);
  const idx = (f: (a: string[]) => boolean) => list.flatMap((a, i) => (f(a) ? [i] : []));
  const inst = idx(isInstall), sh = idx(isCheckSh);
  return list.map((a, i) => [...(isInstall(a) ? [] : inst), ...(usesCore(a) ? sh : [])].filter((d) => d !== i));
}

/** The static read-set scan as its own check: Lean `Fw.Console.LandSpeed.scanId` / `scanReads` / `withScan`. Its reads are every
 *  inclusion glob any other check declares, so a change to anything a check can read selects it (`scan_selected`), also when
 *  `apps/runner` itself is not selected. */
export const READS_SCAN_ID = "reads-scan";
export const READS_SCAN_ARGV = ["pnpm", "--filter", "./apps/runner", "exec", "vitest", "run", "test/land-inputs.test.ts"];
export const withScan = (cs: Check[]): Check[] =>
  [...cs, { id: READS_SCAN_ID, argv: READS_SCAN_ARGV, reads: cs.flatMap((c) => c.reads.filter((g) => !g.startsWith("!"))) }];

export function candidateChecks(root: string): Check[] {
  const out: Check[] = [
    { id: "install", argv: ["pnpm", "install", "--frozen-lockfile"], reads: INSTALL_READS },
    { id: "check.sh", argv: ["sh", "lean/scripts/check.sh"], reads: CHECK_SH_READS },
  ];
  for (const t of ["apps", "packages"]) {
    let names: string[] = [];
    try { names = readdirSync(join(root, t)).sort(); } catch { /* no such directory */ }
    for (const n of names) {
      const p = `${t}/${n}`;
      try {
        const pkg = JSON.parse(readFileSync(join(root, p, "package.json"), "utf8"));
        if (pkg.scripts?.test) out.push({ id: p, argv: ["pnpm", "--filter", `./${p}`, "test"],
          reads: [`${p}/**`, NODE_BUDGET_GEN, ...workspaceDeps(root, pkg).map((d) => `${d}/**`), ...(PACKAGE_EXTRA_READS[p] ?? []), ...(FWCORE_USERS.includes(p) ? [FWCORE_BIN] : [])] });
      } catch { /* no package.json: nothing to run */ }
    }
  }
  return withScan(out);
}

/** The checks that cover the changed files, each with its declared input set. Digests main0 `d0` and merge tree `d1`
 *  default to unknown (every fwcore user follows a change to `FWCORE_BUILD_READS`). */
export function checksWithReads(root: string, changed: string[], d0: Digest = null, d1: Digest = null, select: typeof selectTwoPhase = selectTwoPhase): Check[] {
  const all = candidateChecks(root);
  const ids = new Set(select(all, changed, d0, d1));
  return all.filter((c) => ids.has(c.id));
}

/** Content key of a check's declared inputs: sha256 over the sorted (path, content hash) of the tracked files its globs
 *  select. Premise: equal keys give equal verdicts (`cache_sound`). Not used for caching yet. */
export function inputKey(root: string, reads: string[]): string {
  const files = execFileSync("git", ["ls-files", "-z"], { cwd: root, encoding: "utf8" }).split("\0").filter((f) => f && inScope(reads, f)).sort();
  const h = createHash("sha256");
  for (const f of files) {
    let c: Buffer | string = "";
    try { c = readFileSync(join(root, f)); } catch { c = "<missing>"; }
    h.update(`${f}\0${createHash("sha256").update(c).digest("hex")}\n`);
  }
  return h.digest("hex");
}

/** Checks that cover the changed files (argv only). */
export function checksFor(root: string, changed: string[]): string[][] {
  return checksWithReads(root, changed).map((c) => c.argv);
}

/** One `gh run list` call through the gh-budget ledger (`ci.budget.reserve` at `ghCost`), advisory only: a budget wait or
 *  stop skips the call and says so. */
export function ciLines(ref: string, cwd: string = process.cwd(), env?: Env): string[] {
  const args = ["run", "list", "--branch", ref, "--limit", "5", "--json", "name,conclusion,status,headSha"];
  try {
    const e = env ?? realEnv(cwd);
    const r = chargedOnce(e, (state, now) => e.core({ op: "ci.budget.reserve", now, state, cost: ghCost(args) }), () => args, 20_000);
    if (!r.ran) return [`budget ${r.decision} (${r.reason})`];
    if (r.code !== 0) return ["unavailable"];
    const rs = JSON.parse(r.stdout) as { name: string; conclusion: string; status: string; headSha: string }[];
    return rs.length ? rs.map((x) => `${x.name} ${x.headSha.slice(0, 7)} ${x.conclusion || x.status}`) : ["no runs"];
  } catch { return ["unavailable"]; }
}

/** Set `evidence` of `task` in the work graph of `dir` when it has none, keeping the file's formatting (1-space JSON). */
export function writeEvidence(dir: string, task: string, evidence: string): "written" | "present" | "none" | "failed" {
  const f = join(dir, "docs/team/work-graph.json");
  let raw: string;
  try { raw = readFileSync(f, "utf8"); } catch { return "none"; }
  try {
    const g = JSON.parse(raw) as { tasks?: (PlanTask & { evidence?: string | null })[] };
    const t = g.tasks?.find((x) => x.id === task);
    if (!t) return "none";
    if (t.evidence) return "present";
    t.evidence = evidence;
    writeFileSync(f, JSON.stringify(g, null, 1) + (raw.endsWith("\n") ? "\n" : ""));
    return tryGit(dir, ["add", "--", "docs/team/work-graph.json"]) ? "written" : "failed";
  } catch { return "failed"; }
}

/** What to do after the pre-lock checks, given where `HEAD` is now. TS stand-in for Lean `Fw.Console.LandSpeed.prelockAction`
 *  (lean/Fw/Console/LandSpeed.lean:497; `prelockAction_pre`, `prelockAction_fallback`); marked for Lean replacement (an `fwcore`
 *  op); checked against the `landSpeed.prelock` golden (test/land-prelock.test.ts). Attempts count from 0. */
export type PreAct = "ff" | "refuse" | "recheck" | "fallback";
export const prelockAction = (head: string, main0: string, verdict: boolean, attempt: number, maxRetry: number): PreAct =>
  head === main0 ? (verdict ? "ff" : "refuse") : attempt < maxRetry ? "recheck" : "fallback";
export const PRELOCK_RETRIES = 3;

/** Checks that may run at once: Lean `Fw.Console.LandPool.poolFair` (an `fwcore` op, `console.landPool`; golden
 *  `console.landPool.jsonl`): the cores not taken by other work, never fewer than half the cores. `loadCeil` is the one-minute
 *  load average rounded up. Without fwcore: 1 (serial; the verdict is the same, `verdict_perm`). */
export const poolFor = (cores: number, loadCeil: number): number => {
  const r = askCore("console.landPool", { cores, load: loadCeil });
  return r && Number.isInteger(r.pool) && r.pool >= 1 ? r.pool : 1;
};
/** Path of the generated Lean `Fw.Sched.NodeBudget` table, from the repo root. */
export const NODE_BUDGET_GEN = "packages/contracts/golden/sched/node-budget.gen.json";
/** Env of a check that runs in a pool of `pool` checks: `VITEST_MAX_WORKERS` (vitest's own override, also read by the node --test
 *  scripts) is Lean `Fw.Sched.NodeBudget.workers` of today's room with that pool, looked up in the generated `byPool` (pools 1 to
 *  the cores; a larger pool gets 1: `workers_pool_gt_cores`). A tree without the file: no env. */
export function testWorkersEnv(root: string, pool: number): Record<string, string> {
  let byPool: Record<string, number>;
  try { byPool = (JSON.parse(readFileSync(join(root, NODE_BUDGET_GEN), "utf8")) as { byPool: Record<string, number> }).byPool; } catch { return {}; }
  return { VITEST_MAX_WORKERS: String(byPool[String(pool)] ?? 1) };
}
/** Does a failed check re-run alone? Lean `Fw.Console.LandPool.rerunAlone` (`console.landRetry`); `loadFailure` is the fact that
 *  the output shows a timeout. Without fwcore: no (the failure stands). */
export const rerunAlone = (passed: boolean, loadFailure: boolean): boolean =>
  askCore("console.landRetry", { passed, loadFailure })?.rerun === true;
/** A failure that load, not the code, can cause: a timeout (vitest "timed out in 5000ms", a killed child). */
export const LOAD_FAILURE_RE = /timed out in \d+\s*ms|ETIMEDOUT|Hook timed out|Test timed out/;

/** One slot of the land worktrees (`<main>/.claude/land-wt/<n>`, gitignored, persistent so its `.lake` and `node_modules` stay warm).
 *  A slot is claimed by a pid file; a claim of a dead pid is taken over. One slot per concurrent land. */
export function claimLandWt(mainDir: string): { dir: string; free: () => void } {
  const root = join(mainDir, ".claude", "land-wt");
  mkdirSync(root, { recursive: true });
  for (let n = 0; ; n++) {
    const claim = join(root, `${n}.claim`);
    for (let again = 0; again < 2; again++) {
      try { writeFileSync(claim, `${process.pid}\n`, { flag: "wx" }); return { dir: join(root, String(n)), free: () => { try { unlinkSync(claim); } catch { /* gone */ } } }; }
      catch (e) {
        if ((e as NodeJS.ErrnoException).code !== "EEXIST") throw e;
        const pid = Number(readFileSync(claim, "utf8").trim());
        if (alive(pid)) break;
        try { unlinkSync(claim); } catch { /* raced */ }
      }
    }
  }
}

/** Put exactly the tree of `commit` in the land worktree `dir` (created on first use): detached checkout, then every
 *  untracked or ignored file removed except `.lake` and `node_modules` (kept warm). */
export function checkoutLandWt(mainDir: string, dir: string, commit: string, prep?: (dir: string) => void): void {
  const known = existsSync(dir) && worktrees(mainDir).some((w) => existsSync(w.dir) && realpathSync(w.dir) === realpathSync(dir));
  if (!known) {
    tryGit(mainDir, ["worktree", "prune"]);
    rmSync(dir, { recursive: true, force: true });
    git(mainDir, ["worktree", "add", "--detach", "--force", dir, commit]);
    prep?.(dir);
  } else git(dir, ["checkout", "--detach", "--force", commit]);
  git(dir, ["clean", "-fdxq", "-e", ".lake", "-e", "node_modules"]);
}

/** First land worktree use: clone the warm Lean build and install node_modules offline (scripts/wt-prep.sh); best effort. */
const prepLandWt = (dir: string) => {
  if (!existsSync(join(dir, "scripts/wt-prep.sh"))) return;
  try { execFileSync("sh", ["scripts/wt-prep.sh"], { cwd: dir, stdio: "ignore" }); } catch { /* the checks build what is missing */ }
  if (existsSync(join(dir, "pnpm-lock.yaml"))) { try { execFileSync("pnpm", ["install", "--offline", "--frozen-lockfile"], { cwd: dir, stdio: "ignore" }); } catch { /* the install check retries online */ } }
};

/** sha256 of the binary at `FWCORE_BIN` under `dir`, or null when it is missing. */
export function binDigest(dir: string): Digest {
  try { return createHash("sha256").update(readFileSync(join(dir, FWCORE_BIN))).digest("hex"); } catch { return null; }
}
const HEX64 = /^[0-9a-f]{64}$/;
const digestFile = (mainDir: string, commit: string) =>
  join(git(mainDir, ["rev-parse", "--path-format=absolute", "--git-common-dir"]), "fw-land", "fwcore-digest", commit);
/** The binary digest of `commit`: the one a land stored under the git common dir, else the main checkout's binary when its
 *  build record names `commit` and the binary's sha256 is the recorded one, else null. */
export function storedDigest(mainDir: string, commit: string): Digest {
  try { const d = readFileSync(digestFile(mainDir, commit), "utf8").trim(); if (HEX64.test(d)) return d; } catch { /* none stored */ }
  try {
    const r = parseBuildRecord(readFileSync(join(mainDir, `${FWCORE_BIN}.commit`), "utf8"));
    if (r && binDigest(mainDir) === r.hash) {
      if (r.kind === "commit" ? r.id === commit : git(mainDir, ["rev-parse", `${commit}^{tree}`]) === r.id) return r.hash;
    }
  } catch { /* no record */ }
  return null;
}
/** The build record (`fwcore.commit`): `tree <tree id> <sha256>` (scripts/fwcore-build.sh) or the legacy `<commit> <sha256>`. */
export function parseBuildRecord(text: string): { kind: "tree" | "commit"; id: string; hash: string } | null {
  const f = text.trim().split(/\s+/);
  if (f[0] === "tree" && f.length === 3 && f[1] && HEX64.test(f[2] ?? "")) return { kind: "tree", id: f[1], hash: f[2] as string };
  if (f.length === 2 && f[0] && f[0] !== "tree" && HEX64.test(f[1] ?? "")) return { kind: "commit", id: f[0], hash: f[1] as string };
  return null;
}
/** The land preflight (task land-queue-why): the reason to refuse early, or null. Facts only; Lean `fwcoreStale` decides. The installed binary is
 *  the main checkout's; its record (`fwcore.commit`) names the commit or tree it was built from, and counts only when the binary's sha256 is the recorded one.
 *  A tree without `scripts/fwcore-build.sh` has no binary to be stale. */
export function fwcorePreflight(mainDir: string, main: string): string | null {
  if (!tryGit(mainDir, ["cat-file", "-e", `${main}:scripts/fwcore-build.sh`])) return null;
  let recorded: string | null = null;
  try {
    const r = parseBuildRecord(readFileSync(join(mainDir, `${FWCORE_BIN}.commit`), "utf8"));
    if (r && binDigest(mainDir) === r.hash) {
      if (r.kind === "commit") recorded = r.id;
      else { // a tree record names the newest first-parent commit of main with that tree; none: the record is unknown
        const hit = git(mainDir, ["log", "--first-parent", "-n", "1000", "--format=%H %T", main]).split("\n").find((l) => l.endsWith(` ${r.id}`));
        if (hit) recorded = hit.split(" ")[0] ?? null;
      }
    }
  } catch { /* no record */ }
  const head = git(mainDir, ["rev-parse", main]);
  const same = recorded === head;
  let moved = true; // an unknown commit counts as moved
  if (recorded !== null && !same) {
    try { moved = git(mainDir, ["diff", "--name-only", recorded, main, "--", "lean", "scripts/fwcore-build.sh", "scripts/fwcore-record-rule.sh"]) !== ""; } catch { moved = true; }
  }
  return fwcoreStale(recorded, same, moved) ? FWCORE_STALE_REASON : null;
}
export function storeDigest(mainDir: string, commit: string, d: string): void {
  try { const f = digestFile(mainDir, commit); mkdirSync(dirname(f), { recursive: true }); writeFileSync(f, `${d}\n`); } catch { /* the next land builds unknown */ }
}
/** `lean/` and the build script of `dir` equal its HEAD and `lean/` holds no untracked file. */
export function buildClean(dir: string): boolean {
  if (!tryGit(dir, ["diff", "--quiet", "HEAD", "--", "lean", "scripts/fwcore-build.sh", "scripts/fwcore-record-rule.sh"])) return false;
  try { return git(dir, ["ls-files", "--others", "--exclude-standard", "--", "lean"]) === ""; } catch { return false; }
}

/** The fast lints of a dry land (task land-dry-full), in the merge-tree worktree `dir`: `node scripts/ci-paths.mjs --check` (0.1 s), and,
 *  when the change touches `lean/`, the axiom check exactly as `lean/scripts/check.sh` runs it (`scripts/axiom-check.sh`), after an
 *  incremental `lake build` (no `fwtest`, no tests; the .lake of the slot is warm). A script the tree lacks is skipped. */
export function dryLintArgv(dir: string, changed: string[]): string[][] {
  return lintPlan(changed, existsSync(join(dir, "scripts/ci-paths.mjs")), existsSync(join(dir, "lean/scripts/axiom-check.sh")));
}

type PreResult = { kind: "done"; sha: string } | { kind: "refuse"; msg: string; k?: Kind } | { kind: "fallback"; why: string };
/** A failing check whose output names the static reads test (`inc-land-undeclared-reads`) is a `reads` refusal, else `checks`. */
const READS_FAIL_RE = /land-inputs\.test|premise land\.readsOnly/;

type PlanTask = { id: string; state: string; owner?: string; stream?: string; writes?: string[] };

/** Facts for `console.landPick`: is `branch` already in main, and the branches that could hold its work (`ci/<task>` and every
 *  branch checked out in a worktree: an agent that switched its worktree to `ci/<task>` commits there), each with
 *  "ahead of main" and "contains `branch`". Lean (`console.landPick`) chooses; this only reads git. */
export function pickFacts(cwd: string, main: string, branch: string, task?: string): { givenAhead: boolean; others: { name: string; ahead: boolean; contains: boolean }[] } {
  const inMain = (ref: string) => tryGit(cwd, ["merge-base", "--is-ancestor", ref, main]);
  const givenAhead = !inMain(branch);
  if (givenAhead) return { givenAhead, others: [] };
  const names = new Set<string>();
  if (task && tryGit(cwd, ["rev-parse", "--verify", "-q", `refs/heads/ci/${task}`])) names.add(`ci/${task}`);
  // only the worktree this branch was made for (<name>/ of `worktree-<name>`): any later branch of main contains a merged one
  const stem = branch.replace(/^worktree-/, "").replace(/\//g, "-");
  for (const w of worktrees(cwd)) if (w.branch && basename(w.dir).endsWith(stem)) names.add(w.branch);
  names.delete(branch); names.delete(main);
  return { givenAhead, others: [...names].map((name) => ({ name, ahead: !inMain(name), contains: tryGit(cwd, ["merge-base", "--is-ancestor", branch, name]) })) };
}

/** The history the render guard reads: every commit of `main..tip`, a merge by its first-parent diff, a rename as delete and add. */
export const renderLogArgv = (main: string, tip: string): string[] =>
  ["-c", "log.showSignature=false", "log", "-z", "--no-renames", "--no-relative", "--no-ext-diff", "--name-status", "--diff-merges=first-parent", "--format=commit %H", `${main}..${tip}`];
export type RenderHit = { commit: string; path: string; media: string };
/** Lean `console.landRenderGuard` over the NUL-separated log: the refused paths, or a reason when it cannot be decided. */
export function renderGuard(cwd: string, main: string, tip: string): { hits: RenderHit[] } | { error: string } {
  let out: string;
  try { out = execFileSync("git", renderLogArgv(main, tip), { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], maxBuffer: 256 * 1024 * 1024 }); }
  catch (e) { return { error: `git log failed: ${String((e as { stderr?: string }).stderr ?? e).trim().slice(0, 200)}` }; }
  const r = askCore("console.landRenderGuard", { tokens: out.split("\0") });
  if (!r || !Array.isArray(r.hits)) return { error: "fwcore is not available to decide (build lean/.lake)" };
  return { hits: r.hits as RenderHit[] };
}

/** One `fw land` as one span ("fw land" / "total"): its 30 s ceiling is Lean `Fw.Obs.Timing.landCeilings`. A nested land (`via`) is part of the outer span. */
export async function land(branch: string, o: LandOptions, via?: string): Promise<LandResult> {
  const end = via ? () => {} : begin("fw land", "total");
  try { const r = await landRun(branch, o, via); end(r.ok ? 0 : 1); return r; } catch (e) { end(1); throw e; }
}

async function landRun(branch: string, o: LandOptions, via?: string): Promise<LandResult> {
  const lines: string[] = via ? [`${via} has nothing to land; landing ${branch}, which is ahead of it and contains it`] : [];
  // a dry refusal carries its stage outcome (default: `threw`, a refusal outside the modelled stages) and its kind is the Lean `dryRun` kind
  const fail = (m: string, kind: Kind = "unknown", out?: Outcome): LandResult => {
    lines.push(`REFUSED: ${m}`);
    if (!o.dry) return { ok: false, lines, kind };
    const oc = out ?? outcome({ threw: true });
    return { ok: false, lines, kind: outcomeKind(oc), outcome: oc };
  };
  const main = o.mainRef ?? "main";
  const bc = branchCard(branch);
  if (branch === main) return fail("cannot land the main branch");
  if (!bc && !o.task) return fail(`branch ${branch} is not a card branch (card/<CARD>[/<agent>]); land it with --task <id>`);
  if (!tryGit(o.cwd, ["rev-parse", "--verify", `refs/heads/${branch}`])) return fail(`no such branch ${branch}`);
  const mainDir = worktreeOf(o.cwd, main);
  if (!mainDir) return fail(`${main} is not checked out in any worktree`);
  if (o.dry && !o.task) return fail("--dry needs --task <id>: the scope check is the task's");
  if (!o.dry && git(mainDir, ["status", "--porcelain", "--untracked-files=no"])) return fail(`${main} checkout has uncommitted changes`, "dirty");
  if (!o.dry && !o.checks) { const why = fwcorePreflight(mainDir, main); if (why) return fail(why, "stale"); }
  // 0. the given branch has nothing to land: the agent may have committed on its ci/<task> branch (Lean: console.landPick)
  if (!via && !o.dry) {
    const pk = pickFacts(o.cwd, main, branch, o.task);
    if (!pk.givenAhead && pk.others.length) {
      const r = askCore("console.landPick", pk);
      if (!r) return fail("fwcore is not available to choose the branch to land (build lean/.lake)");
      if (r.pick === "other") {
        const res = await land(r.branch as string, o, branch);
        if (res.ok && tryGit(mainDir, ["branch", "-d", branch])) res.lines.push(`branch ${branch} deleted (it was already in ${main})`);
        return res;
      }
      if (r.pick === "ambiguous") return fail(`${branch} has nothing to land, and several branches are ahead of ${main} and contain it: ${(r.names as string[]).join(", ")}; land one of them`);
    }
  }
  const sha = git(o.cwd, ["rev-parse", `refs/heads/${branch}`]);
  const behind = !tryGit(o.cwd, ["merge-base", "--is-ancestor", main, sha]);
  if (o.dry && behind) return fail(`${branch} does not contain ${main}: merge ${main} into it (git merge ${main}) and run the dry land again; a stale base can carry another task's diff into the scope check`, "stale", outcome({ fresh: false }));
  // no commit of its own (the tip is already in main): nothing to land. Lean `Outcome.first` (after `stale`): VERDICT empty, exit 0.
  if (o.dry && tryGit(o.cwd, ["merge-base", "--is-ancestor", sha, main])) {
    const oc = outcome({ own: false });
    return { ok: true, lines: [...lines, `dry: ${branch} has no commit of its own (already in ${main}); nothing to land`], kind: outcomeKind(oc), outcome: oc };
  }
  if (behind && !o.task) return fail(`${branch} is behind ${main}; a fast-forward is impossible (land it with --task for a merge commit; branches are never rebased)`);
  const rg = renderGuard(o.cwd, main, sha);
  if ("error" in rg) return fail(`render guard: ${rg.error}`);
  if (rg.hits.length)
    return fail(`render guard: ${main}..${branch} (${sha.slice(0, 7)}) writes media outside snapshot/, and a later removal leaves the blob in history:${rg.hits.map((h) => `\n  ${h.path} (${h.media}) in ${h.commit}`).join("")}\nmove the other changes to a new branch from ${main} without these commits, or add the path with its reason to Fw.Land.RenderGuard.allowlist`, "scope", outcome({ scope: false }));

  // 1. the task and the file scope (Lean: console.landScope)
  let task: PlanTask | undefined;
  if (o.task) {
    if (!/^[A-Za-z0-9._-]+$/.test(o.task)) return fail(`bad task id ${o.task}`);
    const pl = await o.http.get("/api/plan");
    task = (pl.body?.tasks as PlanTask[] | undefined)?.find((x) => x.id === o.task);
    if (!task) return fail(`unknown task ${o.task} (fw plan sync first)`);
    if (task.state === "done") return fail(`task ${o.task} is already done`, "done");
  }
  // the writes are in the work graph file of the main checkout (the board does not carry them)
  let writes: string[] = [];
  let stream = task?.stream ?? "";
  if (task) {
    try {
      const g = JSON.parse(readFileSync(join(mainDir, "docs/team/work-graph.json"), "utf8")) as { tasks?: PlanTask[] };
      const row = g.tasks?.find((x) => x.id === o.task);
      writes = row?.writes ?? [];
      stream = row?.stream ?? stream;
    } catch { /* no work graph file: no writes */ }
  }
  const changed = git(o.cwd, ["diff", "--name-only", `${main}...${sha}`]).split("\n").filter(Boolean);
  const allow = o.allow ?? [];
  const sc = await o.http.post("/api/ops/land-scope", { writes, names: [o.task, task?.owner].filter(Boolean), allow, paths: changed, task: o.task ?? "", stream });
  if (sc.status !== 200) return fail(`scope check unavailable: ${sc.body.reason ?? sc.status}`);
  if (!sc.body.ok) {
    const list = (xs: string[]) => xs.map((x) => `\n  ${x}`).join("");
    if (sc.body.reason === "noWrites")
      return fail(`${o.task ? `task ${o.task}` : branch} has no writes, so no file may land. Changed files:${list(changed)}\nadd writes to the task in docs/team/work-graph.json (then fw plan sync), or pass --allow <glob>`, "scope", outcome({ scope: false }));
    return fail(`files outside the scope of ${o.task ?? branch}:${list(sc.body.violations as string[])}\nwrites: ${writes.join(", ") || "(none)"}; pass --allow <glob> to admit more`, "scope", outcome({ scope: false }));
  }
  lines.push(`scope ok (${changed.length} files)`);

  // 2. a card branch: the console's readiness, then (later) the land request, a decision the reducer may refuse
  const submit = o.submit ?? ((c: Command) => o.http.post("/api/agent/commands", { argv: o.argv ?? [], command: c }));
  if (bc && !o.dry) {
    await o.http.post("/api/reconcile", {});
    const r = await o.http.get(`/api/land/${encodeURIComponent(bc.card)}`);
    if (r.status !== 200) return fail(`console: ${r.body.reason ?? r.status}`);
    const rd = r.body as { stage: string; head: string | null; landed: boolean; ready: boolean; next: { who: string; command: string } };
    if (rd.landed) return fail("card already landed", "done");
    if (!rd.ready) return fail(`card ${bc.card} is at stage ${rd.stage}; next: ${rd.next.who}: ${rd.next.command}`);
    if (rd.head !== sha) return fail(`stale: console head ${rd.head?.slice(0, 7)} is not branch tip ${sha.slice(0, 7)}`);
  }
  const requestLand = async (): Promise<string | null> => {
    if (!bc) return null;
    const cmd = Command.parse({ type: "card.land_request", key: `card.land_request:${bc.card}:${sha}`, actor: "lead", card: bc.card, sha });
    // the actor in `cmd` is a placeholder: the capability door stamps the real one from the hook's capability
    const lr = await submit(cmd);
    return lr.body.ok ? null : `land_request: ${lr.body.reason}`;
  };

  // land checks run on a loaded machine: generous time limits for the source-side waits tests reach
  const LOAD_TOLERANT_ENV = { FW_CORE_CALL_MS: "60000", FW_HOOK_ASK_TIMEOUT_MS: "30000", FW_EXEC_TIMEOUT_MS: "30000" };
  // check output goes to .fw-console/land-logs/<task|branch>-<sha7>.log (gitignored); one line per check
  const logFile = join(mainDir, ".fw-console", "land-logs", `${(o.task ?? branch).replace(/[^A-Za-z0-9._-]/g, "_")}-${sha.slice(0, 7)}.log`);
  let logStarted = false;
  // async (not spawnSync) so SIGINT/SIGTERM handlers of the land run while a check is running
  const runCheck = (cwd: string, argv: string[], pool = 1) => new Promise<{ status: number | null; stdout: string; stderr: string; error?: Error }>((resolve) => {
    // own process group: pnpm/sh and the tools below them stop together when this run is interrupted or exits (reap-auto-stop teardown)
    const c = spawn(argv[0]!, argv.slice(1), { cwd, env: { ...LOAD_TOLERANT_ENV, ...process.env, ...testWorkersEnv(cwd, pool), ...o.env }, detached: true });
    let stdout = "", stderr = "";
    c.stdout.on("data", (d) => { stdout += d; }); c.stderr.on("data", (d) => { stderr += d; });
    const kill = () => { try { process.kill(-c.pid!, "SIGTERM"); } catch { c.kill("SIGTERM"); } };
    process.once("SIGTERM", kill); process.once("SIGINT", kill); process.once("exit", kill);
    const done = (status: number | null, error?: Error) => { process.off("SIGTERM", kill); process.off("SIGINT", kill); process.off("exit", kill); resolve({ status, stdout, stderr, error }); };
    c.on("error", (e) => done(null, e));
    c.on("close", (code) => done(code));
  });
  // Scheduling only; the selection is `checksFor`. Soundness: Lean `Fw.Console.LandSpeed.verdict_perm` (the verdict is the
  // conjunction of the check verdicts, independent of order and of completion), so running independent checks concurrently
  // and collecting every verdict gives the same accept/refuse as the sequential first-failure run; it only lists more failures.
  // Dependencies (`checkDeps`): everything waits for `pnpm install`; fwcore users wait for check.sh (its `lake build` writes
  // the binary they run). A bounded pool (cores) starts a check when its dependencies have finished.
  // Lean `selectTwoPhase`: phase 1 builds fwcore in the merge-tree worktree when the change reaches the build, phase 2 selects
  // the fwcore users by the digests of main0's binary and that build (unknown when the build failed or the tree is dirty).
  let phase1Built = false;
  const twoPhaseChecks = async (dir: string, main0: string, c: string): Promise<Check[]> => {
    const d0 = storedDigest(mainDir, main0);
    let d1: Digest = d0;
    phase1Built = false;
    // Lean `LandTier.phase1Build`: no build when every changed build read is build-free (the binary is main0's: `skip_binMoved`);
    // a local fwcore user then still builds in the local plan (`skip_keeps_local_build`)
    if (phase1Build(changed)) {
      const r = await span("fw land", "fwcore build (phase 1)", () => runCheck(dir, ["sh", "scripts/fwcore-build.sh"]), (p) => p.status);
      phase1Built = r.status === 0; // a failed build leaves the slot binary stale, so the local plan builds again
      d1 = r.status === 0 && buildClean(dir) ? binDigest(dir) : null;
      lines.push(`fwcore digest: ${main} ${d0?.slice(0, 12) ?? "unknown"}, merge ${d1?.slice(0, 12) ?? "unknown"}: fwcore users ${binMoved(changed, d0, d1) ? "selected" : "skipped"}`);
    }
    if (d1) storeDigest(mainDir, c, d1);
    return checksWithReads(dir, changed, d0, d1, selectBin);
  };
  // Lean `Fw.Console.LandRemote`: the Lean local tier runs here, the remote tier on the land lane of the allowed providers (land-remote.ts)
  const tieredChecks = async (dir: string, main0: string, c: string, list: Check[]): Promise<string | null> => {
    if (o.remote === false || !o.task) return runChecks(dir, list.map((x) => x.argv));
    const r = o.remote ?? {};
    const call = fwcoreCall(mainDir);
    const laneChanged = git(mainDir, ["diff", "--name-only", main0, c]).split("\n").filter(Boolean);
    const all = candidateChecks(dir);
    const laneSel = new Set(selectTwoPhase(all, laneChanged, null, null));
    const laneIds = (call({ op: "console.landTier", ids: all.filter((x) => laneSel.has(x.id)).map((x) => x.id) }) as { remote: string[] }).remote;
    // GitHub first; the legs it has no free job slot for go to CircleCI (Lean Fw.Ci.Overflow, land-overflow.ts). Injected adapters (tests) get no overflow.
    let adapters = r.adapters;
    let overflow: OverflowPlan | undefined;
    if (!adapters) {
      const gh = chargedGh(realEnv(mainDir));
      const push = makePusher({ git: (a) => git(mainDir, a), scan: (m) => scanRange(dir, mainDir, m) });
      adapters = { github: githubAdapter({ call, git: (a) => git(mainDir, a), scan: (m) => scanRange(dir, mainDir, m), wait: spawnWait(mainDir), gh, cache: (h, id) => cachedLaneView(realEnv(mainDir).dir, h, id) }, push) };
      try {
        const cc = await realCircle(mainDir, join(mainDir, ".fw-console", "circleci"), logLine);
        const legs = readFileSync(join(dir, "lean", "land-legs.txt"), "utf8").split(/\s+/).filter(Boolean);
        adapters.circleci = circleciAdapter(cc.deps(call, push));
        overflow = overflowFor({ call, legs, now: Date.now, slots: () => readSlots(gh, Date.now, join(realEnv(mainDir).dir, "overflow-slots.json")), ghStatus: () => ghStatusOnce(), ccStatus: () => ccStatusFrom((p) => o.http.get(p)), keys: cc.keys, budget: cc.budget, forceFull: forceFullFromEnv(o.env ?? process.env) });
      } catch (e) { logLine(`remote: CircleCI overflow is off (${e instanceof Error ? e.message : String(e)}); every leg on GitHub`); }
    }
    const res = await runTiered({
      call, checks: list, laneIds, task: o.task, mergeSha: c, allow: r.allow ?? DEFAULT_ALLOW,
      adapters, overflow,
      runLocal: async (argv) => { const bad = await runChecks(dir, argv); return { bad, kind: badKind }; },
      log: logLine, span: (step, startMs, durMs, exit) => record({ tool: "fw land", step, startMs, durMs, exit }, mainDir),
      sliceS: r.sliceS, deadlineS: r.deadlineS, waitsLeft: r.waitsLeft, built: phase1Built,
    });
    if (res.bad !== null) badKind = res.kind as Kind;
    return res.bad;
  };
  /** A remote-tier line goes to the land log file and to stderr at once, and only there: it is not in the result lines, which `fw land` prints afterwards (so each `remote:` line shows once). */
  const logLine = (l: string): void => {
    mkdirSync(join(mainDir, ".fw-console", "land-logs"), { recursive: true });
    if (!logStarted) { writeFileSync(logFile, ""); logStarted = true; }
    appendFileSync(logFile, `${l}\n`);
    process.stderr.write(`${l}\n`);
  };
  let badKind: Kind = "checks";
  const runChecks = async (cwd: string, list: string[][]): Promise<string | null> => {
    badKind = "checks";
    mkdirSync(join(mainDir, ".fw-console", "land-logs"), { recursive: true });
    if (!logStarted) { writeFileSync(logFile, ""); logStarted = true; }
    const deps = checkDeps(list);
    const results: ({ status: number | null; out: string } | undefined)[] = list.map(() => undefined);
    const started = new Set<number>();
    let running = 0;
    const limit = Math.max(1, o.concurrency ?? poolFor(availableParallelism(), Math.ceil(loadavg()[0] ?? 0)));
    await new Promise<void>((done) => {
      const pump = () => {
        for (let i = 0; i < list.length && running < limit; i++) {
          if (started.has(i) || !deps[i]!.every((d) => results[d])) continue;
          started.add(i); running++;
          const argv = list[i]!;
          void span("fw land", argv.join(" "), () => runCheck(cwd, argv, limit), (r) => r.status).then((p) => { // timing-spans
            results[i] = { status: p.status, out: `${p.stdout}${p.stderr}${p.error ? String(p.error) : ""}` };
            running--; pump();
          });
        }
        if (results.every(Boolean)) done();
      };
      pump();
    });
    // A land is never refused because the machine is busy: a check that failed with a timeout is run once more, alone (pool 1),
    // and its second result counts (the verdict is still the conjunction of the final results: `verdict_perm`).
    for (let i = 0; i < list.length; i++) {
      const r0 = results[i]!;
      if (!rerunAlone(r0.status === 0, LOAD_FAILURE_RE.test(r0.out))) continue;
      const argv = list[i]!;
      const p = await span("fw land", `${argv.join(" ")} (retry alone: timed out under load)`, () => runCheck(cwd, argv), (r) => r.status);
      results[i] = { status: p.status, out: `${r0.out}\n[timed out under load; re-run alone]\n${p.stdout}${p.stderr}${p.error ? String(p.error) : ""}` };
    }
    const bad: string[] = [], failedChecks: { reads: boolean; stages: string[] }[] = [];
    list.forEach((argv, i) => {
      const r = results[i]!;
      appendFileSync(logFile, `$ ${argv.join(" ")}  (cwd ${cwd})\n${r.out}\n[exit ${r.status}]\n\n`);
      if (r.status !== 0) {
        failedChecks.push({ reads: READS_FAIL_RE.test(r.out), stages: failedStages(r.out) });
        const tail = r.out.split("\n").filter((l) => l !== "").slice(-30).join("\n");
        bad.push(`check FAILED: ${argv.join(" ")}\nlog: ${logFile}\n${tail}`);
      } else lines.push(`check ok: ${argv.join(" ")}`);
    });
    // Lean `checkFailKind`: reads, else lint (a lint or compile failure: the same kind a dry land prints), else checks
    if (failedChecks.length) badKind = checkFailKind(failedChecks);
    return bad.length ? bad.join("\n\n") : null;
  };
  // --dry: the real land's cheap stages and nothing else (Lean `Fw.Console.LandDry`: dry_pass_land_pass, dry_refusal_is_land_refusal,
  // handback_pass_land_pass). It builds the very commit the pre-lock land builds (merge-tree of main and the tip, plus the evidence),
  // checks that tree in a land worktree slot (a pid claim, not the land lock), runs the static reads test only when the change selects
  // apps/runner (as the real land does) and never touches main, the lock or the queue. The kind is `outcomeKind` of the stage outcomes (Lean `Outcome.kind`).
  if (o.dry) {
    const main0 = git(mainDir, ["rev-parse", "HEAD"]);
    if (tryGit(mainDir, ["merge-base", "--is-ancestor", sha, main0])) { const oc = outcome({ own: false }); return { ok: true, lines: [...lines, `dry: ${branch} has no commit of its own (already in ${main}); nothing to land`], kind: outcomeKind(oc), outcome: oc }; }
    lines.push(`dry: ${branch} contains ${main}; scope ok`);
    let tree: string | null = null;
    try { tree = git(mainDir, ["-c", `attr.tree=${main0}`, "merge-tree", "--write-tree", main0, sha]).split("\n")[0]!; } catch { /* conflicts */ }
    if (!tree) return fail(`${main} cannot merge ${branch} cleanly`, "conflict", outcome({ merges: false }));
    const slot = claimLandWt(mainDir);
    try {
      const c = git(mainDir, ["commit-tree", tree, "-p", main0, "-p", sha, "-m", `dry ${branch}`]);
      checkoutLandWt(mainDir, slot.dir, c, o.dryReads ? undefined : prepLandWt);
      if (writeEvidence(slot.dir, o.task!, sha.slice(0, 7)) === "failed") return fail("could not write the evidence into docs/team/work-graph.json");
      let marks = "";
      try { marks = git(slot.dir, ["grep", "-n", "-E", MARKER_RE]); } catch { /* exit 1: no match */ }
      if (marks) return fail(`conflict markers after the merge:\n${marks.split("\n").slice(0, 10).join("\n")}`, "conflict", outcome({ merges: false }));
      lines.push(`dry: merge ok (${main} ${main0.slice(0, 7)}, tip ${sha.slice(0, 7)}), no conflict markers`);
      const selected = o.dryReads?.selected ?? selectChecks(candidateChecks(slot.dir), changed).includes(READS_SCAN_ID);
      let test = true, detail = "";
      if (selected) {
        const argv = o.dryReads?.argv ?? READS_SCAN_ARGV;
        const bad = await runChecks(slot.dir, [argv]);
        test = bad === null; detail = bad ?? "";
        if (test) lines.push("dry: reads ok (the static land-inputs test passes on the merge tree)");
      } else lines.push("dry: reads not selected (the change selects no read-set scan, so the real land does not run the test either)");
      const reads = !selected || test; // Lean `Stages.reads`: a test the change does not select cannot refuse
      let lints = true;
      if (reads) {
        // the fast lints that refused real lands, on the merge tree, after reads (Lean `Outcome.first` order); which ones: Lean `lintPlan`
        const lintArgv = o.dryLints ?? dryLintArgv(slot.dir, changed);
        if (lintArgv.length) {
          const bad = await runChecks(slot.dir, lintArgv);
          lints = bad === null; detail = bad ?? "";
        }
      } else lines.push("dry: lints skipped (reads refused first)");
      const oc = outcome({ reads, lints });
      if (outcomeKind(oc) !== "dry") return fail(detail || `dry land refused: ${outcomeKind(oc)}`, "unknown", oc);
      lines.push(`dry ok at ${main} ${main0.slice(0, 7)}: the land's scope, merge, reads and fast lints pass unless ${main} moves`);
      return { ok: true, lines, kind: "dry", outcome: oc };
    } finally { slot.free(); }
  }
  const checks = o.checks ?? checksFor(mainDir, changed);

  // Pre-lock protocol (research/notes/2026/10-18-land-speed.md P3; Lean `Fw.Console.LandSpeed`: pre_eq_old_iff, preLand_commit_exact):
  // C = commit(merge-tree(main0, tip) + evidence, parents [main0, tip]) is built and checked in a land worktree with NO lock;
  // under the lock only `HEAD = main0` is compared and C is fast-forwarded (sub-second). Main moved: re-check (bounded), then fall
  // back to the locked protocol below.
  const preLock = async (): Promise<PreResult> => {
    const maxRetry = o.retries ?? PRELOCK_RETRIES;
    const trailer = [`Task: ${o.task}`, ...(allow.length ? [`Land-Allow: ${allow.join(", ")}`] : []), ...(o.attribution ?? ATTRIBUTION)].join("\n");
    const slot = claimLandWt(mainDir);
    let requested = false;
    try {
      for (let attempt = 0; ; attempt++) {
        const main0 = git(mainDir, ["rev-parse", "HEAD"]);
        if (tryGit(mainDir, ["merge-base", "--is-ancestor", sha, main0])) return { kind: "refuse", msg: `${branch} has nothing to land (already in ${main})`, k: "done" };
        let tree: string;
        try { tree = git(mainDir, ["-c", `attr.tree=${main0}`, "merge-tree", "--write-tree", main0, sha]).split("\n")[0]!; }
        catch { return { kind: "fallback", why: `${main} cannot merge ${branch} cleanly` }; }
        const mk = (t: string) => git(mainDir, ["commit-tree", t, "-p", main0, "-p", sha, "-m", `land ${branch}`, "-m", trailer]);
        let c = mk(tree);
        checkoutLandWt(mainDir, slot.dir, c, o.checks ? undefined : prepLandWt);
        // the task's evidence goes into the merge commit, and into the checked tree (the checked tree is the committed tree)
        const ev = writeEvidence(slot.dir, o.task!, sha.slice(0, 7));
        if (ev === "failed") return { kind: "refuse", msg: "could not write the evidence into docs/team/work-graph.json" };
        if (ev === "written") { c = mk(git(slot.dir, ["write-tree"])); if (attempt === 0) lines.push(`evidence ${sha.slice(0, 7)} written into docs/team/work-graph.json (in the merge commit)`); }
        let marks = "";
        try { marks = git(slot.dir, ["grep", "-n", "-E", MARKER_RE]); } catch { /* exit 1: no match */ }
        if (marks) return { kind: "refuse", msg: `conflict markers after the merge:\n${marks.split("\n").slice(0, 10).join("\n")}`, k: "conflict" };
        const bad = o.checks ? await runChecks(slot.dir, o.checks) : await tieredChecks(slot.dir, main0, c, await twoPhaseChecks(slot.dir, main0, c));
        let act = prelockAction(git(mainDir, ["rev-parse", "HEAD"]), main0, bad === null, attempt, maxRetry);
        if (act === "refuse") return { kind: "refuse", msg: bad!, k: badKind };
        if (act === "ff") {
          if (!requested) { requested = true; const e = await requestLand(); if (e) return { kind: "refuse", msg: e }; }
          const wait = Date.now() + (o.lockWaitMs ?? 10_000);
          const lf = lockFile(mainDir);
          let lock: ReturnType<typeof takeLock> = null;
          while (!lock) {
            const lk0 = lockFacts(lf);
            const lv = askCore("console.landLock", { held: lk0.held, alive: lk0.alive });
            const holder = lk0.lock ? `pid ${lk0.lock.pid}, branch ${lk0.lock.branch ?? "?"}, since ${lk0.lock.at ?? "?"}` : "";
            if (!lv) return { kind: "refuse", msg: "fwcore is not available to decide the land lock (build lean/.lake)" };
            if (lv.verdict === "stale") return { kind: "refuse", msg: `stale land lock ${lf} (${holder}; that process is gone). It was not removed: look at \`git status\` in ${mainDir} (an open merge: git merge --abort), then delete the file` };
            if (lv.verdict === "busy") {
              if (Date.now() >= wait) return { kind: "refuse", msg: `another fw land holds ${lf} (${holder}); wait for it`, k: "busy" };
              await new Promise((r) => setTimeout(r, 100));
              continue;
            }
            lock = takeLock(lf, { branch, pre: main0, dir: realpathSync(mainDir) });
          }
          const endLock = begin("fw land", "lock held"); // from take to release; its 5 s ceiling is Lean `Fw.Obs.Timing.landCeilings`
          let released = false;
          const release = () => { if (!released) { released = true; endLock(0); dropLock(lf, lock!.token); } };
          const onSig = (code: number) => () => { release(); process.exit(code); };
          const onInt = onSig(130), onTerm = onSig(143);
          process.once("SIGINT", onInt); process.once("SIGTERM", onTerm);
          try {
            const head = git(mainDir, ["rev-parse", "HEAD"]);
            act = prelockAction(head, main0, true, attempt, maxRetry);
            if (act === "ff") {
              // Lean landTip with these facts: the lock is ours, the commit to advance to is C, HEAD is still main0
              const d = askCore("console.landCommit", { locked: readLock(lf)?.token === lock.token, mergeHead: c, head, pre: main0 });
              if (!d?.ok) return { kind: "refuse", msg: `will not fast-forward: ${d ? d.reason : "fwcore is not available to decide"}. ${main} is at ${tryHead(mainDir)}, the land started at ${main0.slice(0, 7)}; ${main} was not changed` };
              if (!span("fw land", "merge commit", () => tryGit(mainDir, ["merge", "--ff-only", c]), (ok) => (ok ? 0 : 1)))
                return { kind: "refuse", msg: `${main} could not fast-forward to the checked commit ${c.slice(0, 7)} (uncommitted changes in ${mainDir} that the land touches?); ${main} was not changed`, k: "dirty" };
              return { kind: "done", sha: c };
            }
          } finally { process.off("SIGINT", onInt); process.off("SIGTERM", onTerm); release(); }
        }
        if (act === "fallback") return { kind: "fallback", why: `${main} moved ${maxRetry + 1} times while the checks ran` };
        lines.push(`${main} moved during the checks (attempt ${attempt + 1}); checking again against the new ${main}`);
      }
    } finally { slot.free(); }
  };
  let pre: PreResult = { kind: "fallback", why: "pre-lock off" };
  if (o.task && o.prelock !== false) {
    pre = await preLock();
    if (pre.kind === "refuse") return fail(pre.msg, pre.k);
    if (pre.kind === "fallback") lines.push(`pre-lock check not possible (${pre.why}); using the locked protocol`);
  }

  let mergeSha: string;
  if (!o.task) {
    // card fast-forward: the checks run in the branch's own checkout (or main) before main moves
    const bad = await runChecks(worktreeOf(o.cwd, branch) ?? mainDir, checks);
    if (bad) return fail(bad, badKind);
    const e = await requestLand();
    if (e) return fail(e);
    const endMerge = begin("fw land", "merge");
    const ffOk = tryGit(mainDir, ["merge", "--ff-only", sha]);
    endMerge(ffOk ? 0 : 1);
    if (!ffOk) return fail(`${main} cannot fast-forward to ${branch}`);
    mergeSha = git(mainDir, ["rev-parse", "HEAD"]);
  } else if (pre.kind === "done") {
    mergeSha = pre.sha;
  } else {
    // 3. take the land lock (Lean: console.landLock), merge into the main checkout without committing, check, commit, release.
    // While the lock is held the pre-commit hook (hooks/land-guard.mjs) refuses every other commit in this checkout.
    const pre = git(mainDir, ["rev-parse", "HEAD"]);
    const lf = lockFile(mainDir);
    const lk0 = lockFacts(lf);
    const lv = askCore("console.landLock", { held: lk0.held, alive: lk0.alive });
    const holder = lk0.lock ? `pid ${lk0.lock.pid}, branch ${lk0.lock.branch ?? "?"}, since ${lk0.lock.at ?? "?"}` : "";
    if (!lv) return fail("fwcore is not available to decide the land lock (build lean/.lake)");
    if (lv.verdict === "busy") return fail(`another fw land holds ${lf} (${holder}); wait for it`, "busy");
    if (lv.verdict === "stale") return fail(`stale land lock ${lf} (${holder}; that process is gone). It was not removed: look at \`git status\` in ${mainDir} (an open merge: git merge --abort), then delete the file`);
    const lock = takeLock(lf, { branch, pre, dir: realpathSync(mainDir) });
    if (!lock) return fail(`another fw land took ${lf} just now; wait for it`, "busy");
    let released = false;
    const endLock = begin("fw land", "lock held"); // from take to release; its 5 s ceiling is Lean `Fw.Obs.Timing.landCeilings`
    const release = () => { if (!released) { released = true; endLock(0); dropLock(lf, lock.token); } };
    // the facts of `console.landCommit`: is the lock still ours, is MERGE_HEAD there, where is HEAD
    const facts = () => {
      let mh: string | null = null;
      try { mh = git(mainDir, ["rev-parse", "-q", "--verify", "MERGE_HEAD"]); } catch { /* none */ }
      return askCore("console.landCommit", { locked: readLock(lf)?.token === lock.token, mergeHead: mh, head: git(mainDir, ["rev-parse", "HEAD"]), pre });
    };
    // `merge --abort` only while the merge is still ours (lock held, MERGE_HEAD there, HEAD unmoved); otherwise nothing is reset
    const abort = (m: string, kind: Kind = "unknown"): LandResult => {
      const d = facts();
      if (d?.ok) { tryGit(mainDir, ["merge", "--abort"]); return fail(`${m} (merge aborted, ${main} unchanged at ${pre.slice(0, 7)})`, kind); }
      return fail(`${m}\nthe merge state is not intact (${d?.reason ?? "fwcore unavailable"}): ${main} is at ${tryHead(mainDir)}, the land started at ${pre.slice(0, 7)}; nothing was reset`);
    };
    const onSignal = (sig: NodeJS.Signals) => () => {
      try { if (facts()?.ok) tryGit(mainDir, ["merge", "--abort"]); } catch { /* best effort */ }
      release();
      process.exit(sig === "SIGINT" ? 130 : 143);
    };
    const onInt = onSignal("SIGINT"), onTerm = onSignal("SIGTERM");
    process.once("SIGINT", onInt); process.once("SIGTERM", onTerm);
    try {
      if (!span("fw land", "merge", () => tryGit(mainDir, ["merge", "--no-ff", "--no-commit", sha]), (ok) => (ok ? 0 : 1))) return abort(`${main} cannot merge ${branch} cleanly`, "conflict");
      if (!tryGit(mainDir, ["rev-parse", "-q", "--verify", "MERGE_HEAD"])) return fail(`${branch} has nothing to land (already in ${main})`, "done");
      let marks = "";
      try { marks = git(mainDir, ["grep", "-n", "-E", MARKER_RE]); } catch { /* exit 1: no match */ }
      if (marks) return abort(`conflict markers after the merge:\n${marks.split("\n").slice(0, 10).join("\n")}`, "conflict");
      lines.push("no conflict markers");
      // the evidence goes in before the checks: the checked and fwcore-recorded tree is the committed tree
      const ev = writeEvidence(mainDir, o.task, sha.slice(0, 7));
      if (ev === "failed") return abort("could not write the evidence into docs/team/work-graph.json");
      if (ev === "written") lines.push(`evidence ${sha.slice(0, 7)} written into docs/team/work-graph.json (in the merge commit)`);
      const bad = await runChecks(mainDir, checks);
      if (bad) return abort(bad, badKind);
      let e: string | null;
      try { e = await requestLand(); }
      catch (x) {
        // the console went away between the checks and the request: close the merge here, so the queue's retry never starts a land on a main checkout with an open merge
        if (x instanceof ConsoleUnreachable) { if (facts()?.ok) tryGit(mainDir, ["merge", "--abort"]); }
        throw x;
      }
      if (e) return abort(e);
      // commit only into the merge the land opened (Lean: landTip): no lock, no MERGE_HEAD or a moved HEAD means someone
      // else touched main; then nothing is committed and nothing is reset
      const d = facts();
      if (!d?.ok) return fail(`will not commit: ${d ? d.reason : "fwcore is not available to decide"}. ${main} is at ${tryHead(mainDir)}, the land started at ${pre.slice(0, 7)}; ${main} was not reset. Inspect \`git status\` and \`git log\` in ${mainDir}`);
      const trailer = [`Task: ${o.task}`, ...(allow.length ? [`Land-Allow: ${allow.join(", ")}`] : []), ...(o.attribution ?? ATTRIBUTION)].join("\n");
      if (!span("fw land", "merge commit", () => tryGitEnv(mainDir, ["commit", "-m", `land ${branch}`, "-m", trailer], { FW_LAND_TOKEN: lock.token }), (ok) => (ok ? 0 : 1))) return abort("commit of the merge failed");
      mergeSha = git(mainDir, ["rev-parse", "HEAD"]);
    } finally {
      process.off("SIGINT", onInt); process.off("SIGTERM", onTerm);
      release();
    }
  }

  // From here main has moved: nothing below may fail the landing. Each step is tried twice; a step that still fails is
  // listed with the command that finishes it, and the exit stays 0 (ok = main changed).
  const warnings: string[] = [];
  const remaining: string[] = [];
  const pause = () => new Promise((r) => setTimeout(r, o.retryMs ?? 700));
  const why = (e: unknown) => {
    const code = (e as { cause?: { code?: string } })?.cause?.code;
    return `${e instanceof Error ? e.message : String(e)}${code ? ` (${code})` : ""}`;
  };
  const step = async (name: string, cmd: string, fn: () => Promise<string | void>): Promise<void> => {
    let last = "";
    for (let i = 0; i < 2; i++) {
      try { const r = await span("fw land", name, fn, (x) => (x ? 1 : 0)); if (!r) return; last = r; } catch (e) { last = why(e); }
      if (i === 0) await pause();
    }
    warnings.push(`step ${name} failed twice: ${last}`);
    remaining.push(`  ${name}: ${cmd}`);
  };
  const base = o.base ?? "$FW_API";
  const curl = (path: string) => `curl -s -X POST -H 'content-type: application/json' -d '{}' ${base}${path}`;
  lines.push(`merged ${branch} ${sha.slice(0, 7)} into ${main} as ${mergeSha.slice(0, 7)}`);

  // 4. the reconciler records card.landed and, from the Task: trailer, task.done (the only evidence route)
  await step("reconcile", curl("/api/reconcile"), async () => { await o.http.post("/api/reconcile", {}); });
  await step("verify", `${curl("/api/reconcile")} ; pnpm fw status`, async () => {
    if (bc) {
      const after = (await o.http.get(`/api/land/${encodeURIComponent(bc.card)}`)).body as { landed: boolean; violation: boolean };
      lines.push(`landed ${bc.card} ${sha.slice(0, 7)} on ${main}: ${after.landed ? "recorded" : "NOT recorded"}${after.violation ? " VIOLATION" : ""}`);
      if (!after.landed || after.violation) return `card ${bc.card} ${after.landed ? "landed with a VIOLATION" : "NOT recorded as landed"}`;
    }
    if (o.task) {
      const t = ((await o.http.get("/api/plan")).body?.tasks as PlanTask[] | undefined)?.find((x) => x.id === o.task);
      if (t?.state !== "done") return `task ${o.task} NOT recorded as done (state ${t?.state ?? "unknown"}): the Task: trailer was not picked up`;
      const url = (await o.http.get("/api/repo").catch(() => null))?.body?.commit as string | null | undefined;
      lines.push(`task ${o.task} done: ${url ? url + mergeSha : mergeSha}`);
    }
  });

  // 5. advisory CI of the task's ci/* ref: never blocks
  if (o.ci !== false && o.task) {
    try { lines.push(`ci (advisory) ci/${o.task}: ${(o.ci ?? ((ref: string) => ciLines(ref, o.cwd)))(`ci/${o.task}`).join("; ")}`); } catch { lines.push(`ci (advisory) ci/${o.task}: unavailable`); }
  }

  // 6. safe cleanup: `branch -d` only; the worktree only when clean and not locked (local, no console needed)
  const endCleanup = begin("fw land", "worktree cleanup");
  try {
    const wt = worktrees(o.cwd).find((w) => w.branch === branch);
    let removed = true;
    if (wt) {
      const here = resolve(o.cwd);
      if (wt.dir === mainDir) removed = false;
      else if (wt.locked !== null) {
        removed = false;
        const pid = /pid (\d+)/.exec(wt.locked)?.[1];
        lines.push(`worktree ${wt.dir} left: locked${wt.locked ? ` (${wt.locked})` : ""}${pid && !alive(Number(pid)) ? "; the lock looks stale, unlock it by hand" : ""}`);
      } else if (git(wt.dir, ["status", "--porcelain"])) {
        removed = false; lines.push(`worktree ${wt.dir} left: uncommitted changes`);
      } else if (here === resolve(wt.dir) || here.startsWith(resolve(wt.dir) + "/")) {
        removed = false; lines.push(`worktree ${wt.dir} left: it is the current directory`);
      } else if (!tryGit(mainDir, ["worktree", "remove", wt.dir])) { removed = false; lines.push(`worktree ${wt.dir} left: git refused to remove it`); }
      else {
        lines.push(`worktree ${wt.dir} removed`);
        if (o.reap) { try { lines.push(...(await o.reap(mainDir))); } catch { /* the stop is best effort; the report line says what happened */ } }
      }
    }
    if (removed) lines.push(tryGit(mainDir, ["branch", "-d", branch]) ? `branch ${branch} deleted` : `branch ${branch} kept (branch -d refused)`);
    else lines.push(`branch ${branch} kept`);
  } catch (e) {
    warnings.push(`step cleanup failed: ${why(e)}`);
    remaining.push(`  cleanup: git worktree remove <dir of ${branch}> ; git branch -d ${branch}`);
  }
  endCleanup(0);

  if (o.after) await step("plan sync", "pnpm fw plan sync docs/team/work-graph.json", async () => { lines.push(...(await o.after!(mainDir))); });

  if (warnings.length) {
    lines.push(`WARNING: ${main} is changed (${mergeSha.slice(0, 7)}) but ${remaining.length} step(s) did not finish:`);
    for (const w of warnings) lines.push(`  ${w}`);
    lines.push("run these in the main checkout:", ...remaining);
  }
  return { ok: true, lines, warnings, kind: "done" };

}
