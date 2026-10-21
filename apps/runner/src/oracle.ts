// `fw oracle`: typed answers from an outside model (TypeSafe Jev) for decisions we cannot script, used only as
// advice. Every decision is fwcore's (`oracle.*`, lean/Fw/Oracle): declared fields, redaction, request body, send
// gate and caps, validation, policy, calibration, whether a threshold table may be written. This file is I/O: files,
// the keychain (through packages/oracle, read only after Lean's `oracle.pre` says send), printing.
//   fw oracle ask <question> --state <state.json> [--thresholds <table.json>] [--json]
//       advice on one state, or escalate with a reason; no table means uncalibrated (always escalate)
//   fw oracle calibrate <question> --replay <rows.jsonl> [--limit n] [--resume] [--out <table.json>]
//       calls over every labeled row (ids from Lean's oracle.plan; logged answers replay; run cap 60); Lean chooses
//       the per-option thresholds on the choose part and keeps those whose held-out Wilson lower bound reaches the
//       target; written to --out only when every labeled id has an answer (Lean's mayWrite), else exit 2. --resume
//       first checks that the rows missing from the answer log fit in the run cap (exit 2 if not)
//   fw oracle eval <question> --replay <rows.jsonl> --thresholds <table.json>
//       holdout part: accuracy and coverage at the stored thresholds (MEASURED)
import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { userInfo } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fwcoreCall } from "@fw/gh-budget";
import { ask, decisionLine, errorText, keychainKey, loggedReply, readLog, sha256, type Deps, type FwCall,
  type Json } from "@fw/oracle";
import { begin } from "./timing.ts";

export const ORACLE_USAGE = "usage: fw oracle ask <question> --state <state.json> [--thresholds <table.json>] [--json] | " +
  "fw oracle calibrate <question> --replay <rows.jsonl> [--limit n] [--resume] [--out <table.json>] | " +
  "fw oracle eval <question> --replay <rows.jsonl> --thresholds <table.json>";

/** The answer log: FW_ORACLE_LOG, else FW_CONSOLE_DIR, else the main checkout's .fw-console (gitignored). */
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

/** The threshold table of a question in a table file (question to {thresholds, ...}), or null when the file or the
 *  question is absent. */
export function thresholdsOf(file: string | undefined, question: string): Json | null {
  if (file === undefined || !existsSync(file)) return null;
  const t = (JSON.parse(readFileSync(file, "utf8")) as Record<string, { thresholds?: Json | null } | null>)[question];
  return t?.thresholds ?? null;
}

/** The real dependencies of the client. */
export function realDeps(cwd: string, core: FwCall = fwcoreCall(cwd)): Deps {
  return {
    core, fetch: globalThis.fetch, readKey: keychainKey, logPath: logPathFor(cwd), now: () => new Date(),
    span: (step) => begin("oracle", step, cwd),
  };
}

/** Testable seams of the CLI: relative paths resolve against `cwd`. */
export type Io = { deps: Deps; cwd: string; names: string[]; out: (s: string) => void };

/** A replay row (`<rows>.jsonl`). A row whose `label` is null is left out; Lean (`oracle.plan`, `heldOut`) puts each
 *  labeled row in the choose or the holdout part by its id (a `split` key is refused). The state is sent as stored;
 *  Lean redacts it again before building the body. */
export type ReplayRow = { state: Record<string, string | string[]>; label: string | null; runId?: number; id?: string };

/** The value after flag `k`, if any. */
const flag = (args: string[], k: string): string | undefined => {
  const i = args.indexOf(k);
  return i >= 0 ? args[i + 1] : undefined;
};

/** Every row of a replay file, in file order, or the reason it cannot be read. */
export function replayFile(file: string): ReplayRow[] | string {
  if (!existsSync(file)) return `no replay file ${file}`;
  return readFileSync(file, "utf8").split("\n").filter((l) => l.trim()).map((l) => JSON.parse(l) as ReplayRow);
}

async function askCli(io: Io, args: string[]): Promise<number> {
  const q = args[0], sf = flag(args, "--state");
  if (!q || q.startsWith("-") || !sf) { io.out(ORACLE_USAGE); return 64; }
  const state = JSON.parse(readFileSync(resolve(io.cwd, sf), "utf8")) as Record<string, string | string[]>;
  const tf = flag(args, "--thresholds");
  const r = await ask(io.deps, { question: q, state, names: io.names,
    thresholds: thresholdsOf(tf === undefined ? undefined : resolve(io.cwd, tf), q) });
  io.out(args.includes("--json") ? JSON.stringify({ question: q, source: r.source, ...r.decision })
    : `oracle ${q}: ${decisionLine(r.decision)} [${r.source}]`);
  return 0;
}

