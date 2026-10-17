// TS STAND-IN, temporary. Marked for Lean replacement: `lean-ops` (usage join + Fw/Wire decoders) will own
// observation dedupe and aggregation. Everything the spool drain decides about observations goes through the two
// functions below, so the swap is one import. Remove this file when the Lean op lands.
import type { ObsLine, ObsRecord, ObsSummaryRow } from "@fw/contracts";

/** Idempotency key from fields BOTH the hook and a later transcript reconciler see: the agent, the event and the
 *  tool_use_id. Events without a tool_use_id (SubagentStart, ...) are hook-only, so their timestamp joins the key. */
export function obsKey(r: ObsRecord): string {
  const who = r.agent_id ?? "main";
  return r.tool_use_id ? `${who}|${r.hook_event_name}|${r.tool_use_id}` : `${who}|${r.hook_event_name}|${r.ts}`;
}

/** Dedupe: a record is fresh iff its key is not in `seen`. The caller marks the key seen only after acceptance. */
export function dedupe(seen: ReadonlySet<string>, r: ObsRecord): { key: string; fresh: boolean } {
  const key = obsKey(r);
  return { key, fresh: !seen.has(key) };
}

/** Aggregate tool calls per (agent type, tool): count, errors, summed hook duration (excludes permission waits). */
export function summarize(lines: readonly ObsLine[]): ObsSummaryRow[] {
  const m = new Map<string, ObsSummaryRow>();
  for (const l of lines) {
    if (l.hook_event_name !== "PostToolUse" && l.hook_event_name !== "PostToolUseFailure") continue;
    const agent_type = l.agent_type ?? "main", tool_name = l.tool_name ?? "?";
    const k = `${agent_type}\0${tool_name}`;
    const row = m.get(k) ?? { agent_type, tool_name, calls: 0, errors: 0, total_ms: 0 };
    row.calls++;
    if (l.is_error) row.errors++;
    row.total_ms += l.duration_ms ?? 0;
    m.set(k, row);
  }
  return [...m.values()];
}
