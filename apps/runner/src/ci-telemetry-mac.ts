// `fw ci telemetry macos-window`: collects the macOS jobs of the last days from the three providers into one dataset file that the
// Lean reducer (`Fw.Obs.MacTelemetry`, ops obs.macSample / obs.macReduce / obs.macIs) reduces. This file is I/O glue: it lists runs,
// reads jobs, converts times to epoch ms and writes JSON lines. Which runs are read (the sample), which jobs are macOS jobs, and
// every number of the tables are Lean; nothing here decides. A TS stand-in until a Lean-generated golden covers the converters
// (the converters are checked in apps/runner/test/ci-telemetry-mac.test.ts against fake provider replies).
//
// Dataset lines (one JSON object per line, `kind` first): `window` {fromMs,toMs,minRunMs,cap,days}, `run` (every completed run of
// the seven macOS workflows, run-level minutes) and `job` (the jobs of the sampled runs, plus the Codemagic builds and the CircleCI
// macOS jobs). Only ids, names, conclusions and times: no commits, authors, branches or URLs.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";
import { spawnSync } from "node:child_process";
import { realEnv } from "@fw/gh-budget";
import { UsageError } from "./lib.ts";
import { chargedGh, fwcoreCall, type FwCall, type Gh } from "./run.ts";

export const MAC_USAGE = "usage: fw ci telemetry macos-window [--days 7] [--sample 200] [--out <file>] [--cache <dir>] [--now <epoch ms>] [--codemagic-builds id,id] [--no-circleci] [--no-codemagic]";

/** The workflows that hold macOS jobs (Lean `Fw.Obs.MacTelemetry.macJobs`). */
export const MAC_WORKFLOWS = ["trajectory-probe", "webkit-sim", "wktr", "wktr-fixtures", "engine-premises", "gate-gaps", "sim-speed"];

export const MIN_RUN_MS = 120000;
const DAY_MS = 86400000;

export type MacArgs = { days: number; sample: number; out?: string; cache?: string; now?: number; builds?: string[]; circleci: boolean; codemagic: boolean };

export function parseMacArgs(argv: string[]): MacArgs {
  const a: MacArgs = { days: 7, sample: 200, circleci: true, codemagic: true };
  const num = (flag: string, v: string | undefined): number => {
    const n = Number(v);
    if (v === undefined || !Number.isInteger(n) || n < 1) throw new UsageError(`${flag} needs a positive whole number\n${MAC_USAGE}`);
    return n;
  };
  for (let i = 0; i < argv.length; i++) {
    const f = argv[i]!;
    if (f === "--days") a.days = num(f, argv[++i]);
    else if (f === "--sample") a.sample = num(f, argv[++i]);
    else if (f === "--out") { const v = argv[++i]; if (!v) throw new UsageError(`--out needs a file\n${MAC_USAGE}`); a.out = v; }
    else if (f === "--cache") { const v = argv[++i]; if (!v) throw new UsageError(`--cache needs a directory\n${MAC_USAGE}`); a.cache = v; }
    else if (f === "--now") a.now = num(f, argv[++i]);
    else if (f === "--codemagic-builds") { const v = argv[++i]; if (!v || !/^[0-9a-f,]+$/i.test(v)) throw new UsageError(`--codemagic-builds needs build ids separated by commas\n${MAC_USAGE}`); a.builds = v.split(",").filter(Boolean); }
    else if (f === "--no-circleci") a.circleci = false;
    else if (f === "--no-codemagic") a.codemagic = false;
    else throw new UsageError(`unknown argument ${f}\n${MAC_USAGE}`);
  }
  return a;
}

// ---- rows (the wire shapes of obs.macReduce) ----------------------------------------------------------------------------------------
export type StepRow = { name: string; startMs: number; endMs: number };
export type RunRow = { wf: string; id: string; event: string; createdMs: number; startMs: number; endMs: number; concl: string };
export type JobRow = { prov: "github" | "codemagic" | "circleci"; wf: string; run: string; name: string; runner: string; event: string; createdMs: number; startMs: number; endMs: number; concl: string; steps: StepRow[] };

/** ISO time to epoch ms; GitHub's zero time (`0001-01-01...`, a job that never started) and anything unreadable give `null`. */
export function isoMs(iso: unknown): number | null {
  if (typeof iso !== "string") return null;
  const t = Date.parse(iso);
  return Number.isFinite(t) && t > Date.UTC(2000, 0, 1) ? t : null;
}

type GhRun = { databaseId: number; createdAt?: string; startedAt?: string; updatedAt?: string; status?: string; conclusion?: string; event?: string };

