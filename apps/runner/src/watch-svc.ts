// Collector for the staleness rule (task console-stale). Measurement only: per service, its base commit of `main`
// (console-api: HEAD at its start, from .fw-console/api.json; fwcore: the commit the binary was built from) and, per
// input group, whether the first-parent range `base..main` touches it. No timestamp is compared: `fw land` builds the
// merge commit before its checks and moves main 23-89 s later (MEASURED), so commit times predate the move. Whether a
// service is stale, and the alert, are decided by fwcore (`svc.stale`, Fw.Obs.Health.sStale; rule and proofs in
// lean/Fw/Obs/Stale.lean). No process is killed or restarted here.
import { existsSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import type { Paths, Runner, RunOut } from "./watch-collect.ts";

export interface SvcInput { path: string; changed: boolean }
export interface Svc { name: string; inputs: SvcInput[] }

/** The files each service is built from (repo-relative prefixes). console-api reads its sources at start; the fwcore
 *  binary is built from the Lean modules and is NOT rebuilt when console-api restarts or a land runs. */
export const SVC_INPUTS: Record<string, string[]> = {
  "console-api": ["apps/console-api/src", "packages/contracts/src", "packages/contracts/package.json"],
  fwcore: ["lean/Fw", "lean/Fw.lean", "lean/Main.lean", "lean/lakefile.toml", "lean/lean-toolchain"],
};

/** Where `scripts/fwcore-build.sh` records the commit the binary was built from. */
export const CORE_BIN = "lean/.lake/build/bin/fwcore";
export const CORE_COMMIT = `${CORE_BIN}.commit`;

const SHA = /^[0-9a-f]{40}$/;

/** `git log --format=%H` output: non-empty means the range touches the path. Null on anything else. */
export function parseTouched(out: RunOut): boolean | null {
  if (typeof out !== "string") return null;
  const t = out.trim();
  return t === "" ? false : SHA.test(t.split("\n")[0]!) ? true : null;
}

/** The commit console-api started from, from api.json: null when absent, malformed, or the process is gone. */
export function readApiBase(p: Paths, alive: (pid: number) => boolean = isAlive): string | null {
  try {
    const j = JSON.parse(readFileSync(join(p.consoleDir, "api.json"), "utf8")) as { pid?: unknown; commit?: unknown };
    if (typeof j.pid !== "number" || typeof j.commit !== "string" || !SHA.test(j.commit) || !alive(j.pid)) return null;
    return j.commit;
  } catch { return null; }
}

function isAlive(pid: number): boolean {
  try { process.kill(pid, 0); return true; } catch (e) { return (e as NodeJS.ErrnoException).code === "EPERM"; }
}

/** The commit the fwcore binary was built from: the recorded commit when `fwcore-build.sh` wrote one; otherwise, as a
 *  stated PREMISE, the newest first-parent commit of main whose commit time is at or before the binary's mtime (a
 *  land moves main 23-89 s after that time, so a change in that window can be missed). Null: no binary (fwcore is
 *  not judged); "git": a git failure. */
export async function coreBase(p: Paths, exec: Runner): Promise<string | null | "git"> {
  const bin = join(p.root, CORE_BIN);
  if (!existsSync(bin)) return null;
  try {
    const rec = readFileSync(join(p.root, CORE_COMMIT), "utf8").trim();
    if (SHA.test(rec)) return rec;
  } catch { /* no record: fall back to the mtime */ }
  const sec = Math.floor(statSync(bin).mtimeMs / 1000);
  const out = await exec("git", ["rev-list", "-1", "--first-parent", `--before=${sec}`, "main"], 5000, p.root);
  if (typeof out !== "string") return "git";
  const sha = out.trim();
  return SHA.test(sha) ? sha : "git";
}

async function judge(p: Paths, exec: Runner, name: string, base: string): Promise<Svc | null> {
  const inputs: SvcInput[] = [];
  for (const path of SVC_INPUTS[name]!) {
    const t = parseTouched(await exec("git", ["log", "-1", "--first-parent", "--format=%H", `${base}..main`, "--", path], 5000, p.root));
    if (t === null) return null;
    inputs.push({ path, changed: t });
  }
  return { name, inputs };
}

/** The services to judge, each against its own base commit: console-api (HEAD at its start) when it is running, and
 *  the fwcore binary (its build commit) when it is built, independent of console-api restarts. `null` when a git call
 *  failed (the caller carries the previous value and marks it stale); `[]` when neither can be judged. */
export async function collectSvcs(p: Paths, exec: Runner, alive?: (pid: number) => boolean): Promise<Svc[] | null> {
  const out: Svc[] = [];
  const api = readApiBase(p, alive);
  if (api !== null) {
    const s = await judge(p, exec, "console-api", api);
    if (s === null) return null;
    out.push(s);
  }
  const core = await coreBase(p, exec);
  if (core === "git") return null;
  if (core !== null) {
    const s = await judge(p, exec, "fwcore", core);
    if (s === null) return null;
    out.push(s);
  }
  return out;
}
