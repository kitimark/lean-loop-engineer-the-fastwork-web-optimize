#!/usr/bin/env node
// Capability hook: PreToolUse(Bash) on `pnpm fw *`, synchronous. Appends a single-use capability
// {agent_type, tool_use_id, cmd_hash, mac} to .fw-console/caps.jsonl. console-api verifies the MAC, consumes it
// once, and stamps `actor`/`signedBy` itself. Silent, always exit 0 (a missing capability just means the request
// is refused later). One `pnpm fw` command per Bash call: anything after ; & | or a newline is not covered.
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { appendLine, capMac, consoleDir, readPayload, secret, sha256 } from "./lib.mjs";

/** Shell-like split of the first simple command: quotes honoured, stops at an unquoted ; & | or newline. */
export function tokens(cmd) {
  const out = [];
  let cur = null, q = null;
  for (let i = 0; i < cmd.length; i++) {
    const c = cmd[i];
    if (q) {
      if (c === q) q = null;
      else if (c === "\\" && q === '"' && i + 1 < cmd.length) cur += cmd[++i];
      else cur += c;
      continue;
    }
    if (c === "'" || c === '"') { q = c; cur ??= ""; continue; }
    if (c === "\\" && i + 1 < cmd.length) { cur = (cur ?? "") + cmd[++i]; continue; }
    if (c === ";" || c === "&" || c === "|" || c === "\n") break;
    if (/\s/.test(c)) { if (cur !== null) { out.push(cur); cur = null; } continue; }
    cur = (cur ?? "") + c;
  }
  if (cur !== null) out.push(cur);
  return out;
}

/** argv of `pnpm fw <argv...>`, or null when the command is something else. */
export function fwArgv(cmd) {
  const t = tokens(cmd);
  return t[0] === "pnpm" && t[1] === "fw" ? t.slice(2) : null;
}

/** `fw` reconstructs process.argv.slice(2).join(" "); both sides hash exactly this string. */
export const cmdHash = (argv) => sha256(argv.join(" "));

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    const p = readPayload();
    const argv = p && p.tool_name === "Bash" && typeof p.tool_input?.command === "string" ? fwArgv(p.tool_input.command) : null;
    const dir = argv && typeof p.tool_use_id === "string" ? consoleDir(p.cwd) : null;
    if (argv && dir) {
      const agentType = typeof p.agent_type === "string" && p.agent_type ? p.agent_type : "main";
      const hash = cmdHash(argv);
      appendLine(join(dir, "caps.jsonl"), {
        agent_id: typeof p.agent_id === "string" ? p.agent_id : null, agent_type: agentType, tool_use_id: p.tool_use_id,
        cmd_hash: hash, mac: capMac(secret(dir), agentType, p.tool_use_id, hash), ts: Date.now(),
      });
    }
  } catch { /* silent */ }
  process.exit(0);
}