/** The completed runs of `gh run list` as run rows (a run still running has no end, so it is left out). */
export function runRows(wf: string, runs: GhRun[], fromMs: number): RunRow[] {
  const out: RunRow[] = [];
  for (const r of runs) {
    const created = isoMs(r.createdAt);
    if (created == null || created < fromMs || r.status !== "completed") continue;
    const start = isoMs(r.startedAt) ?? created;
    const end = isoMs(r.updatedAt) ?? start;
    out.push({ wf, id: String(r.databaseId), event: r.event ?? "", createdMs: created, startMs: start, endMs: Math.max(start, end), concl: r.conclusion ?? "" });
  }
  return out;
}

type GhViewJob = { name: string; conclusion?: string | null; startedAt?: string | null; completedAt?: string | null; steps?: { name: string; startedAt?: string | null; completedAt?: string | null }[] };

/** The job rows of one sampled run. Steps are kept for macOS jobs only (`macOf` is Lean `obs.macIs`). */
export function jobRows(run: RunRow, jobs: GhViewJob[], macOf: (wf: string, names: string[]) => boolean[]): JobRow[] {
  const mac = macOf(run.wf, jobs.map((j) => j.name));
  return jobs.map((j, i) => {
    const start = isoMs(j.startedAt) ?? run.createdMs;
    const end = Math.max(start, isoMs(j.completedAt) ?? start);
    const steps: StepRow[] = [];
    if (mac[i] === true) {
      for (const s of j.steps ?? []) {
        const a = isoMs(s.startedAt), b = isoMs(s.completedAt);
        if (a != null && b != null) steps.push({ name: s.name, startMs: a, endMs: Math.max(a, b) });
      }
    }
    return { prov: "github", wf: run.wf, run: run.id, name: j.name, runner: "", event: run.event, createdMs: run.createdMs, startMs: start, endMs: end, concl: j.conclusion ?? "", steps };
  });
}

// ---- Codemagic and CircleCI ---------------------------------------------------------------------------------------------------------
type CmBuild = { id: string; status: string; instanceType?: string; createdAt: number | null; startedAt: number | null; finishedAt: number | null; steps: { name: string; durMs: number }[] };

/** A Codemagic build as one job row. Its steps carry durations only, so they are laid end to end from the start. */
export function codemagicRow(b: CmBuild): JobRow | null {
  const created = b.createdAt ?? b.startedAt;
  if (created == null) return null;
  const start = b.startedAt ?? created;
  const end = Math.max(start, b.finishedAt ?? start);
  let at = start;
  const steps = b.steps.map((s) => { const r = { name: s.name, startMs: at, endMs: at + Math.max(0, s.durMs) }; at = r.endMs; return r; });
  return { prov: "codemagic", wf: "webkit-sim", run: b.id, name: "sim", runner: b.instanceType ?? "", event: "", createdMs: created, startMs: start, endMs: end, concl: b.status, steps };
}

export type CircleIo = { get: (url: string) => Promise<any>; urls: { workflows: (p: string) => string; jobs: (w: string) => string; job: (n: number) => string; jobSteps: (n: number) => string; pipelines: string }; log: (l: string) => void };

/** True for the macOS resource classes of CircleCI (`m4pro-medium` and the like). */
export const circleMac = (resourceClass: unknown): boolean => /^m\d|macos/i.test(String(resourceClass ?? ""));

/** The CircleCI macOS jobs (workflow `webkit-sim`) of the pipelines created since `fromMs`, with their steps. */
export async function circleRows(io: CircleIo, fromMs: number): Promise<JobRow[]> {
  const out: JobRow[] = [];
  let token: string | null = null;
  const pipes: { id: string; created_at: string; trigger?: { type?: string } }[] = [];
  for (let page = 0; page < 40; page++) {
    const r = await io.get(token ? `${io.urls.pipelines}?page-token=${encodeURIComponent(token)}` : io.urls.pipelines);
    const items = (r.items ?? []) as typeof pipes;
    pipes.push(...items);
    token = r.next_page_token ?? null;
    const last = items.length > 0 ? isoMs(items[items.length - 1]!.created_at) : null;
    if (!token || (last != null && last < fromMs)) break;
  }
  for (const p of pipes) {
    const created = isoMs(p.created_at);
    if (created == null || created < fromMs || p.trigger?.type === "webhook") continue;
    for (const w of ((await io.get(io.urls.workflows(p.id))).items ?? []) as { id: string; name: string }[]) {
      if (w.name !== "webkit-sim") continue;
      for (const j of ((await io.get(io.urls.jobs(w.id))).items ?? []) as { name: string; status: string; job_number?: number }[]) {
        if (j.job_number === undefined) continue;
        const d = await io.get(io.urls.job(j.job_number));
        if (!circleMac(d.executor?.resource_class)) continue;
        const queued = isoMs(d.queued_at) ?? isoMs(d.created_at) ?? created;
        const start = isoMs(d.started_at) ?? queued;
        const end = Math.max(start, isoMs(d.stopped_at) ?? start);
        const sd = await io.get(io.urls.jobSteps(j.job_number));
        const steps: StepRow[] = [];
        for (const s of (sd.steps ?? []) as { actions?: { name: string; start_time?: string; end_time?: string }[] }[]) {
          for (const a of s.actions ?? []) {
            const x = isoMs(a.start_time), y = isoMs(a.end_time);
            if (x != null && y != null) steps.push({ name: a.name, startMs: x, endMs: Math.max(x, y) });
          }
        }
        out.push({ prov: "circleci", wf: "webkit-sim", run: String(j.job_number), name: j.name, runner: String(d.executor.resource_class), event: "", createdMs: queued, startMs: start, endMs: end, concl: j.status, steps });
      }
    }
  }
  io.log(`circleci: ${out.length} macOS job(s) since the window start`);
  return out;
}

