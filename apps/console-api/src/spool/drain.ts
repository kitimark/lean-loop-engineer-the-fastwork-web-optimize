// Spool drain: .fw-console/spool/*.jsonl -> obs.jsonl (observations) and, for alerts only, events.jsonl through
// the normal reducer path (a `step.post` caused by actor "script", i.e. console-api itself; the Lean authority table
// still decides). A key is marked seen only after its fact is accepted, so a refused alert is retried next drain.
import { existsSync, fsyncSync, openSync, closeSync, readFileSync, readdirSync, statSync, writeSync } from "node:fs";
import { createHash } from "node:crypto";
import { join } from "node:path";
import { ObsLine, ObsRecord, type Command, type ObsSummaryRow } from "@fw/contracts";
import type { Core } from "../core/index.ts";
import type { Store } from "../store.ts";

export type DrainResult = { accepted: number; duplicates: number; invalid: number; retry: number; alerts: number };

/** Hook events that need a human or signal a stopped agent; everything else is an observation only.
 *  The lead's own Notification (no agent_id) is not an alert: its prompt is already in front of the user in the
 *  terminal. TS STAND-IN until task alert-steps moves this rule to Lean. */
export function alertFor(r: ObsRecord, key: string): Command | null {
  if (r.hook_event_name === "Notification" && r.agent_id === null) return null;
  const who = (r.agent_type ?? "main").slice(0, 60);
  const title = r.hook_event_name === "StopFailure" ? `Agent ${who} stopped on an API failure; the lead restarts it from its handoff`
    : r.hook_event_name === "Notification" ? `Agent ${who} waits for you in the Claude Code terminal: answer its prompt there, then press Done` : null;
  if (!title) return null;
  return { type: "step.post", key: `alert:${key}`, actor: "script", step: `alert-${createHash("sha256").update(key).digest("hex").slice(0, 12)}`,
    card: null, title, kind: "action", options: null };
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
  private busy: Promise<unknown> = Promise.resolve();
  private obsPath: string;

  private store: Store;

  constructor(store: Store) {
    this.store = store;
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
    const spool = join(this.store.dir, "spool");
    if (!existsSync(spool)) return res;
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

  /** Name matching only (glue): is there a task with this id? Everything else is the reducer's call. */
  private async claimFor(name: string): Promise<Command | null> {
    const t = (await this.store.board()).plan.tasks.find((x) => x.id === name);
    if (!t || t.state === "done") return null;
    return { type: "task.claim", key: `claim:${name}`, actor: "hook", task: name, agent: name };
  }

  private async handle(raw: string, res: DrainResult): Promise<"done" | "retry"> {
    let rec: ObsRecord;
    try { rec = ObsRecord.parse(JSON.parse(raw)); } catch { res.invalid++; return "done"; } // retrying cannot fix it
    // the key joins agent, event and tool_use_id, the same fields a transcript reconciler sees (Lean `ops.obs`)
    const key = await obsKey(this.store.core, rec);
    if (key === null) { res.invalid++; return "done"; }
    if (this.seen.has(key)) { res.duplicates++; return "done"; }
    // work graph: an agent whose name equals a task id was spawned -> task.claim (the reducer decides if it counts)
    const claim = rec.hook_event_name === "SpawnGuard" && rec.agent_name ? await this.claimFor(rec.agent_name) : null;
    if (claim) await this.store.submit(claim); // a refusal is logged in refused.jsonl; it never blocks the spool
    const alert = alertFor(rec, key);
    if (alert) {
      const reply = await this.store.submit(alert);
      if (!reply.ok) { res.retry++; return "retry"; } // not accepted: do NOT mark seen
      res.alerts++;
    }
    const fd = openSync(this.obsPath, "a");
    try { writeSync(fd, JSON.stringify({ key, ...rec }) + "\n"); fsyncSync(fd); } finally { closeSync(fd); }
    this.seen.add(key); // marked seen only now
    res.accepted++;
    return "done";
  }
}

