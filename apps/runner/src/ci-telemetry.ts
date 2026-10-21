// `fw ci telemetry <github|circleci> <run id | pipeline id> [--store <dir>] [--slug gh/<owner>/<repo>]`: collect the
// telemetry artifacts of one CI run (producer: scripts/ci-telemetry/, record layout and every verdict: Lean
// lean/Fw/Ci/Telemetry.lean, op `ci.telemetry`), add the provider's queue time, append them to the local store
// (`<console dir>/telemetry/records.jsonl`, gitignored) and print the step table and the slow verdicts.
// Decisions are fwcore's: the schema (the decoder refuses anything else), the span names, the baseline per
// (lane, job/step, provider, class) and slow or not. This file is gh and HTTP calls, file reads and a table.
// The CircleCI token comes from the macOS Keychain (service fw-circleci-token) or $CIRCLE_TOKEN, inside the request;
// it is never printed, logged or put into an error.
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { execFileSync, spawnSync } from "node:child_process";
import { realEnv } from "@fw/gh-budget";
import { UsageError } from "./lib.ts";
import { chargedGh, fwcoreCall, type FwCall, type Gh } from "./run.ts";

export const TELEMETRY_USAGE = "usage: fw ci telemetry <github|circleci> <run id | pipeline id> [--store <dir>] [--slug gh/<owner>/<repo>]\n" +
  "  downloads the telemetry artifacts of the run, adds queue time, appends to the local store, prints the step table and the slow verdicts.\n" +
  "       fw ci telemetry macos-window [--days 7] [--sample 200] [--out <file>] [--cache <dir>] [--now <ms>] [--no-circleci] [--no-codemagic]";

export type Provider = "github" | "circleci";
export type TelArgs = { provider: Provider; id: string; store?: string; slug?: string };

export function parseTelArgs(argv: string[]): TelArgs {
  const [p, id, ...rest] = argv;
  if (p !== "github" && p !== "circleci") throw new UsageError(`provider must be github or circleci\n${TELEMETRY_USAGE}`);
  if (!id || !/^[0-9a-f-]+$/i.test(id)) throw new UsageError(`a run id or pipeline id is required\n${TELEMETRY_USAGE}`);
  const a: TelArgs = { provider: p, id };
  for (let i = 0; i < rest.length; i++) {
    const f = rest[i]!, v = rest[i + 1];
    if ((f === "--store" || f === "--slug") && v !== undefined && !v.startsWith("--")) { a[f === "--store" ? "store" : "slug"] = v; i++; }
    else throw new UsageError(`unexpected argument ${f}\n${TELEMETRY_USAGE}`);
  }
  return a;
}

// ---- the record (Lean `Fw.Wire.Ci.Telemetry.recordJson`) --------------------------------------------------------------------
export type TelStep = { name: string; startMs: number; endMs: number; exit?: number | null; netBytes?: number | null };
export type TelRecord = {
  schema: number;
  ident: { provider: string; lane: string; job: string; runId: string; commit: string; class: string };
  machine: Record<string, unknown>;
  times: { createdMs?: number | null; startedMs: number; endedMs: number; simBootMs?: number | null };
  steps: TelStep[];
  probes: Record<string, number>[];
  cache: Record<string, unknown>[];
};
export type TelReply = {
  spans: { runId: string; job: string; name: string; tool: string; step: string; kind: string; durMs: number; code: string; n: number; baseline: number; budgetMs: number }[];
  slow: { subject: string; runId: string; job: string; name: string; durMs: number; baseline: number; n: number }[];
};

export const recordKey = (r: TelRecord): string => `${r.ident.provider}|${r.ident.runId}|${r.ident.job}`;

/** JSON.parse that survives raw control characters inside strings (CircleCI replies carry some): they are escaped first. */
export function parseLoose(text: string): unknown {
  try { return JSON.parse(text); } catch { /* fall through to the tolerant pass */ }
  let out = "", inStr = false, esc = false;
  for (const ch of text) {
    if (inStr) {
      if (esc) { out += ch; esc = false; continue; }
      if (ch === "\\") { out += ch; esc = true; continue; }
      if (ch === "\"") { inStr = false; out += ch; continue; }
      out += ch.charCodeAt(0) < 0x20 ? `\\u${ch.charCodeAt(0).toString(16).padStart(4, "0")}` : ch;
    } else { if (ch === "\"") inStr = true; out += ch; }
  }
  return JSON.parse(out);
}

