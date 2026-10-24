// Span writer (timing-spans): one JSON line per timed automation step in `.fw-console/timings.jsonl` of the MAIN checkout.
// I/O glue only: it records, it decides nothing (the "slow" verdict is Lean, task timing-lean). Rules:
//  - append-only, one O_APPEND write per line (atomic for lines < PIPE_BUF, so concurrent tools never interleave);
//  - never fails or slows the wrapped step: every error is swallowed, no spawn (HEAD is read from .git, not `git rev-parse`);
//  - no personal data: the line holds a tool name, a step label, numbers and a short sha. Never a path or user name.
import { createHash } from "node:crypto";
import { appendFileSync, existsSync, mkdirSync, readFileSync, statSync } from "node:fs";
import { loadavg } from "node:os";
import { dirname, join, resolve } from "node:path";

export type Span = { tool: string; step: string; startMs: number; durMs: number; exit: number | null; commit: string; load: number; host: "local" | "ci"; runId?: number; queue?: { kind: string; waitMs: number; waits: { why: string; ms: number }[] };
  /** the run kind (Lean `Fw.Obs.Timing.Sample.kind`): for a CI run dispatched by `fw run`, the digest of its workflow inputs; "" and absent for every other span */
  kind?: string;
  skipped?: true;
  /** `fw ci wait` spans only (task ci-wait-lag): the runs the verdict covers (key `runIds`, never `runId`: `seenRuns` dedupes CI spans on `"runId":`) and the phase times of the wait (`WaitPhases`, epoch ms). */
  runIds?: number[]; phases?: Record<string, number | string | boolean>;
  slot?: { width: number; jobs: number };
  /** `fw polish commit` spans only: the checkmap commands of the commit (count and kinds). */
  checks?: { n: number; kinds: string[] };
  /** `fw polish commit` spans that ran lake build and `fw land dry lake` spans: the modules lake built. */
  lake?: { built: number } };

export function slotWork(slot: unknown): { work?: Record<string, string> } {
  const w = (slot as { width?: unknown } | null | undefined)?.width;
  return typeof w === "number" && Number.isInteger(w) && w >= 0 ? { work: { width: String(w) } } : {};
}

/** Lean `Fw.Obs.Timing.heavyChecks`, checked against the work golden. */
export const HEAVY_CHECKS = ["lakeBuild", "leanElab", "presetCheck"] as const;

/** Lean `Fw.Obs.Timing.checksWork`: the heavy kinds of a `checks` member joined by `+`, or `light`; none without a
 *  `kinds` array. */
export function checksWork(checks: unknown): { work?: Record<string, string> } {
  const k = (checks as { kinds?: unknown } | null | undefined)?.kinds;
  if (!Array.isArray(k)) return {};
  const heavy = HEAVY_CHECKS.filter((h) => k.includes(h));
  return { work: { checks: heavy.length ? heavy.join("+") : "light" } };
}

/** Lean `Fw.Obs.Timing.modsLow`: 0, else the largest power of 4 at most `n`. */
export function modsLow(n: number): number {
  if (n === 0) return 0;
  let lo = 1;
  while (lo * 4 <= n) lo *= 4;
  return lo;
}

/** Lean `Fw.Obs.Timing.modsWork`: the class of a `lake` member's built count; none without an integer count. */
export function lakeWork(lake: unknown): { work?: Record<string, string> } {
  const b = (lake as { built?: unknown } | null | undefined)?.built;
  return typeof b === "number" && Number.isInteger(b) && b >= 0 ? { work: { mods: String(modsLow(b)) } } : {};
}

export type RawPhases = { how: string; updMs: number; tickMs?: number; prevTickMs?: number; pollS?: number; retryUntilS?: number; prevPollS?: number };

export function rawOf(o: unknown): { startMs?: number; commit?: string; phases?: RawPhases } {
  type In = { how?: unknown; updMs?: unknown; tickMs?: unknown; prevTickMs?: unknown; pollS?: unknown; retryUntilS?: unknown; prevPollS?: unknown };
  const s = o as { startMs?: unknown; commit?: unknown; phases?: In | null } | null | undefined;
  const nat = (v: unknown): v is number => typeof v === "number" && Number.isSafeInteger(v) && v >= 0;
  const ph = s?.phases;
  const opt = (k: "tickMs" | "prevTickMs" | "pollS" | "retryUntilS" | "prevPollS") => (nat(ph?.[k]) ? { [k]: ph[k] } : {});
  return {
    ...(nat(s?.startMs) ? { startMs: s.startMs } : {}),
    ...(typeof s?.commit === "string" && /^[0-9a-f]{0,40}$/.test(s.commit) && s.commit !== "" ? { commit: s.commit } : {}),
    ...(typeof ph?.how === "string" && nat(ph.updMs)
      ? { phases: { how: ph.how, updMs: ph.updMs, ...opt("tickMs"), ...opt("prevTickMs"), ...opt("pollS"), ...opt("retryUntilS"), ...opt("prevPollS") } }
      : {}),
  };
}