// ---- the collection -----------------------------------------------------------------------------------------------------------------
export type MacDeps = {
  call: FwCall; gh: Gh; now: number; log: (l: string) => void;
  /** extra provider rows, or none when the provider is off or has nothing */
  codemagic?: (fromMs: number) => Promise<JobRow[]>;
  circleci?: (fromMs: number) => Promise<JobRow[]>;
  /** raw gh replies kept by key, so a collection that stopped half way resumes without asking GitHub again */
  cache?: { read: (key: string) => string | undefined; write: (key: string, text: string) => void };
  /** the pause before a gh call is made again, in seconds */
  pause?: (s: number) => Promise<void>;
};

const GH_TRIES = 3;

/** One gh read, from the cache when it holds it. A server error (HTTP 5xx) is asked again after 10 s, then 20 s; any other failure
 *  (a rate limit, a 403) is not retried. */
async function ghText(d: MacDeps, key: string, args: string[]): Promise<string> {
  const hit = d.cache?.read(key);
  if (hit !== undefined) return hit;
  for (let n = 1; ; n++) {
    try {
      const text = await d.gh(args);
      d.cache?.write(key, text);
      return text;
    } catch (e) {
      if (n >= GH_TRIES || !/HTTP 5\d\d/.test(String((e as Error).message))) throw e;
      await (d.pause ?? sleepS)(10 * n);
    }
  }
}

/** Run lists of the seven workflows, the sample (Lean `obs.macSample`), the jobs of the sampled runs, then the provider rows. */
export async function collectMac(a: MacArgs, d: MacDeps): Promise<string[]> {
  const toMs = d.now, fromMs = d.now - a.days * DAY_MS;
  const since = new Date(fromMs).toISOString().slice(0, 10);
  const runs: RunRow[] = [];
  for (const wf of MAC_WORKFLOWS) {
    const list = JSON.parse(await ghText(d, `list-${wf}-${since}`, ["run", "list", "--workflow", wf, "--created", `>=${since}`, "--limit", "1000", "--json", "databaseId,createdAt,startedAt,updatedAt,status,conclusion,event"])) as GhRun[];
    if (list.length >= 1000) d.log(`warning: ${wf} returned 1000 runs, the list may be cut`);
    const rows = runRows(wf, list, fromMs);
    d.log(`${wf}: ${rows.length} completed runs since ${since}`);
    runs.push(...rows);
  }
  const sample = d.call({ op: "obs.macSample", cap: a.sample, minRunMs: MIN_RUN_MS, runs }) as unknown as { ids: string[]; strata: { key: string; candidates: number; picked: number }[] };
  for (const s of sample.strata) d.log(`stratum ${s.key}: ${s.picked} of ${s.candidates} runs read`);
  const byId = new Map(runs.map((r) => [r.id, r]));
  const macOf = (wf: string, names: string[]): boolean[] => (d.call({ op: "obs.macIs", rows: names.map((name) => ({ wf, name })) }) as unknown as { mac: boolean[] }).mac;
  const jobs: JobRow[] = [], unread: string[] = [];
  for (const id of sample.ids) {
    const run = byId.get(id);
    if (!run) continue;
    try {
      const v = JSON.parse(await ghText(d, `view-${id}`, ["run", "view", id, "--json", "jobs"])) as { jobs: GhViewJob[] };
      jobs.push(...jobRows(run, v.jobs ?? [], macOf));
    } catch (e) {
      if (!/HTTP 5\d\d/.test(String((e as Error).message))) throw e;
      unread.push(id);
    }
  }
  d.log(`github: ${jobs.length} jobs of ${sample.ids.length - unread.length} sampled runs${unread.length > 0 ? `; ${unread.length} run(s) not read after ${GH_TRIES} server errors (their minutes stay in the run rows only): ${unread.join(" ")}` : ""}`);
  if (d.codemagic) jobs.push(...(await d.codemagic(fromMs)));
  if (d.circleci) jobs.push(...(await d.circleci(fromMs)));
  const lines = [JSON.stringify({ kind: "window", fromMs, toMs, minRunMs: MIN_RUN_MS, cap: a.sample, days: a.days })];
  for (const r of runs) lines.push(JSON.stringify({ kind: "run", ...r }));
  for (const j of jobs) lines.push(JSON.stringify({ kind: "job", ...j }));
  return lines;
}