const walk = (dir: string): string[] =>
  readdirSync(dir, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? walk(join(dir, e.name)) : [join(dir, e.name)]));

/** Every telemetry.json under a directory, parsed. A file that does not parse is refused (the artifact is the producer's). */
export function readRecords(dir: string): TelRecord[] {
  return walk(dir).filter((f) => f.endsWith("telemetry.json")).sort().map((f) => {
    const j = parseLoose(readFileSync(f, "utf8")) as TelRecord;
    if (j?.schema !== 1 || !j.ident) throw new UsageError(`${f.slice(dir.length + 1)} is not a telemetry record (schema 1)`);
    return j;
  });
}

// ---- GitHub: queue time and steps the artifact lacks --------------------------------------------------------------------------
export type GhJob = { name: string; startedAt?: string | null; completedAt?: string | null; steps?: { name: string; conclusion?: string | null; startedAt?: string | null; completedAt?: string | null }[] };
const norm = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
const ms = (iso?: string | null): number | null => { const t = Date.parse(iso ?? ""); return Number.isFinite(t) ? t : null; };

const findJob = (jobs: GhJob[], job: string): GhJob | undefined =>
  jobs.find((j) => norm(j.name) === norm(job)) ?? jobs.find((j) => norm(j.name).startsWith(norm(job)));
const exitOf = (c?: string | null): number | null =>
  c === "success" ? 0 : c === "failure" || c === "cancelled" || c === "timed_out" ? 1 : null;

/** The in-job jobs API call runs before GitHub settles the conclusion of the step that is running (the failing step, and the
 *  last one before the telemetry finish), so those steps have no exit. Every step with `exit == null` gets the exit (and an
 *  end that the job API left open) from the run's job of the same name in `gh run view --json jobs`; the k-th step of a name
 *  is matched with the k-th step of that name there. Created time, start and all other steps stay as the record has them. */
export function backfillExits(r: TelRecord, jobs: GhJob[]): TelRecord {
  const job = findJob(jobs, r.ident.job);
  if (!job || !r.steps.some((s) => s.exit == null)) return r;
  const byName = new Map<string, NonNullable<GhJob["steps"]>>();
  for (const g of job.steps ?? []) if (g.conclusion !== "skipped") byName.set(g.name, [...(byName.get(g.name) ?? []), g]);
  const seen = new Map<string, number>();
  const steps = r.steps.map((s) => {
    const k = seen.get(s.name) ?? 0;
    seen.set(s.name, k + 1);
    const g = byName.get(s.name)?.[k];
    if (s.exit != null || !g) return s;
    const e = exitOf(g.conclusion), end = ms(g.completedAt);
    if (e === null) return s;
    return { ...s, exit: e, endMs: end === null ? s.endMs : Math.max(s.startMs, end) };
  });
  return { ...r, steps };
}

/** A record without a created time (the in-job jobs API call failed) gets the steps of the run's job of the same name from
 *  `gh run view --json jobs`; the queue time stays unknown (that reply has no job creation time). */
export function fillFromGhJobs(r: TelRecord, jobs: GhJob[]): TelRecord {
  if (r.times.createdMs != null) return r;
  const job = findJob(jobs, r.ident.job);
  if (!job) return r;
  const own = new Set(r.steps.map((s) => s.name));
  const add: TelStep[] = [];
  for (const s of job.steps ?? []) {
    const a = ms(s.startedAt), b = ms(s.completedAt);
    if (a === null || b === null || s.conclusion === "skipped" || /^Telemetry/.test(s.name) || own.has(s.name)) continue;
    add.push({ name: s.name, startMs: a, endMs: Math.max(a, b), exit: exitOf(s.conclusion) });
  }
  const started = ms(job.startedAt);
  return { ...r, steps: [...r.steps, ...add].sort((x, y) => x.startMs - y.startMs), times: { ...r.times, startedMs: started ?? r.times.startedMs } };
}

// ---- CircleCI --------------------------------------------------------------------------------------------------------------------
export type Http = (url: string) => Promise<string>;

