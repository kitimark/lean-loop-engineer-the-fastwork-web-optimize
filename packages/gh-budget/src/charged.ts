// `ghCharged`: the one wrapper for every gh call our tools make. Under the state lock: ask fwcore (reserve or next);
// on `issue` run gh with GH_DEBUG=api, keep ONLY the status line, x-ratelimit-*, retry-after and etag of the response
// headers, drop the rest of the trace at once (bodies can name accounts), and hand those lines to `ci.budget.observe`.
// The glue never reads or prints a token and never calls `gh api`.
import { spawnSync } from "node:child_process";
import type { Env, GhOut, Json } from "./core.ts";
import { LockBusy } from "./lock.ts";
import { loadState, locked, saveState } from "./state.ts";

/** Response header lines worth keeping from a GH_DEBUG=api trace (httpretty prints response headers as `< Name: value`). */
const KEEP = /^< (HTTP\/\S+ \d{3}\b.*|x-ratelimit-[a-z-]+:.*|retry-after:.*|etag:.*)$/i;

/** The kept lines of a debug trace. Everything else (request lines, bodies, other headers) is dropped here. */
export function traceLines(stderr: string): string[] {
  const out: string[] = [];
  for (const raw of stderr.split("\n")) {
    const l = raw.replace(/\r$/, "");
    if (l.length < 400 && KEEP.test(l)) out.push(l);
  }
  return out;
}

/** What went wrong, in terms that cannot carry a body: `HTTP 403: message` if gh printed one, else the exit code. */
export function errorSummary(stderr: string, code: number | null): string {
  const m = /^(HTTP \d{3}):? ([^\n(]{0,100})/m.exec(stderr);
  return m ? `${m[1]}: ${m[2]!.trim()}` : `gh exited with ${code ?? "a signal"}`;
}

export type Ran = {
  ran: true; kind: string; cost: number; code: number | null; status: number | null;
  stdout: string; lines: string[]; error?: string; now: number; reply: Json; state: Json;
};
export type NotRan =
  | { ran: false; decision: "wait"; until: number; reason: string }
  | { ran: false; decision: "stop"; reason: string }
  | { ran: false; decision: "busy"; reason: string };
export type Charged = Ran | NotRan;

export type Decide = (state: Json | null, now: number) => Json;

export function chargedOnce(env: Env, decide: Decide, buildArgs: (reply: Json) => string[], timeoutMs = 60_000, lockWaitMs = 120_000): Charged {
  try {
    return chargedLocked(env, decide, buildArgs, timeoutMs, lockWaitMs);
  } catch (e) {
    if (e instanceof LockBusy) return { ran: false, decision: "busy", reason: `the gh budget lock stayed held by another fw process for ${lockWaitMs / 1000} s` };
    throw e;
  }
}

function chargedLocked(env: Env, decide: Decide, buildArgs: (reply: Json) => string[], timeoutMs: number, lockWaitMs: number): Charged {
  return locked(env, () => {
    const s = loadState(env.dir);
    const r = decide(s, env.now());
    saveState(env.dir, r.state as Json); // the booking (or the advanced clock) is on disk before gh starts
    if (r.decision === "wait") return { ran: false, decision: "wait", until: Number(r.until), reason: String(r.reason) };
    if (r.decision !== "issue") return { ran: false, decision: "stop", reason: String(r.reason) };
    const args = buildArgs(r);
    const out: GhOut = env.exec ? env.exec(args) : spawnSync(env.gh, args, {
      env: { ...process.env, GH_DEBUG: "api", GH_PROMPT_DISABLED: "1", GH_NO_UPDATE_NOTIFIER: "1", NO_COLOR: "1", CLICOLOR: "0" },
      encoding: "utf8", maxBuffer: 1 << 28, timeout: timeoutMs,
    });
    const stderr = String(out.stderr ?? ""); // the trace: filtered below, then dropped
    const lines = traceLines(stderr);
    const timedOut = (out as { error?: NodeJS.ErrnoException }).error?.code === "ETIMEDOUT";
    const error = out.status === 0 ? undefined : timedOut ? `gh timed out after ${timeoutMs / 1000} s and was killed; the request may still have reached GitHub, check gh run list before running it again` : errorSummary(stderr, out.status);
    const o = env.core({ op: "ci.budget.observe", now: env.now(), state: r.state, lines });
    saveState(env.dir, o.state as Json);
    const h = o.headers as { status?: number | null } | undefined;
    return {
      ran: true, kind: String(r.kind), cost: Number(r.cost), code: out.status, status: h?.status ?? null,
      stdout: String(out.stdout ?? ""), lines, ...(error ? { error } : {}), now: env.now(), reply: r, state: o.state as Json,
    };
  }, lockWaitMs);
}

export type Opts = {
  /** Requests the call costs (default 1). */
  cost?: number;
  /** On wait, sleep until the time fwcore named and ask again (default: return the wait). */
  block?: boolean;
  /** Epoch second after which a blocking call returns the wait it last got. */
  deadline?: number;
  timeoutMs?: number;
  lockWaitMs?: number;
};

/** `chargedOnce`, repeated on wait when `block` is set. A `stop` is always returned. */
export async function chargedCall(env: Env, decide: Decide, buildArgs: (reply: Json) => string[], o: Opts = {}): Promise<Charged> {
  for (;;) {
    const res = chargedOnce(env, decide, buildArgs, o.timeoutMs, o.lockWaitMs);
    if (res.ran || res.decision === "stop" || res.decision === "busy" || !o.block) return res;
    if (o.deadline !== undefined && res.until >= o.deadline) return res;
    await env.sleepUntil(res.until);
  }
}

/** A one-off charged call: ask `ci.budget.reserve` for `cost` requests, run `gh <args>` only if fwcore says issue. */
export async function ghCharged(env: Env, args: string[], o: Opts = {}): Promise<Charged> {
  const cost = o.cost ?? 1;
  if (args[0] === "api" || args[0] === "auth") throw new Error(`ghCharged does not run \`gh ${args[0]}\` (option B is not approved; tokens are never read)`);
  return chargedCall(env, (state, now) => env.core({ op: "ci.budget.reserve", now, state, cost }), () => args, o);
}
