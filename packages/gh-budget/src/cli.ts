// `fw ci wait` and `fw ci budget` (also runnable as `node packages/gh-budget/src/cli.ts wait ...`).
import { spawnSync } from "node:child_process";
import { cleanups, waitFor, type Target } from "./wait.ts";
import { realEnv, type Env, type Json } from "./core.ts";
import { ghCharged } from "./charged.ts";
import { loadState, paths, readJson, stepEvent } from "./state.ts";

export const WAIT_USAGE = [
  "usage: fw ci wait <runId> [--timeout s]",
  "       fw ci wait --branch <ci/x> [--workflow <name>] [--sha <sha>] [--since <epoch>] [--timeout s]",
  "  Blocks on the shared poller's local file (no GitHub call of its own). Exit 0: success, 1: failure,",
  "  3: timeout or the poller stopped (call it again), 2: gh could not find the run. Prints `run <id> <workflow> <conclusion>`.",
  "  With --branch it follows the NEWEST run of each workflow created after the commit (superseded runs are cancelled).",
  "usage: fw ci budget [--json] [--resume] [--probe]   (0 requests; --probe makes 1 charged `gh run list --limit 1`)",
].join("\n");

class Usage extends Error {}

const DEFAULT_TIMEOUT_S = 540; // fits one Bash tool call (the Bash tool's cap is 600 s)

function git(cwd: string, args: string[]): string {
  const r = spawnSync("git", args, { cwd, encoding: "utf8" });
  return r.status === 0 ? r.stdout.trim() : "";
}

export function parseWait(argv: string[], cwd: string): { target: Target; timeoutS: number } {
  let timeoutS = DEFAULT_TIMEOUT_S;
  let branch: string | undefined, workflow: string | undefined, sha: string | undefined, since: number | undefined, runId: number | undefined;
  const val = (i: number, f: string) => { const v = argv[i + 1]; if (v === undefined || v.startsWith("--")) throw new Usage(`flag ${f} needs a value\n${WAIT_USAGE}`); return v; };
  for (let i = 0; i < argv.length; i++) {
    const f = argv[i]!;
    if (f === "--timeout") timeoutS = Number(val(i++, f));
    else if (f === "--branch") branch = val(i++, f);
    else if (f === "--workflow") workflow = val(i++, f);
    else if (f === "--sha") sha = val(i++, f);
    else if (f === "--since") since = Number(val(i++, f));
    else if (/^[0-9]+$/.test(f) && runId === undefined) runId = Number(f);
    else throw new Usage(`unexpected argument ${f}\n${WAIT_USAGE}`);
  }
  if (!Number.isFinite(timeoutS) || timeoutS <= 0) throw new Usage(`--timeout must be a positive number\n${WAIT_USAGE}`);
  if ((runId === undefined) === (branch === undefined)) throw new Usage(`give a run id or --branch, not both and not neither\n${WAIT_USAGE}`);
  if (runId !== undefined) return { target: { kind: "run", runId }, timeoutS };
  const b = branch!;
  const s = sha ?? (git(cwd, ["rev-parse", "--verify", "-q", `refs/remotes/origin/${b}^{commit}`]) || git(cwd, ["rev-parse", "--verify", "-q", `refs/heads/${b}^{commit}`]));
  if (!s) throw new Usage(`cannot resolve the commit of branch ${b} (push it first, or pass --sha)\n${WAIT_USAGE}`);
  const at = since ?? Number(git(cwd, ["log", "-1", "--format=%ct", s]));
  if (!Number.isFinite(at) || at <= 0) throw new Usage(`cannot read the commit time of ${s} (pass --since <epoch>)\n${WAIT_USAGE}`);
  return { target: { kind: "branch", branch: b, ...(workflow ? { workflow } : {}), sha: s, since: at }, timeoutS };
}

async function budget(env: Env, argv: string[]): Promise<number> {
  const bad = argv.find((a) => !["--json", "--resume", "--probe"].includes(a));
  if (bad) throw new Usage(`unexpected argument ${bad}\n${WAIT_USAGE}`);
  if (argv.includes("--resume")) stepEvent(env, { resume: true });
  if (argv.includes("--probe")) {
    const p = await ghCharged(env, ["run", "list", "--limit", "1"], { cost: 2 });
    console.log(p.ran ? `probe: gh exited ${p.code}, HTTP ${p.status ?? "?"}${p.error ? `, ${p.error}` : ""}` : `probe: not made (${p.decision}${"until" in p ? ` until ${p.until}` : ""}, ${p.reason})`);
  }
  const r = env.core({ op: "ci.budget.status", now: env.now(), state: loadState(env.dir) });
  const st = r.state as Json;
  const { ledger: _l, ...state } = st;
  if (argv.includes("--json")) { console.log(JSON.stringify({ ...r, state })); return 0; }
  const L = r.limits as { shares: Record<"tick" | "oneoff", { hour: number; minute: number }>; B: number; F: number };
  const u = r.used as Record<"tick" | "oneoff", { hour: number; minute: number }>;
  const holder = readJson<{ pid: number }>(paths(env.dir).poller);
  console.log(`requests in the last hour: tick ${u.tick.hour}/${L.shares.tick.hour}, one-off ${u.oneoff.hour}/${L.shares.oneoff.hour} (cap ${L.B})`);
  console.log(`last minute: tick ${u.tick.minute}/${L.shares.tick.minute}, one-off ${u.oneoff.minute}/${L.shares.oneoff.minute}`);
  console.log(`GitHub says: remaining ${st.remaining ?? "unknown"}, reset ${st.reset ?? "unknown"} (floor ${L.F}); retry-until ${r.retryUntil}, failures ${r.fails}`);
  console.log(`poll interval ${r.interval} s, headroom ${r.headroom ? "yes" : "no"}, watched runs ${r.watched}, list created>= ${r.createdSince ?? "-"}, poller pid ${holder?.pid ?? "none"}`);
  return 0;
}

/** Entry for `fw ci wait|budget`; returns the exit code. */
export async function ghBudgetCli(argv: string[], cwd: string): Promise<number> {
  const [cmd, ...rest] = argv;
  try {
    if (cmd !== "wait" && cmd !== "budget") throw new Usage(WAIT_USAGE);
    const parsed = cmd === "wait" ? parseWait(rest, cwd) : null;
    const env = realEnv(cwd);
    const onSig = (sig: NodeJS.Signals) => () => { for (const c of [...cleanups]) { try { c(); } catch { /* best effort */ } } process.exit(sig === "SIGINT" ? 130 : 143); };
    process.once("SIGINT", onSig("SIGINT"));
    process.once("SIGTERM", onSig("SIGTERM"));
    if (!parsed) return await budget(env, rest);
    const res = await waitFor(env, parsed.target, { timeoutS: parsed.timeoutS });
    for (const l of res.lines) (res.code === 0 || res.code === 1 ? console.log : console.error)(l);
    return res.code;
  } catch (e) {
    console.error(e instanceof Error ? e.message : String(e));
    return e instanceof Usage ? 64 : 1;
  }
}

if (import.meta.main) process.exitCode = await ghBudgetCli(process.argv.slice(2), process.cwd());