/** The token, read at the moment of the request: $CIRCLE_TOKEN, else the macOS Keychain item fw-circleci-token. */
function circleToken(env: Record<string, string | undefined>): string {
  if (env.CIRCLE_TOKEN) return env.CIRCLE_TOKEN;
  try { return execFileSync("security", ["find-generic-password", "-s", "fw-circleci-token", "-w"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim(); }
  catch { throw new UsageError("no CircleCI token: the Keychain item fw-circleci-token is missing and CIRCLE_TOKEN is not set"); }
}

export function circleHttp(env: Record<string, string | undefined> = process.env): Http {
  return async (url) => {
    const res = await fetch(url, { headers: { "Circle-Token": circleToken(env), accept: "application/json" } });
    if (!res.ok) throw new Error(`GET ${url.replace(/\?.*$/, "")} answered ${res.status}`);
    return res.text();
  };
}

type Items<T> = { items?: T[] };
const CIRCLE = "https://circleci.com/api/v2";

/** The telemetry records of one pipeline, each with the queue time of its job (queued_at to started_at). */
export async function circleRecords(http: Http, slug: string, pipelineId: string): Promise<TelRecord[]> {
  const get = async <T>(path: string): Promise<T> => parseLoose(await http(`${CIRCLE}${path}`)) as T;
  const out: TelRecord[] = [];
  for (const w of (await get<Items<{ id: string }>>(`/pipeline/${pipelineId}/workflow`)).items ?? []) {
    for (const j of (await get<Items<{ job_number?: number }>>(`/workflow/${w.id}/job`)).items ?? []) {
      if (j.job_number === undefined) continue;
      const arts = (await get<Items<{ path: string; url: string }>>(`/project/${slug}/${j.job_number}/artifacts`)).items ?? [];
      const art = arts.find((a) => a.path.endsWith("telemetry.json"));
      if (!art) continue;
      const rec = parseLoose(await http(art.url)) as TelRecord;
      if (rec?.schema !== 1 || !rec.ident) throw new UsageError(`job ${j.job_number}: its telemetry.json is not a record (schema 1)`);
      const d = await get<{ queued_at?: string; created_at?: string; started_at?: string }>(`/project/${slug}/job/${j.job_number}`);
      const created = ms(d.queued_at ?? d.created_at), started = ms(d.started_at);
      out.push({ ...rec, times: { ...rec.times, ...(created === null ? {} : { createdMs: created }), startedMs: started ?? rec.times.startedMs } });
    }
  }
  return out;
}

// ---- the store and the verdicts ---------------------------------------------------------------------------------------------
export const loadStore = (file: string): TelRecord[] =>
  existsSync(file) ? readFileSync(file, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l) as TelRecord) : [];

/** Old records with the same key are replaced by the fresh ones; the order is the old one, new keys last. */
export function mergeStore(old: TelRecord[], fresh: TelRecord[]): TelRecord[] {
  const f = new Map(fresh.map((r) => [recordKey(r), r]));
  const kept = old.map((r) => f.get(recordKey(r)) ?? r);
  const have = new Set(old.map(recordKey));
  return [...kept, ...fresh.filter((r) => !have.has(recordKey(r)))];
}

const bare = (r: TelRecord): TelRecord => ({ ...r, probes: [] }); // the verdicts do not read probes; the request stays small

/** One fwcore call: every stored record is history for the others (Lean orders by start time and judges each span against
 *  the spans before it of the same lane, job/step, provider and class). */
export function judge(call: FwCall, all: TelRecord[]): TelReply {
  return call({ op: "ci.telemetry", records: all.map(bare) }) as unknown as TelReply;
}

const sec = (ms: number) => (Math.round(ms / 100) / 10).toFixed(1);

/** The step-matched time of a job: its wall time minus the upload, telemetry and post steps that only GitHub has (Lean
 *  `Fw.Obs.MacTelemetry.matchedMs`, op `obs.macMatched`). The spans carry durations only, so each step is placed at 0. */
export function matchedOf(call: FwCall, wallMs: number, steps: { name: string; durMs: number }[]): { matchedMs: number; unmatchedMs: number } {
  const r = call({ op: "obs.macMatched", wallMs, steps: steps.map((s) => ({ name: s.name, startMs: 0, endMs: s.durMs })) }) as unknown as { matchedMs: number; unmatchedMs: number };
  return { matchedMs: r.matchedMs, unmatchedMs: r.unmatchedMs };
}

/** The table of the spans of the given runs, then the slow verdicts. With `call`, each job ends with a `(matched)` row: the
 *  job time that exists on every provider, to compare a GitHub job with a Codemagic or CircleCI one. */
export function tableLines(reply: TelReply, runIds: Set<string>, call?: FwCall): string[] {
  const rows = reply.spans.filter((s) => runIds.has(s.runId));
  const lines = [`${"job".padEnd(26)} ${"step".padEnd(44)} ${"s".padStart(8)} ${"base s".padStart(8)} ${"n".padStart(3)}  verdict`];
  const row = (job: string, name: string, s: number, base: string, n: string, code: string) =>
    `${job.slice(0, 26).padEnd(26)} ${name.slice(0, 44).padEnd(44)} ${sec(s).padStart(8)} ${base.padStart(8)} ${n.padStart(3)}  ${code}`;
  for (const s of rows) {
    lines.push(row(s.job, s.name, s.durMs, s.n > 0 ? sec(s.baseline) : "-", String(s.n), s.code));
    if (call && s.name === "(job)") {
      const steps = rows.filter((x) => x.runId === s.runId && x.job === s.job && x.name !== "(job)" && x.name !== "(queue)");
      const m = matchedOf(call, s.durMs, steps);
      lines.push(row(s.job, "(matched: wall - upload, telemetry, post)", m.matchedMs, "-", "-", "matched"));
    }
  }
  const slow = reply.slow.filter((s) => runIds.has(s.runId));
  lines.push(slow.length === 0 ? "slow: none" : `slow: ${slow.length}`);
  for (const s of slow) lines.push(`  SLOW ${s.subject}: ${sec(s.durMs)} s against baseline ${sec(s.baseline)} s over ${s.n} runs`);
  return lines;
}

// ---- the command -------------------------------------------------------------------------------------------------------------------
export type TelDeps = { call: FwCall; gh: Gh; http: Http; store: string; tmp: string; slug: () => string; log: (l: string) => void };

export async function telemetryMain(args: TelArgs, d: TelDeps): Promise<number> {
  let fresh: TelRecord[];
  if (args.provider === "github") {
    mkdirSync(d.tmp, { recursive: true });
    const dl = mkdtempSync(join(d.tmp, `tel-${args.id}-`));
    try {
      await d.gh(["run", "download", args.id, "-D", dl, "--pattern", "telemetry-*"]);
      fresh = readRecords(dl);
      const v = JSON.parse(await d.gh(["run", "view", args.id, "--json", "jobs"])) as { jobs: GhJob[] };
      fresh = fresh.map((r) => backfillExits(fillFromGhJobs(r, v.jobs), v.jobs));
    } finally { rmSync(dl, { recursive: true, force: true }); }
  } else {
    fresh = await circleRecords(d.http, args.slug ?? d.slug(), args.id);
  }
  if (fresh.length === 0) { d.log(`refused: no telemetry artifact in ${args.provider} run ${args.id} (the run predates the telemetry action, or its jobs are not wired)`); return 2; }
  const file = join(d.store, "records.jsonl");
  const all = mergeStore(loadStore(file), fresh);
  const reply = judge(d.call, all);
  mkdirSync(d.store, { recursive: true });
  writeFileSync(file, all.map((r) => JSON.stringify(r)).join("\n") + "\n");
  const runs = new Set(fresh.map((r) => r.ident.runId));
  const noQueue = fresh.filter((r) => r.times.createdMs == null).length;
  d.log(`${args.provider} ${args.id}: ${fresh.length} job records stored (${all.length} in the store)${noQueue > 0 ? `, ${noQueue} without queue time` : ""}`);
  for (const l of tableLines(reply, runs, d.call)) d.log(l);
  return 0;
}

const originSlug = (cwd: string): string => {
  const url = spawnSync("git", ["remote", "get-url", "origin"], { cwd, encoding: "utf8" }).stdout.trim();
  const m = /github\.com[:/]([^/]+)\/([^/]+?)(?:\.git)?$/.exec(url);
  if (!m) throw new UsageError("cannot read the repository from the origin remote; pass --slug gh/<owner>/<repo>");
  return `gh/${m[1]}/${m[2]}`;
};

export async function telemetryCli(argv: string[], cwd: string, env: Record<string, string | undefined> = process.env): Promise<number> {
  if (argv[0] === "macos-window") return (await import("./ci-telemetry-mac.ts")).macWindowCli(argv.slice(1), cwd);
  const args = parseTelArgs(argv);
  const common = spawnSync("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd, encoding: "utf8" }).stdout.trim();
  const consoleDir = env.FW_CONSOLE_DIR ?? join(dirname(common), ".fw-console");
  const unused = (): never => { throw new Error("no gh call for circleci"); };
  return telemetryMain(args, {
    call: fwcoreCall(cwd), gh: args.provider === "github" ? chargedGh(realEnv(cwd)) : unused, http: circleHttp(env),
    store: args.store ?? join(consoleDir, "telemetry"), tmp: join(consoleDir, "tmp"), slug: () => originSlug(cwd), log: (l) => console.log(l),
  });
}
