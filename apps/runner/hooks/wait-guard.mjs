#!/usr/bin/env node
// Wait guard (mistake class c-orphan-wait): PreToolUse(Bash). Asks Lean (`fwcore ops.wait`, Fw.Ops.Wait) whether this
// Bash command starts a long-running process with `&` in a foreground call (fw watch, until/while loop, server, tail -f,
// long sleep) or runs an until/while loop with no bound, and logs the decision to the spool (ObsRecord: event
// `WaitGuard`, tool `Bash`, `verb` = decision[:reason[:shape]]; the command text is never logged).
// Mode (docs/team/tools/wait-guard.md): `shadow` (DEFAULT, ships this way) only logs, no stdout; `enforce` prints a
// PreToolUse permission decision (deny) for a refused command; `off` does nothing. Always exit 0; fwcore missing or
// slow fails open. All parsing and the decision are in Lean; this file only builds the request and writes the line.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { appendLine, consoleDir, readPayload, safeName } from "./lib.mjs";
import { ask, fwcorePath } from "./spawn-guard.mjs";

/** The `ops.wait` request for one PreToolUse(Bash) payload (null when there is no command text). */
export function request(p) {
  const c = p && p.tool_input && typeof p.tool_input === "object" ? p.tool_input.command : undefined;
  return typeof c === "string" && c.length <= 100000 ? { op: "ops.wait", cmd: c } : null;
}

/** The guard mode: FW_WAIT_GUARD, else `mode` in <console dir>/wait-guard.json, else `shadow`. Unknown values = shadow. */
export function modeOf(dir, env = process.env) {
  let m = env.FW_WAIT_GUARD;
  if (!m && dir) {
    try { m = JSON.parse(readFileSync(join(dir, "wait-guard.json"), "utf8")).mode; } catch { /* no file: default */ }
  }
  return m === "enforce" || m === "off" ? m : "shadow";
}

/** The refusal text: the reason, the shape, and what to do instead (this wording is the contract, tested). */
export function message(reply) {
  if (reply.reason === "bgLong") {
    return `wait-guard refused: this command starts a long-running process (${reply.shape ?? "?"}) with a trailing & in a foreground call, `
      + "which leaves an orphan process. Run it with the Bash tool's run_in_background: true and no &, so the tool owns it, "
      + "can stop it and tells you when it ends. For a smoke test (`node server.mjs & pid=$!; ...; kill $pid`), start the "
      + "server in one Bash call with run_in_background: true, run the checks in the next call, then stop the background "
      + "task (TaskStop). Set FW_WAIT_GUARD=shadow to only log.";
  }
  return "wait-guard refused: an until/while loop with no bound never ends if its condition cannot come true. Give it a deadline "
    + "(wrap it in `timeout N`, or test a counter or SECONDS in the loop), or use `pnpm fw ci wait` / run_in_background. "
    + "A read loop counts as bounded only when its condition is exactly `while [VAR=..] read [opts] [names]` followed by "
    + "`do` (no `||`, `&&` or second command) and its input is a file (`done < f`), a here-doc/here-string, or an "
    + "allowlisted producer: `cmd | while read` or `done < <(cmd)` with cmd one of git (read-only subcommands), ls, find, "
    + "grep, rg, jq, printf, echo, seq, sort, head, wc, gh run list/view, cat FILE (docs/team/tools/wait-guard.md). "
    + "Set FW_WAIT_GUARD=shadow to only log.";
}

/** What to print for a decision in the given mode: the PreToolUse hook output, or null (allow, shadow, off, no reply). */
export function verdict(mode, reply) {
  if (mode !== "enforce" || !reply || reply.decision !== "deny") return null;
  return { hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: message(reply) } };
}

/** The spool record for a decision. */
export function record(p, reply, now = Date.now()) {
  const verb = reply ? [reply.decision, reply.reason, reply.shape].filter((x) => typeof x === "string").join(":") : "unavailable";
  const str = (v) => (typeof v === "string" && v.length <= 200 ? v : null);
  return {
    agent_id: str(p.agent_id), agent_type: str(p.agent_type), hook_event_name: "WaitGuard", tool_name: "Bash",
    tool_use_id: str(p.tool_use_id), duration_ms: null, is_error: null, verb: verb.slice(0, 40), ts: now,
  };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    const p = readPayload();
    if (p && p.tool_name === "Bash") {
      const dir = consoleDir(p.cwd);
      const mode = modeOf(dir);
      const q = request(p);
      if (dir && mode !== "off" && q) {
        const reply = ask(fwcorePath(dir), q);
        appendLine(join(dir, "spool", `${safeName(p.agent_id)}.jsonl`), record(p, reply));
        const out = verdict(mode, reply);
        if (out) process.stdout.write(JSON.stringify(out) + "\n");
      }
    }
  } catch { /* fail open: never disturb the agent */ }
  process.exit(0);
}
