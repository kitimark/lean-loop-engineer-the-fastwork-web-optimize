// Spool drain: .fw-console/spool/*.jsonl -> obs.jsonl (observations) and, for alerts and agent life, events.jsonl through
// the normal reducer path (`step.post` / `step.cancel` / `agent.spawn` / `agent.stop` caused by actor "hook" or "script",
// i.e. console-api itself; the Lean authority table still decides). A key is marked seen only after its fact is accepted,
// so a refused alert is retried next drain.
//
// Task task-state-truth: every decision is Lean's (`ops.obs`): which lines are admitted (`Fw.Ops.Obs.admit`: only the
// decision fields can reject a line; every rejection, soft-field note and unknown field is an issue, raised as one spool
// alert), what a record does to agent life (`Fw.Ops.Obs.lifeOf`: liveness by agent id, any event of an id is a
// heartbeat) and which ids the health index names (`Fw.Ops.Obs.labelOf`, `agent.label`). Round 5: no timeout stop; a key
// not seen for `Fw.Plan.quietMs` shows quiet on the board (`Fw.Plan.quietOf`, derived at query time), and only an
// identity stop ends it. This file only reads files, keeps the name index and the stop epochs, and submits what Lean
// returns. A life key is an agent id (or a spawn guard's bridge key), never a name: a name only labels
// a key (round 4). The whole drain body runs in one try (round 5), so no throw escapes `run()`. Every throw a sweep or
// the drain catches is counted (`sweepErrors`, written to sweep-errors.json) and
// the watch raises `svc.sweepError` with the count (Lean `Fw.Obs.sweep_error_alerts`); none is swallowed.
import { existsSync, fsyncSync, openSync, closeSync, readFileSync, readdirSync, statSync, writeFileSync, writeSync } from "node:fs";
import { dirname, join } from "node:path";
import { ObsLine, type Command, type ObsRecord, type ObsSummaryRow } from "@fw/contracts";
import type { Core } from "../core/index.ts";
import type { Store } from "../store.ts";
import { NameIndex } from "../health.ts";
import { scanWorkflows, workflowDirs, WfMemo } from "./workflow.ts";

/** One drain's counts. `invalid`: lines Lean rejected (logged with the reason); `unknown`: occurrences of fields Lean
 *  does not know on new accepted lines; `issues`: issue occurrences (rejections, soft-field notes, unknown fields,
 *  lifeOf errors; Lean `Fw.Ops.Obs.issuesOf`); `stops`: agent.stop sent from SubagentStop records (by id); `unnamed`: of
 *  those, stops of an id the health index does not name yet; `labels`: agent.label sent; `sweepErrors`: throws caught in
 *  this drain (each also counted in sweep-errors.json). */
export type DrainResult = {
  accepted: number; duplicates: number; invalid: number; retry: number; alerts: number;
  unknown: number; issues: number; stops: number; unnamed: number; labels: number; sweepErrors: number;
};

/** The file the watch reads for `svc.sweepError`: `{pid, count, ops: {<op>: count}}` of this console-api process. */
export const SWEEP_ERRORS = "sweep-errors.json";

/** A tool call in flight (a PreToolUse seen, no PostToolUse yet); no agent_id is the lead. */
export type Flight = { agent_id: string | null; agent_type: string | null; tool_name: string | null };
/** What the drain does for one record (Lean `console.alert`, `Fw.Console.Alert.act`): the alert step to post and the
 *  open alert steps to cancel, both as commands of actor script. */
export type AlertPlan = { post: Command | null; close: Command[] };

/** Lean's verdict on one spool line (`ops.obs` raw): the kept known fields, their obs key, the unknown field names and
 *  the soft-field notes, or the rejection reason; with the line's issues (`Fw.Ops.Obs.Verdict.issues`). */
export type Admitted = { ok: true; key: string; rec: ObsRecord; unknown: string[]; notes: string[]; issues: string[] }
  | { ok: false; why: string; issues: string[] };

/** One life command of an admitted record (`ops.obs` life): a spawn or stop of a life key (`agent`: an agent id or a spawn
 *  guard's bridge key, never a name) at a time, or a label of a life key with a name (Lean `Fw.Ops.Obs.Life`). */
export type LifeDecision = { kind: "spawn" | "stop"; key: string; agent: string; at: number }
  | { kind: "label"; key: string; agent: string; name: string };

