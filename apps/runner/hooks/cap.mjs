#!/usr/bin/env node
// Capability hook: PreToolUse(Bash) on `pnpm fw *`, synchronous. Appends a single-use capability
// {agent_id, agent_type, tool_use_id, cmd_hash, mac} to .fw-console/caps.jsonl. console-api verifies the MAC, consumes
// it once, and stamps `actor`/`signedBy` itself. Silent and exit 0, except one case: a `pnpm fw` call whose identity
// is unknown (Lean `Fw.Ops.Identity.who`: an agent_id with an empty or missing agent_type, e.g. a forked internal
// agent) gets no capability and is blocked with exit 2 and a one-line reason on stderr (fail closed; never minted
// as the lead). One `pnpm fw` command per Bash call: anything after ; & | or a newline is not covered.
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

/** Identity of a hook payload or caps.jsonl record: MIRROR of Lean `ops.actor` (`Fw.Ops.Identity.who`/`capActor`),
 *  checked case by case against packages/contracts/golden/ops/ops.actor.jsonl (hooks.test.ts). No agent_id = the
 *  lead; non-empty agent_id and agent_type = that agent (reviewer when the type contains "review", ASCII case
 *  folded, else owner); anything else = unknown (actor null: mint nothing). A non-string field is an error. */
export function identity(agentId, agentType) {
  const opt = (k, v) => (v === undefined || v === null ? { v: null } : typeof v === "string" ? { v } : { error: `field ${k}: expected a string` });
  const i = opt("agent_id", agentId);
  if (i.error) return { error: i.error };
  const t = opt("agent_type", agentType);
  if (t.error) return { error: t.error };
  if (i.v === null) return { who: "lead", role: null, actor: "lead" };
  if (i.v === "" || t.v === null || t.v === "") return { who: "unknown", role: null, actor: null };
  const review = t.v.replace(/[A-Z]/g, (c) => c.toLowerCase()).includes("review");
  return { who: "agent", role: t.v, actor: review ? "reviewer" : "owner" };
}

/** `fw` reconstructs process.argv.slice(2).join(" "); both sides hash exactly this string. */
export const cmdHash = (argv) => sha256(argv.join(" "));

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    const p = readPayload();
    const argv = p && p.tool_name === "Bash" && typeof p.tool_input?.command === "string" ? fwArgv(p.tool_input.command) : null;
    const dir = argv && typeof p.tool_use_id === "string" ? consoleDir(p.cwd) : null;
    if (argv && dir) {
      const id = identity(p.agent_id, p.agent_type);
      if (!id.actor) {
        process.stderr.write(`cap: no capability minted for \`pnpm fw\`: ${id.error ?? "unknown identity (agent_id without agent_type)"}; console-api will refuse this call\n`);
        process.exit(2);
      }
      // The lead's record is {agent_id: null, agent_type: "main"}; an agent's carries both of its own fields.
      const agentId = id.who === "lead" ? null : p.agent_id, agentType = id.who === "lead" ? "main" : id.role;
      const hash = cmdHash(argv);
      appendLine(join(dir, "caps.jsonl"), {
        agent_id: agentId, agent_type: agentType, tool_use_id: p.tool_use_id,
        cmd_hash: hash, mac: capMac(secret(dir), agentId, agentType, p.tool_use_id, hash), ts: Date.now(),
      });
    }
  } catch { /* silent */ }
  process.exit(0);
}
