#!/usr/bin/env node
// Observer hook (PLAN 3.2 "observers", 3.4 hooks). Appends ONE privacy-filtered JSON line to
// .fw-console/spool/<agent>.jsonl. No socket, no stdout, always exit 0. Never decides anything.
import { readdirSync, readFileSync, unlinkSync, writeFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { basename, join } from "node:path";
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

/** The nearest `claude` ancestor of this hook (at most 6 hops of `ps -o ppid=,comm= -p`); null when none is found, so
 *  the record carries no session pid and no agent is judged by it. TS glue: it reads the process table, decides nothing. */
export function claudePid(start = process.ppid, ps = psRow) {
  let pid = start;
  for (let i = 0; i < 6 && Number.isInteger(pid) && pid > 1; i++) {
    const row = ps(pid);
    if (!row) return null;
    if (basename(row.comm.split(" ")[0] ?? "") === "claude") return pid;
    pid = row.ppid;
  }
  return null;
}
let table = null;
function psRow(pid) {
  if (!table) {
    table = new Map();
    try {
      const out = execFileSync("ps", ["-A", "-o", "pid=,ppid=,comm="], { encoding: "utf8", timeout: 1500 });
      for (const line of out.split("\n")) {
        const m = /^\s*(\d+)\s+(\d+)\s+(.+)$/.exec(line);
        if (m) table.set(Number(m[1]), { ppid: Number(m[2]), comm: m[3] });
      }
    } catch { /* no table: nobody is judged */ }
  }
  return table.get(pid) ?? null;
}

/** The session pid with a per-session cache: one `ps` per session, later hooks read a small file and probe the pid
 *  (a hook may not spawn a process on every call). A dead cached pid is looked up again (a resumed session). */
export function sessionPidCached(p, dir, find = claudePid) {
  const sid = str(p.session_id);
  const file = sid && dir ? join(dir, `session-pid-${safeName(sid)}`) : null;
  if (file) {
    try {
      const pid = Number(readFileSync(file, "utf8"));
      if (pid === 0) return null; // looked up before: no claude ancestor, nobody is judged
      if (Number.isInteger(pid) && pid > 1) { process.kill(pid, 0); return pid; }
    } catch { /* no cache, or the cached pid is gone */ }
  }
  const pid = find();
  if (file) { try { writeFileSync(file, String(pid ?? 0)); } catch { /* cache only */ } }
  return pid;
}

/** The only fields that ever leave the payload. */
export function record(p, now = Date.now(), sessionPid = null) {
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
    // the Claude session that fired the hook: the hook's parent process (an agent whose session pid is gone is dead)
    ...(sessionPid === null ? {} : { session_pid: sessionPid }),
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
    const dir = p && consoleDir(p.cwd);
    const r = p && record(p, Date.now(), sessionPidCached(p, dir));
    if (r && dir) {
      appendLine(join(dir, "spool", `${safeName(p.agent_id)}.jsonl`), r);
      const u = unseenSpawn(p, dir);
      if (u) appendLine(join(dir, "spool", `${safeName(p.agent_id)}.jsonl`), u);
    }
  } catch { /* silent by design: an observer must never disturb the agent */ }
  process.exit(0);
}
