#!/usr/bin/env node
// Spawn guard (PLAN 8.3): PreToolUse(Agent). Asks Lean (`fwcore ops.spawn`) what it decides for this `Agent` call and
// logs the decision to the spool. Mode (docs/team/tools/spawn-guard.md): `enforce` (default) prints a PreToolUse
// permission decision (deny / ask) for a refused spawn; `shadow` only logs (no stdout); `off` does nothing. Always
// exit 0; fwcore missing or slow fails open. Lead decision:
// `caps.unnamedReadOnly = true` (unnamed read-only subagents are allowed). The decision is made in Lean; this file only
// builds the request and writes the log line (an ObsRecord: event `SpawnGuard`, `verb` = decision[:reason]).
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { appendLine, consoleDir, readPayload, safeName } from "./lib.mjs";

/** Role table (.claude/agents). INFERRED mapping; the real one belongs in Lean/config. runsAs: how the role is run. */
export const ROLES = [
  ["lean-prover", "worktree", true], ["console-builder", "worktree", true], ["measure-engineer", "worktree", true],
  ["part-builder", "worktree", true], ["env-ops", "worktree", true], ["page-writer", "worktree", true],
  ["researcher", "teammate", true], ["plan-editor", "teammate", true],
  ["reviewer", "subagent", false], ["math-reviewer", "subagent", false], ["checker", "subagent", false],
  ["slop-checker", "subagent", false], ["scout", "subagent", false], ["runner", "subagent", false], ["patcher", "subagent", true],
  ["Explore", "subagent", false], ["Plan", "subagent", false], ["general-purpose", "subagent", true],
  ["fork", "subagent", false], ["workflow-subagent", "subagent", false], // = Lean SpawnGuard.prodRoles
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

/** Expected vs given kind, logged so a kindMismatch explains itself. Both come from the same fwcore `ops.spawn` reply
 *  as the decision (`wantKind` = Lean `SpawnGuard.wantKind`, the role's runsAs or null; `kind` = `effKind`), so no
 *  extra call; null when fwcore was unavailable. */
export function kinds(req, reply) {
  const k = (v) => (typeof v === "string" ? v : null);
  return { role: req.role, want_kind: k(reply?.wantKind), got_kind: k(reply?.kind), has_name: !!req.name, isolation: !!req.isolation, depth: req.depth };
}

/** The guard mode: FW_SPAWN_GUARD, else `mode` in <console dir>/spawn-guard.json, else `enforce`. Unknown values = enforce. */
export function modeOf(dir, env = process.env) {
  let m = env.FW_SPAWN_GUARD;
  if (!m && dir) {
    try { m = JSON.parse(readFileSync(join(dir, "spawn-guard.json"), "utf8")).mode; } catch { /* no file: default */ }
  }
  return m === "shadow" || m === "off" ? m : "enforce";
}

/** The refusal message: always names the reason (Lean `deny_names_reason`). */
export function message(req, reply) {
  const r = reply.reason ?? "unspecified";
  const more = r === "kindMismatch" ? ` (role ${req.role} wants ${reply.want}, this call gives ${reply.got}; use isolation: "worktree" for a worktree role)`
    : r === "capRole" ? ` (${reply.role})` : "";
  return `spawn-guard ${reply.decision === "deny" ? "refused" : "asks"}: ${r}${more}. Set FW_SPAWN_GUARD=shadow to only log.`;
}

/** What to print for a decision in the given mode: the PreToolUse hook output, or null (allow, shadow, off, no reply). */
export function verdict(mode, req, reply) {
  if (mode !== "enforce" || !reply || (reply.decision !== "deny" && reply.decision !== "needsApproval")) return null;
  return { hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: reply.decision === "deny" ? "deny" : "ask", permissionDecisionReason: message(req, reply) } };
}

/** The spool record for a decision. */
export function record(p, reply, now = Date.now()) {
  const verb = reply ? (reply.reason ? `${reply.decision}:${reply.reason}` : reply.decision) : "unavailable";
  const str = (v) => (typeof v === "string" && v.length <= 200 ? v : null);
  return {
    agent_id: str(p.agent_id), agent_type: str(p.agent_type), hook_event_name: "SpawnGuard", tool_name: "Agent",
    tool_use_id: str(p.tool_use_id), duration_ms: null, is_error: null, verb: verb.slice(0, 40), ts: now,
    agent_name: str(p.tool_input && typeof p.tool_input === "object" ? p.tool_input.name : null),
    ...kinds(request(p).req, reply), seen_by: "pre-tool-use",
  };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    const p = readPayload();
    if (p && p.tool_name === "Agent") {
      const dir = consoleDir(p.cwd);
      const mode = modeOf(dir);
      if (dir && mode !== "off") {
        const q = request(p);
        const reply = ask(fwcorePath(dir), q);
        appendLine(join(dir, "spool", `${safeName(p.agent_id)}.jsonl`), record(p, reply));
        const out = verdict(mode, q.req, reply);
        if (out) process.stdout.write(JSON.stringify(out) + "\n");
        // a refused spawn never starts; otherwise a pending marker: emit.mjs claims it on SubagentStart, so only spawns this guard did not see get a second record
        if (!(out && out.hookSpecificOutput.permissionDecision === "deny")) {
          const pd = join(dir, "spawn-pending");
          mkdirSync(pd, { recursive: true });
          writeFileSync(join(pd, `${Date.now()}-${safeName(p.tool_use_id)}.json`), JSON.stringify({ role: q.req.role }));
        }
      }
    }
  } catch { /* fail open: never disturb the agent */ }
  process.exit(0);
}
