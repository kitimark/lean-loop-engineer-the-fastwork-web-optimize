// Spool drain: .fw-console/spool/*.jsonl -> obs.jsonl (observations) and, for alerts and agent life, events.jsonl through
// the normal reducer path (`step.post` / `step.cancel` / `agent.spawn` / `agent.stop` caused by actor "hook" or "script",
// i.e. console-api itself; the Lean authority table still decides). A key is marked seen only after its fact is accepted,
// so a refused alert is retried next drain.
//
// Task task-state-truth: every decision is Lean's (`ops.obs`): which lines are admitted (`Fw.Ops.Obs.admit`: an unknown
// field never rejects a line, it is counted and raised once as a spool alert), what a record does to agent life
// (`Fw.Ops.Obs.lifeOf`) and which quiet agents have timed out (`plan.timeouts`, `Fw.Plan.timeouts`). This file only
// reads files, keeps the name index and the stop epochs, and submits what Lean returns.
import { existsSync, fsyncSync, openSync, closeSync, readFileSync, readdirSync, statSync, writeSync } from "node:fs";
import { dirname, join } from "node:path";
import { ObsLine, type Command, type ObsRecord, type ObsSummaryRow } from "@fw/contracts";
import type { Core } from "../core/index.ts";
import type { Store } from "../store.ts";
import { NameIndex } from "../health.ts";
import { scanWorkflows, workflowDirs } from "./workflow.ts";

/** One drain's counts. `invalid`: lines Lean rejected (logged with the reason); `unknown`: occurrences of fields Lean
 *  does not know on new accepted lines; `stops`: agent.stop sent from SubagentStop records; `unnamed`: SubagentStop
 *  records whose agent id has no name in the health index (the quiet timeout ends those agents); `timeouts`: agent.stop
 *  sent by the quiet timeout. */
export type DrainResult = {
  accepted: number; duplicates: number; invalid: number; retry: number; alerts: number;
  unknown: number; stops: number; unnamed: number; timeouts: number;
};

/** A tool call in flight (a PreToolUse seen, no PostToolUse yet); no agent_id is the lead. */
export type Flight = { agent_id: string | null; agent_type: string | null; tool_name: string | null };
/** What the drain does for one record (Lean `console.alert`, `Fw.Console.Alert.act`): the alert step to post and the
 *  open alert steps to cancel, both as commands of actor script. */
export type AlertPlan = { post: Command | null; close: Command[] };

/** Lean's verdict on one spool line (`ops.obs` raw): the kept known fields, their obs key and the unknown field names,
 *  or the rejection reason. */
export type Admitted = { ok: true; key: string; rec: ObsRecord; unknown: string[] } | { ok: false; why: string };

/** Lean's life decision for one admitted record (`ops.obs` life). */
export type LifeDecision = { kind: "spawn" | "stop" | "unnamed" | "skip"; key: string | null; agent: string | null; at: number | null };

/** Which alert (if any) a record opens and which open alerts it closes. The rule is Lean's; this only maps the reply to
 *  commands. Open alerts are the board's waiting/started steps with an `alert-` id. */
export async function alertPlan(core: Pick<Core, "ops">, rec: ObsRecord, flights: readonly Flight[], open: readonly string[]): Promise<AlertPlan> {
  const r = await core.ops("console.alert", {
    event: { hook_event_name: rec.hook_event_name, agent_id: rec.agent_id, agent_type: rec.agent_type, tool_name: rec.tool_name,
      notification_type: rec.notification_type ?? null, ts: rec.ts },
    flights, open,
  });
  const p = r.post as { step: string; key: string; title: string } | null;
  const close = (r.close as { step: string; key: string }[]).map((c): Command => ({ type: "step.cancel", key: c.key, actor: "script", step: c.step }));
  return { post: p ? { type: "step.post", key: p.key, actor: "script", step: p.step, card: null, title: p.title, kind: "action", options: null } : null, close };
}

/** Tool calls per (agent type, tool): count, errors, summed hook duration, in first-seen order. Lean `ops.obs`
 *  (`Fw.Ops.Obs.summarize`); only the fields the rule reads are sent. */
