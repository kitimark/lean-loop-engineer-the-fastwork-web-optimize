#!/usr/bin/env node
// Observer hook (PLAN 3.2 "observers", 3.4 hooks). Appends ONE privacy-filtered JSON line to
// .fw-console/spool/<agent>.jsonl. No socket, no stdout, always exit 0. Never decides anything.
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

/** The only fields that ever leave the payload. */
export function record(p, now = Date.now()) {
  const ev = str(p.hook_event_name);
  if (!ev) return null;
  const failed = ev === "PostToolUseFailure";
  return {
    agent_id: str(p.agent_id), agent_type: str(p.agent_type), hook_event_name: ev,
    tool_name: str(p.tool_name), tool_use_id: str(p.tool_use_id), duration_ms: num(p.duration_ms),
    is_error: ev === "PostToolUse" || failed ? failed : null,
    verb: p.tool_name === "Bash" ? verbOf(p.tool_input?.command) : null,
    ts: now,
  };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    const p = readPayload();
    const r = p && record(p);
    const dir = r && consoleDir(p.cwd);
    if (r && dir) appendLine(join(dir, "spool", `${safeName(p.agent_id)}.jsonl`), r);
  } catch { /* silent by design: an observer must never disturb the agent */ }
  process.exit(0);
}
