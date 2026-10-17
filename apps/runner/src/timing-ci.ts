// CI spans (timing-spans): fetch a finished run's jobs ONCE through the gh-budget charged call and write one span per job
// and per step. Deduped by run id (timing.ts seenRuns), so a second call for the same run costs no gh request.
import { ghCharged, realEnv } from "@fw/gh-budget";
import { CI_VIEW_FIELDS, parseTimings, recordCiRun, seenRuns, timingsFile, type GhRun } from "./timing.ts";

type Gh = (args: string[]) => Promise<string | null>;

const chargedGh = (cwd: string): Gh => async (args) => {
  const r = await ghCharged(realEnv(cwd), args, { cost: 2 });
  return r.ran && r.code === 0 ? r.stdout : null; // wait / stop / failure: skip silently, the next wait tries again
};

/** Write the spans of each completed run not seen yet. Never throws. Returns lines written. */
export async function ingestRuns(ids: number[], cwd: string, gh: Gh = chargedGh(cwd)): Promise<number> {
  let n = 0;
  try {
    const f = timingsFile(cwd);
    if (!f) return 0;
    const seen = seenRuns(f);
    for (const id of ids) {
      if (seen.has(id)) continue;
      const out = await gh(["run", "view", String(id), "--json", CI_VIEW_FIELDS]);
      if (!out) continue;
      n += recordCiRun(id, JSON.parse(out) as GhRun, cwd);
    }
  } catch { /* timing never fails the wait */ }
  return n;
}

/** Run ids named in the output lines of `fw ci wait` ("run <id> <workflow> <conclusion>"). */
export const runIdsOf = (lines: string[]): number[] => lines.flatMap((l) => { const m = /^run (\d+) /.exec(l); return m ? [Number(m[1])] : []; });

/** `fw timings --backfill [ids] [--per n]`: the given runs, plus up to n recent completed runs per workflow. One list call. */
export async function backfill(args: string[], cwd: string, gh: Gh = chargedGh(cwd)): Promise<string> {
  const o = parseTimings(args);
  const ids = new Set(o.runs);
  const list = await gh(["run", "list", "--limit", "60", "--json", "databaseId,workflowName,status"]);
  const per = new Map<string, number>();
  for (const r of list ? (JSON.parse(list) as { databaseId: number; workflowName: string; status: string }[]) : []) {
    if (r.status !== "completed" || (per.get(r.workflowName) ?? 0) >= o.per) continue;
    per.set(r.workflowName, (per.get(r.workflowName) ?? 0) + 1);
    ids.add(r.databaseId);
  }
  const n = await ingestRuns([...ids], cwd, gh);
  return `backfill: ${ids.size} runs considered, ${n} span lines written`;
}