/** Ask every row (no thresholds: only the replies matter); stops on a missing key. `answers` has one entry per row
 *  that got a reply text (logged or live), with the id Lean gave it. */
async function replies(io: Io, q: string, rows: ReplayRow[], ids: string[]):
    Promise<{ answers: { id: string; reply: string }[]; summary: string } | "nokey"> {
  const answers: { id: string; reply: string }[] = [];
  const counts: Record<string, number> = {};
  let sent = 0;
  for (const [i, row] of rows.entries()) {
    const r = await ask(io.deps, { question: q, state: row.state, names: io.names, thresholds: null, run: sent });
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
  const q = args[0], rf = flag(args, "--replay");
  if (!q || q.startsWith("-") || !rf) { io.out(ORACLE_USAGE); return 64; }
  const lim = flag(args, "--limit");
  const limit = lim !== undefined ? Number(lim) : undefined;
  if (limit !== undefined && !(Number.isInteger(limit) && limit >= 0)) { io.out(ORACLE_USAGE); return 64; }
  const all = replayFile(resolve(io.cwd, rf));
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
  const out = flag(args, "--out");
  if (out === undefined) { io.out(line); return 0; }
  const tf = resolve(io.cwd, out);
  const table = existsSync(tf) ? JSON.parse(readFileSync(tf, "utf8")) as Record<string, unknown> : {};
  const model = String(io.deps.core({ op: "oracle.question", name: q }).model);
  table[q] = { thresholds: c.thresholds, choose: c.choose, holdout: c.holdout, used: c.used, dropped: c.dropped,
    rows: c.labeled, model, measuredOn: io.deps.now().toISOString().slice(0, 10), status: "MEASURED" };
  writeFileSync(tf, JSON.stringify(table, null, 2) + "\n");
  io.out(`${line}; wrote ${out}`);
  return 0;
}

/** Holdout accuracy (hits / covered) and coverage (covered / rows) at the stored thresholds, MEASURED; writes
 *  nothing. */
async function evaluate(io: Io, args: string[]): Promise<number> {
  const q = args[0], rf = flag(args, "--replay"), tf = flag(args, "--thresholds");
  if (!q || q.startsWith("-") || !rf || !tf) { io.out(ORACLE_USAGE); return 64; }
  const all = replayFile(resolve(io.cwd, rf));
  if (typeof all === "string") { io.out(`oracle eval: ${all}`); return 2; }
  const thresholds = thresholdsOf(resolve(io.cwd, tf), q);
  if (thresholds === null) { io.out(`oracle eval ${q}: no thresholds for ${q} in ${tf}`); return 2; }
  const { ids, rows } = planOf(io, all, "holdout");
  if (rows.length === 0) { io.out(`oracle eval ${q}: no holdout rows`); return 2; }
  const got = await replies(io, q, rows, ids);
  if (got === "nokey") { io.out(`oracle eval: ${NOKEY}`); return 2; }
  const e = io.deps.core({ op: "oracle.eval", name: q, thresholds, replay: all, answers: got.answers });
  const cov = Number(e.covered), hits = Number(e.hits), n = Number(e.rows);
  const pct = (a: number, b: number) => (b > 0 ? `${((100 * a) / b).toFixed(1)} %` : "n/a");
  io.out(`oracle eval ${q} (MEASURED, holdout): thresholds ${JSON.stringify(thresholds)}, accuracy ${hits}/${cov} = ` +
    `${pct(hits, cov)}, coverage ${cov}/${n} = ${pct(cov, n)} (used ${e.used}, dropped ${e.dropped}; ${got.summary})`);
  return 0;
}

/** `fw oracle ...`. */
export async function oracleCli(args: string[], cwd: string, io?: Io): Promise<number> {
  const [sub, ...rest] = args;
  let real: Io | undefined = io;
  try {
    real ??= { deps: realDeps(cwd), cwd, names: redactNames(cwd), out: (s) => console.log(s) };
    if (sub === "ask") return await askCli(real, rest);
    if (sub === "calibrate") return await calibrate(real, rest);
    if (sub === "eval") return await evaluate(real, rest);
    real.out(ORACLE_USAGE);
    return 64;
  } catch (e) {
    (real?.out ?? console.error)(`oracle: ${errorText(e)}`);
    return 1;
  }
}