export async function summarize(core: Pick<Core, "ops">, lines: readonly ObsLine[]): Promise<ObsSummaryRow[]> {
  const r = await core.ops("ops.obs", { lines: lines.map((l) => ({
    hook_event_name: l.hook_event_name, agent_type: l.agent_type, tool_name: l.tool_name, is_error: l.is_error, duration_ms: l.duration_ms,
  })) });
  return r.summary as ObsSummaryRow[];
}

/** The obs key of a spool record: `agent|event|tool_use_id`, the timestamp standing in for a missing tool_use_id and
 *  `main` for a missing agent_id. Lean `ops.obs` (`Fw.Ops.Obs.obsKey`); null when fwcore refuses the record. */
export async function obsKey(core: Pick<Core, "ops">, rec: ObsRecord): Promise<string | null> {
  try {
    const r = await core.ops("ops.obs", { records: [{ agent_id: rec.agent_id, hook_event_name: rec.hook_event_name, tool_use_id: rec.tool_use_id, ts: rec.ts }] });
    const k = (r.keys as unknown[] | undefined)?.[0];
    return typeof k === "string" ? k : null;
  } catch { return null; }
}

/** Lean admission of raw spool lines (`Fw.Ops.Obs.admit`), one verdict per line in order. */
export async function admitLines(core: Pick<Core, "ops">, raw: readonly string[]): Promise<Admitted[]> {
  return (await core.ops("ops.obs", { raw })).admitted as Admitted[];
}

/** Lean's life decision of one admitted record (`Fw.Ops.Obs.lifeOf`): `name` is the health index's name of its agent
 *  id, `epoch` the time of the last stop the drain sent for that name (0 if none). */
export async function lifeOf(core: Pick<Core, "ops">, rec: ObsRecord, key: string, name: string | null, epoch: number): Promise<LifeDecision> {
  const r = await core.ops("ops.obs", { life: [{ event: rec.hook_event_name, agent_id: rec.agent_id, agent_name: rec.agent_name ?? null,
    name, key, ts: rec.ts, epoch }] });
  return (r.life as LifeDecision[])[0]!;
}

export class Drain {
  private seen = new Set<string>();
  private offsets = new Map<string, number>();
  /** tool calls in flight by tool_use_id (evidence for attributing an agent-less Notification; empty after a restart) */
  private flights = new Map<string, Flight>();
  private openAlerts = new Set<string>();
  private busy: Promise<unknown> = Promise.resolve();
  private obsPath: string;

  private store: Store;

  private wfDirs: () => string[];
  private wfSent = new Set<string>();
  /** agent id -> name, from health.jsonl (read once, then only what was appended) */
  private names: NameIndex;
  /** agent name -> the record time of the last stop this drain sent for it (the heartbeat key's epoch; empty after a restart) */
  private epochs = new Map<string, number>();
  /** unknown field -> count on new accepted lines since the last spool alert was posted */
  private unknown = new Map<string, number>();
  /** life event keys already accepted (a heartbeat key repeats for every tool event of its 10-minute bucket) */
  private lifeSent = new Set<string>();

  /** `wfDirs`: the session `workflows/` dirs to sweep for workflow runs (default: this checkout's sessions, see workflow.ts). */
  constructor(store: Store, wfDirs: () => string[] = () => workflowDirs(dirname(store.dir))) {
    this.store = store;
    this.wfDirs = wfDirs;
    this.obsPath = join(store.dir, "obs.jsonl");
    this.names = new NameIndex(store.dir);
    for (const l of this.obsLines()) this.seen.add(l.key);
  }

  obsLines(): ObsLine[] {
    if (!existsSync(this.obsPath)) return [];
    const out: ObsLine[] = [];
    for (const l of readFileSync(this.obsPath, "utf8").split("\n")) {
      if (!l) continue;
      try { out.push(ObsLine.parse(JSON.parse(l))); } catch { /* torn or foreign line: ignore */ }
    }
    return out;
  }

  summary(): Promise<ObsSummaryRow[]> { return summarize(this.store.core, this.obsLines()); }

  /** Serialised: two drains never interleave. */
  run(): Promise<DrainResult> {
    const p = this.busy.then(() => this.once());
    this.busy = p.catch(() => undefined);
    return p;
  }

