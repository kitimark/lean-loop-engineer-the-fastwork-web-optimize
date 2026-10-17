#!/usr/bin/env node
// Observer hook (PLAN 3.2 "observers", 3.4 hooks). Appends ONE privacy-filtered JSON line to
// .fw-console/spool/<agent>.jsonl. No socket, no stdout, always exit 0. Never decides anything.
import { readdirSync, readFileSync, unlinkSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { appendLine, consoleDir, readPayload, safeName } from "./lib.mjs";

// first token of a Bash command, kept only when it is on this list (never a path, never an argument)
export const VERBS = new Set(["pnpm", "npm", "npx", "node", "git", "lake", "lean", "ls", "cat", "grep", "rg", "sed", "awk",
  "find", "curl", "mkdir", "rm", "cp", "mv", "echo", "cd", "brew", "python3", "sleep", "wc", "head", "tail", "jq",
  "tsc", "vitest", "open", "chmod", "touch", "diff", "xcrun", "which", "sort", "tee", "gh", "cargo", "make"]);

export function verbOf(command) {
  if (typeof command !== "string") return null;
  const first = command.trim().split(/\s+/)[0] ?? "";
  return VERBS.has(first) ? first : "other";
}

const str = (v) => (typeof v === "string" && v.length <= 200 ? v : null);
const num = (v) => (Number.isFinite(v) ? Math.round(v) : null);

/** Notification facts for alert steps: the type (a short token), the message LENGTH, and, for a permission prompt, the
 *  tool name taken from "...permission to use <Tool>" (one identifier token; the message text itself never leaves). */
export function notification(p) {
  const msg = typeof p.message === "string" ? p.message : "";
  const m = /permission to use ([A-Za-z0-9_.:-]{1,60})/.exec(msg);
  const type = typeof p.notification_type === "string" && /^[a-z_]{1,40}$/.test(p.notification_type) ? p.notification_type : null;
  return { type, len: msg.length, tool: m ? m[1] : null };
}

/** The only fields that ever leave the payload. */
export function record(p, now = Date.now()) {
  const ev = str(p.hook_event_name);
  if (!ev) return null;
  const failed = ev === "PostToolUseFailure";
  const note = ev === "Notification" ? notification(p) : null;
  return {
    agent_id: str(p.agent_id), agent_type: str(p.agent_type), hook_event_name: ev,
    tool_name: str(p.tool_name) ?? note?.tool ?? null, tool_use_id: str(p.tool_use_id), duration_ms: num(p.duration_ms),
    ...(note ? { notification_type: note.type, message_len: note.len } : {}),
    is_error: ev === "PostToolUse" || failed ? failed : null,
    verb: p.tool_name === "Bash" ? verbOf(p.tool_input?.command) : null,
    ts: now,
    // SPK-p part 3 (wake test): a count only, never the task text
    ...(Array.isArray(p.background_tasks) || Number.isFinite(p.background_tasks)
      ? { background_tasks: Array.isArray(p.background_tasks) ? p.background_tasks.length : Math.round(p.background_tasks) } : {}),
  };
}

/** SubagentStart of an agent the spawn guard did not see (workflow agents never fire PreToolUse(Agent)): claim a pending
 *  guard marker of the same role (unlink is the atomic claim); none claimable -> a SpawnGuard-equivalent observation.
 *  TS STAND-IN (matching by role + recency; not a Lean decision; no blocking, Q31). */
export function unseenSpawn(p, dir, now = Date.now()) {
  if (p.hook_event_name !== "SubagentStart" || !str(p.agent_id)) return null;
  const role = str(p.agent_type) ?? "general-purpose";
  const pd = join(dir, "spawn-pending");
  try {
    for (const f of readdirSync(pd).sort()) {
      const t = Number(f.split("-")[0]);
      try {
        if (now - t > 600000) { unlinkSync(join(pd, f)); continue; }
        if (JSON.parse(readFileSync(join(pd, f), "utf8")).role !== role) continue;
        unlinkSync(join(pd, f));
        return null; // seen by the guard
      } catch { /* raced with another hook: try the next marker */ }
    }
  } catch { /* no pending dir: nothing seen */ }
  return { agent_id: p.agent_id, agent_type: str(p.agent_type), hook_event_name: "SpawnGuard", tool_name: "Agent",
    tool_use_id: null, duration_ms: null, is_error: null, verb: "observed", ts: now, role, seen_by: "subagent-start" };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    const p = readPayload();
    const r = p && record(p);
    const dir = r && consoleDir(p.cwd);
    if (r && dir) {
      appendLine(join(dir, "spool", `${safeName(p.agent_id)}.jsonl`), r);
      const u = unseenSpawn(p, dir);
      if (u) appendLine(join(dir, "spool", `${safeName(p.agent_id)}.jsonl`), u);
    }
  } catch { /* silent by design: an observer must never disturb the agent */ }
  process.exit(0);
}