/** Which alert (if any) a record opens and which open alerts it closes. The rule is Lean's; this only maps the reply to
 *  commands. Open alerts are the board's waiting/started steps with an `alert-` id. */
export async function alertPlan(core: Pick<Core, "ops">, rec: ObsRecord, flights: readonly Flight[], open: readonly string[]): Promise<AlertPlan> {
  const r = await core.ops("console.alert", {
    event: { hook_event_name: rec.hook_event_name, agent_id: rec.agent_id, agent_type: rec.agent_type, tool_name: rec.tool_name,
      notification_type: rec.notification_type ?? null, ts: rec.ts },
    flights, open,
  });
  const p = r.post as { step: string; key: string; title: string; audience: "user" | "lead"; body: string } | null;
  const close = (r.close as { step: string; key: string }[]).map((c): Command => ({ type: "step.cancel", key: c.key, actor: "script", step: c.step }));
  return { post: p ? { type: "step.post", key: p.key, actor: "script", step: p.step, card: null, title: p.title, kind: "action", options: null, audience: p.audience, body: p.body } : null, close };
}

/** Tool calls per (agent type, tool): count, errors, summed hook duration, in first-seen order. Lean `ops.obs`
 *  (`Fw.Ops.Obs.summarize`); only the fields the rule reads are sent. */
export async function summarize(core: Pick<Core, "ops">, lines: readonly ObsLine[]): Promise<ObsSummaryRow[]> {
  const r = await core.ops("ops.obs", { lines: lines.map((l) => ({
    hook_event_name: l.hook_event_name, agent_type: l.agent_type, tool_name: l.tool_name, is_error: l.is_error, duration_ms: l.duration_ms,
  })) });
  return r.summary as ObsSummaryRow[];
}



/** Lean admission of raw spool lines (`Fw.Ops.Obs.admit`), one verdict per line in order. */
export async function admitLines(core: Pick<Core, "ops">, raw: readonly string[]): Promise<Admitted[]> {
  return (await core.ops("ops.obs", { raw })).admitted as Admitted[];
}

/** Lean's life commands of one admitted record (`Fw.Ops.Obs.lifeOf`) and the agent's stop epoch after it
 *  (`Fw.Ops.Obs.epochNext`: a stop raises it, a newer start resets it to 0 so the agent heartbeats again). `epoch` is the
 *  epoch before the record (0 if the drain sent no stop for its agent id). No name is sent: a name never keys a life. */
export async function lifeOf(core: Pick<Core, "ops">, rec: ObsRecord, key: string, epoch: number): Promise<{ life: LifeDecision[]; epoch: number }> {
  const r = await core.ops("ops.obs", { life: [{ event: rec.hook_event_name, agent_id: rec.agent_id, agent_name: rec.agent_name ?? null,
    key, ts: rec.ts, epoch }] });
  return { life: (r.life as LifeDecision[][])[0]!, epoch: (r.epochs as number[])[0]! };
}

/** Lean's label commands for (agent id, name) pairs of the health index (`Fw.Ops.Obs.labelOf`); null for an unusable pair. */
export async function labelsOf(core: Pick<Core, "ops">, pairs: readonly { id: string; name: string }[]): Promise<({ key: string; agent: string; name: string } | null)[]> {
  return (await core.ops("ops.obs", { labels: pairs })).labels as ({ key: string; agent: string; name: string } | null)[];
}

