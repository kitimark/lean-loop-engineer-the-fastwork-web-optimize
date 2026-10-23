// fwcore access and the environment of the glue. No decision is made here: every budget decision is an fwcore op
// (`ci.budget.*`, lean/Fw/Ci/Wire.lean). If fwcore is missing or answers with an error the caller makes no GitHub call.
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { GH_BOUNDS } from "./bounds.gen.ts";

export type Json = Record<string, unknown>;
export type FwCall = (req: Json) => Json;

/** Candidate fwcore binaries: FW_CORE_BIN, this checkout, the main checkout (the parent of the git common dir). */
export function fwcoreBin(cwd: string): string {
  const rel = "lean/.lake/build/bin/fwcore";
  const git = (a: string[]) => spawnSync("git", a, { cwd, encoding: "utf8" }).stdout.trim();
  const common = git(["rev-parse", "--path-format=absolute", "--git-common-dir"]);
  const top = git(["rev-parse", "--show-toplevel"]);
  const cands = [process.env.FW_CORE_BIN, top && join(top, rel), common && join(dirname(common), rel)].filter((x): x is string => !!x);
  const bin = cands.find((p) => existsSync(p));
  if (!bin) throw new Error("fwcore not built: cd lean && lake build");
  return bin;
}

/** One request to fwcore (one process per decision, ticks are at least P_min = 10 s apart), one reply. An `error` reply throws. */
export function fwcoreCall(cwd: string): FwCall {
  const bin = fwcoreBin(cwd);
  return (req) => {
    const r = spawnSync(bin, [], { input: JSON.stringify({ ...req, id: 0 }) + "\n", env: { ...process.env, LEAN_ABORT_ON_PANIC: "1" }, maxBuffer: 1 << 28, timeout: Number(process.env.FW_CORE_CALL_MS) || GH_BOUNDS.fwcoreCallMs });
    if (r.status !== 0) throw new Error(`fwcore exited with ${r.status ?? r.signal}: ${String(r.stderr).slice(0, 200)}`);
    const { id: _id, ...rest } = JSON.parse(r.stdout.toString().trim().split("\n")[0]!) as Json;
    if (typeof rest.error === "string") throw new Error(`fwcore ${String(req.op)}: ${rest.error}`);
    return rest;
  };
}

/** What the glue needs from one `gh` run. */
export type GhOut = { status: number | null; stdout: string; stderr: string };
export type GhExec = (args: string[]) => GhOut;

/** Everything the glue touches outside itself, so tests can run it on a simulated clock with a stub `gh`. */
export type Env = {
  /** The shared directory (state, locks, runs-status): under the git common dir, so every worktree shares it. */
  dir: string;
  core: FwCall;
  /** The gh executable (looked up on PATH when not absolute). */
  gh: string;
  /** Run `gh` with `args` and give back its exit code and output. Default: spawn `gh` (`spawnGh`). A test may answer
   *  in-process instead (a fake server; the spawn of a node process costs ~0.1 s and is all a replay of thousands of
   *  calls would spend). Production never sets it. */
  exec?: GhExec;
  mark?: (e: "loadStart" | "loadEnd") => void;
  /** Epoch seconds. */
  now(): number;
  /** Resolve at epoch second `t`, or earlier (callers re-check). */
  sleepUntil(t: number): Promise<void>;
};

/** The shared directory: `FW_GH_BUDGET_DIR`, else `<git common dir>/fw-gh-budget` (inside .git, never tracked). */
export function stateDir(cwd: string): string {
  if (process.env.FW_GH_BUDGET_DIR) return process.env.FW_GH_BUDGET_DIR;
  const common = spawnSync("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd, encoding: "utf8" }).stdout.trim();
  if (!common) throw new Error("not inside a git checkout (no git common dir)");
  return join(common, "fw-gh-budget");
}

export function realEnv(cwd: string): Env {
  return {
    dir: stateDir(cwd),
    core: fwcoreCall(cwd),
    gh: process.env.FW_GH_BIN || "gh",
    now: () => Math.floor(Date.now() / 1000),
    sleepUntil: (t) => new Promise((res) => setTimeout(res, Math.max(10, t * 1000 - Date.now()))),
  };
}
