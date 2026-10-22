import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { userInfo } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fwcoreCall } from "@fw/gh-budget";
import { ask, decisionLine, errorText, keychainKey, loggedReply, readLog, sha256, type Deps, type FwCall,
  type Json } from "@fw/oracle";
import { ARMS, armAnswers, armPrompt, bodyOf, jevAnswers, scoreArm, writeResult } from "./oracle-score.ts";
import { begin } from "./timing.ts";

export const ORACLE_USAGE = "usage: fw oracle ask <question> --state <state.json> [--thresholds <table.json>] [--json] | " +
  "fw oracle calibrate <question> --replay <rows.jsonl> [--limit n] [--resume] [--out <table.json>] | " +
  "fw oracle eval <question> --replay <rows.jsonl> --thresholds <table.json> | " +
  "fw oracle send --set <d1|d2> [--part calibrate|holdout] [--limit n] | " +
  "fw oracle score --set <d1|d2> [--arm jev|haiku|sonnet] [--answers <arm.jsonl>] [--dir] [--out <results.json>] | " +
  "fw oracle arm-input --set <d1|d2> --out <prompts.jsonl> [--dir]";

export function logPathFor(cwd: string, env: NodeJS.ProcessEnv = process.env): string {
  if (env.FW_ORACLE_LOG) return env.FW_ORACLE_LOG;
  const common = execFileSync("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd }).toString().trim();
  return join(env.FW_CONSOLE_DIR ?? join(dirname(common), ".fw-console"), "oracle.jsonl");
}

export function redactNames(cwd: string): string[] {
  const cfg = (k: string) => spawnSync("git", ["config", k], { cwd, encoding: "utf8" }).stdout?.trim() ?? "";
  const git = cfg("user.name");
  const email = cfg("user.email");
  let login = "";
  try { login = userInfo().username; } catch { }
  return [...new Set([git, ...git.split(/\s+/), email, login].filter((w) => w.length >= 3))];
}

export function thresholdsOf(file: string | undefined, question: string): Json | null {
  if (file === undefined || !existsSync(file)) return null;
  const t = (JSON.parse(readFileSync(file, "utf8")) as Record<string, { thresholds?: Json | null } | null>)[question];
  return t?.thresholds ?? null;
}

export function realDeps(cwd: string, core: FwCall = fwcoreCall(cwd)): Deps {
  return {
    core, fetch: globalThis.fetch, readKey: keychainKey, logPath: logPathFor(cwd), now: () => new Date(),
    span: (step) => begin("oracle", step, cwd),
  };
}

export type Io = { deps: Deps; cwd: string; names: string[]; out: (s: string) => void; datasets?: string };

export type ReplayRow = { state: Record<string, string | string[]>; label: string | null; runId?: number; id?: string };

const flag = (args: string[], k: string): string | undefined => {
  const i = args.indexOf(k);
  return i >= 0 ? args[i + 1] : undefined;
};

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

function loggedRows(io: Io, q: string, rows: ReplayRow[]): boolean[] {
  const entries = readLog(io.deps.logPath);
  return rows.map((r) => {
    const body = String(io.deps.core({ op: "oracle.request", name: q, names: io.names, state: r.state }).bodyText);
    return loggedReply(entries, sha256(body)) !== undefined;
  });
}

function planOf(io: Io, all: ReplayRow[], part?: "holdout", limit?: number): { ids: string[]; rows: ReplayRow[] } {
  const plan = io.deps.core({ op: "oracle.plan", rows: all, ...(part ? { part } : {}), ...(limit !== undefined ? { limit } : {}) });
  return { ids: plan.ids as string[], rows: (plan.indices as number[]).map((i) => all[i]!) };
}

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

/** The datasets directory of task jev-datasets: `.cache/jev` of the main checkout (gitignored). */
export function datasetsDir(cwd: string): string {
  const common = execFileSync("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd }).toString().trim();
  return join(dirname(common), ".cache", "jev");
}

/** One row as `oracle.replay` gives it. */
export type Picked = { id: string; label: string; part: string; state: Record<string, string | string[]> };

/** The rows of a replay set to send, as Lean picks them (`oracle.replay`), or the reason they cannot be read. */
export function pickedRows(core: FwCall, set: string, dir: string, extra: Json = {}):
    { question: string; rows: Picked[]; reply: Json } | string {
  const head = core({ op: "oracle.replay", set, rows: [] });
  const file = join(dir, String(head.file));
  if (!existsSync(file)) return `no dataset ${file} (run node scripts/jev-datasets.mjs first)`;
  const rows = readFileSync(file, "utf8").split("\n").filter((l) => l.trim()).map((l) => JSON.parse(l) as Json);
  const r = core({ op: "oracle.replay", set, rows, ...extra });
  return { question: String(r.question), rows: r.rows as Picked[], reply: r };
}

const SEND_FLAGS = ["--set", "--part", "--limit"];

async function sendSet(io: Io, args: string[]): Promise<number> {
  const set = flag(args, "--set");
  const part = flag(args, "--part");
  const lim = flag(args, "--limit");
  const limit = lim !== undefined ? Number(lim) : undefined;
  const known = args.every((a, k) => k % 2 === 1 || SEND_FLAGS.includes(a)) && args.length % 2 === 0;
  if (!known || !set || (limit !== undefined && !(Number.isInteger(limit) && limit >= 0))) { io.out(ORACLE_USAGE); return 64; }
  const picked = pickedRows(io.deps.core, set, io.datasets ?? datasetsDir(io.cwd),
    { ...(part !== undefined ? { part } : {}), ...(limit !== undefined ? { limit } : {}) });
  if (typeof picked === "string") { io.out(`oracle send: ${picked}`); return 2; }
  const counts: Record<string, number> = {};
  let sent = 0, spent = 0, done = 0, stop = "";
  for (const row of picked.rows) {
    const r = await ask(io.deps, { question: picked.question, state: row.state, names: io.names, thresholds: null,
      replayRun: { sent, spent } });
    counts[r.source] = (counts[r.source] ?? 0) + 1;
    if (r.sent) { sent++; spent += r.tokens ?? 0; }
    if (r.source === "replay" || r.source === "live") done++;
    if (r.source === "nokey") { stop = "no key"; break; }
    if (r.source === "refused") {
      stop = (r.decision.reason as { failure?: { kind?: string } } | undefined)?.failure?.kind ?? "refused";
      break;
    }
  }
  const n = picked.rows.length;
  const tally = Object.entries(counts).map(([k, v]) => `${k} ${v}`).join(", ") || "none";
  io.out(`oracle send ${set} (${picked.question}): ${done}/${n} answered (${tally}); sent ${sent}, estimated input ` +
    `tokens ${spent}${stop ? `; stopped: ${stop}` : ""}${done < n ? "; run again to send the rest (logged answers replay)" : ""}`);
  return done === n ? 0 : 2;
}

function pickedOf(io: Io, args: string[]): ReturnType<typeof pickedRows> | undefined {
  const set = flag(args, "--set");
  if (!set) return undefined;
  const dir = flag(args, "--dir");
  return pickedRows(io.deps.core, set, dir !== undefined ? resolve(io.cwd, dir) : io.datasets ?? datasetsDir(io.cwd));
}

async function scoreCli(io: Io, args: string[]): Promise<number> {
  const set = flag(args, "--set");
  const arm = flag(args, "--arm") ?? "jev";
  const file = flag(args, "--answers");
  const picked = pickedOf(io, args);
  if (!set || picked === undefined || !(ARMS as readonly string[]).includes(arm) || (arm !== "jev") !== (file !== undefined)) {
    io.out(ORACLE_USAGE);
    return 64;
  }
  if (typeof picked === "string") { io.out(`oracle score: ${picked}`); return 2; }
  const answers = arm === "jev"
    ? jevAnswers(io.deps.core, picked.question, io.names, picked.rows, io.deps.logPath)
    : armAnswers(resolve(io.cwd, file!));
  const score = scoreArm(io.deps.core, picked.question, arm, picked.rows, answers);
  const { rows: _rows, ...head } = picked.reply;
  const out = resolve(io.cwd, flag(args, "--out") ?? join("results", "jev", `${set}.json`));
  writeResult(out, head, arm, score);
  const all = score.all as { right: number; rows: number };
  io.out(`oracle score ${set} ${arm} (${picked.question}): right ${all.right}/${all.rows}, missing ${String(score.missing)}; ` +
    `wrote ${out}`);
  return score.missing === 0 ? 0 : 2;
}

async function armInputCli(io: Io, args: string[]): Promise<number> {
  const out = flag(args, "--out");
  const picked = pickedOf(io, args);
  if (out === undefined || picked === undefined) { io.out(ORACLE_USAGE); return 64; }
  if (typeof picked === "string") { io.out(`oracle arm-input: ${picked}`); return 2; }
  const lines = picked.rows.map((r) => JSON.stringify({ id: r.id, prompt: armPrompt(bodyOf(io.deps.core, picked.question, io.names, r)) }));
  writeFileSync(resolve(io.cwd, out), lines.join("\n") + "\n");
  io.out(`oracle arm-input ${flag(args, "--set")}: ${lines.length} prompts in ${out}`);
  return 0;
}

export const ORACLE_SUBS = ["ask", "calibrate", "eval", "send", "score", "arm-input"] as const;

export async function oracleCli(args: string[], cwd: string, io?: Io): Promise<number> {
  const [sub, ...rest] = args;
  let real: Io | undefined = io;
  try {
    real ??= { deps: realDeps(cwd), cwd, names: redactNames(cwd), out: (s) => console.log(s) };
    if (sub === "ask") return await askCli(real, rest);
    if (sub === "calibrate") return await calibrate(real, rest);
    if (sub === "eval") return await evaluate(real, rest);
    if (sub === "send") return await sendSet(real, rest);
    if (sub === "score") return await scoreCli(real, rest);
    if (sub === "arm-input") return await armInputCli(real, rest);
    real.out(ORACLE_USAGE);
    return 64;
  } catch (e) {
    (real?.out ?? console.error)(`oracle: ${errorText(e)}`);
    return 1;
  }
}
