import { readFileSync } from "node:fs";
import { ghCharged, paths, readJson, realEnv, type WaitPhases } from "@fw/gh-budget";
import { ghCost } from "./run.ts";
import { CI_VIEW_FIELDS, fmtMs, parseTimings, quantile, recordCiRun, seenRuns, timingsFile, type GhRun, type Span } from "./timing.ts";

type Gh = (args: string[]) => Promise<string | null>;

/** `gh run view --json jobs` costs 3 requests (as wait.ts books it); ingest booked 2 and the ledger needed a correction per run (task ci-wait-lag). */
const chargedGh = (cwd: string): Gh => async (args) => {
  const r = await ghCharged(realEnv(cwd), args, { cost: ghCost(args) });
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

// ---- wait lag (task ci-wait-lag): the phases of a `fw ci wait` span and how the lag splits ---------------------------
// The split is Lean `Fw.Ci.Lag.parts`; lagParts replays golden ci-budget/lag.jsonl (apps/runner/test/timing-lag.test.ts).
// TS stand-ins: lagView, waitSpanExtra (formatting). Whether a lag is "too long" stays Lean's (timing-lean).

/** The poller's tick interval in s at `atS` (Lean `Fw.Ci.Budget.interval` via fwcore `ci.budget.status`); undefined when unread. */
export function pollIntervalS(cwd: string, atS?: number): number | undefined {
  try {
    const env = realEnv(cwd);
    const v = env.core({ op: "ci.budget.status", now: atS ?? env.now(), state: readJson(paths(env.dir).state) }).interval;
    return typeof v === "number" && Number.isSafeInteger(v) && v >= 0 ? v : undefined;
  } catch {
    return undefined;
  }
}

export function waitSpanExtra(p: WaitPhases | null, ingestStartMs: number, ingestEndMs: number,
  pollS: (atS: number | undefined) => number | undefined = (atS) => pollIntervalS(process.cwd(), atS)): Pick<Span, "runIds" | "phases"> {
  if (!p) return {};
  const { runIds, ...rest } = p;
  const phases: Record<string, number | string | boolean> = {};
  for (const [k, v] of Object.entries(rest)) if (v !== undefined) phases[k] = v as number | string | boolean;
  phases.ingestStartMs = ingestStartMs;
  phases.ingestEndMs = ingestEndMs;
  const poll = p.how === "done" ? pollS(p.tickMs === undefined ? undefined : Math.floor(p.tickMs / 1000)) : undefined;
  if (poll !== undefined) phases.pollS = poll;
  return { runIds, phases };
}

/** The lag components of one wait, ms. They add up: list + pickup + view + verdict + cleanup + ingest + exit = total. */
export type LagParts = {
  /** run done at GitHub (updatedAt) to the tick whose list showed it completed: GitHub's marking, list staleness and the poll phase */
  list: number;
  /** tick to this waiter's read of the file: the 2 s re-read, or a poller handoff */
  pickup: number;
  /** read to the end of the jobs fetch (per-run lock, state lock, fwcore reserve/observe, gh) */
  view: number;
  /** jobs fetched to fwcore's verdict */
  verdict: number;
  /** verdict to the end of wait.ts: unregister (fwcore step under the state lock) and releasing the poller lock */
  cleanup: number;
  /** fw.ts: the CI-span ingest after the verdict (one more gh view per run) */
  ingest: number;
  /** printing the verdict and ending the process, up to the span end */
  exit: number;
  /** span end minus updatedAt */
  total: number;
  /** evidence of GitHub's list lagging: a tick after updatedAt whose list still showed the run unfinished (ms past updatedAt); null: no such tick seen */
  stale: number | null;
  /** the two ticks around the finish: previous tick (list still unfinished) to the deciding tick; null when the previous one was not seen */
  gap: number | null;
};

const num = (x: unknown): number | undefined => (typeof x === "number" && Number.isFinite(x) ? x : undefined);

/** Components of a span from `phases` (null when it is not a `done` wait with every time recorded). */
export function lagParts(s: Pick<Span, "startMs" | "durMs" | "phases">): LagParts | null {
  const p = s.phases;
  if (!p || p.how !== "done") return null;
  const [upd, tick, read, viewEnd, done, ret, i0, i1] = ["updMs", "tickMs", "readMs", "viewEndMs", "doneMs", "retMs", "ingestStartMs", "ingestEndMs"].map((k) => num(p[k]));
  if (upd === undefined || tick === undefined || read === undefined || viewEnd === undefined || done === undefined || ret === undefined || i0 === undefined || i1 === undefined) return null;
  const end = s.startMs + s.durMs;
  const prev = num(p.prevTickMs);
  return {
    list: tick - upd, pickup: read - tick, view: viewEnd - read, verdict: done - viewEnd, cleanup: ret - done, ingest: i1 - i0, exit: end - ret - (i1 - i0), total: end - upd,
    stale: prev === undefined ? null : Math.max(0, prev - upd), gap: prev === undefined ? null : tick - prev,
  };
}

const COMPONENTS = ["list", "pickup", "view", "verdict", "cleanup", "ingest", "exit", "total"] as const;
const sorted = (xs: number[]) => [...xs].sort((a, b) => a - b);

/** The text of `fw timings --lag`: for the waits whose lag is their own (`how` = done) each component's p50 / p90 / max and its share of the summed
 *  lag, the poller's tick gap and the list-staleness evidence, the lag by host load, and how many waits were of the other kinds. */
export function lagView(text: string, sinceMs = 0): string {
  const spans: Span[] = [];
  for (const l of text.split("\n")) {
    try { const s = JSON.parse(l) as Span; if (s.tool === "fw" && s.step === "ci wait" && s.phases && s.startMs >= sinceMs) spans.push(s); } catch { /* torn or foreign line */ }
  }
  if (!spans.length) return "no `fw ci wait` spans with phases yet (they are written by waits that ran after task ci-wait-lag)";
  const kinds = new Map<string, number>();
  for (const s of spans) kinds.set(String(s.phases!.how), (kinds.get(String(s.phases!.how)) ?? 0) + 1);
  const own = spans.map((s) => ({ s, p: lagParts(s) })).filter((x): x is { s: Span; p: LagParts } => x.p !== null);
  const out = [`waits with phases: ${spans.length} (${[...kinds].map(([k, n]) => `${k} ${n}`).join(", ")}); with every time recorded and a lag of their own: ${own.length} (holder ${own.filter((x) => x.s.phases!.holder === true).length})`];
  if (!own.length) return out.join("\n");
  const total = own.reduce((a, x) => a + x.p.total, 0);
  const rows = [["component", "p50", "p90", "max", "share"]];
  for (const c of COMPONENTS) {
    const v = sorted(own.map((x) => x.p[c]));
    rows.push([c, fmtMs(quantile(v, 0.5)), fmtMs(quantile(v, 0.9)), fmtMs(v[v.length - 1]!), c === "total" ? "100%" : `${total > 0 ? Math.round((100 * own.reduce((a, x) => a + x.p[c], 0)) / total) : 0}%`]);
  }
  const w = rows[0]!.map((_, i) => Math.max(...rows.map((r) => r[i]!.length)));
  for (const r of rows) out.push(r.map((x, i) => (i === 0 ? x.padEnd(w[i]!) : x.padStart(w[i]!))).join("  ").trimEnd());
  const gaps = sorted(own.flatMap((x) => (x.p.gap === null ? [] : [x.p.gap])));
  if (gaps.length) out.push(`tick gap around the finish: n ${gaps.length}, p50 ${fmtMs(quantile(gaps, 0.5))}, p90 ${fmtMs(quantile(gaps, 0.9))}, max ${fmtMs(gaps[gaps.length - 1]!)}`);
  const st = sorted(own.flatMap((x) => (x.p.stale === null ? [] : [x.p.stale])));
  if (st.length) out.push(`list still unfinished after updatedAt (staleness evidence): ${st.filter((x) => x > 0).length} of ${st.length} waits, max ${fmtMs(st[st.length - 1]!)}`);
  for (const [lo, hi] of [[0, 20], [20, 60], [60, 120], [120, Infinity]] as const) {
    const v = sorted(own.filter((x) => (x.s.load ?? 0) >= lo && (x.s.load ?? 0) < hi).map((x) => x.p.total));
    if (v.length) out.push(`load ${lo}-${hi === Infinity ? "up" : hi}: n ${v.length}, total p50 ${fmtMs(quantile(v, 0.5))}, p90 ${fmtMs(quantile(v, 0.9))}`);
  }
  return out.join("\n");
}

/** `fw timings --lag [--since h]` on the timings file of the main checkout. */
export function lagCli(args: string[], cwd: string, now = Date.now()): string {
  const o = parseTimings(args);
  const f = timingsFile(cwd, { ...process.env, VITEST: "" });
  let text = "";
  try { if (f) text = readFileSync(f, "utf8"); } catch { /* none yet */ }
  return lagView(text, o.sinceH ? now - o.sinceH * 3_600_000 : 0);
}