  private async once(): Promise<DrainResult> {
    const res: DrainResult = { accepted: 0, duplicates: 0, invalid: 0, retry: 0, alerts: 0, unknown: 0, stops: 0, unnamed: 0, timeouts: 0 };
    await this.workflowSweep();
    const spool = join(this.store.dir, "spool");
    if (existsSync(spool)) {
      this.names.refresh();
      // the alert steps still open on the board (refreshed each drain: a person may have answered or cancelled one)
      this.openAlerts = new Set((await this.store.board()).steps
        .filter((st) => st.id.startsWith("alert-") && (st.status === "waiting" || st.status === "started")).map((st) => st.id));
      for (const f of readdirSync(spool).filter((n) => n.endsWith(".jsonl")).sort()) {
        const path = join(spool, f);
        const start = this.offsets.get(path) ?? 0;
        if (statSync(path).size <= start) continue;
        const buf = readFileSync(path).subarray(start);
        const end = buf.lastIndexOf(10) + 1; // a torn last line (no newline yet) waits for the next drain
        const raws = buf.subarray(0, end).toString("utf8").split("\n").slice(0, -1);
        const verdicts = raws.length ? await admitLines(this.store.core, raws) : [];
        let pos = 0, advance = true, consumed = 0;
        for (let i = 0; i < raws.length; i++) {
          const len = Buffer.byteLength(raws[i]!) + 1;
          const verdict = await this.handle(verdicts[i]!, res);
          if (verdict === "retry") advance = false;
          pos += len;
          if (advance) consumed = pos;
        }
        this.offsets.set(path, start + consumed);
      }
      await this.fieldAlert(res);
    }
    await this.timeoutSweep(res);
    return res;
  }

  /** Workflow runs named like a task: `agent.spawn` at the start, `agent.stop` at the end (Lean `Fw.Plan.wfEvents`). The
   *  event key carries the run id, so a repeated sweep is a duplicate; a refusal never blocks the drain. */
  private async workflowSweep(): Promise<void> {
    let dirs: string[];
    try { dirs = this.wfDirs(); } catch { return; }
    if (dirs.length === 0) return;
    const ids = (await this.store.board()).plan.tasks.map((t) => t.id);
    for (const d of dirs) {
      for (const e of scanWorkflows(d, ids)) {
        if (this.wfSent.has(e.key)) continue;
        const reply = await this.store.submit({ type: e.type, key: e.key, actor: "hook", agent: e.agent });
        if (reply.ok) this.wfSent.add(e.key); // refused: tried again next drain
      }
    }
  }

  /** The quiet timeout (Lean `plan.timeouts`, `Fw.Plan.timeouts`): an agent bound to an undone task and not seen for
   *  `Fw.Plan.quietMs` gets `agent.stop` at now (key `timeout:<agent>|<since>`, so one per sighting). Never blocks. */
  private async timeoutSweep(res: DrainResult): Promise<void> {
    try {
      const b = await this.store.board();
      const tasks = b.plan.tasks.map((t) => ({ id: t.id, evidence: t.evidence, agent: t.agent, since: t.since ?? null }));
      const r = await this.store.core.ops("plan.timeouts", { tasks, now: b.now });
      for (const s of r.stops as { agent: string; since: number }[]) {
        const reply = await this.store.submit({ type: "agent.stop", key: `timeout:${s.agent}|${s.since}`, actor: "script", agent: s.agent, at: b.now });
        if (reply.ok) res.timeouts++;
      }
    } catch { /* the next drain tries again */ }
  }

  /** Unknown spool fields (Lean `Fw.Ops.Obs.fieldAlert`): one spool alert naming them while none is open. */
  private async fieldAlert(res: DrainResult): Promise<void> {
    if (this.unknown.size === 0) return;
    try {
      const r = await this.store.core.ops("ops.obs", { fieldAlert: { now: (await this.store.board()).now, open: [...this.openAlerts],
        unknown: [...this.unknown].map(([field, count]) => ({ field, count })) } });
      const a = r.alert as { step: string; key: string; title: string } | null;
      if (!a) return;
      const reply = await this.store.submit({ type: "step.post", key: a.key, actor: "script", step: a.step, card: null, title: a.title, kind: "action", options: null });
      if (reply.ok) { this.openAlerts.add(a.step); this.unknown.clear(); res.alerts++; }
    } catch { /* the next drain tries again */ }
  }

