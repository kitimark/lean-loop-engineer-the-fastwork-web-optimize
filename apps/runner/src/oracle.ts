// `fw oracle`: typed answers from an outside model (TypeSafe Jev) for decisions we cannot script, used only as
// advice. Every decision is fwcore's (`oracle.*`, lean/Fw/Oracle): provenance check, redaction, request body, send
// gate and caps, validation, policy, calibration, whether a threshold may be written. This file is I/O: gh calls
// (charged, `gh run view` only, never `gh api`), git reads, the keychain, files, printing. It gathers provenance
// (which run or commit a field's text comes from) and Lean checks it: ci-triage fields are `githubRunnerLog(runId,
// jobs, log)` with the run's `--log-failed` text and one fact per job of the workflow files at the run's head commit
// (its YAML `runs-on` value); mistake-class fields are `committedPublic(research/mistakes/ledger.json, sha)` with
// sha = `git rev-parse origin/main` (passed as the public head; Lean refuses any other commit as notPublic) and the
// file text from `git show sha:path`.
//   fw oracle triage <runId> [--json]        advice on why a failed run failed, or escalate with a reason
//   fw oracle calibrate <question> [--limit n] [--resume]   calls over every labeled row (ids from Lean's
//                                             oracle.plan; logged answers replay; run cap 60); Lean chooses the
//                                             per-option thresholds on the choose part and keeps those the holdout
//                                             part certifies; written only when every labeled id has an answer
//                                             (Lean's mayWrite), else printed with exit 2. --resume first checks that
//                                             the rows missing from the answer log fit in the run cap (exit 2 if not)
//   fw oracle eval <question>                 holdout part: accuracy and coverage at the stored thresholds (MEASURED)
//   fw oracle collect --runs <runs.json> --out <file.jsonl> [--max 40]   unlabeled replay rows from failed runs
import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { userInfo } from "node:os";
import { dirname, join } from "node:path";
import { fwcoreCall, ghCharged, realEnv, type Env } from "@fw/gh-budget";
import { parse as parseYaml } from "yaml";
import { ask, decisionLine, errorText, keychainKey, loggedReply, readLog, sha256, type Deps, type FileAt, type FwCall, type JobFact,
  type Json, type Provenance } from "../../../packages/oracle/src/index.ts";
import { begin } from "./timing.ts";

export const ORACLE_USAGE = "usage: fw oracle triage <runId> [--json] | fw oracle calibrate <question> [--limit n] [--resume] | " +
  "fw oracle eval <question> | fw oracle collect --runs <runs.json> --out <rows.jsonl> [--max 40]";

/** The golden directory of the oracle (replay set, thresholds), under the checkout root. */
export function oracleDir(cwd: string): string {
  const top = spawnSync("git", ["rev-parse", "--show-toplevel"], { cwd, encoding: "utf8" }).stdout.trim() || cwd;
  return join(top, "packages", "contracts", "golden", "oracle");
}