export function builtLine(l: string): boolean {
  const parts = l.split("] Built ");
  if (parts.length !== 2) return false;
  const progress = parts[0]!.split("[").at(-1)!.split("/");
  const name = parts[1]!.split(" ")[0]!;
  return progress.length === 2 && progress.every((x) => /^[0-9]+$/.test(x)) && name !== "" && !name.includes(":");
}

/** Lean `Fw.Obs.Timing.builtModules`: the modules a lake run built, from its output. */
export const builtModules = (out: string): number => out.split("\n").filter(builtLine).length;

/** Lean `Fw.Obs.Timing.spanWork`: the checks class, the rebuilt-module class and the slot width of a span line. */
export function spanWork(o: { slot?: unknown; checks?: unknown; lake?: unknown }): { work?: Record<string, string> } {
  const work = { ...checksWork(o.checks).work, ...lakeWork(o.lake).work, ...slotWork(o.slot).work };
  return Object.keys(work).length ? { work } : {};
}

type Where = { main: string; sha: string };
const cache = new Map<string, Where>();

const rd = (f: string): string | null => { try { return readFileSync(f, "utf8").trim(); } catch { return null; } };

/** Main checkout dir and short HEAD sha of the repo holding `cwd`, by reading .git files only. */
export function whereIs(cwd: string): Where | null {
  const hit = cache.get(cwd);
  if (hit) return hit;
  let dir = resolve(cwd);
  for (;;) {
    const g = join(dir, ".git");
    if (existsSync(g)) {
      let gitdir = g, common = g;
      if (statSync(g).isFile()) {
        const m = /^gitdir:\s*(.+)$/m.exec(rd(g) ?? "");
        if (!m) return null;
        gitdir = resolve(dir, m[1]!);
        const c = rd(join(gitdir, "commondir"));
        common = c ? resolve(gitdir, c) : gitdir;
      }
      const head = rd(join(gitdir, "HEAD")) ?? "";
      const ref = /^ref:\s*(\S+)/.exec(head)?.[1];
      let sha = ref ? (rd(join(gitdir, ref)) ?? rd(join(common, ref)) ?? "") : head;
      if (ref && !/^[0-9a-f]{40}/.test(sha)) sha = new RegExp(`^([0-9a-f]{40}) ${ref}$`, "m").exec(rd(join(common, "packed-refs")) ?? "")?.[1] ?? "";
      const w = { main: dirname(common), sha: sha.slice(0, 7) };
      cache.set(cwd, w);
      return w;
    }
    const up = dirname(dir);
    if (up === dir) return null;
    dir = up;
  }
}

/** The timings file for `cwd`: FW_TIMINGS_FILE, else the main checkout's .fw-console. Null under vitest unless forced. */
export function timingsFile(cwd: string = process.cwd(), env: NodeJS.ProcessEnv = process.env): string | null {
  if (env.FW_TIMINGS_FILE) return env.FW_TIMINGS_FILE;
  if (env.VITEST) return null;
  const w = whereIs(cwd);
  return w ? join(w.main, ".fw-console", "timings.jsonl") : null;
}

/** Append one span line. Never throws. */
export function record(s: Partial<Span> & Pick<Span, "tool" | "step" | "startMs" | "durMs" | "exit">, cwd: string = process.cwd()): void {
  try {
    const f = timingsFile(cwd);
    if (!f) return;
    const full: Span = { commit: whereIs(cwd)?.sha ?? "", load: Math.round(loadavg()[0]! * 100) / 100, host: process.env.CI ? "ci" : "local", ...s };
    mkdirSync(dirname(f), { recursive: true });
    appendFileSync(f, JSON.stringify(full) + "\n");
  } catch { /* a timing line never fails a step */ }
}

const notes = new Map<string, Partial<Span>>();

/** Add fields to the line of the `begin` span of `tool`/`step` this process ends: the `checks` of `fw polish commit`. */
export function noteSpan(tool: string, step: string, extra: Partial<Span>): void {
  notes.set(`${tool}/${step}`, { ...notes.get(`${tool}/${step}`), ...extra });
}

/** Start a span now; call the returned function once with the exit code when the step ends (later calls are ignored).
 *  `extra`: fields to add to the line (the phases of a `fw ci wait`), after the fields noted for this span. */
