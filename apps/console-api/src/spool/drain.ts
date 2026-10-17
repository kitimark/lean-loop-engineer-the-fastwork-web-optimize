// Spool drain: .fw-console/spool/*.jsonl -> obs.jsonl (observations) and, for alerts only, events.jsonl through
// the normal reducer path (a `step.post` / `step.cancel` caused by actor "script", i.e. console-api itself; the Lean authority table
// still decides). A key is marked seen only after its fact is accepted, so a refused alert is retried next drain.
import { existsSync, fsyncSync, openSync, closeSync, readFileSync, readdirSync, statSync, writeSync } from "node:fs";
import { dirname, join } from "node:path";
import { ObsLine, ObsRecord, type Command, type ObsSummaryRow } from "@fw/contracts";
import type { Core } from "../core/index.ts";
import type { Store } from "../store.ts";
import { agentNameOf } from "../health.ts";
import { scanWorkflows, workflowDirs } from "./workflow.ts";

export type DrainResult = { accepted: number; duplicates: number; invalid: number; retry: number; alerts: number };

/** A tool call in flight (a PreToolUse seen, no PostToolUse yet); no agent_id is the lead. */
export type Flight = { agent_id: string | null; agent_type: string | null; tool_name: string | null };
/** What the drain does for one record (Lean `console.alert`, `Fw.Console.Alert.act`): the alert step to post and the
 *  open alert steps to cancel, both as commands of actor script. */
export type AlertPlan = { post: Command | null; close: Command[] };

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

  /** `wfDirs`: the session `workflows/` dirs to sweep for workflow runs (default: this checkout's sessions, see workflow.ts). */
  constructor(store: Store, wfDirs: () => string[] = () => workflowDirs(dirname(store.dir))) {
    this.store = store;
    this.wfDirs = wfDirs;
    this.obsPath = join(store.dir, "obs.jsonl");
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
    const res: DrainResult = { accepted: 0, duplicates: 0, invalid: 0, retry: 0, alerts: 0 };
    await this.workflowSweep();
    const spool = join(this.store.dir, "spool");
    if (!existsSync(spool)) return res;
    // the alert steps still open on the board (refreshed each drain: a person may have answered or cancelled one)
    this.openAlerts = new Set((await this.store.board()).steps
      .filter((st) => st.id.startsWith("alert-") && (st.status === "waiting" || st.status === "started")).map((st) => st.id));
    for (const f of readdirSync(spool).filter((n) => n.endsWith(".jsonl")).sort()) {
      const path = join(spool, f);
      const start = this.offsets.get(path) ?? 0;
      if (statSync(path).size <= start) continue;
      const buf = readFileSync(path).subarray(start);
      const end = buf.lastIndexOf(10) + 1; // a torn last line (no newline yet) waits for the next drain
      let pos = 0, advance = true, consumed = 0;
      for (const raw of buf.subarray(0, end).toString("utf8").split("\n").slice(0, -1)) {
        const len = Buffer.byteLength(raw) + 1;
        const verdict = await this.handle(raw, res);
        if (verdict === "retry") advance = false;
        pos += len;
        if (advance) consumed = pos;
      }
      this.offsets.set(path, start + consumed);
    }
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

  private async handle(raw: string, res: DrainResult): Promise<"done" | "retry"> {
    let rec: ObsRecord;
    try { rec = ObsRecord.parse(JSON.parse(raw)); } catch { res.invalid++; return "done"; } // retrying cannot fix it
    // the key joins agent, event and tool_use_id, the same fields a transcript reconciler sees (Lean `ops.obs`)
    const key = await obsKey(this.store.core, rec);
    if (key === null) { res.invalid++; return "done"; }
    if (this.seen.has(key)) { res.duplicates++; return "done"; }
    // work graph: agent life as facts, sent unconditionally (whether or not a task of that name exists yet). Which task
    // an agent works on is derived on the board (Lean `Fw.Plan.agentOf`, `run_comm`), so the order of a spawn and the
    // task's define never matters. A refusal is logged in refused.jsonl; it never blocks the spool.
    if (rec.hook_event_name === "SpawnGuard" && rec.agent_name && rec.agent_name.length <= 120) {
      await this.store.submit({ type: "agent.spawn", key: `spawn:${key}`, actor: "hook", agent: rec.agent_name });
    }
    if (rec.hook_event_name === "SubagentStop" && rec.agent_id) {
      const name = agentNameOf(this.store.dir, rec.agent_id); // the hook record has no name; fw watch's health line does
      if (name) await this.store.submit({ type: "agent.stop", key: `stop:${rec.agent_id}`, actor: "hook", agent: name });
    }
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
    const fd = openSync(this.obsPath, "a");
    try { writeSync(fd, JSON.stringify({ key, ...rec }) + "\n"); fsyncSync(fd); } finally { closeSync(fd); }
    this.seen.add(key); // marked seen only now
    res.accepted++;
    return "done";
  }
}