export class Drain {
  /** The latest sweep, for the automatic close of spool steps (Lean `Fw.Ops.Obs.resolveSpool`): lines read and the issue
   *  names seen in it. Unlike `issues` it is not cleared by a posted alert. */
  private passLines = 0;
  private passIssues = new Set<string>();
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
  /** journal lines and settled runs between sweeps (apps/console-api/src/spool/journal-cache.ts) */
  readonly wfMemo = new WfMemo();
  /** agent id -> name, from health.jsonl (read once, then only what was appended) */
  private names: NameIndex;
  /** agent id -> its stop epoch (Lean `epochNext`: the time of the last stop this drain sent, reset by a newer start; the heartbeat key's epoch; empty after a restart) */
  private epochs = new Map<string, number>();
  /** issue -> count since the last spool alert was posted (Lean `Fw.Ops.Obs.issuesOf`, plus `lifeOf:error`) */
  private issues = new Map<string, number>();
  /** (id, name) pairs already labelled on the board */
  private labelSent = new Set<string>();
  /** life event keys already accepted (a heartbeat key repeats for every tool event of its 10-minute bucket) */
  private lifeSent = new Set<string>();
  /** op -> throws caught since this process started (never reset; the watch alerts on any) */
  private caughtOps = new Map<string, number>();

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
    const res: DrainResult = { accepted: 0, duplicates: 0, invalid: 0, retry: 0, alerts: 0, unknown: 0, issues: 0, stops: 0, unnamed: 0, labels: 0, sweepErrors: 0 };
    try {
      await this.workflowSweep(res);
      await this.spoolSweep(res);
    } catch (e) { this.caught("drain", e, res); } // board, submits and posts: a throw is counted, never escapes
    return res;
  }

  /** The spool files: labels, then each new complete line admitted by Lean and handled, then the spool alert. A throw
   *  here (`store.board`, `readdir`, a `store.submit` rejection) skips the remaining spool files until the next drain and
   *  is counted by `once`; the workflow sweep catches its own throws, so it never skips this sweep. */
  private async spoolSweep(res: DrainResult): Promise<void> {
    const spool = join(this.store.dir, "spool");
    if (!existsSync(spool)) return;
    this.passLines = 0;
    this.passIssues = new Set();
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
      let verdicts: Admitted[];
      try { verdicts = raws.length ? await admitLines(this.store.core, raws) : []; }
      catch (e) { this.caught("admit", e, res); continue; } // offset kept: the lines are read again next drain
      this.passLines += raws.length; // counted only once Lean admitted them: the reader ran (Lean `other_closes_only_after_lines`)
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
    await this.resolveSweep(res);
  }

  /** Spool alert steps for the lead that the latest sweep shows clean close themselves (Lean `ops.obs` resolve,
   *  `Fw.Ops.Obs.resolveSpool`): a `step.done` of the script with Lean's note. Runs on every sweep, also with no new lines. */
  private async resolveSweep(res: DrainResult): Promise<void> {
    try {
      const board = await this.store.board();
      const steps = board.steps
        .filter((st) => st.id.startsWith("alert-spool-") && (st.status === "waiting" || st.status === "started") && st.audience === "lead")
        .map((st) => ({ id: st.id, title: st.title, body: st.body, audience: st.audience }));
      if (steps.length === 0) return;
      const r = await this.store.core.ops("ops.obs", { resolve: { now: board.now,
        window: { lines: this.passLines, issues: [...this.passIssues] }, steps } });
      for (const c of r.resolve as { step: string; key: string; note: string }[]) {
        const reply = await this.store.submit({ type: "step.done", key: c.key, actor: "script", step: c.step, note: c.note });
        if (reply.ok) {
          this.openAlerts.delete(c.step);
          // counts gathered while the step was open, for keys that did not occur in this sweep, are not raised again
          for (const k of [...this.issues.keys()]) if (!this.passIssues.has(k)) this.issues.delete(k);
        }
      }
    } catch (e) { this.caught("resolve", e, res); } // the next drain tries again
  }

  /** Workflow runs and their labelled agents (Lean `Fw.Plan.wfAllEvents`): `agent.label` of the run key or agent id with
   *  the task, `agent.spawn` at the start, `agent.stop` at the end, each with `at` the file time of the fact
   *  (`scanWorkflows`), so a late read never postdates a SubagentStop. The event key carries the run (and agent) id, so a
   *  repeated sweep is a duplicate; a refusal is tried again next drain; a throw is counted. */
  private async workflowSweep(res: DrainResult): Promise<void> {
    try {
      const dirs = this.wfDirs();
      if (dirs.length === 0) return;
      const ids = (await this.store.board()).plan.tasks.map((t) => t.id);
      for (const d of dirs) {
        for (const e of scanWorkflows(d, ids, this.wfMemo)) {
          if (this.wfSent.has(e.key)) continue;
          const reply = await this.store.submit(e.type === "agent.label"
            ? { type: e.type, key: e.key, actor: "hook", agent: e.agent, name: e.name }
            : { type: e.type, key: e.key, actor: "hook", agent: e.agent, at: "at" in e ? e.at : null });
          if (reply.ok) this.wfSent.add(e.key);
        }
        this.wfMemo.markSent(d, this.wfSent);
      }
    } catch (e) { this.caught("workflow", e, res); }
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
    } catch (e) { this.caught("label", e, res); } // the next drain tries again
  }

  /** Spool issues (Lean `Fw.Ops.Obs.fieldAlert`): one spool alert naming them with counts while none is open. */
  private async fieldAlert(res: DrainResult): Promise<void> {
    if (this.issues.size === 0) return;
    try {
      const r = await this.store.core.ops("ops.obs", { fieldAlert: { now: (await this.store.board()).now, open: [...this.openAlerts],
        issues: [...this.issues].map(([issue, count]) => ({ issue, count })) } });
      const a = r.alert as { step: string; key: string; title: string; audience: "user" | "lead"; body: string } | null;
      if (!a) return;
      const reply = await this.store.submit({ type: "step.post", key: a.key, actor: "script", step: a.step, card: null, title: a.title, kind: "action", options: null, audience: a.audience, body: a.body });
      if (reply.ok) { this.openAlerts.add(a.step); this.issues.clear(); res.alerts++; }
    } catch (e) { this.caught("fieldAlert", e, res); } // the next drain tries again
  }

  /** A caught throw: counted per op, written to sweep-errors.json for the watch (`svc.sweepError`), raised as a spool
   *  issue `sweep:<op>`, and its message logged. The write never throws. */
  private caught(op: string, e: unknown, res: DrainResult): void {
    this.caughtOps.set(op, (this.caughtOps.get(op) ?? 0) + 1);
    res.sweepErrors++;
    this.issue([`sweep:${op}`], res);
    console.error(`spool drain: ${op} threw:`, e instanceof Error ? e.message : e);
    const ops = Object.fromEntries(this.caughtOps);
    const count = [...this.caughtOps.values()].reduce((a, b) => a + b, 0);
    try { writeFileSync(join(this.store.dir, SWEEP_ERRORS), JSON.stringify({ pid: process.pid, count, ops }) + "\n"); }
    catch (w) { console.error("spool drain: sweep-errors.json write failed:", w instanceof Error ? w.message : w); }
  }

  /** Throws caught since this process started, per op. */
  sweepErrors(): Record<string, number> { return Object.fromEntries(this.caughtOps); }

  private issue(names: readonly string[], res: DrainResult): void {
    for (const n of names) { this.passIssues.add(n); this.issues.set(n, (this.issues.get(n) ?? 0) + 1); res.issues++; }
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
    let epoch = 0;
    try { ({ life, epoch } = await lifeOf(this.store.core, rec, key, rec.agent_id ? this.epochs.get(rec.agent_id) ?? 0 : 0)); }
    catch (e) { this.caught("lifeOf", e, res); res.retry++; return "retry"; }
    let allOk = true;
    for (const c of life) {
      if (this.lifeSent.has(c.key)) continue;
      const reply = await this.store.submit(c.kind === "label"
        ? { type: "agent.label", key: c.key, actor: "hook", agent: c.agent, name: c.name }
        : { type: c.kind === "spawn" ? "agent.spawn" : "agent.stop", key: c.key, actor: "hook", agent: c.agent, at: c.at });
      if (reply.ok) this.lifeSent.add(c.key); else if (c.agent === rec.agent_id) allOk = false;
      if (c.kind === "stop" && reply.ok && c.agent === rec.agent_id) {
        res.stops++;
        if (!name) res.unnamed++;
      }
    }
    // the epoch after the record is Lean's, kept only when the agent's own commands were all accepted
    if (rec.agent_id && allOk) { if (epoch === 0) this.epochs.delete(rec.agent_id); else this.epochs.set(rec.agent_id, epoch); }
    // flight bookkeeping (glue): a PreToolUse starts a tool call, its PostToolUse(Failure) ends it, SubagentStop drops the agent's
    if (rec.tool_use_id && rec.hook_event_name === "PreToolUse") this.flights.set(rec.tool_use_id, { agent_id: rec.agent_id, agent_type: rec.agent_type, tool_name: rec.tool_name });
    if (rec.tool_use_id && (rec.hook_event_name === "PostToolUse" || rec.hook_event_name === "PostToolUseFailure")) this.flights.delete(rec.tool_use_id);
    if (rec.hook_event_name === "SubagentStop") for (const [k, f] of this.flights) if (f.agent_id === rec.agent_id) this.flights.delete(k);
    let plan: AlertPlan;
    try { plan = await alertPlan(this.store.core, rec, [...this.flights.values()], [...this.openAlerts]); }
    catch (e) { this.caught("alertPlan", e, res); res.retry++; return "retry"; } // not marked seen: decided again next drain
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