export function begin(tool: string, step: string, cwd: string = process.cwd()): (exit?: number | null, extra?: Partial<Span>) => void {
  const startMs = Date.now(), t0 = performance.now();
  let done = false;
  return (exit = 0, extra = {}) => {
    if (done) return;
    done = true;
    record({ ...notes.get(`${tool}/${step}`), ...extra, tool, step: extra.step ?? step, startMs, durMs: Math.round(performance.now() - t0), exit }, cwd);
  };
}

/** Run `fn` inside a span. exitOf maps the result to an exit code (default 0; a throw is 1 and is rethrown). */
export function span<T>(tool: string, step: string, fn: () => T, exitOf?: (r: Awaited<T>) => number | null): T {
  const end = begin(tool, step);
  let r: T;
  try { r = fn(); } catch (e) { end(1); throw e; }
  if (r && typeof (r as { then?: unknown }).then === "function") {
    return (r as unknown as Promise<Awaited<T>>).then((v) => { end(exitOf ? exitOf(v) : 0); return v; }, (e) => { end(1); throw e; }) as T;
  }
  end(exitOf ? exitOf(r as Awaited<T>) : 0);
  return r;
}

// ---- CI: one span per job and per step of a finished run (host "ci") ----------------------------------------------

type GhStep = { name: string; startedAt?: string; completedAt?: string; conclusion?: string };
type GhJob = { name: string; startedAt?: string; completedAt?: string; conclusion?: string; steps?: GhStep[] };
export type GhRun = { workflowName: string; headSha?: string; jobs?: GhJob[] };
export const CI_VIEW_FIELDS = "workflowName,headSha,jobs";

const exitOfConclusion = (c?: string): number | null => (c === "success" || c === "skipped" ? 0 : c ? 1 : null);

/** Spans of one finished run, pure: skips jobs/steps without both timestamps. */
export function ciSpans(runId: number, run: GhRun, load = 0, kind = ""): Span[] {
  const out: Span[] = [];
  const mk = (step: string, a?: string, b?: string, c?: string): void => {
    const s = Date.parse(a ?? ""), e = Date.parse(b ?? "");
    if (!Number.isFinite(s) || !Number.isFinite(e) || s <= 0) return; // gh prints 0001-01-01 for steps that never ran
    out.push({ tool: run.workflowName, step, startMs: s, durMs: Math.max(0, e - s), exit: exitOfConclusion(c), commit: (run.headSha ?? "").slice(0, 7), load, host: "ci", runId, ...(kind ? { kind } : {}), ...(c === "skipped" ? { skipped: true as const } : {}) });
  };
  for (const j of run.jobs ?? []) {
    mk(j.name, j.startedAt, j.completedAt, j.conclusion);
    for (const s of j.steps ?? []) mk(`${j.name}/${s.name}`, s.startedAt, s.completedAt, s.conclusion);
  }
  return out;
}

// ---- run kinds: which inputs a dispatched CI run had ----------------------------------------------------------------
// `fw run` knows the inputs it dispatched (PlanJob.inputs) once the run id is decided; the spans of that run are written
// later (`fw ci wait`, `fw timings --backfill`), so the kind is passed through a file of {runId, kind} lines. A run not
// dispatched by `fw run` (a push, a hand dispatch) has no line: its spans carry no kind (kind "").

/** The kinds file beside a timings file. */
export const kindsFile = (timings: string): string => join(dirname(timings), "run-kinds.jsonl");

/** The kind of a dispatch: a short digest of its inputs, in key order (equal inputs, equal kind; the order of keys is not part of it). */
export function inputsKind(inputs: Record<string, string | number | boolean>): string {
  const rows = Object.entries(inputs).map(([k, v]) => [k, String(v)] as const).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
  return createHash("sha256").update(JSON.stringify(rows)).digest("hex").slice(0, 12);
}

/** Remember the kind of a dispatched run. Never throws; returns the kind written ("" when nothing could be written). */
export function recordRunKind(runId: number, inputs: Record<string, string | number | boolean>, cwd: string = process.cwd()): string {
  try {
    const t = timingsFile(cwd);
    if (!t) return "";
    const kind = inputsKind(inputs);
    mkdirSync(dirname(t), { recursive: true });
    appendFileSync(kindsFile(t), JSON.stringify({ runId, kind }) + "\n");
    return kind;
  } catch { return ""; }
}

/** run id -> kind from a kinds file (the newest line of a run wins; torn lines are skipped). */
export function kindsOf(file: string): Map<number, string> {
  const m = new Map<number, string>();
  for (const l of (rd(file) ?? "").split("\n")) {
    try { const o = JSON.parse(l); if (Number.isInteger(o.runId) && typeof o.kind === "string" && o.kind !== "") m.set(o.runId, o.kind); } catch { /* torn line */ }
  }
  return m;
}

/** Run ids already written to the timings file. */
export function seenRuns(file: string): Set<number> {
  const seen = new Set<number>();
  for (const l of (rd(file) ?? "").split("\n")) { const m = /"runId":(\d+)/.exec(l); if (m) seen.add(Number(m[1])); }
  return seen;
}

