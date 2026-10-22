import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { parseFlags, UsageError } from "./lib.ts";
import { fwcoreCall, type FwCall } from "./run.ts";

const USAGE = "usage: fw ci pool route --state <json|@file> --reqs <json|@file> [--cfg phase1|enterprise] [--over <json|@file>] [--json]\n       fw ci pool consts [--cfg phase1|enterprise] [--over <json|@file>]\n       fw ci pool tier | tier-consts | dispatch (the three-tier pool, Fw.Ci.PoolTier)";

/** A flag value as JSON: inline, or `@path` read relative to `cwd`. */
export function jsonArg(v: string, cwd: string, what: string): unknown {
  const text = v.startsWith("@") ? readFileSync(resolve(cwd, v.slice(1)), "utf8") : v;
  try { return JSON.parse(text); } catch { throw new UsageError(`--${what}: not JSON`); }
}

/** The fwcore request of `fw ci pool <verb>`. */
export function poolRequest(argv: string[], cwd: string): Record<string, unknown> {
  const [verb, ...rest] = argv;
  const { pos, flags } = parseFlags(rest.filter((a) => a !== "--json"));
  if (pos.length) throw new UsageError(`unexpected argument ${pos[0]}\n${USAGE}`);
  const base: Record<string, unknown> = { cfg: flags.cfg ?? "phase1" };
  if (flags.over) base.over = jsonArg(flags.over, cwd, "over");
  if (verb === "consts") return { op: "ci.poolConsts", ...base };
  if (verb !== "route") throw new UsageError(USAGE);
  if (!flags.state || !flags.reqs) throw new UsageError(`route needs --state and --reqs\n${USAGE}`);
  return { op: "ci.poolRoute", ...base, state: jsonArg(flags.state, cwd, "state"), reqs: jsonArg(flags.reqs, cwd, "reqs") };
}

type Row = { lane: string; rep: number; attempt: number; decision: string; outcome?: string; target?: { via: string; os: string; cls: string; engine: string; timeoutMin: number; credits: number } };

/** One printed line per routed request. */
export function rowLine(r: Row): string {
  const head = `${r.lane} rep ${r.rep} attempt ${r.attempt}: ${r.decision}`;
  if (r.target) return `${head} ${r.target.via}/${r.target.os} ${r.target.cls} ${r.target.engine} timeout ${r.target.timeoutMin} min, ${r.target.credits} credits`;
  return r.outcome ? `${head} ${r.outcome}` : head;
}

export function poolMain(argv: string[], cwd: string, call: FwCall, log: (l: string) => void): number {
  const req = poolRequest(argv, cwd);
  const reply = call(req);
  if (argv.includes("--json") || req.op === "ci.poolConsts") {
    log(JSON.stringify(reply, null, 2));
    return 0;
  }
  for (const r of reply.log as Row[]) log(rowLine(r));
  log(`sent ${reply.sent}, waiting ${reply.waiting}, done ${reply.done}; macFree ${reply.macFree}, expWaitS ${reply.expWaitS}`);
  return 0;
}

export async function poolCli(argv: string[], cwd: string): Promise<number> {
  if (["tier", "tier-consts", "dispatch"].includes(argv[0] ?? "")) return (await import("./ci-pool-tier.ts")).tierCli(argv, cwd);
  return poolMain(argv, cwd, fwcoreCall(cwd), (l) => console.log(l));
}
