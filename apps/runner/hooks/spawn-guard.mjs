#!/usr/bin/env node
// Spawn guard, SHADOW MODE (PLAN 8.3): PreToolUse(Agent). Asks Lean (`fwcore ops.spawn`) what it would decide for this
// `Agent` call and logs the decision to the spool; it NEVER blocks: no stdout, always exit 0. Lead decision:
// `caps.unnamedReadOnly = true` (unnamed read-only subagents are allowed). The decision is made in Lean; this file only
// builds the request and writes the log line (an ObsRecord: event `SpawnGuard`, `verb` = decision[:reason]).
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { appendLine, consoleDir, readPayload, safeName } from "./lib.mjs";

/** Role table (.claude/agents). INFERRED mapping; the real one belongs in Lean/config. runsAs: how the role is run. */
export const ROLES = [
  ["lean-prover", "worktree", true], ["console-builder", "worktree", true], ["measure-engineer", "worktree", true],
  ["part-builder", "worktree", true], ["env-ops", "worktree", true], ["page-writer", "worktree", true],
  ["researcher", "teammate", true], ["plan-editor", "teammate", true],
  ["reviewer", "subagent", false], ["math-reviewer", "subagent", false], ["checker", "subagent", false],
  ["scout", "subagent", false], ["runner", "subagent", false], ["patcher", "subagent", true],
  ["Explore", "subagent", false], ["Plan", "subagent", false], ["general-purpose", "subagent", true],
].map(([name, runsAs, edits]) => ({ name, runsAs, edits }));

/** Lead decision: unnamed read-only subagents are allowed. */
export const CAPS = { unnamedReadOnly: true };

/** The `ops.spawn` request for one PreToolUse(Agent) payload. `alive`/`recent` are empty in shadow mode (no liveness feed yet). */
export function request(p, now = Math.floor(Date.now() / 1000)) {
  const i = p.tool_input && typeof p.tool_input === "object" ? p.tool_input : {};
  const s = (v) => (typeof v === "string" && v.length > 0 && v.length <= 200 ? v : undefined);
  const nested = typeof p.agent_id === "string" && p.agent_id.length > 0;
  const req = { role: s(i.subagent_type) ?? "general-purpose", depth: nested ? 1 : 0, spawner: nested ? (s(p.agent_type) ?? "agent") : "lead" };
  if (s(i.name)) req.name = s(i.name);
  if (i.isolation === "worktree" || typeof i.isolation === "boolean") req.isolation = i.isolation;
  if (s(i.model)) req.model = s(i.model);
  return { op: "ops.spawn", alive: [], roles: ROLES, caps: CAPS, recent: [], now, req };
}

/** Where fwcore is: FW_CORE_BIN, else <main checkout>/lean/.lake/build/bin/fwcore. */
export function fwcorePath(dir) {
  if (process.env.FW_CORE_BIN) return process.env.FW_CORE_BIN;
  return dir ? join(dirname(dir), "lean/.lake/build/bin/fwcore") : null;
}

/** Ask Lean. Returns the reply object, or null when fwcore is missing, slow or answers an error. */
export function ask(bin, req) {
  if (!bin || !existsSync(bin)) return null;
  const r = spawnSync(bin, [], { input: JSON.stringify({ id: 1, ...req }) + "\n", encoding: "utf8", timeout: 3000 });
  try {
    const m = JSON.parse((r.stdout ?? "").split("\n")[0] ?? "");
    return m && m.id === 1 && typeof m.decision === "string" ? m : null;
  } catch { return null; }
}

/** TS STAND-IN for Lean `Fw.Ops.SpawnGuard.effKind`/`roleOf`: expected vs given kind, logged so a kindMismatch explains
 *  itself. The decision itself still comes from fwcore; this only describes the request. Replace by a fwcore reply field. */
export function kinds(req) {
  const role = ROLES.find((r) => r.name === req.role);
  const got = req.isolation ? "worktree" : req.depth === 0 && req.name ? "teammate" : "subagent";
  return { role: req.role, want_kind: role ? role.runsAs : null, got_kind: got, has_name: !!req.name, isolation: !!req.isolation, depth: req.depth };
}

/** The spool record for a decision. */
export function record(p, reply, now = Date.now()) {
  const verb = reply ? (reply.reason ? `${reply.decision}:${reply.reason}` : reply.decision) : "unavailable";
  const str = (v) => (typeof v === "string" && v.length <= 200 ? v : null);
  return {
    agent_id: str(p.agent_id), agent_type: str(p.agent_type), hook_event_name: "SpawnGuard", tool_name: "Agent",
    tool_use_id: str(p.tool_use_id), duration_ms: null, is_error: null, verb: verb.slice(0, 40), ts: now,
    agent_name: str(p.tool_input && typeof p.tool_input === "object" ? p.tool_input.name : null),
    ...kinds(request(p).req), seen_by: "pre-tool-use",
  };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    const p = readPayload();
    if (p && p.tool_name === "Agent") {
      const dir = consoleDir(p.cwd);
      if (dir) {
        appendLine(join(dir, "spool", `${safeName(p.agent_id)}.jsonl`), record(p, ask(fwcorePath(dir), request(p))));
        // pending marker: emit.mjs claims it on SubagentStart, so only spawns this guard did not see get a second record
        const pd = join(dir, "spawn-pending");
        mkdirSync(pd, { recursive: true });
        writeFileSync(join(pd, `${Date.now()}-${safeName(p.tool_use_id)}.json`), JSON.stringify({ role: request(p).req.role }));
      }
    }
  } catch { /* shadow mode: never disturb the agent */ }
  process.exit(0);
}
