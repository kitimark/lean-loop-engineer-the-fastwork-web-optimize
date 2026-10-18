// Spool drain: .fw-console/spool/*.jsonl -> obs.jsonl (observations) and, for alerts and agent life, events.jsonl through
// the normal reducer path (`step.post` / `step.cancel` / `agent.spawn` / `agent.stop` caused by actor "hook" or "script",
// i.e. console-api itself; the Lean authority table still decides). A key is marked seen only after its fact is accepted,
// so a refused alert is retried next drain.
//
// Task task-state-truth: every decision is Lean's (`ops.obs`): which lines are admitted (`Fw.Ops.Obs.admit`: only the
// decision fields can reject a line; every rejection, soft-field note and unknown field is an issue, raised as one spool
// alert), what a record does to agent life (`Fw.Ops.Obs.lifeOf`: liveness by agent id, any event of an id is a
// heartbeat), which ids the health index names (`Fw.Ops.Obs.labelOf`, `agent.label`) and which quiet keys have timed
// out (`plan.timeouts`, `Fw.Plan.timeouts`). This file only reads files, keeps the name index and the stop epochs, and
// submits what Lean returns.
import { existsSync, fsyncSync, openSync, closeSync, readFileSync, readdirSync, statSync, writeSync } from "node:fs";
import { dirname, join } from "node:path";
import { ObsLine, type Command, type ObsRecord, type ObsSummaryRow } from "@fw/contracts";
import type { Core } from "../core/index.ts";
import type { Store } from "../store.ts";
import { NameIndex } from "../health.ts";
import { scanWorkflows, workflowDirs } from "./workflow.ts";

/** One drain's counts. `invalid`: lines Lean rejected (logged with the reason); `unknown`: occurrences of fields Lean
 *  does not know on new accepted lines; `issues`: issue occurrences (rejections, soft-field notes, unknown fields,
 *  lifeOf errors; Lean `Fw.Ops.Obs.issuesOf`); `stops`: agent.stop sent from SubagentStop records (by id); `unnamed`: of
 *  those, stops of an id the health index does not name yet; `labels`: agent.label sent; `timeouts`: agent.stop sent by
 *  the quiet timeout. */
export type DrainResult = {
  accepted: number; duplicates: number; invalid: number; retry: number; alerts: number;
  unknown: number; issues: number; stops: number; unnamed: number; labels: number; timeouts: number;
};

/** A tool call in flight (a PreToolUse seen, no PostToolUse yet); no agent_id is the lead. */
export type Flight = { agent_id: string | null; agent_type: string | null; tool_name: string | null };
/** What the drain does for one record (Lean `console.alert`, `Fw.Console.Alert.act`): the alert step to post and the
 *  open alert steps to cancel, both as commands of actor script. */
export type AlertPlan = { post: Command | null; close: Command[] };

/** Lean's verdict on one spool line (`ops.obs` raw): the kept known fields, their obs key, the unknown field names and
 *  the soft-field notes, or the rejection reason; with the line's issues (`Fw.Ops.Obs.Verdict.issues`). */
export type Admitted = { ok: true; key: string; rec: ObsRecord; unknown: string[]; notes: string[]; issues: string[] }
  | { ok: false; why: string; issues: string[] };

/** One life command of an admitted record (`ops.obs` life): event key, life key (`agent`: an id or a name) and time. */
export type LifeDecision = { kind: "spawn" | "stop"; key: string; agent: string; at: number };

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

/** Lean's life commands of one admitted record (`Fw.Ops.Obs.lifeOf`): `name` is the health index's name of its agent
 *  id, `epoch` the time of the last stop the drain sent for that id (0 if none). */
export async function lifeOf(core: Pick<Core, "ops">, rec: ObsRecord, key: string, name: string | null, epoch: number): Promise<LifeDecision[]> {
  const r = await core.ops("ops.obs", { life: [{ event: rec.hook_event_name, agent_id: rec.agent_id, agent_name: rec.agent_name ?? null,
    name, key, ts: rec.ts, epoch }] });
  return (r.life as LifeDecision[][])[0]!;
}

