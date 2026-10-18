// CI shape (ci-shape-obs): one row per finished run x job in .fw-console/ci-shape.jsonl, and the `ci.shape` alerts of
// `fw watch`. Glue only: the collector reads run ids from the gh poller's cached status (no list call of its own) and
// fetches each finished, non-cancelled run's jobs ONCE through the gh-budget charged call; every metric, threshold and
// alert is fwcore's `obs.ciShape` (lean/Fw/Obs/CiShape.lean). Design: research/notes/2026/10-18-ci-shape-obs.md.
import { appendFileSync, existsSync, mkdirSync, readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { ghCharged, realEnv, stateDir } from "@fw/gh-budget";
import { whereIs } from "./timing.ts";

type Gh = (args: string[]) => Promise<string | null>;
export type CoreCall = (req: Record<string, unknown>) => Promise<Record<string, unknown>>;

/** One ledger row (the `obs.ciShape` request row; times in epoch seconds). */
export interface CiRow {
  run: number; workflow: string; branch: string; sha: string; event: string; attempt: number;
  createdS: number; startedS: number; job: string; conclusion: string; startS: number; endS: number;
}
/** The fields of one charged `gh run view`. */
export const SHAPE_VIEW_FIELDS = "createdAt,startedAt,attempt,event,headBranch,headSha,workflowName,conclusion,jobs";
/** Charged run views per collection pass at most (the rest wait for the next pass). */
export const MAX_VIEWS = 4;

interface GhJob { name: string; conclusion: string | null; startedAt: string | null; completedAt: string | null }
export interface GhView {
  createdAt: string; startedAt?: string; attempt?: number; event?: string; headBranch?: string; headSha?: string;
  workflowName: string; conclusion?: string | null; jobs: GhJob[];
}

const sec = (iso: string | null | undefined): number | null => {
  if (!iso || iso.startsWith("0001-")) return null; // gh prints the zero time for a job that never started
  const t = Date.parse(iso);
  return Number.isFinite(t) ? Math.floor(t / 1000) : null;
};

/** The rows of one run view: one per job that has a start and an end (a never-started job has no time to record). */
export function rowsOf(run: number, v: GhView): CiRow[] {
  const createdS = sec(v.createdAt) ?? 0;
  const startedS = sec(v.startedAt) ?? createdS;
  const out: CiRow[] = [];
  for (const j of v.jobs ?? []) {
    const s = sec(j.startedAt), e = sec(j.completedAt);
    if (s === null || e === null) continue;
    out.push({ run, workflow: v.workflowName, branch: v.headBranch ?? "", sha: (v.headSha ?? "").slice(0, 7),
      event: v.event ?? "", attempt: v.attempt ?? 1, createdS, startedS, job: j.name,
      conclusion: j.conclusion ?? "success", startS: s, endS: Math.max(e, s) });
  }
  return out;
}

/** .fw-console/ci-shape.jsonl of the main checkout (FW_CI_SHAPE_FILE overrides; none under vitest). */
export function shapeFile(cwd: string = process.cwd(), env: NodeJS.ProcessEnv = process.env): string | null {
  if (env.FW_CI_SHAPE_FILE) return env.FW_CI_SHAPE_FILE;
  if (env.VITEST) return null;
  const w = whereIs(cwd);
  return w ? join(w.main, ".fw-console", "ci-shape.jsonl") : null;
}

/** All parseable rows of the ledger ([] when it does not exist). */
export function readRows(file: string): CiRow[] {
  if (!existsSync(file)) return [];
  return readFileSync(file, "utf8").split("\n").flatMap((l) => { try { return l ? [JSON.parse(l) as CiRow] : []; } catch { return []; } });
}

/** Finished runs worth a view: completed and neither cancelled nor skipped (a cancelled run is never fetched). */
export interface Cand { id: number; status: string; conclusion: string | null }
export const candidates = (rs: Cand[], seen: Set<number>): number[] =>
  [...new Set(rs.filter((r) => r.status === "completed" && r.conclusion !== "cancelled" && r.conclusion !== "skipped" && !seen.has(r.id)).map((r) => r.id))];

/** The finished runs named in `fw ci wait` output lines ("run <id> <workflow> <conclusion>": the last word). */
export const finishedOf = (lines: string[]): Cand[] => lines.flatMap((l) => {
  const m = /^run (\d+) .*?(\S+)\s*$/.exec(l);
  return m ? [{ id: Number(m[1]), status: "completed", conclusion: m[2]! }] : [];
});

/** The poller's cached run rows (runs-status.json in the gh-budget state dir); [] when there is none. */
export function polledRuns(cwd: string): Cand[] {
  try {
    const f = join(stateDir(cwd), "runs-status.json");
    const s = JSON.parse(readFileSync(f, "utf8")) as { rows?: { databaseId: number; status: string; conclusion: string | null }[] };
    return (s.rows ?? []).map((r) => ({ id: r.databaseId, status: r.status, conclusion: r.conclusion }));
  } catch { return []; }
}

const chargedGh = (cwd: string): Gh => async (args) => {
  const r = await ghCharged(realEnv(cwd), args, { cost: 2 });
  return r.ran && r.code === 0 ? r.stdout : null; // wait / stop / failure: skip, the next pass tries again
};

/** Append the rows of up to `max` new finished runs. Never throws. Returns the rows written. */
export async function collect(runs: Cand[], cwd: string, gh: Gh = chargedGh(cwd), file: string | null = shapeFile(cwd), max = MAX_VIEWS): Promise<number> {
  let n = 0;
  try {
    if (!file) return 0;
    const seen = new Set(readRows(file).map((r) => r.run));
    mkdirSync(dirname(file), { recursive: true });
    for (const id of candidates(runs, seen).slice(0, max)) {
      const out = await gh(["run", "view", String(id), "--json", SHAPE_VIEW_FIELDS]);
      if (!out) continue;
      const v = JSON.parse(out) as GhView;
      if (v.conclusion === "cancelled") continue;
      const rows = rowsOf(id, v);
      if (rows.length) appendFileSync(file, rows.map((r) => JSON.stringify(r)).join("\n") + "\n");
      n += rows.length;
    }
  } catch { /* the shape ledger never fails a caller */ }
  return n;
}

/** `timeout-minutes` per (workflow name, job id) from .github/workflows/*.yml, line-based: a job id is a 2-space key
 *  under `jobs:`, its timeout the first `timeout-minutes:` at 4 spaces below it. Seconds. */
export function timeoutsOf(root: string): { workflow: string; job: string; s: number }[] {
  const dir = join(root, ".github", "workflows");
  const out: { workflow: string; job: string; s: number }[] = [];
  let files: string[] = [];
  try { files = readdirSync(dir).filter((f) => /\.ya?ml$/.test(f)); } catch { return out; }
  for (const f of files) {
    const lines = readFileSync(join(dir, f), "utf8").split("\n");
    const name = lines.map((l) => /^name:\s*(.+?)\s*$/.exec(l)).find(Boolean)?.[1]?.replace(/^["']|["']$/g, "");
    if (!name) continue;
    let inJobs = false, job: string | null = null;
    for (const l of lines) {
      if (/^jobs:\s*$/.test(l)) { inJobs = true; continue; }
      if (/^\S/.test(l)) { inJobs = false; job = null; continue; }
      const k = inJobs ? /^ {2}([A-Za-z0-9_-]+):\s*$/.exec(l) : null;
      if (k) { job = k[1]!; continue; }
      const t = job ? /^ {4}timeout-minutes:\s*(\d+)\s*$/.exec(l) : null;
      if (t && job) { out.push({ workflow: name, job, s: Number(t[1]) * 60 }); job = null; }
    }
  }
  return out;
}

export interface ShapeAlert { workflow: string; cls: string; run: number; branch: string; sha: string; createdS: number; subject: string; value: number; bound: number }
export interface ShapeRun { workflow: string; run: number; branch: string; sha: string; createdS: number; jobS: number;
  groups: { group: string; n: number; maxS: number; sumS: number }[]; fires: string[] }
export interface ShapeReply { runs: ShapeRun[]; raised: ShapeAlert[]; open: ShapeAlert[] }

/** The rows of the last `keepRuns` runs (by creation time) of the ledger: the decision only needs a window. */
export function lastRuns(rows: CiRow[], keepRuns = 200): CiRow[] {
  const created = new Map<number, number>();
  for (const r of rows) if (!created.has(r.run)) created.set(r.run, r.createdS);
  const keep = new Set([...created].sort((a, b) => a[1] - b[1] || a[0] - b[0]).slice(-keepRuns).map(([id]) => id));
  return rows.filter((r) => keep.has(r.run));
}

/** fwcore `obs.ciShape` over the ledger; null when the ledger is empty or the op is unavailable. */
export async function shapeFor(file: string | null, root: string, core: CoreCall, lastN = 8): Promise<ShapeReply | null> {
  try {
    if (!file) return null;
    const rows = lastRuns(readRows(file));
    if (rows.length === 0) return null;
    const r = await core({ op: "obs.ciShape", rows, params: { timeouts: timeoutsOf(root) }, lastN });
    return Array.isArray(r.open) && Array.isArray(r.runs) ? (r as unknown as ShapeReply) : null;
  } catch { return null; }
}

/** The `ci.shape` alerts of `fw watch`: one per open (workflow, class) of fwcore, subject `<workflow>/<class>`. */
export const shapeAlerts = (r: ShapeReply | null): { code: string; subject: string; detail: string }[] =>
  (r?.open ?? []).map((a) => ({ code: "ci.shape", subject: `${a.workflow}/${a.cls}`,
    detail: `${a.subject} ${a.value} vs ${a.bound} (run ${a.run} ${a.sha} ${a.branch})` }));

/** The console view: per workflow its recent runs, and the open alerts. */
export const shapeView = (r: ShapeReply | null) => (r ? { runs: r.runs, open: r.open } : null);
