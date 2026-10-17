// Spool drain: .fw-console/spool/*.jsonl -> obs.jsonl (observations) and, for alerts only, events.jsonl through
// the normal reducer path (a `step.post` caused by actor "script", i.e. console-api itself; the Lean authority table
// still decides). A key is marked seen only after its fact is accepted, so a refused alert is retried next drain.
import { existsSync, fsyncSync, openSync, closeSync, readFileSync, readdirSync, statSync, writeSync } from "node:fs";
import { createHash } from "node:crypto";
import { join } from "node:path";
import { ObsLine, ObsRecord, type Command } from "@fw/contracts";
import type { Store } from "../store.ts";
import { dedupe, summarize } from "./standin.ts";

export type DrainResult = { accepted: number; duplicates: number; invalid: number; retry: number; alerts: number };

/** Hook events that need a human or signal a stopped agent; everything else is an observation only. */
export function alertFor(r: ObsRecord, key: string): Command | null {
  const who = (r.agent_type ?? "main").slice(0, 60);
  const title = r.hook_event_name === "StopFailure" ? `Agent ${who} stopped on an API failure`
    : r.hook_event_name === "Notification" ? `Agent ${who} needs input` : null;
  if (!title) return null;
  return { type: "step.post", key: `alert:${key}`, actor: "script", step: `alert-${createHash("sha256").update(key).digest("hex").slice(0, 12)}`,
    card: null, title, kind: "action", options: null };
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

  summary() { return summarize(this.obsLines()); }

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

  private async handle(raw: string, res: DrainResult): Promise<"done" | "retry"> {
    let rec: ObsRecord;
    try { rec = ObsRecord.parse(JSON.parse(raw)); } catch { res.invalid++; return "done"; } // retrying cannot fix it
    const { key, fresh } = dedupe(this.seen, rec);
    if (!fresh) { res.duplicates++; return "done"; }
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