  /** Append why Lean rejected a spool line to spool-rejects.jsonl: the reason only, never the payload. */
  private reject(why: string): void {
    try {
      const fd = openSync(join(dirname(this.obsPath), "spool-rejects.jsonl"), "a");
      try { writeSync(fd, JSON.stringify({ ts: Date.now(), why: [why] }) + "\n"); } finally { closeSync(fd); }
    } catch { /* logging never blocks the drain */ }
  }

  private async handle(v: Admitted, res: DrainResult): Promise<"done" | "retry"> {
    // retrying cannot fix a bad record; it is counted AND logged (Lean `drop_counted`: every line is accepted or rejected)
    if (!v.ok) { res.invalid++; this.reject(v.why); return "done"; }
    const { key, rec } = v;
    if (this.seen.has(key)) { res.duplicates++; return "done"; }
    // work graph: agent life as facts, sent unconditionally (whether or not a task of that name exists yet). Which task
    // an agent works on is derived on the board (Lean `Fw.Plan.agentOf`), so the order of a spawn and the task's define
    // never matters, and a stop ends exactly the spawns older than it (`at`). A refusal is logged in refused.jsonl; it
    // never blocks the spool.
    const name = rec.agent_id ? this.names.get(rec.agent_id) : null;
    let life: LifeDecision;
    try { life = await lifeOf(this.store.core, rec, key, name, name ? this.epochs.get(name) ?? 0 : 0); } catch { life = { kind: "skip", key: null, agent: null, at: null }; }
    if ((life.kind === "spawn" || life.kind === "stop") && life.key && life.agent && life.at !== null && !this.lifeSent.has(life.key)) {
      const reply = await this.store.submit({ type: life.kind === "spawn" ? "agent.spawn" : "agent.stop", key: life.key, actor: "hook", agent: life.agent, at: life.at });
      if (reply.ok) this.lifeSent.add(life.key);
      if (life.kind === "stop" && reply.ok) { res.stops++; this.epochs.set(life.agent, Math.max(this.epochs.get(life.agent) ?? 0, life.at)); }
    }
    if (life.kind === "unnamed") res.unnamed++;
    // flight bookkeeping (glue): a PreToolUse starts a tool call, its PostToolUse(Failure) ends it, SubagentStop drops the agent's
    if (rec.tool_use_id && rec.hook_event_name === "PreToolUse") this.flights.set(rec.tool_use_id, { agent_id: rec.agent_id, agent_type: rec.agent_type, tool_name: rec.tool_name });
    if (rec.tool_use_id && (rec.hook_event_name === "PostToolUse" || rec.hook_event_name === "PostToolUseFailure")) this.flights.delete(rec.tool_use_id);
    if (rec.hook_event_name === "SubagentStop") for (const [k, f] of this.flights) if (f.agent_id === rec.agent_id) this.flights.delete(k);
    let plan: AlertPlan;
    try { plan = await alertPlan(this.store.core, rec, [...this.flights.values()], [...this.openAlerts]); } catch { plan = { post: null, close: [] }; }
    for (const c of plan.close) { // a refusal (answered or cancelled meanwhile) is logged; never blocks
      await this.store.submit(c);
      if (c.type === "step.cancel") this.openAlerts.delete(c.step);
    }
    if (plan.post) {
      const reply = await this.store.submit(plan.post);
      if (!reply.ok) { res.retry++; return "retry"; } // not accepted: do NOT mark seen
      if (plan.post.type === "step.post") this.openAlerts.add(plan.post.step);
      res.alerts++;
    }
    for (const u of v.unknown) { this.unknown.set(u, (this.unknown.get(u) ?? 0) + 1); res.unknown++; }
    const fd = openSync(this.obsPath, "a");
    try { writeSync(fd, JSON.stringify({ key, ...rec }) + "\n"); fsyncSync(fd); } finally { closeSync(fd); }
    this.seen.add(key); // marked seen only now
    res.accepted++;
    return "done";
  }
}