/** Lean's label commands for (agent id, name) pairs of the health index (`Fw.Ops.Obs.labelOf`); null for an unusable pair. */
export async function labelsOf(core: Pick<Core, "ops">, pairs: readonly { id: string; name: string }[]): Promise<({ key: string; agent: string; name: string } | null)[]> {
  return (await core.ops("ops.obs", { labels: pairs })).labels as ({ key: string; agent: string; name: string } | null)[];
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
  /** agent id -> the record time of the last stop this drain sent for it (the heartbeat key's epoch; empty after a restart) */
  private epochs = new Map<string, number>();
  /** issue -> count since the last spool alert was posted (Lean `Fw.Ops.Obs.issuesOf`, plus `lifeOf:error`) */
  private issues = new Map<string, number>();
  /** (id, name) pairs already labelled on the board */
  private labelSent = new Set<string>();
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
    const res: DrainResult = { accepted: 0, duplicates: 0, invalid: 0, retry: 0, alerts: 0, unknown: 0, issues: 0, stops: 0, unnamed: 0, labels: 0, timeouts: 0 };
    await this.workflowSweep();
    const spool = join(this.store.dir, "spool");
    if (existsSync(spool)) {
      this.names.refresh();
      await this.labelSweep(res);
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

  /** Labels (Lean `Fw.Ops.Obs.labelOf`): each (agent id, name) pair of the health index not yet sent becomes
   *  `agent.label`, so the id's life counts for that name. A refusal is tried again next drain; never blocks. */
  private async labelSweep(res: DrainResult): Promise<void> {
    const pairs = this.names.entries().filter(([id, name]) => !this.labelSent.has(`${id}|${name}`)).map(([id, name]) => ({ id, name }));
    if (pairs.length === 0) return;
    try {
      const ls = await labelsOf(this.store.core, pairs);
      for (let i = 0; i < pairs.length; i++) {
        const l = ls[i];
        const tag = `${pairs[i]!.id}|${pairs[i]!.name}`;
        if (!l) { this.labelSent.add(tag); continue; } // unusable pair: Lean says no label
        const reply = await this.store.submit({ type: "agent.label", key: l.key, actor: "script", agent: l.agent, name: l.name });
        if (reply.ok) { this.labelSent.add(tag); if (!reply.duplicate) res.labels++; }
      }
    } catch { /* the next drain tries again */ }
  }

  /** The quiet timeout (Lean `plan.timeouts`, `Fw.Plan.timeouts`): a live key of an undone task's agent not seen for
   *  `Fw.Plan.quietMs` gets `agent.stop` at its last sighting (key `timeout:<key>|<at>`, so one per sighting; a later
   *  event revives it). Never blocks. */
  private async timeoutSweep(res: DrainResult): Promise<void> {
    try {
      const b = await this.store.board();
      const tasks = b.plan.tasks.map((t) => ({ id: t.id, evidence: t.evidence, keys: t.keys ?? [] }));
      const r = await this.store.core.ops("plan.timeouts", { tasks, now: b.now });
      for (const s of r.stops as { agent: string; at: number }[]) {
        const reply = await this.store.submit({ type: "agent.stop", key: `timeout:${s.agent}|${s.at}`, actor: "script", agent: s.agent, at: s.at });
        if (reply.ok) res.timeouts++;
      }
    } catch { /* the next drain tries again */ }
  }

  /** Spool issues (Lean `Fw.Ops.Obs.fieldAlert`): one spool alert naming them with counts while none is open. */
  private async fieldAlert(res: DrainResult): Promise<void> {
    if (this.issues.size === 0) return;
    try {
      const r = await this.store.core.ops("ops.obs", { fieldAlert: { now: (await this.store.board()).now, open: [...this.openAlerts],
        issues: [...this.issues].map(([issue, count]) => ({ issue, count })) } });
      const a = r.alert as { step: string; key: string; title: string } | null;
      if (!a) return;
      const reply = await this.store.submit({ type: "step.post", key: a.key, actor: "script", step: a.step, card: null, title: a.title, kind: "action", options: null });
      if (reply.ok) { this.openAlerts.add(a.step); this.issues.clear(); res.alerts++; }
    } catch { /* the next drain tries again */ }
  }

  private issue(names: readonly string[], res: DrainResult): void {
    for (const n of names) { this.issues.set(n, (this.issues.get(n) ?? 0) + 1); res.issues++; }
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
    if (!v.ok) { res.invalid++; this.reject(v.why); this.issue(v.issues, res); return "done"; } // Lean `reject_alerts`
    const { key, rec } = v;
    if (this.seen.has(key)) { res.duplicates++; return "done"; }
    // work graph: agent life as facts, by agent id, sent unconditionally (whether or not a task of that name exists yet).
    // Which task an agent works on is derived on the board (Lean `Fw.Plan.agentOf`, through `agent.label`), so the order
    // of a spawn, a label and the task's define never matters, and a stop ends exactly the sightings older than it (`at`).
    // A refusal is logged in refused.jsonl; it never blocks the spool. A throw from fwcore is an issue and the line is
    // retried (not marked seen).
    const name = rec.agent_id ? this.names.get(rec.agent_id) : null;
    let life: LifeDecision[];
    try { life = await lifeOf(this.store.core, rec, key, name, rec.agent_id ? this.epochs.get(rec.agent_id) ?? 0 : 0); }
    catch { this.issue(["lifeOf:error"], res); res.retry++; return "retry"; }
    for (const c of life) {
      if (this.lifeSent.has(c.key)) continue;
      const reply = await this.store.submit({ type: c.kind === "spawn" ? "agent.spawn" : "agent.stop", key: c.key, actor: "hook", agent: c.agent, at: c.at });
      if (reply.ok) this.lifeSent.add(c.key);
      if (c.kind === "stop" && reply.ok && c.agent === rec.agent_id) {
        res.stops++;
        if (!name) res.unnamed++;
        this.epochs.set(c.agent, Math.max(this.epochs.get(c.agent) ?? 0, c.at));
      }
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
    res.unknown += v.unknown.length;
    this.issue(v.issues, res);
    const fd = openSync(this.obsPath, "a");
    try { writeSync(fd, JSON.stringify({ key, ...rec }) + "\n"); fsyncSync(fd); } finally { closeSync(fd); }
    this.seen.add(key); // marked seen only now
    res.accepted++;
    return "done";
  }
}
