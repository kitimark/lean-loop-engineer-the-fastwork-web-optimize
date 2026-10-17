// Observation + capability records (PLAN 3.2 "agent -> console-api", "observers -> console-api").
// Observations are facts, not events: they live in .fw-console/obs.jsonl. Only alerts reach events.jsonl.
import { z } from "zod";

/** One spool line written by apps/runner/hooks/emit.mjs. Nothing else leaves a hook payload. */
export const ObsRecord = z.object({
  agent_id: z.string().max(200).nullable(),
  agent_type: z.string().max(200).nullable(),
  hook_event_name: z.string().min(1).max(200),
  tool_name: z.string().max(200).nullable(),
  tool_use_id: z.string().max(200).nullable(),
  duration_ms: z.number().int().nonnegative().nullable(),
  is_error: z.boolean().nullable(),
  verb: z.string().max(40).nullable(),
  /** SpawnGuard only: the `name` of the spawned agent (work-graph tasks are claimed by agents named like the task) */
  agent_name: z.string().max(200).nullable().optional(),
  ts: z.number().int().nonnegative(),
}).strict();
export type ObsRecord = z.infer<typeof ObsRecord>;

/** One line of obs.jsonl: an accepted observation and its idempotency key. */
export const ObsLine = ObsRecord.extend({ key: z.string().min(1) }).strict();
export type ObsLine = z.infer<typeof ObsLine>;

/** One line of caps.jsonl, written by apps/runner/hooks/cap.mjs. */
export const CapRecord = z.object({
  agent_id: z.string().nullable(),
  agent_type: z.string().min(1),
  tool_use_id: z.string().min(1),
  cmd_hash: z.string().regex(/^[0-9a-f]{64}$/),
  mac: z.string().regex(/^[0-9a-f]{64}$/),
  ts: z.number().int().nonnegative(),
}).strict();
export type CapRecord = z.infer<typeof CapRecord>;

/** Body of POST /api/agent/commands: `argv` is what `fw` was started with; the actor inside `command` is ignored. */
export const AgentRequest = z.object({ argv: z.array(z.string()), command: z.unknown() });
export type AgentRequest = z.infer<typeof AgentRequest>;

/** Per (agent type, tool) aggregate of observed tool calls. */
export const ObsSummaryRow = z.object({
  agent_type: z.string(), tool_name: z.string(), calls: z.number().int(), errors: z.number().int(), total_ms: z.number().int(),
});
export type ObsSummaryRow = z.infer<typeof ObsSummaryRow>;