/** The answer log: FW_CONSOLE_DIR, else the main checkout's .fw-console (gitignored). */
export function logPathFor(cwd: string, env: NodeJS.ProcessEnv = process.env): string {
  if (env.FW_ORACLE_LOG) return env.FW_ORACLE_LOG;
  const common = execFileSync("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd }).toString().trim();
  return join(env.FW_CONSOLE_DIR ?? join(dirname(common), ".fw-console"), "oracle.jsonl");
}

/** Words to redact besides the fixed rules: the git user name (and its words), the git user e-mail and the login
 *  name. Never printed. fwcore matches them in any letter case. */
export function redactNames(cwd: string): string[] {
  const cfg = (k: string) => spawnSync("git", ["config", k], { cwd, encoding: "utf8" }).stdout?.trim() ?? "";
  const git = cfg("user.name");
  const email = cfg("user.email");
  let login = "";
  try { login = userInfo().username; } catch { /* none */ }
  return [...new Set([git, ...git.split(/\s+/), email, login].filter((w) => w.length >= 3))];
}

/** The stored threshold table of a question (option key to {num, den} or null) or null: `thresholds.json` maps
 *  question to {thresholds, ...}. */
export function thresholdsOf(dir: string, question: string): Json | null {
  const f = join(dir, "thresholds.json");
  if (!existsSync(f)) return null;
  const t = (JSON.parse(readFileSync(f, "utf8")) as Record<string, { thresholds?: Json | null } | null>)[question];
  return t?.thresholds ?? null;
}

/** The real dependencies of the client. */
export function realDeps(cwd: string, core: FwCall = fwcoreCall(cwd)): Deps {
  return {
    core, fetch: globalThis.fetch, readKey: keychainKey, logPath: logPathFor(cwd), now: () => new Date(),
    span: (step) => begin("oracle", step, cwd),
  };
}

/** git in the checkout: its stdout, or undefined when git fails. */
export function gitIn(cwd: string): (args: string[]) => string | undefined {
  return (args) => {
    const r = spawnSync("git", args, { cwd, encoding: "utf8", maxBuffer: 256 * 1024 * 1024 });
    return r.status === 0 ? r.stdout : undefined;
  };
}

/** A failed run's head commit and `--log-failed` text, through the charged gh wrapper. */
export async function failedRun(env: Env, runId: string, headSha?: string):
    Promise<{ headSha?: string; log: string } | string> {
  let sha = headSha;
  if (sha === undefined) {
    const meta = await ghCharged(env, ["run", "view", runId, "--json", "headSha"], { cost: 1, block: true });
    if (!meta.ran) return `gh budget: ${meta.reason}`;
    if (meta.code !== 0) return `gh run view: ${meta.error ?? meta.code}`;
    sha = String((JSON.parse(meta.stdout) as { headSha?: string }).headSha ?? "") || undefined;
  }
  const log = await ghCharged(env, ["run", "view", runId, "--log-failed"], { cost: 3, block: true });
  if (!log.ran) return `gh budget: ${log.reason}`;
  if (log.code !== 0) return `gh run view --log-failed: ${log.error ?? log.code}`;
  return { ...(sha ? { headSha: sha } : {}), log: log.stdout };
}

/** Testable seams of the CLI. */
export type Io = { deps: Deps; env: () => Env; dir: string; names: string[]; out: (s: string) => void;
  /** git in the checkout (stdout, or undefined on failure). */
  git: (args: string[]) => string | undefined };

/** The job facts of the workflow files of one YAML text: one fact per job with its `runs-on` value as parsed; a text
 *  that does not parse, or has no `jobs` mapping, gives one fact without `runsOn` (Lean's `hostedLog` refuses it). */
export function jobsOfYaml(file: string, text: string): JobFact[] {
  let doc: unknown;
  try { doc = parseYaml(text); } catch { return [{ file }]; }
  const jobs = doc !== null && typeof doc === "object" ? (doc as Record<string, unknown>).jobs : undefined;
  if (jobs === null || typeof jobs !== "object" || Array.isArray(jobs)) return [{ file }];
  return Object.entries(jobs as Record<string, unknown>).map(([job, j]) => {
    const r = j !== null && typeof j === "object" ? (j as Record<string, unknown>)["runs-on"] : undefined;
    return r === undefined ? { file, job } : { file, job, runsOn: r };
  });
}

/** The job facts of every workflow file at a commit; [] when the commit or a file cannot be read (Lean's `hostedLog`
 *  refuses an empty list). */
export function jobFacts(io: Io, sha: string): JobFact[] {
  if (!/^[0-9a-f]{40}$/.test(sha)) return [];
  const names = io.git(["ls-tree", "--full-tree", "--name-only", sha, ".github/workflows/"]);
  if (names === undefined) return [];
  const facts: JobFact[] = [];
  for (const p of names.split("\n").filter((n) => /\.ya?ml$/.test(n))) {
    const t = io.git(["show", `${sha}:${p}`]);
    if (t === undefined) return [];
    facts.push(...jobsOfYaml(p, t));
  }
  return facts;
}

/** A run's fetched `--log-failed` text and the job facts at its head commit. */
export type RunFacts = { log: string; jobs: JobFact[] };

/** The run fetcher of one invocation (cached per run id): a reason string when gh fails. */
export function runFacts(io: Io): (runId: number, headSha?: string) => Promise<RunFacts | string> {
  const cache = new Map<number, RunFacts | string>();
  return async (runId, headSha) => {
    const hit = cache.get(runId);
    if (hit !== undefined) return hit;
    const fr = runId > 0 ? await failedRun(io.env(), String(runId), headSha) : "no run id";
    const f = typeof fr === "string" ? fr : { log: fr.log, jobs: fr.headSha ? jobFacts(io, fr.headSha) : [] };
    cache.set(runId, f);
    return f;
  };
}

/** The CI-triage state of a fetched log (Lean's `triageState`, not yet redacted). */
function triageStateOf(io: Io, log: string): Record<string, string | string[]> {
  return io.deps.core({ op: "oracle.triage.state", lines: log.split("\n") }).state as Record<string, string | string[]>;
}

/** The committed file a mistake-class state is quoted from. */
export const LEDGER = "research/mistakes/ledger.json";

/** Where a state's fields come from, as Lean's `oracle.pre` checks it, and the public head (`origin/main`). */
export type Sourcing = { provenance: Record<string, Provenance>; files: FileAt[]; publicHead?: string };

/** The provenance gatherer of one invocation (caches the ledger text, and the runs through `runs`). Unknown questions
 *  and unreadable sources give no provenance, so Lean refuses the state as unsourced. */
export function sourcer(io: Io, runs = runFacts(io)): (q: string, state: Record<string, unknown>,
    row: { runId?: number; headSha?: string }) => Promise<Sourcing> {
  let ledger: FileAt | undefined | null = null;
  const every = (state: Record<string, unknown>, p: Provenance) => Object.fromEntries(Object.keys(state).map((k) => [k, p]));
  return async (q, state, row) => {
    if (q === "mistake-class") {
      if (ledger === null) {
        // the public head only: never HEAD or a worktree (Lean refuses any other commit as notPublic)
        const sha = io.git(["rev-parse", "--verify", "origin/main^{commit}"])?.trim();
        const content = sha ? io.git(["show", `${sha}:${LEDGER}`]) : undefined;
        ledger = sha && content !== undefined ? { path: LEDGER, sha, content } : undefined;
      }
      return ledger ? { provenance: every(state, { kind: "committedPublic", path: ledger.path, sha: ledger.sha }), files: [ledger],
          publicHead: ledger.sha }
        : { provenance: {}, files: [] };
    }
    if (q === "ci-triage") {
      const runId = row.runId ?? 0;
      const f = await runs(runId, row.headSha);
      if (typeof f === "string") return { provenance: {}, files: [] };
      return { provenance: every(state, { kind: "githubRunnerLog", runId, jobs: f.jobs, log: f.log }), files: [] };
    }
    return { provenance: {}, files: [] };
  };
}

async function triage(io: Io, args: string[]): Promise<number> {
  const runId = args[0];
  if (!runId || !/^\d+$/.test(runId)) { io.out(ORACLE_USAGE); return 64; }
  const runs = runFacts(io);
  const run = await runs(Number(runId));
  if (typeof run === "string") { io.out(`oracle ci-triage ${runId}: escalate: ${run}`); return 0; }
  const st = triageStateOf(io, run.log);
  const src = await sourcer(io, runs)("ci-triage", st, { runId: Number(runId) });
  const r = await ask(io.deps, { question: "ci-triage", state: st, names: io.names, thresholds: thresholdsOf(io.dir, "ci-triage"), ...src });
  io.out(args.includes("--json") ? JSON.stringify({ runId, source: r.source, ...r.decision })
    : `oracle ci-triage ${runId}: ${decisionLine(r.decision)} [${r.source}]`);
  return 0;
}

/** A replay row (`<question>.jsonl`). A row whose `label` is null is left out; Lean (`oracle.plan`, `heldOut`) puts
 *  each labeled row in the choose or the holdout part by its id (a `split` key is refused). A ci-triage row's state is
 *  stored redacted; a call re-derives it from the run's fetched log, which is what Lean checks line by line. */
export type ReplayRow = { state: Record<string, string | string[]>; label: string | null;
  runId?: number; headSha?: string; labelSource?: string | null; id?: string };

/** Every row of `<question>.jsonl`, in file order. */
export function replayFile(dir: string, q: string): ReplayRow[] | string {
  const file = join(dir, `${q}.jsonl`);
  if (!existsSync(file)) return `no replay set ${file}`;
  return readFileSync(file, "utf8").split("\n").filter((l) => l.trim()).map((l) => JSON.parse(l) as ReplayRow);
}

/** Ask every row (no thresholds: only the replies matter); stops on a missing key. `answers` has one entry per row
 *  that got a reply text (logged or live), with the id Lean gave it. */
async function replies(io: Io, q: string, rows: ReplayRow[], ids: string[]):
    Promise<{ answers: { id: string; reply: string }[]; summary: string } | "nokey"> {
  const answers: { id: string; reply: string }[] = [];
  const counts: Record<string, number> = {};
  const runs = runFacts(io);
  const source = sourcer(io, runs);
  const logged = loggedRows(io, q, rows);
  let sent = 0;
  for (const [i, row] of rows.entries()) {
    // a logged request replays with no call; any other ci-triage row is re-derived from its run's fetched log
    let state = row.state;
    if (q === "ci-triage" && !logged[i] && row.runId !== undefined) {
      const f = await runs(row.runId, row.headSha);
      if (typeof f !== "string") state = triageStateOf(io, f.log);
    }
    const src = await source(q, state, row);
    const r = await ask(io.deps, { question: q, state, names: io.names, thresholds: null, run: sent, ...src });
    if (r.sent) sent++;
    counts[r.source] = (counts[r.source] ?? 0) + 1;
    if (r.reply !== undefined) answers.push({ id: ids[i]!, reply: r.reply });
    if (r.source === "nokey") return "nokey";
  }
  return { answers, summary: Object.entries(counts).map(([k, v]) => `${k} ${v}`).join(", ") };
}

/** Whether each row's request is already in the answer log (it replays and costs no call). */
function loggedRows(io: Io, q: string, rows: ReplayRow[]): boolean[] {
  const entries = readLog(io.deps.logPath);
  return rows.map((r) => {
    const body = String(io.deps.core({ op: "oracle.request", name: q, names: io.names, state: r.state }).bodyText);
    return loggedReply(entries, sha256(body)) !== undefined;
  });
}

/** The labeled rows as Lean's `oracle.plan` picks them (ids and file positions; one part when `part` is given), at
 *  most `limit`. */
function planOf(io: Io, all: ReplayRow[], part?: "holdout", limit?: number): { ids: string[]; rows: ReplayRow[] } {
  const plan = io.deps.core({ op: "oracle.plan", rows: all, ...(part ? { part } : {}), ...(limit !== undefined ? { limit } : {}) });
  return { ids: plan.ids as string[], rows: (plan.indices as number[]).map((i) => all[i]!) };
}

/** One part's counts from `oracle.calibrate` (Lean's Stats). */
type Stats = { rows: number; covered: number; hits: number };

const NOKEY = "no key in the keychain (service typesafe-api); nothing sent";

async function calibrate(io: Io, args: string[]): Promise<number> {
  const q = args[0];
  if (!q) { io.out(ORACLE_USAGE); return 64; }
  const li = args.indexOf("--limit");
  const limit = li >= 0 ? Number(args[li + 1]) : undefined;
  if (limit !== undefined && !(Number.isInteger(limit) && limit >= 0)) { io.out(ORACLE_USAGE); return 64; }
  const all = replayFile(io.dir, q);
  if (typeof all === "string") { io.out(`oracle calibrate: ${all}`); return 2; }
  const { ids, rows } = planOf(io, all, undefined, limit);
  if (args.includes("--resume")) {
    const plan = io.deps.core({ op: "oracle.plan", rows: all, ...(limit !== undefined ? { limit } : {}),
      logged: loggedRows(io, q, rows) });
    if (plan.resumable !== true) {
      io.out(`oracle calibrate ${q}: ${plan.missing} rows are not in the answer log, over the run cap ${plan.runCap}; nothing sent`);
      return 2;
    }
  }
  const got = await replies(io, q, rows, ids);
  if (got === "nokey") { io.out(`oracle calibrate: ${NOKEY}`); return 2; }
  // Lean splits the same file by id, chooses on one part, certifies on the other, and decides whether the table may
  // be stored: every labeled id has an answer (Fw.Oracle.certify, Fw.Oracle.mayWrite)
  const c = io.deps.core({ op: "oracle.calibrate", name: q, replay: all, answers: got.answers });
  const ch = c.choose as Stats, ho = c.holdout as Stats;
  const line = `oracle calibrate ${q}: thresholds ${JSON.stringify(c.thresholds ?? null)}, choose covered ${ch.covered} ` +
    `hits ${ch.hits} of ${ch.rows}, holdout covered ${ho.covered} hits ${ho.hits} of ${ho.rows}, used ${c.used}/${c.labeled} ` +
    `(${got.summary})`;
  if (c.write !== true) {
    io.out(`${line}; not written: every labeled row must be answered (run again with --resume: logged answers ` +
      "replay, only the missing rows are sent)");
    return 2;
  }
  const tf = join(io.dir, "thresholds.json");
  const table = existsSync(tf) ? JSON.parse(readFileSync(tf, "utf8")) as Record<string, unknown> : {};
  const model = String(io.deps.core({ op: "oracle.question", name: q }).model);
  table[q] = { thresholds: c.thresholds, choose: c.choose, holdout: c.holdout, used: c.used, dropped: c.dropped,
    rows: c.labeled, model, measuredOn: new Date().toISOString().slice(0, 10), status: "MEASURED" };
  writeFileSync(tf, JSON.stringify(table, null, 2) + "\n");
  io.out(`${line}; wrote ${tf}`);
  return 0;
}

/** Holdout accuracy (hits / covered) and coverage (covered / rows) at the stored thresholds, MEASURED; writes
 *  nothing. */
async function evaluate(io: Io, args: string[]): Promise<number> {
  const q = args[0];
  if (!q) { io.out(ORACLE_USAGE); return 64; }
  const all = replayFile(io.dir, q);
  if (typeof all === "string") { io.out(`oracle eval: ${all}`); return 2; }
  const { ids, rows } = planOf(io, all, "holdout");
  if (rows.length === 0) { io.out(`oracle eval ${q}: no holdout rows`); return 2; }
  const got = await replies(io, q, rows, ids);
  if (got === "nokey") { io.out(`oracle eval: ${NOKEY}`); return 2; }
  const thresholds = thresholdsOf(io.dir, q);
  const e = io.deps.core({ op: "oracle.eval", name: q, ...(thresholds ? { thresholds } : {}), replay: all, answers: got.answers });
  const cov = Number(e.covered), hits = Number(e.hits), n = Number(e.rows);
  const pct = (a: number, b: number) => (b > 0 ? `${((100 * a) / b).toFixed(1)} %` : "n/a");
  io.out(`oracle eval ${q} (MEASURED, holdout): thresholds ${JSON.stringify(thresholds)}, accuracy ${hits}/${cov} = ` +
    `${pct(hits, cov)}, coverage ${cov}/${n} = ${pct(cov, n)} (used ${e.used}, dropped ${e.dropped}; ${got.summary})`);
  return 0;
}

async function collect(io: Io, args: string[]): Promise<number> {
  const val = (k: string) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : undefined; };
  const runsFile = val("--runs"), out = val("--out");
  const max = Math.min(40, Number(val("--max") ?? 40));
  if (!runsFile || !out) { io.out(ORACLE_USAGE); return 64; }
  const runs = (JSON.parse(readFileSync(runsFile, "utf8")) as { databaseId: number; conclusion?: string; headSha?: string }[])
    .filter((r) => r.conclusion === undefined || r.conclusion === "failure").slice(0, max);
  const lines: string[] = [];
  for (const r of runs) {
    const fr = await failedRun(io.env(), String(r.databaseId), r.headSha);
    if (typeof fr === "string") { io.out(`${r.databaseId}: ${fr}`); continue; }
    const red = io.deps.core({ op: "oracle.request", name: "ci-triage", names: io.names, state: triageStateOf(io, fr.log) }).state;
    lines.push(JSON.stringify({ runId: r.databaseId, ...(fr.headSha ? { headSha: fr.headSha } : {}),
      state: red, label: null, labelSource: null }));
  }
  writeFileSync(out, lines.join("\n") + (lines.length ? "\n" : ""));
  io.out(`oracle collect: ${lines.length}/${runs.length} runs written to ${out}`);
  return 0;
}

/** `fw oracle ...`. */
export async function oracleCli(args: string[], cwd: string, io?: Io): Promise<number> {
  const [sub, ...rest] = args;
  let real: Io | undefined = io;
  try {
    real ??= { deps: realDeps(cwd), env: () => realEnv(cwd), dir: oracleDir(cwd), names: redactNames(cwd), out: (s) => console.log(s),
      git: gitIn(cwd) };
    if (sub === "triage") return await triage(real, rest);
    if (sub === "calibrate") return await calibrate(real, rest);
    if (sub === "eval") return await evaluate(real, rest);
    if (sub === "collect") return await collect(real, rest);
    real.out(ORACLE_USAGE);
    return 64;
  } catch (e) {
    (real?.out ?? console.error)(`oracle: ${errorText(e)}`);
    return 1;
  }
}