// ---- real providers -----------------------------------------------------------------------------------------------------------------
/** scripts/*.mjs are plain JS: loaded at run time from the checkout root so the typechecker never resolves them. */
const load = async (root: string, file: string): Promise<any> => import(pathToFileURL(join(root, "scripts", file)).href);

const sleepS = (s: number) => new Promise<void>((r) => setTimeout(r, s * 1000));

/** Codemagic builds of the ledger (`.local/codemagic-ledger.json`) and the ids given with `--codemagic-builds`, created since the window start. A build that cannot be read is logged and left out. */
export async function realCodemagic(root: string, log: (l: string) => void, extra: string[] = []): Promise<(fromMs: number) => Promise<JobRow[]>> {
  const m = await load(root, "codemagic.mjs");
  const ctx = { fetchFn: fetch, getToken: m.keychainToken, sleep: sleepS, log: () => {} };
  return async (fromMs) => {
    const ledger = m.readLedger(join(root, ".local", "codemagic-ledger.json")) as { builds?: Record<string, unknown> };
    const out: JobRow[] = [];
    for (const id of new Set([...Object.keys(ledger.builds ?? {}), ...extra])) {
      try {
        const b = m.normBuild(await m.call(ctx, "GET", m.urls.build(id))) as CmBuild;
        const row = codemagicRow(b);
        if (row && row.createdMs >= fromMs) out.push(row);
      } catch (e) { log(`codemagic build ${id}: not read (${String((e as Error).message).slice(0, 80)})`); }
    }
    log(`codemagic: ${out.length} build(s) in the window`);
    return out;
  };
}

/** CircleCI macOS jobs. The project slug holds a user name: it stays inside the URLs and any error text is cut before it is logged. */
export async function realCircleci(root: string, log: (l: string) => void): Promise<((fromMs: number) => Promise<JobRow[]>) | undefined> {
  const m = await load(root, "circleci.mjs");
  const cfg = m.loadConfig(root) as { slug: string };
  if (!cfg.slug) { log("circleci: no project slug configured, skipped"); return undefined; }
  const ctx = { fetchFn: fetch, getToken: m.keychainToken, sleep: sleepS, log: () => {} };
  const io: CircleIo = {
    get: async (url) => { try { return await m.call(ctx, "GET", url); } catch (e) { throw new Error(String((e as Error).message).split(cfg.slug).join("SLUG").slice(0, 120)); } },
    urls: { workflows: m.urls.workflows, jobs: m.urls.jobs, job: (n) => m.urls.job(cfg.slug, n), jobSteps: (n) => m.urls.jobSteps(cfg.slug, n), pipelines: `${m.API}/project/${cfg.slug}/pipeline` },
    log,
  };
  return (fromMs) => circleRows(io, fromMs);
}

/** A directory of raw gh replies, one file per key (the keys are `list-<workflow>-<date>` and `view-<run id>`). */
export function dirCache(dir: string): NonNullable<MacDeps["cache"]> {
  return {
    read: (key) => { const f = join(dir, `${key}.json`); return existsSync(f) ? readFileSync(f, "utf8") : undefined; },
    write: (key, text) => { mkdirSync(dir, { recursive: true }); writeFileSync(join(dir, `${key}.json`), text); },
  };
}

export async function macWindowCli(argv: string[], cwd: string): Promise<number> {
  const a = parseMacArgs(argv);
  const common = spawnSync("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd, encoding: "utf8" }).stdout.trim();
  const root = dirname(common);
  const log = (l: string) => console.log(l);
  const lines = await collectMac(a, {
    call: fwcoreCall(cwd), gh: chargedGh(realEnv(cwd)), now: a.now ?? Date.now(), log, cache: a.cache ? dirCache(a.cache) : undefined,
    codemagic: a.codemagic ? await realCodemagic(root, log, a.builds) : undefined,
    circleci: a.circleci ? await realCircleci(root, log) : undefined,
  });
  const out = a.out ?? join(cwd, "packages", "contracts", "golden", "obs", "mactelemetry-window-input.jsonl");
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, lines.join("\n") + "\n");
  log(`${lines.length} lines written to ${out}`);
  return 0;
}
