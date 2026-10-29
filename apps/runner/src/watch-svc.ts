// Collector for the staleness rule (task console-stale). Measurement only: per piece of running code, its base commit
// of `main` and, per input group, whether the first-parent range `base..main` touches it. No timestamp is compared:
// `fw land` builds the merge commit before its checks and moves main 23-89 s later (MEASURED), so commit times predate
// the move. Whether a service is stale, and the alerts, are decided by fwcore (`svc.stale`, `svc.unknown`; rule and
// proofs in lean/Fw/Obs/Stale.lean, lean/Fw/Obs/Health.lean). No process is killed or restarted here.
//
// What RUNS is judged, not what is on disk:
//  - service `console-api`: its own inputs against the commit it started from (api.json `commit`) AND the fwcore
//    inputs against the build commit of the fwcore child it holds (api.json `coreCommit`, written at every child
//    spawn). A rebuild on disk without a restart leaves it stale (Fw.Obs.rebuild_without_restart_api_stale).
//  - service `fwcore`: the binary on disk, against the commit it was built from.
// Design rule: when the code that runs cannot be identified, the service is reported `unknown` with the reason
// (svc.unknown). Nothing is silently skipped, and a failure to judge one service never drops the other.
import { createHash } from "node:crypto";
import { closeSync, existsSync, fstatSync, openSync, readFileSync, readSync } from "node:fs";
import { join } from "node:path";
import { CORE_BIN_REL, CORE_COMMIT_REL, SHA, binIn, chooseBase, mainLog, readRecord, type Base } from "../../console-api/src/core/build-base.ts";
import type { Paths, Runner, RunOut } from "./watch-collect.ts";

export interface SvcInput { path: string; changed: boolean }
export interface Svc { name: string; inputs: SvcInput[]; unknown?: string; sweepErrors?: number }

/** The files each piece of running code is built from (repo-relative prefixes). console-api reads its sources and
 *  packages at start; the fwcore binary is built from the Lean modules and is NOT rebuilt when console-api restarts or
 *  a land runs. console-api is also judged on the `fwcore` list, against its child's build commit. */
export const SVC_INPUTS: Record<string, string[]> = {
  "console-api": ["apps/console-api/src", "apps/console-api/package.json", "pnpm-lock.yaml", "packages/contracts/src", "packages/contracts/package.json"],
  fwcore: ["lean/Fw", "lean/Fw.lean", "lean/Main.lean", "lean/lakefile.toml", "lean/lean-toolchain"],
};

/** Where `scripts/fwcore-build.sh` records the commit the binary was built from. */
export const CORE_BIN = CORE_BIN_REL;
export const CORE_COMMIT = CORE_COMMIT_REL;

/** `git log --format=%H` output: non-empty means the range touches the path. Null on anything else. */
export function parseTouched(out: RunOut): boolean | null {
  if (typeof out !== "string") return null;
  const t = out.trim();
  return t === "" ? false : SHA.test(t.split("\n")[0]!) ? true : null;
}

export interface ApiRecord { commit: string | null; coreCommit: string | null; coreUnknown: string | null }

/** What the live console-api recorded in api.json; null when no console-api runs (absent, malformed or pid gone). */
export function readApi(p: Paths, alive: (pid: number) => boolean = isAlive): ApiRecord | null {
  try {
    const j = JSON.parse(readFileSync(join(p.consoleDir, "api.json"), "utf8")) as Record<string, unknown>;
    if (typeof j.pid !== "number" || !alive(j.pid)) return null;
    const sha = (v: unknown) => (typeof v === "string" && SHA.test(v) ? v : null);
    return { commit: sha(j.commit), coreCommit: sha(j.coreCommit), coreUnknown: typeof j.coreUnknown === "string" ? j.coreUnknown : null };
  } catch { return null; }
}

/** The commit console-api started from: null when no live console-api records one. */
export function readApiBase(p: Paths, alive?: (pid: number) => boolean): string | null {
  return readApi(p, alive)?.commit ?? null;
}

/** The fwcore throws the live console-api's drain caught since it started (its sweep-errors.json, written by
 *  apps/console-api/src/spool/drain.ts): 0 when it wrote none; the file of an earlier process (another pid) or of a pid that is not alive is ignored.
 *  fwcore raises `svc.sweepError` for any count above 0 (Lean `Fw.Obs.sweep_error_alerts`). */
export function readSweepErrors(p: Paths): number {
  try {
    const api = JSON.parse(readFileSync(join(p.consoleDir, "api.json"), "utf8")) as Record<string, unknown>;
    const j = JSON.parse(readFileSync(join(p.consoleDir, "sweep-errors.json"), "utf8")) as Record<string, unknown>;
    return j.pid === api.pid && typeof j.pid === "number" && isAlive(j.pid) && typeof j.count === "number" && Number.isSafeInteger(j.count) && j.count > 0 ? j.count : 0;
  } catch { return 0; }
}

