import { execFileSync, spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { appendFileSync, existsSync, mkdirSync, readdirSync, readFileSync, realpathSync, rmSync, unlinkSync, writeFileSync } from "node:fs";
import { availableParallelism, loadavg } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { Command } from "@fw/contracts";
import { branchCard } from "../../console-api/src/reconcile/naming.ts";
import { begin as rawBegin, builtModules, lakeMember, noteSpan, outerBuilt, record as rawRecord, span as rawSpan, writeLakeHandoff } from "./timing.ts";

let stepPrefix = "";
export const dryTotalStep = (plan: string[][], fwcoreBuild: boolean): string => (plan.some((a) => a.join("\0") === LINT_ARGV.axioms.join("\0")) || fwcoreBuild ? "dry total lake" : "dry total");
let dryStep: string | null = null;
let dryLake: { built: number } | null = null;
export const lastDryStep = (): string | null => dryStep;
const begin: typeof rawBegin = (tool, step, cwd) => rawBegin(tool, stepPrefix + step, cwd);
const record: typeof rawRecord = (s, cwd) => rawRecord({ ...s, step: stepPrefix + s.step }, cwd);
const span: typeof rawSpan = (tool, step, fn, exitOf) => rawSpan(tool, stepPrefix + step, fn, exitOf);
import { cachedLaneView, circleciAdapter, DEFAULT_ALLOW, githubAdapter, makePusher, BUILD_ARGV, runTiered, spawnWait, type Adapter, type OverflowPlan, type Provider } from "./land-remote.ts";
import { ccStatusFrom, forceFullFromEnv, ghStatusOnce, overflowFor, readSlots, realCircle } from "./land-overflow.ts";
import { fileIntents } from "./land-intent.ts";
import { askCore, dropLock, lockFacts, lockFile, readLock, takeLock } from "../hooks/land-guard.mjs";
import { dryRun, exitCode, FWCORE_STALE_REASON, checkFailKind, failedStages, fwcoreStale, installKind, installNeeded, installRunsOnline, installStep, LINT_ARGV, lintPlan, noteKeyRefusal, outcome, outcomeKind, type Kind, type NoteKey, type Outcome } from "./land-verdict.ts";
import { noteShapeProblems } from "./land-notes.ts";
import { consoleSecret } from "./lib.ts";
import { CHECK_SH_READS } from "./land-reads.gen.ts";
import { ConsoleUnreachable } from "./land-queue.ts";
import { WORKFLOW_LINT_ARGV, WORKFLOW_LINT_ID, WORKFLOW_LINT_READS } from "./land-checks-workflow.ts";
import { chargedGh, fwcoreCall, ghCost } from "./run.ts";
import { chargedOnce, GH_BOUNDS, realEnv, type Env } from "@fw/gh-budget";

export type Http = {
  get(path: string): Promise<{ status: number; body: any }>;
  post(path: string, body: unknown): Promise<{ status: number; body: any }>;
};

export const loopback = (base: string) => base.replace(/^(https?:\/\/)localhost(?=[:/]|$)/, "$1127.0.0.1");
export const HTTP_DEADLINE_MS = 90_000;
export const httpFor = (base0: string): Http => { const base = loopback(base0); let secret: string | undefined;
  const dial = async (p: string, init: RequestInit): Promise<Response> => {
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
  cwd: string;
  mainRef?: string;
  argv?: string[];
  submit?: (cmd: Command) => Promise<{ status: number; body: any }>;
  checks?: string[][];
  remote?: false | { allow?: Provider[]; adapters?: Partial<Record<Provider, Adapter>>; sliceS?: number; deadlineS?: number; waitsLeft?: number };
  concurrency?: number;
  env?: Record<string, string | undefined>;
  task?: string;
  allow?: string[];
  ci?: false | ((ref: string) => string[]);
  attribution?: string[];
  after?: (mainDir: string) => Promise<string[]>;
  reap?: (mainDir: string) => Promise<string[]>;
  unpushedLag?: (mainDir: string, head: string, main: string) => number | null;
  base?: string;
  retryMs?: number;
  prelock?: boolean;
  retries?: number;
  lockWaitMs?: number;
  dry?: boolean;
  dryReads?: { argv: string[]; selected?: boolean };
  dryLocal?: Check[];
  dryLints?: string[][];
  installExec?: InstallExec;
  installFs?: StampFs;
};
export type LandResult = { ok: boolean; lines: string[]; warnings?: string[];
  kind?: Kind;
  outcome?: Outcome };

export const ATTRIBUTION = [
  "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>",
  "Claude-Session: https://claude.ai/code/session_01R3GWpzaWka38ev9uPDctoA",
];
export const MARKER_RE = "^(<<<<<<<|>>>>>>>)";

const git = (cwd: string, args: string[]) => execFileSync("git", args, { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();
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

export function worktreeOf(cwd: string, ref: string): string | null {
  return worktrees(cwd).find((w) => w.branch === ref)?.dir ?? null;
}

const alive = (pid: number) => { try { process.kill(pid, 0); return true; } catch (e) { return (e as NodeJS.ErrnoException).code === "EPERM"; } };

export type Check = { id: string; argv: string[]; reads: string[] };

import { inScope, scopeOf, trackedFiles } from "./land-inputs.ts";
export { inScope };
export const selectChecks = (ds: { id: string; reads: string[] }[], changed: string[]) =>
  ds.filter((d) => changed.some((c) => inScope(d.reads, c))).map((d) => d.id);

export { CHECK_SH_READS };
export const INSTALL_READS = ["pnpm-lock.yaml", "**/package.json"];
export function siteAssetReads(manifestPath = join(new URL(import.meta.url).pathname, "../../../site/assets.manifest.json")): string[] {
  const m = JSON.parse(readFileSync(manifestPath, "utf8")) as { files: { src: string }[]; bundled?: string[] };
  return [...new Set([...m.files.map((f) => f.src), ...(m.bundled ?? [])])].sort();
}
const WALLCLOCK_LINT_FILES = ["scripts/lint-wallclock.mjs", "scripts/wallclock-allow.json", "scripts/lint-wallclock-cases/**"];
const WALLCLOCK_LINT_TESTS = ["scripts/*.test.mjs", "apps/*/test/**", "packages/*/test/**", ".github/scripts/*.test.mjs", "apps/site/src/**/*.test.*", "apps/site/scripts/*.test.*"];

export const PACKAGE_EXTRA_READS: Record<string, string[]> = {
  "apps/console-web": ["results/review-reports/**"],
  "apps/console-api": ["research/findings/ledger.json", "lean/Fw/Console/PreviewFacts.lean", "snapshot/site/index.html", "apps/console-web/**", "results/review-reports/**","apps/runner/hooks/lib.mjs", "apps/runner/src/plan.ts", "packages/contracts/golden/**", "apps/site/src/registry/resolve.ts", "apps/site/src/registry/types.ts", ...WALLCLOCK_LINT_FILES],
  "apps/runner": ["lean/**", ...WALLCLOCK_LINT_FILES, ...WALLCLOCK_LINT_TESTS, "apps/console-api/**", "docs/team/work-graph.json", "docs/team/incidents/ledger.json", "lean/scripts/check-imports.mjs",
    "packages/contracts/golden/**", "packages/gh-budget/test/util.ts", "scripts/span.sh",
    ".github/workflows/**", ".github/actions/setup-lean/action.yml", ".github/scripts/changed-inputs.mjs", ".github/scripts/changed-inputs.test.mjs", "scripts/ci-paths.mjs", "scripts/ci-paths.test.mjs",
    "scripts/ci-push.mjs", "scripts/ci-push.test.mjs", "scripts/hooks/**",
    "scripts/circleci.mjs", "scripts/circleci.test.mjs", "scripts/circleci-fixtures/**", ".circleci/**",
    "scripts/codemagic.mjs", "scripts/codemagic.test.mjs", "codemagic.yaml",
    "research/notes/2026/10-2x-macos-telemetry.md",
    "scripts/lake-slot.sh", "scripts/lake-slot-lib.sh", "scripts/lake-slot.test.mjs",
    "scripts/sim-lock.sh",
    "scripts/scrub.mjs", "scripts/test-scrub.mjs", "scripts/scrub.test.mjs", "scripts/scrub-allow.json",
    "scripts/ci-telemetry/**",
    "lean/lakefile.toml", "lean/scripts/**", "apps/site/scripts/**", "lean/Fw/Ops/LakeJobsGen.lean"],
  "apps/site": ["packages/contracts/src/flag-key.mjs", "packages/contracts/golden/preset/probes.jsonl", "packages/contracts/golden/wire/flag-key.jsonl", "lean/Fw/Console/BuildsOpen.lean", "packages/contracts/golden/console/layer-opts.jsonl", "packages/contracts/golden/console/layers-search.jsonl", "lean/Fw/Parts/HiddenPause.lean", "lean/Fw/Parts/HeroCountdownHidden.lean", "lean/Fw/Parts/HeroAccentOpt.lean", "packages/gate-breakpoints/src/serve.mjs", "packages/gate-breakpoints/src/anchors.json", "packages/contracts/golden/parts/**", "packages/contracts/golden/measure/wkcost.jsonl",
    "packages/contracts/golden/preset/look-change.candidates.jsonl", "packages/contracts/golden/morph-geom.jsonl", "packages/contracts/golden/morph-geom-timed.jsonl",
    "packages/contracts/golden/port/**", "scripts/port/**", "packages/visual-diff/src/engines.mjs", "packages/visual-diff/src/fonts.mjs", "snapshot/site/index.html", "snapshot/site/_app/**", ...siteAssetReads()],
  "packages/measure-wktr": ["packages/contracts/src/flag-key.mjs", "packages/gate-breakpoints/src/track-accel-page.mjs", "packages/measure-chromium/src/fwcore.mjs", "packages/measure-webkit/src/page.mjs", "packages/measure-webkit/src/serve.mjs", "packages/measure-webkit/src/paintclip.mjs", "packages/contracts/golden/device/sweep-pause.jsonl", "packages/contracts/golden/device/recalc-source.jsonl", "packages/contracts/golden/device/recalc-bisect.jsonl", "packages/contracts/golden/device/glint-hold.jsonl", "packages/contracts/golden/device/glint-compositor.jsonl", "packages/contracts/golden/device/end-wktr.jsonl", "packages/contracts/golden/parts/morph-mount-toolbar.gate.jsonl", "apps/site/src/parts/morph.mount/**", "apps/site/src/parts/engine.scroll/unthrottle.ts"],
  "packages/measure-chromium": ["packages/contracts/src/**", "lean/Fw/Store/Layout.lean", "lean/Fw/Faithful/Measured.lean", "packages/contracts/golden/measure/**", "packages/contracts/golden/faithful/**", "packages/contracts/golden/parts/stage-mode.jsonl", ".github/workflows/chromium-counts.yml", "results/baselines/chromium/**",
    "packages/contracts/golden/device/**", "packages/measure-webkit/src/pathpix*.mjs", "scripts/port/fonts.mjs", "packages/measure-webkit/src/session.mjs", "packages/measure-webkit/src/page.mjs"],
  "packages/gate-breakpoints": ["packages/contracts/src/flag-key.mjs", "lean/**", "packages/measure-webkit/src/device.mjs", "scripts/sim-lock.sh", "apps/site/src/breakpoints.gen.json", "apps/site/src/parts/**",
    "packages/contracts/golden/gate/**", "packages/contracts/golden/morph-geom.jsonl", "packages/contracts/golden/morph-geom-timed.jsonl", "packages/contracts/golden/parts/**", "packages/contracts/fixtures/trajectory-gpu/**",
    "packages/contracts/golden/preset/reader-files.json",
    "packages/measure-webkit/src/images/arm.mjs", "apps/site/src/flags/images/drawn.json",
    "packages/measure-webkit/src/profile/recorder.mjs", "packages/measure-webkit/src/profile/reduce.mjs", "packages/measure-webkit/src/profile/raw.mjs", "packages/measure-webkit/src/device-arms.mjs"],
  "packages/premise-tests": ["packages/contracts/golden/parts/platform-glint-compositor.jsonl", "packages/contracts/golden/morph-geom.jsonl", "packages/gate-breakpoints/src/align-equiv.mjs", "packages/gate-breakpoints/src/page.mjs", "packages/gate-breakpoints/src/serve.mjs", "packages/visual-diff/src/engines.mjs", "packages/visual-diff/src/diff.mjs", "packages/visual-diff/src/run.mjs"],
  "packages/e2e-preview": ["apps/console-api/src/**", "apps/console-api/package.json", "packages/contracts/src/**", "packages/contracts/package.json", "packages/contracts/golden/console/**", "snapshot/site/**"],
  "packages/engine-check": ["packages/contracts/golden/measure/**"],
  "packages/difftest": ["apps/console-api/src/cap/cap.ts", "apps/runner/hooks/cap.mjs", "packages/measure-chromium/src/n0.mjs",
    "packages/measure-chromium/src/trace.mjs", "packages/measure-webkit/src/quietsteps.mjs", "packages/measure-webkit/src/reduce.mjs"],
  "packages/measure-webkit": ["packages/contracts/src/flag-key.mjs", "packages/measure-chromium/src/offscreen.mjs", "packages/contracts/golden/engine/resource.jsonl", "results/accent-draw-nolayout-pixels/run-40037992429/**", "packages/contracts/golden/measure/**","packages/contracts/golden/sup/**", "apps/site/src/flags/images/drawn.json",
    "packages/contracts/golden/device/**", "packages/contracts/golden/ci/telemetry.jsonl", "packages/measure-chromium/src/profile.mjs", "packages/measure-chromium/src/census.mjs", "packages/measure-chromium/profiles/**",
    "apps/site/src/registry/presets/**", "apps/site/src/parts/**",
    "research/notes/2026/10-21-webkit-lag-probe.md",
    "packages/measure-chromium/src/fwcore.mjs", "packages/gate-breakpoints/src/smooth/schedule.mjs", "packages/gate-breakpoints/src/smooth/reduce.mjs",
    "packages/gate-breakpoints/src/smooth/bound.mjs",
    "packages/gate-breakpoints/src/trajectory/reduce.mjs", "packages/gate-breakpoints/src/page.mjs",
    "packages/measure-chromium/src/pathpix*.mjs", "packages/contracts/golden/gate/path-pix.jsonl",
    "packages/measure-chromium/src/cols-verdict.mjs", "packages/measure-chromium/src/cols-reduce.mjs"],
  "packages/snapshot-extract": ["packages/gate-breakpoints/src/**"],
  "packages/visual-diff": ["packages/contracts/src/flag-key.mjs", "packages/gate-breakpoints/src/**", "apps/site/src/breakpoints.gen.json", "packages/contracts/golden/gate/**", "scripts/port/**", "packages/contracts/golden/port/**"],
};

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

export const FWCORE_USERS = ["apps/console-api", "apps/runner", "packages/difftest", "packages/e2e-preview", "packages/engine-check", "packages/gate-breakpoints", "packages/gh-budget", "packages/measure-chromium", "packages/measure-webkit", "packages/measure-wktr", "console-api:compose", "runner:overflow-widths"];
export const FWCORE_BIN = "lean/.lake/build/bin/fwcore";
export const FWCORE_BUILD_READS = ["lean/**", "scripts/fwcore-build.sh", "scripts/fwcore-record-rule.sh"];
export type Digest = string | null;
export const binMoved = (changed: string[], d0: Digest, d1: Digest): boolean =>
  changed.some((c) => inScope(FWCORE_BUILD_READS, c)) && (d0 === null || d1 === null || d0 !== d1);
export const SEED_READS = ["lean/lean-toolchain", "lean/lake-manifest.json", "lean/lakefile.toml", "lean/*.lean", "lean/Fw/**", "lean/FwTest/**"];
export const SEED_THRESHOLD = 5;
export const seedLag = (changed: string[]): number => changed.filter((p) => inScope(SEED_READS, p)).length;
export const seedDue = (lag: number): boolean => lag > SEED_THRESHOLD;
export function unpushedLag(mainDir: string, head: string, main: string): number | null {
  try { return seedLag(git(mainDir, ["diff", "--name-only", "--no-renames", `refs/remotes/origin/${main}`, head]).split("\n").filter(Boolean)); } catch { return null; }
}
export const BUILD_FREE = ["lean/scripts/**", "lean/golden/**", "lean/README.md", "lean/land-filter.txt", "lean/land-legs.txt"];
export const binaryChange = (changed: string[]): string[] => changed.filter((p) => !inScope(BUILD_FREE, p));
export const phase1Build = (changed: string[]): boolean => binaryChange(changed).some((p) => inScope(FWCORE_BUILD_READS, p));
export const selectBin = (ds: { id: string; reads: string[] }[], changed: string[], d0: Digest, d1: Digest) =>
  selectChecks(ds, binMoved(binaryChange(changed), d0, d1) ? [...changed, FWCORE_BIN] : changed);
export const selectTwoPhase = (ds: { id: string; reads: string[] }[], changed: string[], d0: Digest, d1: Digest) =>
  selectChecks(ds, binMoved(changed, d0, d1) ? [...changed, FWCORE_BIN] : changed);

export function checkDeps(list: string[][]): number[][] {
  const isInstall = (a: string[]) => a[0] === "pnpm" && a[1] === "install";
  const isCheckSh = (a: string[]) => a[0] === "sh" && (a[1] === "lean/scripts/check.sh" || a[1] === BUILD_ARGV[1]);
  const usesCore = (a: string[]) => a[0] === "pnpm" && a[1] === "--filter" && FWCORE_USERS.some((p) => a[2] === `./${p}`);
  const idx = (f: (a: string[]) => boolean) => list.flatMap((a, i) => (f(a) ? [i] : []));
  const inst = idx(isInstall), sh = idx(isCheckSh);
  return list.map((a, i) => [...(isInstall(a) ? [] : inst), ...(usesCore(a) ? sh : [])].filter((d) => d !== i));
}

export const READS_SCAN_ID = "reads-scan";
export const READS_SCAN_ARGV = ["pnpm", "--filter", "./apps/runner", "exec", "vitest", "run", "test/land-inputs.test.ts"];
export const withScan = (cs: Check[]): Check[] =>
  [...cs, { id: READS_SCAN_ID, argv: READS_SCAN_ARGV, reads: cs.flatMap((c) => c.reads.filter((g) => !g.startsWith("!"))) }];

export const COMPOSE_READS = ["apps/site/src/parts/*/part.json", "apps/site/src/registry/**", "research/findings/ledger.json", "apps/console-api/src/**",
  "apps/console-api/test/compose.test.ts", "packages/contracts/golden/console/console.compose.jsonl", "lean/.lake/build/bin/fwcore"];
export const LAND_TIER_LOCAL_GOLDEN = "packages/contracts/golden/console/land-tier-local.jsonl";
export const LAND_TIER_LOCAL_ROW = "nothing changed";
export function localReadsFromGolden(id: string, goldenPath = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..", LAND_TIER_LOCAL_GOLDEN)): string[] {
  const rows = readFileSync(goldenPath, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l) as { name: string; request: { tests: { id: string; reads: string[] }[] } });
  const row = rows.find((r) => r.name === LAND_TIER_LOCAL_ROW);
  if (!row) throw new Error(`${goldenPath}: no row named ${LAND_TIER_LOCAL_ROW}`);
  const t = row.request.tests.find((x) => x.id === id);
  if (!t) throw new Error(`${goldenPath}: no ${id} test`);
  return t.reads;
}
export const overflowWidthsReadsFromGolden = (goldenPath?: string): string[] => localReadsFromGolden("runner:overflow-widths", goldenPath);
export const OVERFLOW_WIDTHS_READS = overflowWidthsReadsFromGolden();
export const LEDGER_NOTES_ID = "runner:ledger-notes";
export const LEDGER_NOTES_READS = localReadsFromGolden(LEDGER_NOTES_ID);
export const LOCAL_TESTS: Check[] = [
  { id: "console-api:compose", argv: ["pnpm", "--filter", "./apps/console-api", "exec", "vitest", "run", "test/compose.test.ts"], reads: COMPOSE_READS },
  { id: "runner:overflow-widths", argv: ["pnpm", "--filter", "./apps/runner", "exec", "vitest", "run", "test/land-overflow-widths.test.ts"], reads: OVERFLOW_WIDTHS_READS },
  { id: LEDGER_NOTES_ID, argv: ["pnpm", "--filter", "./apps/runner", "exec", "vitest", "run", "test/ledger-merge.test.ts", "test/land-notes.test.ts"], reads: LEDGER_NOTES_READS },
];

export const WORKFLOW_LINT: Check = { id: WORKFLOW_LINT_ID, argv: WORKFLOW_LINT_ARGV, reads: WORKFLOW_LINT_READS };
export const LOCAL_GATES: Check[] = [...LOCAL_TESTS, WORKFLOW_LINT];

export function candidateChecks(root: string): Check[] {
  const out: Check[] = [
    { id: "install", argv: ["pnpm", "install", "--frozen-lockfile"], reads: INSTALL_READS },
    { id: "check.sh", argv: ["sh", "lean/scripts/check.sh"], reads: CHECK_SH_READS },
  ];
  for (const t of ["apps", "packages"]) {
    let names: string[] = [];
    try { names = readdirSync(join(root, t)).sort(); } catch { }
    for (const n of names) {
      const p = `${t}/${n}`;
      try {
        const pkg = JSON.parse(readFileSync(join(root, p, "package.json"), "utf8"));
        if (pkg.scripts?.test) out.push({ id: p, argv: ["pnpm", "--filter", `./${p}`, "test"],
          reads: [`${p}/**`, NODE_BUDGET_GEN, "scripts/slot-self.mjs", ...workspaceDeps(root, pkg).map((d) => `${d}/**`), ...(PACKAGE_EXTRA_READS[p] ?? []), ...(FWCORE_USERS.includes(p) ? [FWCORE_BIN] : [])] });
      } catch { }
    }
  }
  return withScan([...out, ...LOCAL_GATES]);
}

export function checksWithReads(root: string, changed: string[], d0: Digest = null, d1: Digest = null, select: typeof selectTwoPhase = selectTwoPhase): Check[] {
  const all = candidateChecks(root);
  const ids = new Set(select(all, changed, d0, d1));
  return all.filter((c) => ids.has(c.id));
}

export function inputKey(root: string, reads: string[]): string {
  const scope = scopeOf(reads);
  const files = trackedFiles(root).filter((f) => scope(f)).sort();
  const h = createHash("sha256");
  for (const f of files) {
    let c: Buffer | string = "";
    try { c = readFileSync(join(root, f)); } catch { c = "<missing>"; }
    h.update(`${f}\0${createHash("sha256").update(c).digest("hex")}\n`);
  }
  return h.digest("hex");
}

export function checksFor(root: string, changed: string[]): string[][] {
  return checksWithReads(root, changed).map((c) => c.argv);
}

export function ciLines(ref: string, cwd: string = process.cwd(), env?: Env): string[] {
  const args = ["run", "list", "--branch", ref, "--limit", "5", "--json", "name,conclusion,status,headSha"];
  try {
    const e = env ?? realEnv(cwd);
    const r = chargedOnce(e, (state, now) => e.core({ op: "ci.budget.reserve", now, state, cost: ghCost(args) }), () => args, GH_BOUNDS.landCallTimeoutMs);
    if (!r.ran) return [`budget ${r.decision} (${r.reason})`];
    if (r.code !== 0) return ["unavailable"];
    const rs = JSON.parse(r.stdout) as { name: string; conclusion: string; status: string; headSha: string }[];
    return rs.length ? rs.map((x) => `${x.name} ${x.headSha.slice(0, 7)} ${x.conclusion || x.status}`) : ["no runs"];
  } catch { return ["unavailable"]; }
}

export const LEDGER_FILE = "research/findings/ledger.json";

export function allocN(mainNs: readonly number[], rows: readonly (number | null)[]): number[] {
  let next = Math.max(0, ...mainNs, ...rows.filter((n): n is number => n !== null)) + 1;
  return rows.map((n) => (n !== null ? n : next++));
}

const rowN = (r: { n?: unknown }): number | null => (typeof r.n === "number" ? r.n : null);

export function allocLedger(dir: string, mainRef: string): "written" | "none" | "failed" {
  const f = join(dir, LEDGER_FILE);
  let raw: string;
  try { raw = readFileSync(f, "utf8"); } catch { return "none"; }
  try {
    const d = JSON.parse(raw) as { findings: Record<string, unknown>[] };
    if (!d.findings.some((r) => rowN(r) === null)) return "none";
    const main = JSON.parse(git(dir, ["show", `${mainRef}:${LEDGER_FILE}`])) as { findings: { n?: unknown }[] };
    const mainNs = main.findings.map(rowN).filter((n): n is number => n !== null);
    const ns = allocN(mainNs, d.findings.map(rowN));
    d.findings = d.findings.map((r, i) => (rowN(r) !== null ? r : (({ n: _n, ...rest }) => ({ n: ns[i]!, ...rest }))(r)));
    writeFileSync(f, JSON.stringify(d, null, 1) + (raw.endsWith("\n") ? "\n" : ""));
    return tryGit(dir, ["add", "--", LEDGER_FILE]) ? "written" : "failed";
  } catch { return "failed"; }
}

export function ledgerNoteKeyCheck(dir: string): string | null {
  let raw: string;
  try { raw = readFileSync(join(dir, LEDGER_FILE), "utf8"); } catch { return null; }
  let notes: unknown;
  try { notes = (JSON.parse(raw) as { notes?: unknown }).notes; } catch { return `ledger-note-key: ${LEDGER_FILE} is not valid JSON`; }
  if (!Array.isArray(notes)) return null;
  const keyed = notes.filter((n): n is NoteKey & { field?: unknown } => typeof n?.entry === "string" && typeof n?.task === "string");
  const dup = noteKeyRefusal(LEDGER_FILE, keyed);
  if (dup) return dup;
  const shape = noteShapeProblems(raw);
  return shape.length ? `ledger-note-shape: ${LEDGER_FILE} has notes the ledger tests refuse:\n${shape.map((l) => `  ${l}`).join("\n")}` : null;
}

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

export type PreAct = "ff" | "refuse" | "recheck" | "fallback";
export const prelockAction = (head: string, main0: string, verdict: boolean, attempt: number, maxRetry: number): PreAct =>
  head === main0 ? (verdict ? "ff" : "refuse") : attempt < maxRetry ? "recheck" : "fallback";
export const PRELOCK_RETRIES = 3;

export const poolFor = (cores: number, loadCeil: number): number => {
  const r = askCore("console.landPool", { cores, load: loadCeil });
  return r && Number.isInteger(r.pool) && r.pool >= 1 ? r.pool : 1;
};
export const NODE_BUDGET_GEN = "packages/contracts/golden/sched/node-budget.gen.json";
export function testWorkersEnv(root: string, pool: number): Record<string, string> {
  let byPool: Record<string, number>;
  try { byPool = (JSON.parse(readFileSync(join(root, NODE_BUDGET_GEN), "utf8")) as { byPool: Record<string, number> }).byPool; } catch { return {}; }
  return { VITEST_MAX_WORKERS: String(byPool[String(pool)] ?? 1) };
}
export const rerunAlone = (passed: boolean, loadFailure: boolean): boolean =>
  askCore("console.landRetry", { passed, loadFailure })?.rerun === true;
export const LOAD_FAILURE_RE = /timed out in \d+\s*ms|ETIMEDOUT|Hook timed out|Test timed out/;

export type WtSlot = { idx: number; dist: number | null };
export function pickLandWt(slots: WtSlot[]): number | null {
  const before = (a: WtSlot, b: WtSlot): boolean =>
    a.dist !== null && b.dist !== null ? a.dist < b.dist || (a.dist === b.dist && a.idx < b.idx) : a.dist !== null ? true : b.dist !== null ? false : a.idx < b.idx;
  let best: WtSlot | undefined;
  for (const s of slots) if (best === undefined || before(s, best)) best = s;
  return best === undefined ? null : best.idx;
}
export const LAND_WT_INPUT_RE = /\.lean$|(^|\/)lakefile|(^|\/)lean-toolchain$|(^|\/)lake-manifest/;
export function landWtDist(dir: string, commit: string): number | null {
  if (!existsSync(join(dir, "lean", ".lake"))) return null;
  try {
    return git(dir, ["diff", "--name-only", "HEAD", commit, "--", "lean"]).split("\n").filter((f) => LAND_WT_INPUT_RE.test(f)).length;
  } catch { return null; }
}

export function claimLandWt(mainDir: string, commit?: string): { dir: string; free: () => void } {
  const root = join(mainDir, ".claude", "land-wt");
  mkdirSync(root, { recursive: true });
  const take = (n: number): { dir: string; free: () => void } | null => {
    const claim = join(root, `${n}.claim`);
    for (let again = 0; again < 2; again++) {
      try { writeFileSync(claim, `${process.pid}\n`, { flag: "wx" }); return { dir: join(root, String(n)), free: () => { try { unlinkSync(claim); } catch { } } }; }
      catch (e) {
        if ((e as NodeJS.ErrnoException).code !== "EEXIST") throw e;
        const pid = Number(readFileSync(claim, "utf8").trim());
        if (alive(pid)) return null;
        try { unlinkSync(claim); } catch { }
      }
    }
    return null;
  };
  const isFree = (n: number): boolean => {
    try { return !alive(Number(readFileSync(join(root, `${n}.claim`), "utf8").trim())); } catch { return true; }
  };
  const tried = new Set<number>();
  for (;;) {
    let top = 0;
    for (const f of readdirSync(root)) { const m = /^(\d+)(\.claim)?$/.exec(f); if (m) top = Math.max(top, Number(m[1]) + 1); }
    const cands: WtSlot[] = [];
    for (let n = 0; n <= top; n++) if (!tried.has(n) && isFree(n)) cands.push({ idx: n, dist: commit === undefined ? null : landWtDist(join(root, String(n)), commit) });
    const n = pickLandWt(cands);
    if (n === null) { tried.clear(); continue; }
    const got = take(n);
    if (got) return got;
    tried.add(n);
  }
}

export function checkoutLandWt(mainDir: string, dir: string, commit: string, prep?: (dir: string, known: boolean) => string | null | void): string | null {
  let refusal: string | null = null;
  const known = existsSync(dir) && worktrees(mainDir).some((w) => existsSync(w.dir) && realpathSync(w.dir) === realpathSync(dir));
  if (!known) {
    tryGit(mainDir, ["worktree", "prune"]);
    rmSync(dir, { recursive: true, force: true });
    git(mainDir, ["worktree", "add", "--detach", "--force", dir, commit]);
    refusal = prep?.(dir, false) ?? null;
    git(dir, ["clean", "-fdxq", "-e", ".lake", "-e", "node_modules"]);
  } else {
    git(dir, ["checkout", "--detach", "--force", commit]);
    git(dir, ["clean", "-fdxq", "-e", ".lake", "-e", "node_modules"]);
    refusal = prep?.(dir, true) ?? null;
  }
  return refusal;
}

export type InstallResult = boolean | { ok: boolean; tail?: string };
export type InstallExec = (argv: string[], cwd: string) => InstallResult;
export const INSTALL_TIMEOUT_MS = 10 * 60_000;
const tailOf = (text: string, n = 6) => text.split("\n").map((l) => l.trimEnd()).filter((l) => l !== "").slice(-n).join(" | ");
const installExec: InstallExec = (argv, cwd) => {
  try { execFileSync(argv[0]!, argv.slice(1), { cwd, stdio: ["ignore", "ignore", "pipe"], timeout: INSTALL_TIMEOUT_MS, maxBuffer: 64 * 1024 * 1024 }); return { ok: true }; }
  catch (e) {
    const x = e as { stderr?: Buffer | string; code?: string; signal?: string };
    const err = x.stderr ? x.stderr.toString() : "";
    return { ok: false, tail: tailOf(err) || (x.code === "ETIMEDOUT" || x.signal === "SIGTERM" ? `timed out after ${INSTALL_TIMEOUT_MS / 1000}s` : String(x.code ?? e)) };
  }
};
const resultOf = (r: InstallResult) => (typeof r === "boolean" ? { ok: r, tail: "" } : { ok: r.ok, tail: r.tail ?? "" });
export const landExit = (res: { ok: boolean; kind?: Kind }): number => exitCode(res.kind ?? (res.ok ? "done" : "unknown"));
export const dryLandReport = (res: Pick<LandResult, "lines" | "outcome">, task: string): { err: string[]; out: string[]; code: number } => {
  const oc = res.outcome ?? outcome({ threw: true });
  return { err: res.lines, out: dryRun(oc, task), code: exitCode(outcomeKind(oc)) };
};
export function landInstall(dir: string, exec: InstallExec = installExec): string | null {
  const off = resultOf(exec(["pnpm", "install", "--offline", "--frozen-lockfile"], dir));
  const on = installRunsOnline(off.ok) ? resultOf(exec(["pnpm", "install", "--frozen-lockfile"], dir)) : { ok: false, tail: "" };
  if (installKind(off.ok, on.ok) === null) return null;
  return `install failed in ${dir}: offline and online \`pnpm install --frozen-lockfile\` both failed (no network, or a bad lockfile?)\n  offline stderr: ${off.tail || "(none)"}\n  online stderr: ${on.tail || "(none)"}`;
}

export type StampFs = { lockHash(dir: string): string | null; readStamp(dir: string): string | null; writeStamp(dir: string, hash: string): void; clearStamp(dir: string): void };
export const STAMP_FILE = "node_modules/.fw-lock-stamp";
export const realStampFs: StampFs = {
  lockHash: (dir) => { try { return createHash("sha256").update(readFileSync(join(dir, "pnpm-lock.yaml"))).digest("hex"); } catch { return null; } },
  readStamp: (dir) => { try { return readFileSync(join(dir, STAMP_FILE), "utf8").trim() || null; } catch { return null; } },
  writeStamp: (dir, hash) => { mkdirSync(join(dir, "node_modules"), { recursive: true }); writeFileSync(join(dir, STAMP_FILE), `${hash}\n`); },
  clearStamp: (dir) => { rmSync(join(dir, STAMP_FILE), { force: true }); },
};
export function landInstallStamped(dir: string, known: boolean, exec: InstallExec = installExec, fs: StampFs = realStampFs): string | null {
  const lock = fs.lockHash(dir);
  const stamp = fs.readStamp(dir);
  if (lock === null || !installNeeded(known, lock, stamp)) return null;
  fs.clearStamp(dir);
  const why = landInstall(dir, exec);
  const st = installStep(known, lock, stamp, why === null, why === null);
  if (st.kind === null && st.stampAfter === lock) fs.writeStamp(dir, lock);
  return why;
}
const prepLandWt = (exec?: InstallExec, fs?: StampFs) => (dir: string, known: boolean): string | null => {
  if (!known && existsSync(join(dir, "scripts/wt-prep.sh"))) { try { execFileSync("sh", ["scripts/wt-prep.sh"], { cwd: dir, stdio: "ignore" }); } catch { } }
  return landInstallStamped(dir, known, exec, fs);
};

export function binDigest(dir: string): Digest {
  try { return createHash("sha256").update(readFileSync(join(dir, FWCORE_BIN))).digest("hex"); } catch { return null; }
}
const HEX64 = /^[0-9a-f]{64}$/;
const digestFile = (mainDir: string, commit: string) =>
  join(git(mainDir, ["rev-parse", "--path-format=absolute", "--git-common-dir"]), "fw-land", "fwcore-digest", commit);
export function storedDigest(mainDir: string, commit: string): Digest {
  try { const d = readFileSync(digestFile(mainDir, commit), "utf8").trim(); if (HEX64.test(d)) return d; } catch { }
  try {
    const r = parseBuildRecord(readFileSync(join(mainDir, `${FWCORE_BIN}.commit`), "utf8"));
    if (r && binDigest(mainDir) === r.hash) {
      if (r.kind === "commit" ? r.id === commit : git(mainDir, ["rev-parse", `${commit}^{tree}`]) === r.id) return r.hash;
    }
  } catch { }
  return null;
}
export function parseBuildRecord(text: string): { kind: "tree" | "commit"; id: string; hash: string } | null {
  const f = text.trim().split(/\s+/);
  if (f[0] === "tree" && f.length === 3 && f[1] && HEX64.test(f[2] ?? "")) return { kind: "tree", id: f[1], hash: f[2] as string };
  if (f.length === 2 && f[0] && f[0] !== "tree" && HEX64.test(f[1] ?? "")) return { kind: "commit", id: f[0], hash: f[1] as string };
  return null;
}
export function fwcorePreflight(mainDir: string, main: string): string | null {
  if (!tryGit(mainDir, ["cat-file", "-e", `${main}:scripts/fwcore-build.sh`])) return null;
  let recorded: string | null = null;
  try {
    const r = parseBuildRecord(readFileSync(join(mainDir, `${FWCORE_BIN}.commit`), "utf8"));
    if (r && binDigest(mainDir) === r.hash) {
      if (r.kind === "commit") recorded = r.id;
      else {
        const hit = git(mainDir, ["log", "--first-parent", "-n", "1000", "--format=%H %T", main]).split("\n").find((l) => l.endsWith(` ${r.id}`));
        if (hit) recorded = hit.split(" ")[0] ?? null;
      }
    }
  } catch { }
  const head = git(mainDir, ["rev-parse", main]);
  const same = recorded === head;
  let moved = true;
  if (recorded !== null && !same) {
    try { moved = git(mainDir, ["diff", "--name-only", recorded, main, "--", "lean", "scripts/fwcore-build.sh", "scripts/fwcore-record-rule.sh"]) !== ""; } catch { moved = true; }
  }
  return fwcoreStale(recorded, same, moved) ? FWCORE_STALE_REASON : null;
}
export function storeDigest(mainDir: string, commit: string, d: string): void {
  try { const f = digestFile(mainDir, commit); mkdirSync(dirname(f), { recursive: true }); writeFileSync(f, `${d}\n`); } catch { }
}
export function buildClean(dir: string): boolean {
  if (!tryGit(dir, ["diff", "--quiet", "HEAD", "--", "lean", "scripts/fwcore-build.sh", "scripts/fwcore-record-rule.sh"])) return false;
  try { return git(dir, ["ls-files", "--others", "--exclude-standard", "--", "lean"]) === ""; } catch { return false; }
}

export function dryLintArgv(dir: string, changed: string[]): string[][] {
  return lintPlan(changed, existsSync(join(dir, "scripts/ci-paths.mjs")), existsSync(join(dir, "lean/scripts/axiom-check.sh")),
    existsSync(join(dir, "apps/site/scripts/part-footprint.mjs")));
}

export type LakeKey = { lean: string; golden: string };
export type LakeRec = { key: LakeKey; src: "dryLint" | "checkSh"; pass: boolean };
export const LAKE_GOLDEN_DIR = "packages/contracts/golden";
const CHECK_SH_ARGV = ["sh", "lean/scripts/check.sh"];
const sameLakeKey = (a: LakeKey, b: LakeKey): boolean => a.lean === b.lean && a.golden === b.golden;
export const lakeHit = (rs: LakeRec[], k: LakeKey): boolean => rs.some((r) => r.pass && sameLakeKey(r.key, k));
export const runLake = (touchesLean: boolean, rs: LakeRec[], k: LakeKey): boolean => touchesLean && !lakeHit(rs, k);
export function lakeKeyOf(cwd: string, rev: string): LakeKey | null {
  try { return { lean: git(cwd, ["rev-parse", `${rev}:lean`]), golden: git(cwd, ["rev-parse", `${rev}:${LAKE_GOLDEN_DIR}`]) }; } catch { return null; }
}
export const lakePassFile = (conDir: string, k: LakeKey): string => join(conDir, "review-cache", "land-lake", `${k.lean}-${k.golden}`);
export const checkShRecordFile = (conDir: string, tree: string): string =>
  join(conDir, "review-cache", "slot", `${createHash("sha256").update(JSON.stringify({ kind: "check", argv: CHECK_SH_ARGV, tree, base: "" })).digest("hex").slice(0, 32)}.json`);
export function lakeRecords(conDir: string, cwd: string, revs: string[], k: LakeKey): LakeRec[] {
  const out: LakeRec[] = [];
  if (existsSync(lakePassFile(conDir, k))) out.push({ key: k, src: "dryLint", pass: true });
  for (const rev of revs) {
    try {
      const tree = git(cwd, ["rev-parse", `${rev}^{tree}`]);
      const rec = JSON.parse(readFileSync(checkShRecordFile(conDir, tree), "utf8")) as { key?: { tree?: string }; exit?: number };
      const key = lakeKeyOf(cwd, rev);
      if (rec.exit === 0 && rec.key?.tree === tree && key) out.push({ key, src: "checkSh", pass: true });
    } catch { }
  }
  return out;
}
export const isLakeLint = (a: string[]): boolean => a.join("\0") === LINT_ARGV.axioms.join("\0");
export const withoutLake = (plan: string[][]): string[][] => plan.filter((a) => !isLakeLint(a));

export type DryBase = "contains" | "clean" | "conflict";
export const dryBase = (behind: boolean, mergeClean: boolean): DryBase => !behind ? "contains" : mergeClean ? "clean" : "conflict";
export function dryOutcome(base: DryBase, f: { own: boolean; scope: boolean; merges: boolean; reads: boolean; lints: boolean }): Outcome {
  return base === "conflict" ? outcome({ own: f.own, merges: false }) : outcome(f);
}
export function dryMerge(cwd: string, main: string, sha: string): { tree: string; changed: string[] } | null {
  let tree: string;
  try { tree = git(cwd, ["-c", `attr.tree=${main}`, "merge-tree", "--write-tree", main, sha]).split("\n")[0]!; }
  catch (e) { if ((e as { status?: number }).status === 1) return null; throw e; }
  return { tree, changed: git(cwd, ["diff", "--no-renames", "--name-only", main, tree]).split("\n").filter(Boolean) };
}

type PreResult = { kind: "done"; sha: string } | { kind: "refuse"; msg: string; k?: Kind } | { kind: "fallback"; why: string };
const READS_FAIL_RE = /land-inputs\.test|premise land\.readsOnly/;

type PlanTask = { id: string; state: string; owner?: string; stream?: string; writes?: string[] };

export function pickFacts(cwd: string, main: string, branch: string, task?: string): { givenAhead: boolean; others: { name: string; ahead: boolean; contains: boolean }[] } {
  const inMain = (ref: string) => tryGit(cwd, ["merge-base", "--is-ancestor", ref, main]);
  const givenAhead = !inMain(branch);
  if (givenAhead) return { givenAhead, others: [] };
  const names = new Set<string>();
  if (task && tryGit(cwd, ["rev-parse", "--verify", "-q", `refs/heads/ci/${task}`])) names.add(`ci/${task}`);
  const stem = branch.replace(/^worktree-/, "").replace(/\//g, "-");
  for (const w of worktrees(cwd)) if (w.branch && basename(w.dir).endsWith(stem)) names.add(w.branch);
  names.delete(branch); names.delete(main);
  return { givenAhead, others: [...names].map((name) => ({ name, ahead: !inMain(name), contains: tryGit(cwd, ["merge-base", "--is-ancestor", branch, name]) })) };
}

export const renderLogArgv = (main: string, tip: string): string[] =>
  ["-c", "log.showSignature=false", "log", "-z", "--no-renames", "--no-relative", "--no-ext-diff", "--name-status", "--diff-merges=first-parent", "--format=commit %H", `${main}..${tip}`];
export type RenderHit = { commit: string; path: string; media: string };
export function renderGuard(cwd: string, main: string, tip: string): { hits: RenderHit[] } | { error: string } {
  let out: string;
  try { out = execFileSync("git", renderLogArgv(main, tip), { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], maxBuffer: 256 * 1024 * 1024 }); }
  catch (e) { return { error: `git log failed: ${String((e as { stderr?: string }).stderr ?? e).trim().slice(0, 200)}` }; }
  const r = askCore("console.landRenderGuard", { tokens: out.split("\0") });
  if (!r || !Array.isArray(r.hits)) return { error: "fwcore is not available to decide (build lean/.lake)" };
  return { hits: r.hits as RenderHit[] };
}

export async function land(branch: string, o: LandOptions, via?: string): Promise<LandResult> {
  const before = stepPrefix;
  if (!via) stepPrefix = o.dry ? "dry " : "";
  const end = via ? () => {} : begin("fw land", "total");
  if (!via) { dryStep = null; dryLake = null; }
  const named = (code: number) => end(code, dryStep === null ? {} : { step: dryStep, ...(dryLake === null ? {} : { lake: dryLake }) });
  try { const r = await landRun(branch, o, via); named(r.ok ? 0 : 1); return r; } catch (e) { named(1); throw e; } finally { stepPrefix = before; }
}

async function landRun(branch: string, o: LandOptions, via?: string): Promise<LandResult> {
  const lines: string[] = via ? [`${via} has nothing to land; landing ${branch}, which is ahead of it and contains it`] : [];
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
  let dm: { main0: string; tree: string; changed: string[] } | null = null;
  if (o.dry) {
    const main0 = git(mainDir, ["rev-parse", "HEAD"]);
    if (tryGit(o.cwd, ["merge-base", "--is-ancestor", sha, main0])) {
      const oc = dryOutcome(dryBase(behind, true), { own: false, scope: true, merges: true, reads: true, lints: true });
      return { ok: true, lines: [...lines, `dry: ${branch} has no commit of its own (already in ${main}); nothing to land`], kind: outcomeKind(oc), outcome: oc };
    }
    const m = dryMerge(mainDir, main0, sha);
    const base = dryBase(behind, m !== null);
    if (!m) return fail(`${main} ${main0.slice(0, 7)} cannot merge ${branch} cleanly (git merge-tree): merge ${main} into it, resolve the conflict and run the dry land again`, "conflict", dryOutcome(base, { own: true, scope: true, merges: true, reads: true, lints: true }));
    lines.push(base === "clean" ? `dry: ${branch} is behind ${main}; git merge-tree merges it cleanly, so the checks run on that merge's diff with ${main}` : `dry: ${branch} contains ${main}`);
    dm = { main0, ...m };
  }
  if (behind && !o.task) return fail(`${branch} is behind ${main}; a fast-forward is impossible (land it with --task for a merge commit; branches are never rebased)`);
  const rg = renderGuard(o.cwd, main, sha);
  if ("error" in rg) return fail(`render guard: ${rg.error}`);
  if (rg.hits.length)
    return fail(`render guard: ${main}..${branch} (${sha.slice(0, 7)}) writes media outside snapshot/, and a later removal leaves the blob in history:${rg.hits.map((h) => `\n  ${h.path} (${h.media}) in ${h.commit}`).join("")}\nmove the other changes to a new branch from ${main} without these commits, or add the path with its reason to Fw.Land.RenderGuard.allowlist`, "scope", outcome({ scope: false }));

  let task: PlanTask | undefined;
  if (o.task) {
    if (!/^[A-Za-z0-9._-]+$/.test(o.task)) return fail(`bad task id ${o.task}`);
    const pl = await o.http.get("/api/plan");
    task = (pl.body?.tasks as PlanTask[] | undefined)?.find((x) => x.id === o.task);
    if (!task) return fail(`unknown task ${o.task} (fw plan sync first)`);
    if (task.state === "done") return fail(`task ${o.task} is already done`, "done");
  }
  let writes: string[] = [];
  let stream = task?.stream ?? "";
  if (task) {
    try {
      const g = JSON.parse(readFileSync(join(mainDir, "docs/team/work-graph.json"), "utf8")) as { tasks?: PlanTask[] };
      const row = g.tasks?.find((x) => x.id === o.task);
      writes = row?.writes ?? [];
      stream = row?.stream ?? stream;
    } catch { }
  }
  const own3 = git(o.cwd, ["diff", "--no-renames", "--name-only", `${main}...${sha}`]).split("\n").filter(Boolean);
  const changed = dm ? [...new Set([...dm.changed, ...own3])] : own3;
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
    const lr = await submit(cmd);
    return lr.body.ok ? null : `land_request: ${lr.body.reason}`;
  };

  const LOAD_TOLERANT_ENV = { FW_CORE_CALL_MS: "60000", FW_HOOK_ASK_TIMEOUT_MS: "30000", FW_EXEC_TIMEOUT_MS: "30000" };
  const logFile = join(mainDir, ".fw-console", "land-logs", `${(o.task ?? branch).replace(/[^A-Za-z0-9._-]/g, "_")}-${sha.slice(0, 7)}.log`);
  let logStarted = false;
  const runCheck = (cwd: string, argv: string[], pool = 1) => new Promise<{ status: number | null; stdout: string; stderr: string; error?: Error }>((resolve) => {
    const c = spawn(argv[0]!, argv.slice(1), { cwd, env: { ...LOAD_TOLERANT_ENV, ...process.env, ...testWorkersEnv(cwd, pool), ...o.env }, detached: true });
    let stdout = "", stderr = "";
    c.stdout.on("data", (d) => { stdout += d; }); c.stderr.on("data", (d) => { stderr += d; });
    const kill = () => { try { process.kill(-c.pid!, "SIGTERM"); } catch { c.kill("SIGTERM"); } };
    process.once("SIGTERM", kill); process.once("SIGINT", kill); process.once("exit", kill);
    const done = (status: number | null, error?: Error) => { process.off("SIGTERM", kill); process.off("SIGINT", kill); process.off("exit", kill); resolve({ status, stdout, stderr, error }); };
    c.on("error", (e) => done(null, e));
    c.on("close", (code) => done(code));
  });
  let phase1Built = false;
  const twoPhaseChecks = async (dir: string, main0: string, c: string): Promise<Check[]> => {
    const d0 = storedDigest(mainDir, main0);
    let d1: Digest = d0;
    phase1Built = false;
    if (phase1Build(changed)) {
      const endBuild = begin("fw land", "fwcore build (phase 1)");
      const r = await runCheck(dir, ["sh", "scripts/fwcore-build.sh"]);
      endBuild(r.status, r.status === 0 ? lakeMember(`${r.stdout}${r.stderr}`) : {});
      phase1Built = r.status === 0;
      d1 = r.status === 0 && buildClean(dir) ? binDigest(dir) : null;
      lines.push(`fwcore digest: ${main} ${d0?.slice(0, 12) ?? "unknown"}, merge ${d1?.slice(0, 12) ?? "unknown"}: fwcore users ${binMoved(changed, d0, d1) ? "selected" : "skipped"}`);
    }
    if (d1) storeDigest(mainDir, c, d1);
    return checksWithReads(dir, changed, d0, d1, selectBin);
  };
  const tieredChecks = async (dir: string, main0: string, c: string, list: Check[]): Promise<string | null> => {
    if (o.remote === false || !o.task) return runChecks(dir, list.map((x) => x.argv));
    const r = o.remote ?? {};
    const call = fwcoreCall(mainDir);
    const laneChanged = git(mainDir, ["diff", "--name-only", main0, c]).split("\n").filter(Boolean);
    const all = candidateChecks(dir);
    const laneSel = new Set(selectTwoPhase(all, laneChanged, null, null));
    const laneIds = (call({ op: "console.landTier", ids: all.filter((x) => laneSel.has(x.id)).map((x) => x.id) }) as { remote: string[] }).remote;
    let adapters = r.adapters;
    let overflow: OverflowPlan | undefined;
    if (!adapters) {
      const gh = chargedGh(realEnv(mainDir));
      const push = makePusher({ git: (a) => git(mainDir, a), scan: (m) => scanRange(dir, mainDir, m), intent: fileIntents(() => git(mainDir, ["rev-parse", "--path-format=absolute", "--git-common-dir"])) });
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
  const logLine = (l: string): void => {
    mkdirSync(join(mainDir, ".fw-console", "land-logs"), { recursive: true });
    if (!logStarted) { writeFileSync(logFile, ""); logStarted = true; }
    appendFileSync(logFile, `${l}\n`);
    process.stderr.write(`${l}\n`);
  };
  let badKind: Kind = "checks";
  const builds: number[] = [];
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
          const end = begin("fw land", argv.join(" "));
          void runCheck(cwd, argv, limit).then((p) => {
            end(p.status, p.status === 0 ? lakeMember(`${p.stdout}${p.stderr}`) : {});
            results[i] = { status: p.status, out: `${p.stdout}${p.stderr}${p.error ? String(p.error) : ""}` };
            running--; pump();
          });
        }
        if (results.every(Boolean)) done();
      };
      pump();
    });
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
      builds.push(builtModules(r.out));
      appendFileSync(logFile, `$ ${argv.join(" ")}  (cwd ${cwd})\n${r.out}\n[exit ${r.status}]\n\n`);
      if (r.status !== 0) {
        failedChecks.push({ reads: READS_FAIL_RE.test(r.out), stages: failedStages(r.out) });
        const tail = r.out.split("\n").filter((l) => l !== "").slice(-30).join("\n");
        bad.push(`check FAILED: ${argv.join(" ")}\nlog: ${logFile}\n${tail}`);
      } else lines.push(`check ok: ${argv.join(" ")}`);
    });
    if (failedChecks.length) badKind = checkFailKind(failedChecks);
    return bad.length ? bad.join("\n\n") : null;
  };
  if (dm) {
    const { main0, tree } = dm;
    const c = git(mainDir, ["commit-tree", tree, "-p", main0, "-p", sha, "-m", `dry ${branch}`]);
    const slot = claimLandWt(mainDir, c);
    let lakeKey: LakeKey | null = null, lakeSkipped = false, dryPlan: string[][] | null = null;
    try {
      const instDry = checkoutLandWt(mainDir, slot.dir, c, o.dryReads ? undefined : prepLandWt(o.installExec, o.installFs));
      if (instDry) return fail(instDry, "install", outcome({ installs: false }));
      if (writeEvidence(slot.dir, o.task!, sha.slice(0, 7)) === "failed") return fail("could not write the evidence into docs/team/work-graph.json");
      if (allocLedger(slot.dir, main0) === "failed") return fail(`could not assign numbers to the new rows of ${LEDGER_FILE}`);
      let marks = "";
      try { marks = git(slot.dir, ["grep", "-n", "-E", MARKER_RE]); } catch { }
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
      const reads = !selected || test;
      let lints = true;
      if (reads) {
        let lintArgv = o.dryLints ?? dryLintArgv(slot.dir, changed);
        if (!o.dryLints && process.env.FW_LAND_LAKE_CACHE !== "off" && lintArgv.some(isLakeLint)) {
          lakeKey = lakeKeyOf(mainDir, tree);
          if (lakeKey) {
            const revs = git(mainDir, ["rev-list", "--first-parent", "-n", "12", `${main}..${sha}`]).split("\n").filter(Boolean);
            if (!runLake(true, lakeRecords(join(mainDir, ".fw-console"), mainDir, revs, lakeKey), lakeKey)) {
              lintArgv = withoutLake(lintArgv);
              lakeSkipped = true;
              lines.push(`dry: lake build and axiom check skipped (a pass is on record for the lean/ tree ${lakeKey.lean.slice(0, 12)} and the golden tree ${lakeKey.golden.slice(0, 12)})`);
            }
          }
        }
        dryPlan = lintArgv;
        dryStep = dryTotalStep(lintArgv, false);
        if (lintArgv.length) {
          const bad = await runChecks(slot.dir, lintArgv);
          lints = bad === null; detail = bad ?? "";
          if (lints && lakeKey && !lakeSkipped && lintArgv.some(isLakeLint)) {
            const f = lakePassFile(join(mainDir, ".fw-console"), lakeKey);
            mkdirSync(dirname(f), { recursive: true });
            writeFileSync(f, `${new Date().toISOString()}\n`);
          }
        }
      } else lines.push("dry: lints skipped (reads refused first)");
      if (reads && lints) {
        const bad = ledgerNoteKeyCheck(slot.dir);
        lints = bad === null; detail = bad ?? "";
        if (lints) lines.push(`dry: ledger notes ok (one note per (entry, task) in ${LEDGER_FILE})`);
      }
      if (reads && lints) {
        const local = (o.dryLocal ?? LOCAL_GATES).filter((t) => selectChecks([t], changed).length > 0);
        if (local.length) {
          const needsBuild = !o.dryLocal && local.some((t) => FWCORE_USERS.includes(t.id)) && (phase1Build(changed) || lakeSkipped || !existsSync(join(slot.dir, FWCORE_BIN)));
          dryStep = dryTotalStep(dryPlan ?? o.dryLints ?? dryLintArgv(slot.dir, changed), needsBuild);
          const argv = [...(needsBuild ? [["sh", "scripts/fwcore-build.sh"]] : []), ...local.map((t) => t.argv)];
          const bad = await runChecks(slot.dir, argv);
          lints = bad === null; detail = bad ?? "";
          if (lints) lines.push(`dry: local tests ok (${local.map((t) => t.id).join(", ")})`);
        }
      }
      const oc = outcome({ reads, lints });
      if (outcomeKind(oc) !== "dry") return fail(detail || `dry land refused: ${outcomeKind(oc)}`, "unknown", oc);
      lines.push(`dry ok at ${main} ${main0.slice(0, 7)}: the land's scope, merge, reads and fast lints pass unless ${main} moves`);
      return { ok: true, lines, kind: "dry", outcome: oc };
    } finally {
      slot.free();
      if (dryStep?.endsWith("lake")) {
        dryLake = { built: outerBuilt(builds) };
        noteSpan("fw", "land dry", { lake: dryLake });
        writeLakeHandoff(dryLake);
      }
    }
  }
  const checks = o.checks ?? checksFor(mainDir, changed);

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
        const inst = checkoutLandWt(mainDir, slot.dir, c, o.checks ? undefined : prepLandWt(o.installExec, o.installFs));
        if (inst) return { kind: "refuse", msg: inst, k: "install" };
        const ev = writeEvidence(slot.dir, o.task!, sha.slice(0, 7));
        if (ev === "failed") return { kind: "refuse", msg: "could not write the evidence into docs/team/work-graph.json" };
        if (ev === "written") { c = mk(git(slot.dir, ["write-tree"])); if (attempt === 0) lines.push(`evidence ${sha.slice(0, 7)} written into docs/team/work-graph.json (in the merge commit)`); }
        const al = allocLedger(slot.dir, main0);
        if (al === "failed") return { kind: "refuse", msg: `could not assign numbers to the new rows of ${LEDGER_FILE}` };
        if (al === "written") { c = mk(git(slot.dir, ["write-tree"])); if (attempt === 0) lines.push(`${LEDGER_FILE}: new rows numbered at the land (in the merge commit)`); }
        let marks = "";
        try { marks = git(slot.dir, ["grep", "-n", "-E", MARKER_RE]); } catch { }
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
          const endLock = begin("fw land", "lock held");
          let released = false;
          const release = () => { if (!released) { released = true; endLock(0); dropLock(lf, lock!.token); } };
          const onSig = (code: number) => () => { release(); process.exit(code); };
          const onInt = onSig(130), onTerm = onSig(143);
          process.once("SIGINT", onInt); process.once("SIGTERM", onTerm);
          try {
            const head = git(mainDir, ["rev-parse", "HEAD"]);
            act = prelockAction(head, main0, true, attempt, maxRetry);
            if (act === "ff") {
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
    const endLock = begin("fw land", "lock held");
    const release = () => { if (!released) { released = true; endLock(0); dropLock(lf, lock.token); } };
    const facts = () => {
      let mh: string | null = null;
      try { mh = git(mainDir, ["rev-parse", "-q", "--verify", "MERGE_HEAD"]); } catch { }
      return askCore("console.landCommit", { locked: readLock(lf)?.token === lock.token, mergeHead: mh, head: git(mainDir, ["rev-parse", "HEAD"]), pre });
    };
    const abort = (m: string, kind: Kind = "unknown"): LandResult => {
      const d = facts();
      if (d?.ok) { tryGit(mainDir, ["merge", "--abort"]); return fail(`${m} (merge aborted, ${main} unchanged at ${pre.slice(0, 7)})`, kind); }
      return fail(`${m}\nthe merge state is not intact (${d?.reason ?? "fwcore unavailable"}): ${main} is at ${tryHead(mainDir)}, the land started at ${pre.slice(0, 7)}; nothing was reset`);
    };
    const onSignal = (sig: NodeJS.Signals) => () => {
      try { if (facts()?.ok) tryGit(mainDir, ["merge", "--abort"]); } catch { }
      release();
      process.exit(sig === "SIGINT" ? 130 : 143);
    };
    const onInt = onSignal("SIGINT"), onTerm = onSignal("SIGTERM");
    process.once("SIGINT", onInt); process.once("SIGTERM", onTerm);
    try {
      if (!span("fw land", "merge", () => tryGit(mainDir, ["merge", "--no-ff", "--no-commit", sha]), (ok) => (ok ? 0 : 1))) return abort(`${main} cannot merge ${branch} cleanly`, "conflict");
      if (!tryGit(mainDir, ["rev-parse", "-q", "--verify", "MERGE_HEAD"])) return fail(`${branch} has nothing to land (already in ${main})`, "done");
      let marks = "";
      try { marks = git(mainDir, ["grep", "-n", "-E", MARKER_RE]); } catch { }
      if (marks) return abort(`conflict markers after the merge:\n${marks.split("\n").slice(0, 10).join("\n")}`, "conflict");
      lines.push("no conflict markers");
      const ev = writeEvidence(mainDir, o.task, sha.slice(0, 7));
      if (ev === "failed") return abort("could not write the evidence into docs/team/work-graph.json");
      if (ev === "written") lines.push(`evidence ${sha.slice(0, 7)} written into docs/team/work-graph.json (in the merge commit)`);
      const al = allocLedger(mainDir, "HEAD");
      if (al === "failed") return abort(`could not assign numbers to the new rows of ${LEDGER_FILE}`);
      if (al === "written") lines.push(`${LEDGER_FILE}: new rows numbered at the land (in the merge commit)`);
      const bad = await runChecks(mainDir, checks);
      if (bad) return abort(bad, badKind);
      let e: string | null;
      try { e = await requestLand(); }
      catch (x) {
        if (x instanceof ConsoleUnreachable) { if (facts()?.ok) tryGit(mainDir, ["merge", "--abort"]); }
        throw x;
      }
      if (e) return abort(e);
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

  if (o.ci !== false && o.task) {
    try { lines.push(`ci (advisory) ci/${o.task}: ${(o.ci ?? ((ref: string) => ciLines(ref, o.cwd)))(`ci/${o.task}`).join("; ")}`); } catch { lines.push(`ci (advisory) ci/${o.task}: unavailable`); }
  }

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
        if (o.reap) { try { lines.push(...(await o.reap(mainDir))); } catch { } }
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
  const lag = (o.unpushedLag ?? unpushedLag)(mainDir, mergeSha, main);
  if (lag !== null && seedDue(lag)) {
    lines.push(`${main} is ${lag} Lake-key paths ahead of origin/${main}: scan origin/${main}..${main} for personal data, then git push origin ${main}`);
    lines.push(`PUSH-DUE ${lag}`);
  }
  return { ok: true, lines, warnings, kind: "done" };

}
