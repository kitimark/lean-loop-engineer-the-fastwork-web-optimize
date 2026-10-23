import type { Env } from "@fw/gh-budget";
import type { Span } from "./timing.ts";
import type { Gh, WaitFn } from "./run.ts";

type Begin = (tool: string, step: string) => (exit?: number | null, extra?: Partial<Span>) => void;
type Phase = "plan" | "lock" | "backoff" | "call" | "wait" | "file" | "dry";

export const stepOf = (p: Phase): string => (p === "lock" || p === "backoff" || p === "call" ? `run dispatch ${p}` : `run ${p}`);

export type GhPart = "lock" | "backoff" | "call";
export type GhEvent = "issue" | "wait" | "slept" | "ghEnd";

export class GhClock {
  ms: Record<GhPart, number> = { lock: 0, backoff: 0, call: 0 };
  calls = 0;
  private part: GhPart | null = null;
  private at = 0;
  private readonly onPart: ((p: GhPart) => void) | undefined;
  private readonly clock: () => number;
  constructor(onPart?: (p: GhPart) => void, clock: () => number = () => performance.now()) { this.onPart = onPart; this.clock = clock; }
  private to(p: GhPart | null): void {
    const t = this.clock();
    if (this.part) this.ms[this.part] += t - this.at;
    this.part = p;
    this.at = t;
    if (p) this.onPart?.(p);
  }
  start(): void { this.calls++; this.to("lock"); }
  on(e: GhEvent): void {
    if (this.part === null) return;
    if (e === "issue") this.to("call");
    else if (e === "wait") this.to("backoff");
    else if (e === "slept") this.to("lock");
    else this.to(null);
  }
  end(): void { this.to(null); }
  reset(): void { this.ms = { lock: 0, backoff: 0, call: 0 }; this.calls = 0; }
}

export function phasedEnv(env: Env, on: (e: GhEvent) => void): Env {
  return {
    ...env,
    core: (req) => {
      if (req.op === "ci.budget.observe") on("ghEnd");
      const r = env.core(req);
      if (req.op === "ci.budget.reserve") on(r.decision === "issue" ? "issue" : "wait");
      return r;
    },
    sleepUntil: async (t) => { await env.sleepUntil(t); on("slept"); },
  };
}

export function passParts(c: Pick<GhClock, "ms" | "calls">, totalMs: number): { step: string; durMs: number }[] {
  if (c.calls === 0) return [];
  const lock = Math.round(c.ms.lock), call = Math.round(c.ms.call), backoff = Math.round(c.ms.backoff);
  return [
    { step: "watch pass gh lock", durMs: lock },
    { step: "watch pass gh call", durMs: call },
    ...(backoff > 0 ? [{ step: "watch pass gh backoff", durMs: backoff }] : []),
    { step: "watch pass other", durMs: Math.max(0, Math.round(totalMs) - lock - call - backoff) },
  ];
}

export function runPhases(begin: Begin, dry: boolean) {
  let open: { phase: Phase; end: ReturnType<Begin> } | null = null;
  let current: GhClock | null = null;
  const enter = (phase: Phase) => {
    open?.end(0);
    open = { phase, end: begin("fw", stepOf(phase)) };
  };
  const inCall = () => open?.phase === "lock" || open?.phase === "backoff" || open?.phase === "call";
  enter(dry ? "dry" : "plan");
  const isDispatch = (a: string[]) => a[0] === "workflow" && a[1] === "run";
  return {
    env: (env: Env): Env => phasedEnv(env, (e) => current?.on(e)),
    gh: (gh: Gh): Gh => async (a, o) => {
      const mine = isDispatch(a) && (open?.phase === "plan" || open?.phase === "file" || inCall());
      const clock = mine ? new GhClock((p) => { if (open?.phase === "plan" || open?.phase === "file" || inCall()) enter(p); }) : null;
      current = clock;
      clock?.start();
      let r: string;
      try {
        r = await gh(a, o);
      } finally {
        clock?.end();
        current = null;
      }
      if (clock && inCall()) enter("wait");
      return r;
    },
    wait: (wait: WaitFn): WaitFn => async (t, s) => {
      if (inCall() || open?.phase === "plan") enter("wait");
      const w = await wait(t, s);
      if (w.code !== 3 && open?.phase === "wait") {
        const id = /^run (\d+) /.exec(w.lines[0] ?? "")?.[1];
        open.end(w.code, id ? { runId: Number(id) } : {});
        open = { phase: "file", end: begin("fw", stepOf("file")) };
      }
      return w;
    },
    finish: (exit: number) => { open?.end(exit); open = null; },
  };
}
