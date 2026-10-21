import { scrub } from "./scrub.ts";
import { appendLog, loggedReply, readLog, sha256 } from "./log.ts";
import type { KeyReader } from "./key.ts";

export type Json = Record<string, unknown>;
export type FwCall = (req: Json) => Json;

/** The API endpoint (CONFIRMED https://docs.typesafe.ai/api.md, read 2026-10-18). */
export const ENDPOINT = "https://api.typesafe.ai/v1/systemone";

export type Deps = {
  core: FwCall;
  fetch: typeof fetch;
  readKey: KeyReader;
  logPath: string;
  now: () => Date;
  timeoutMs?: number;
  span?: (step: string) => (exit?: number) => void;
};

export type Ask = {
  question: string;
  state: Record<string, string | string[]>;
  names?: string[];
  thresholds: Json | null;
  run?: number;
  /** Sends and estimated input tokens already spent in this replay run (`fw oracle send`): the gate is
   *  `oracle.preRun`, and `run` is ignored. */
  replayRun?: { sent: number; spent: number };
};

export type Asked = {
  decision: Json;
  key: string;
  source: "replay" | "live" | "refused" | "nokey" | "failed";
  reply?: string;
  sent: boolean;
  /** The body's estimated input tokens, when `oracle.preRun` let it go out. */
  tokens?: number;
};

export function utcDay(d: Date): string {
  return d.toISOString().slice(0, 10);
}

/** Ask one question about one state. Never throws for an API, network or key problem: those are failures that
 *  `oracle.decide` turns into an escalation. It throws only when fwcore itself fails (a bug, not an outcome). */
export async function ask(d: Deps, a: Ask): Promise<Asked> {
  const end = d.span?.(`ask ${a.question}`);
  const names = a.names ?? [];
  const req = d.core({ op: "oracle.request", name: a.question, names, state: a.state });
  const bodyText = String(req.bodyText);
  const key = sha256(bodyText);
  const entries = readLog(d.logPath);
  const prior = loggedReply(entries, key);
  const today = utcDay(d.now());
  const days = entries.map((e) => e.day);
  const pre = a.replayRun
    ? d.core({ op: "oracle.preRun", name: a.question, names, state: a.state, logged: prior !== undefined, today, days, ...a.replayRun })
    : d.core({
      op: "oracle.pre", name: a.question, names, state: a.state,
      logged: prior !== undefined, today, days, ...(a.run !== undefined ? { run: a.run } : {}),
    });
  const tokens = typeof pre.tokens === "number" ? { tokens: pre.tokens } : {};
  const decide = (o: { reply: string } | { failure: Json }) =>
    d.core({ op: "oracle.decide", name: a.question, ...(a.thresholds ? { thresholds: a.thresholds } : {}), ...o });
  if (pre.pre === "replay" && prior !== undefined) {
    end?.(0);
    return { decision: decide({ reply: prior }), key, source: "replay", reply: prior, sent: false };
  }
  if (pre.pre !== "send") {
    end?.(0);
    return { decision: decide({ failure: (pre.failure as Json) ?? { kind: "schema", detail: "pre" } }), key, source: "refused", sent: false };
  }
  const sendText = String(pre.bodyText);
  if (sendText !== bodyText) throw new Error("oracle: oracle.pre body differs from oracle.request body");
  const secret = d.readKey();
  if (!secret) {
    end?.(0);
    return { decision: decide({ failure: { kind: "noKey" } }), key, source: "nokey", sent: false, ...tokens };
  }
  const t0 = performance.now();
  let reply: string | undefined;
  let failure: Json | undefined;
  try {
    const r = await d.fetch(ENDPOINT, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: `Bearer ${secret}` },
      body: sendText,
      signal: AbortSignal.timeout(d.timeoutMs ?? 30_000),
    });
    const text = await r.text();
    if (r.status === 200) reply = text;
    else failure = { kind: "http", status: r.status };
  } catch (e) {
    const name = e instanceof Error ? e.name : "";
    failure = name === "TimeoutError" || name === "AbortError" ? { kind: "timeout" } : { kind: "http", status: 0 };
  }
  const ms = Math.round(performance.now() - t0);
  const model = (() => { try { return String((JSON.parse(bodyText) as Json).model); } catch { return ""; } })();
  const stored = reply !== undefined ? String(d.core({ op: "oracle.store", text: scrub(reply, secret) }).text) : undefined;
  appendLog(d.logPath, {
    key, question: a.question, model, day: today, at: d.now().toISOString(), ms,
    ...(stored !== undefined ? { reply: stored } : { failure: failure! }),
  });
  end?.(stored !== undefined ? 0 : 1);
  const outcome = stored !== undefined ? { reply: stored } : { failure: failure! };
  return { decision: decide(outcome), key, source: stored !== undefined ? "live" : "failed", ...(stored !== undefined ? { reply: stored } : {}), sent: true, ...tokens };
}

export function decisionLine(dec: Json): string {
  const q = (x: unknown) => {
    const r = x as { num?: string; den?: string } | undefined;
    return r?.num !== undefined && r.den !== undefined ? (Number(r.num) / Number(r.den)).toFixed(3) : "?";
  };
  const gate = dec.gate !== undefined ? ` (gate ${q(dec.gate)})` : "";
  if (dec.action === "advise") {
    const a = dec.advice as { kind: string; value?: unknown };
    return `advise ${a.value !== undefined ? String(a.value) : a.kind}${gate}`;
  }
  const r = dec.reason as { reason: string; failure?: { kind: string; status?: number; detail?: string }; gate?: unknown; threshold?: unknown };
  const why = r.reason === "failure" ? `failure ${r.failure?.kind}${r.failure?.status !== undefined ? ` ${r.failure.status}` : ""}${r.failure?.detail ? `: ${r.failure.detail}` : ""}`
    : r.reason === "below" ? `gate ${q(r.gate)} below threshold ${q(r.threshold)}`
    : r.reason === "uncalibrated" ? "uncalibrated (no threshold yet)"
    : r.reason === "badThreshold" ? `threshold ${q(r.threshold)} outside (0, 1]`
    : r.reason;
  return `escalate: ${why}${r.reason === "below" ? "" : gate}`;
}
