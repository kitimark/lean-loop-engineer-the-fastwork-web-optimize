import { spawnSync } from "node:child_process";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { jsonArg } from "./ci-pool.ts";
import { parseFlags, UsageError } from "./lib.ts";
import { fwcoreCall, type FwCall } from "./run.ts";

const USAGE = [
  "usage: fw ci pool tier --state <json|@file> --reqs <json|@file> [--over <json|@file>] [--json]",
  "       fw ci pool tier-consts [--over <json|@file>]",
  "       fw ci pool dispatch --branch ci/<name> --state <json|@file> --reqs <json|@file> [--over <json|@file>] [--go]",
].join("\n");

const BRANCH = /^ci\/[A-Za-z0-9._/-]+$/;

/** The fwcore request of `fw ci pool tier` and `tier-consts`. */
export function tierRequest(argv: string[], cwd: string): Record<string, unknown> {
  const [verb, ...rest] = argv;
  const { pos, flags } = parseFlags(rest.filter((a) => a !== "--json" && a !== "--go"));
  if (pos.length) throw new UsageError(`unexpected argument ${pos[0]}\n${USAGE}`);
  const base: Record<string, unknown> = flags.over ? { over: jsonArg(flags.over, cwd, "over") } : {};
  if (verb === "tier-consts") return { op: "ci.poolTierConsts", ...base };
  if (verb !== "tier" && verb !== "dispatch") throw new UsageError(USAGE);
  if (!flags.state || !flags.reqs) throw new UsageError(`${verb} needs --state and --reqs\n${USAGE}`);
  return { op: "ci.poolTier", ...base, state: jsonArg(flags.state, cwd, "state"), reqs: jsonArg(flags.reqs, cwd, "reqs") };
}

/** The ledger facts the route reads for the two extra tiers. */
export type TierFacts = { cmUsed: number; cmBusy: number; ccSpent: number; ccStorage: number };

/** The state with each tier fact the caller left out taken from the ledgers. */
export function fillFacts(state: Record<string, unknown>, facts: TierFacts): Record<string, unknown> {
  const out = { ...state };
  for (const [k, v] of Object.entries(facts)) if (out[k] === undefined) out[k] = v;
  return out;
}

type Target = { via: string; os: string; cls: string; engine: string; timeoutMin: number; credits: number };
type Row = { lane: string; rep: number; attempt: number; via: string | null; decision: string; outcome?: string; target?: Target };

/** One dispatch step: the provider and the command that starts it (none for GitHub, which the push starts, and for a row that does not run). */
export type Step = { lane: string; rep: number; via: string | null; decision: string; cmd: string[] | null; note: string };

/** The dispatch plan of a `ci.poolTier` reply for the jobs of `branch`. */
export function dispatchPlan(log: Row[], branch: string): Step[] {
  return log.map((r) => {
    const head = { lane: r.lane, rep: r.rep, via: r.via, decision: r.decision };
    if (r.decision === "codemagic") return { ...head, cmd: ["scripts/codemagic.mjs", "trigger", "--pool", "--branch", branch], note: `codemagic ${r.target!.cls}, cap ${r.target!.timeoutMin} min` };
    if (r.decision === "run" && r.via === "circleci") return { ...head, cmd: ["scripts/circleci.mjs", "trigger", "--lane", r.lane, "--branch", branch], note: `circleci ${r.target!.cls}, timeout ${r.target!.timeoutMin} min, ${r.target!.credits} credits` };
    if (r.decision === "run") return { ...head, cmd: null, note: `${r.via} ${r.target!.os} ${r.target!.cls}: the push of ${branch} runs it` };
    return { ...head, cmd: null, note: r.outcome ? `${r.decision} ${r.outcome}` : r.decision };
  });
}

/** The printed line of a step. */
export const stepLine = (s: Step): string => `${s.lane} rep ${s.rep}: ${s.note}${s.cmd ? ` -> node ${s.cmd.join(" ")}` : ""}`;

/** Codemagic minutes used and builds not yet fetched (`codemagic.mjs facts`), CircleCI credits and storage (`circleci.mjs` ledger). */
export async function readFacts(root: string): Promise<TierFacts> {
  const r = spawnSync(process.execPath, [join(root, "scripts/codemagic.mjs"), "facts"], { cwd: root, encoding: "utf8" });
  if (r.status !== 0) throw new Error(`codemagic facts failed: ${r.stderr.trim()}`);
  const cm = JSON.parse(r.stdout.trim().split("\n").pop()!) as { used: number; busy: number };
  const cc = (await import(pathToFileURL(join(root, "scripts/circleci.mjs")).href)) as {
    creditsSoFar: (ctx: { ledgerPath: string }) => number; storageSoFar: (ctx: { ledgerPath: string }) => number };
  const ctx = { ledgerPath: join(root, ".local", "circleci-ledger.json") };
  return { cmUsed: cm.used, cmBusy: cm.busy, ccSpent: cc.creditsSoFar(ctx), ccStorage: cc.storageSoFar(ctx) };
}

export type Io = { call: FwCall; facts: () => Promise<TierFacts>; run: (cmd: string[]) => number; log: (l: string) => void };

export async function tierMain(argv: string[], cwd: string, io: Io): Promise<number> {
  const req = tierRequest(argv, cwd);
  if (req.op === "ci.poolTierConsts") { io.log(JSON.stringify(io.call(req), null, 2)); return 0; }
  const dispatch = argv[0] === "dispatch";
  const branch = parseFlags(argv.slice(1).filter((a) => a !== "--json" && a !== "--go")).flags.branch;
  if (dispatch && !BRANCH.test(branch ?? "")) throw new UsageError(`dispatch needs --branch ci/<name>\n${USAGE}`);
  if (dispatch) req.state = fillFacts(req.state as Record<string, unknown>, await io.facts());
  const reply = io.call(req);
  if (argv.includes("--json")) { io.log(JSON.stringify(reply, null, 2)); if (!dispatch) return 0; }
  const plan = dispatchPlan(reply.log as Row[], branch ?? "ci/<branch>");
  for (const s of plan) io.log(stepLine(s));
  io.log(`counts ${JSON.stringify(reply.counts)}; inflight ${reply.inflight} of ${reply.macCap}; state ${JSON.stringify(reply.state)}`);
  if (!dispatch || !argv.includes("--go")) return 0;
  let code = 0;
  for (const s of plan.filter((p) => p.cmd)) {
    const c = io.run(s.cmd!);
    io.log(`${s.via} ${s.lane} rep ${s.rep}: exit ${c}${c === 5 ? " (the provider's stop rule refused)" : ""}`);
    if (c !== 0 && code === 0) code = c;
  }
  return code;
}

export async function tierCli(argv: string[], cwd: string): Promise<number> {
  const root = new URL("../../..", import.meta.url).pathname;
  return tierMain(argv, cwd, {
    call: fwcoreCall(cwd),
    facts: () => readFacts(root),
    run: (cmd) => spawnSync(process.execPath, [join(root, cmd[0]!), ...cmd.slice(1)], { cwd: root, stdio: "inherit" }).status ?? 1,
    log: (l) => console.log(l),
  });
}
