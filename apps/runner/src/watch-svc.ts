// Collector for the staleness rule (task console-stale). Measurement only: the start time of the running console-api
// (from .fw-console/api.json, written by console-api itself) and, per input group, the commit time of the last commit
// on `main` that touched it. Whether a service is stale, and the alert, are decided by fwcore (`svc.stale`,
// Fw.Obs.Health.sStale; rule and proofs in lean/Fw/Obs/Stale.lean). No process is killed or restarted here.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { Paths, Runner, RunOut } from "./watch-collect.ts";

export interface SvcInput { path: string; changedAt: number }
export interface Svc { name: string; startedAt: number; inputs: SvcInput[] }

/** The files each service is built from (repo-relative prefixes). The fwcore binary is spawned by console-api, so it
 *  starts when console-api does; its inputs are the Lean modules. */
export const SVC_INPUTS: Record<string, string[]> = {
  "console-api": ["apps/console-api/src", "packages/contracts/src", "packages/contracts/package.json"],
  fwcore: ["lean/Fw", "lean/Fw.lean", "lean/Main.lean", "lean/lakefile.toml", "lean/lean-toolchain"],
};

/** `git log -1 --format=%ct` output (seconds) to ms; empty (no commit touched the paths) is 0. Null on anything else. */
export function parseCommitTime(out: RunOut): number | null {
  if (typeof out !== "string") return null;
  const t = out.trim();
  if (t === "") return 0;
  return /^\d+$/.test(t) ? Number(t) * 1000 : null;
}

/** What console-api wrote to api.json when it started: `{pid, startedAt}`; null when absent or the process is gone. */
export function readApiStart(p: Paths, alive: (pid: number) => boolean = isAlive): number | null {
  try {
    const j = JSON.parse(readFileSync(join(p.consoleDir, "api.json"), "utf8")) as { pid?: unknown; startedAt?: unknown };
    if (typeof j.pid !== "number" || typeof j.startedAt !== "number" || !alive(j.pid)) return null;
    return j.startedAt;
  } catch { return null; }
}

function isAlive(pid: number): boolean {
  try { process.kill(pid, 0); return true; } catch (e) { return (e as NodeJS.ErrnoException).code === "EPERM"; }
}

/** The services to judge: console-api and the fwcore it spawned, both started at console-api's start time. `null`
 *  when a git call failed (the caller carries the previous value and marks it stale); `[]` when console-api is not
 *  running. */
export async function collectSvcs(p: Paths, exec: Runner, alive?: (pid: number) => boolean): Promise<Svc[] | null> {
  const startedAt = readApiStart(p, alive);
  if (startedAt === null) return [];
  const out: Svc[] = [];
  for (const [name, paths] of Object.entries(SVC_INPUTS)) {
    const inputs: SvcInput[] = [];
    for (const path of paths) {
      const t = parseCommitTime(await exec("git", ["log", "-1", "--first-parent", "--format=%ct", "main", "--", path], 5000, p.root));
      if (t === null) return null;
      inputs.push({ path, changedAt: t });
    }
    out.push({ name, startedAt, inputs });
  }
  return out;
}