/** Write the job/step spans of a run once (deduped by run id). Returns the number of lines written. */
export function recordCiRun(runId: number, run: GhRun, cwd: string = process.cwd()): number {
  try {
    const f = timingsFile(cwd);
    if (!f || seenRuns(f).has(runId)) return 0;
    const spans = ciSpans(runId, run, 0, kindsOf(kindsFile(f)).get(runId) ?? "");
    if (!spans.length) return 0;
    mkdirSync(dirname(f), { recursive: true });
    appendFileSync(f, spans.map((s) => JSON.stringify(s)).join("\n") + "\n");
    return spans.length;
  } catch { return 0; }
}

// ---- the read-only view: `fw timings` -----------------------------------------------------------------------------

export type Row = { tool: string; step: string; n: number; p50: number; p90: number; last: number; max: number };

/** Display-only nearest-rank quantile. The "slow" verdict comes from Lean (timing-lean), not from here. */
export const quantile = (sorted: number[], q: number): number => sorted.length ? sorted[Math.min(sorted.length - 1, Math.ceil(q * sorted.length) - 1)]! : 0;

export function summarize(lines: string[], o: { tool?: string; sinceMs?: number } = {}): Row[] {
  const g = new Map<string, Span[]>();
  for (const l of lines) {
    let s: Span;
    try { s = JSON.parse(l) as Span; } catch { continue; }
    if (typeof s.tool !== "string" || typeof s.step !== "string" || typeof s.durMs !== "number") continue;
    if (o.tool && s.tool !== o.tool) continue;
    if (o.sinceMs !== undefined && s.startMs < o.sinceMs) continue;
    const k = `${s.tool}\u0000${s.step}`;
    (g.get(k) ?? g.set(k, []).get(k)!).push(s);
  }
  return [...g.values()].map((v) => {
    const d = v.map((s) => s.durMs).sort((a, b) => a - b);
    const last = v.reduce((a, b) => (b.startMs >= a.startMs ? b : a));
    return { tool: v[0]!.tool, step: v[0]!.step, n: v.length, p50: quantile(d, 0.5), p90: quantile(d, 0.9), last: last.durMs, max: d[d.length - 1]! };
  }).sort((a, b) => b.p90 - a.p90);
}

export const fmtMs = (ms: number): string => (ms >= 10_000 ? `${(ms / 1000).toFixed(0)}s` : ms >= 1000 ? `${(ms / 1000).toFixed(1)}s` : `${ms}ms`);

export function renderRows(rows: Row[]): string {
  const cells = [["tool", "step", "n", "p50", "p90", "last", "max"], ...rows.map((r) => [r.tool, r.step, String(r.n), fmtMs(r.p50), fmtMs(r.p90), fmtMs(r.last), fmtMs(r.max)])];
  const w = cells[0]!.map((_, i) => Math.max(...cells.map((c) => c[i]!.length)));
  return cells.map((c) => c.map((x, i) => (i < 2 ? x.padEnd(w[i]!) : x.padStart(w[i]!))).join("  ").trimEnd()).join("\n");
}

export const TIMINGS_USAGE = "usage: fw timings [--tool <t>] [--since <hours>] [--backfill [<runId>...] [--per <n>]] | fw timings --lag [--since <hours>]";

export function parseTimings(args: string[]): { tool?: string; sinceH?: number; backfill: boolean; lag: boolean; runs: number[]; per: number } {
  const o = { backfill: false, lag: false, runs: [] as number[], per: 3 } as ReturnType<typeof parseTimings>;
  for (let i = 0; i < args.length; i++) {
    const a = args[i]!;
    if (a === "--tool" && args[i + 1]) o.tool = args[++i];
    else if (a === "--since" && Number(args[i + 1]) > 0) o.sinceH = Number(args[++i]);
    else if (a === "--per" && Number(args[i + 1]) > 0) o.per = Number(args[++i]);
    else if (a === "--lag") o.lag = true;
    else if (a === "--backfill") o.backfill = true;
    else if (/^\d+$/.test(a) && o.backfill) o.runs.push(Number(a));
    else throw new Error(TIMINGS_USAGE);
  }
  return o;
}

export function timingsView(args: string[], cwd: string, now = Date.now()): string {
  const o = parseTimings(args);
  const f = timingsFile(cwd, { ...process.env, VITEST: "" });
  const rows = f ? summarize((rd(f) ?? "").split("\n").filter(Boolean), { tool: o.tool, sinceMs: o.sinceH ? now - o.sinceH * 3_600_000 : undefined }) : [];
  return rows.length ? renderRows(rows) : "no timings recorded yet";
}
