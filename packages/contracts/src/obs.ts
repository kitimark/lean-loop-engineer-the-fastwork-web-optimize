// Observation + capability records (PLAN 3.2 "agent -> console-api", "observers -> console-api").
// Observations are facts, not events: they live in .fw-console/obs.jsonl. Only alerts reach events.jsonl.
import { z } from "zod";

/** One spool line written by apps/runner/hooks/emit.mjs. Nothing else leaves a hook payload. Typing only: the drain
 *  admits lines with Lean (`ops.obs` raw, `Fw.Ops.Obs.admit`): only the decision fields (hook_event_name, agent_id,
 *  agent_name, ts) can reject a line; any other field that is missing or ill-typed is kept as null (or left out) with a
 *  note, and an unknown field is left out and named. Rejections, notes and unknown fields are all raised as one spool
 *  alert. The drain writes only the kept fields, so every obs.jsonl line still parses as `ObsLine`. Keep the fields in
 *  step with `Fw.Ops.Obs.specs` (a golden test checks that zod accepts every Lean-kept record). */
export const ObsRecord = z.object({
  agent_id: z.string().min(1).max(120).nullable(),
  agent_type: z.string().max(200).nullable(),
  hook_event_name: z.string().min(1).max(200),
  tool_name: z.string().max(200).nullable(),
  tool_use_id: z.string().max(200).nullable(),
  duration_ms: z.number().int().nonnegative().nullable(),
  is_error: z.boolean().nullable(),
  verb: z.string().max(40).nullable(),
  /** SpawnGuard only: the `name` of the spawned agent (work-graph tasks are claimed by agents named like the task) */
  agent_name: z.string().min(1).max(120).nullable().optional(),
  /** SpawnGuard only (spawn-guard-workflows): who saw the spawn, and the kind the guard expected vs was given */
  seen_by: z.string().max(40).nullable().optional(),
  role: z.string().max(200).nullable().optional(),
  want_kind: z.string().max(40).nullable().optional(),
  got_kind: z.string().max(40).nullable().optional(),
  isolation: z.boolean().nullable().optional(),
  depth: z.number().int().nonnegative().nullable().optional(),
  has_name: z.boolean().nullable().optional(),
  /** Notification only (alert-steps): the notification type and the message length; never the message text */
  notification_type: z.string().max(40).nullable().optional(),
  message_len: z.number().int().nonnegative().nullable().optional(),
  /** Stop / SubagentStop (SPK-p part 3): the count of still-running background tasks, never their text. MEASURED
   *  (task-state-truth): session-wide, 6 to 31 on every SubagentStop of the spool, never 0, so it does not decide
   *  whether an agent ended; the drain does not read it (Lean `Fw.Ops.Obs.lifeOf`). */
  background_tasks: z.number().int().nonnegative().nullable().optional(),
  /** The pid of the Claude session whose hook wrote the line (the hook's parent process); an agent whose session pid is
   *  not in the process table is dead (Lean `Fw.Obs.Health.deadSession`). */
  session_pid: z.number().int().nonnegative().nullable().optional(),
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