function isAlive(pid: number): boolean {
  try { process.kill(pid, 0); return true; } catch (e) { return (e as NodeJS.ErrnoException).code === "EPERM"; }
}

/** The build commit of the binary on disk: its build record when the record's sha256 equals the binary's, else unknown
 *  with the hint to run scripts/fwcore-build.sh (Fw.Obs.chooseBase; no file time and no reflog is read). Null: no
 *  binary on disk. */
export function coreBase(p: Paths): Base | null {
  const bin = join(p.root, CORE_BIN);
  if (!existsSync(bin)) return null;
  // the steps of buildBase (console-api/src/core/build-base.ts), with the binary hashed in 1 MiB reads and only when it changed
  let h: string;
  try { h = binHash(bin); } catch (e) { return { unknown: `cannot read the fwcore binary: ${(e as Error).message.split("\n")[0]}` }; }
  const rec = readRecord(bin);
  const b = chooseBase(h, rec, rec !== null && "tree" in rec ? mainLog(p.root) : []);
  if ("sha" in b || bin === binIn(p.root)) return b;
  return { unknown: `${b.unknown}; the binary is not ${CORE_BIN_REL} of the checkout this code runs from` };
}

const hashMemo = new Map<string, { ino: number; size: number; mtimeMs: number; hash: string }>();
/** The sha256 of a file, read in 1 MiB pieces (a readFileSync of the 83 MB binary held 180 MB per tick); kept while the
 *  file's inode, size and mtime stay. */
function binHash(file: string): string {
  const fd = openSync(file, "r");
  try {
    const st = fstatSync(fd), hit = hashMemo.get(file);
    if (hit && hit.ino === st.ino && hit.size === st.size && hit.mtimeMs === st.mtimeMs) return hit.hash;
    const h = createHash("sha256"), buf = Buffer.allocUnsafe(1 << 20);
    for (let pos = 0; ;) {
      const n = readSync(fd, buf, 0, buf.length, pos);
      if (n <= 0) break;
      h.update(buf.subarray(0, n));
      pos += n;
    }
    const hash = h.digest("hex");
    hashMemo.set(file, { ino: st.ino, size: st.size, mtimeMs: st.mtimeMs, hash });
    return hash;
  } finally { closeSync(fd); }
}

/** Judge one group of paths against `base`; the paths that could not be judged make it `null`. */
async function judgeInputs(p: Paths, exec: Runner, paths: string[], base: string): Promise<SvcInput[] | null> {
  const inputs: SvcInput[] = [];
  for (const path of paths) {
    const t = parseTouched(await exec("git", ["log", "-1", "--first-parent", "--format=%H", `${base}..main`, "--", path], 5000, p.root));
    if (t === null) return null;
    inputs.push({ path, changed: t });
  }
  return inputs;
}

/** The services to judge. Never `null`: a service whose running code cannot be identified, or whose git calls failed,
 *  is returned `unknown` with the reason (the other services are still judged). `[]` when nothing runs. */
export async function collectSvcs(p: Paths, exec: Runner, alive?: (pid: number) => boolean): Promise<Svc[]> {
  const out: Svc[] = [];
  const api = readApi(p, alive);
  if (api !== null) {
    const inputs: SvcInput[] = [];
    const why: string[] = [];
    if (api.commit === null) why.push("api.json records no start commit");
    else {
      const own = await judgeInputs(p, exec, SVC_INPUTS["console-api"]!, api.commit);
      if (own === null) why.push("git failed on the start commit's range"); else inputs.push(...own);
    }
    if (api.coreCommit === null) why.push(api.coreUnknown ?? "api.json records no core build commit");
    else {
      const core = await judgeInputs(p, exec, SVC_INPUTS.fwcore!, api.coreCommit);
      if (core === null) why.push("git failed on the core child's range"); else inputs.push(...core);
    }
    const sweepErrors = readSweepErrors(p);
    out.push({ name: "console-api", inputs, ...(why.length ? { unknown: why.join("; ") } : {}), ...(sweepErrors > 0 ? { sweepErrors } : {}) });
  }
  const disk = coreBase(p);
  if (disk !== null) {
    if ("unknown" in disk) out.push({ name: "fwcore", inputs: [], unknown: disk.unknown });
    else {
      const inputs = await judgeInputs(p, exec, SVC_INPUTS.fwcore!, disk.sha);
      out.push(inputs === null ? { name: "fwcore", inputs: [], unknown: "git failed on the binary's range" } : { name: "fwcore", inputs });
    }
  }
  return out;
}
