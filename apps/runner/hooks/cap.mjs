#!/usr/bin/env node
// Capability hook: PreToolUse(Bash) on `pnpm fw *`, synchronous. Appends a single-use capability
// {agent_id, agent_type, tool_use_id, cmd_hash, mac} to .fw-console/caps.jsonl. console-api verifies the MAC, consumes
// it once, and stamps `actor`/`signedBy` itself. Silent and exit 0, except one case: a `pnpm fw` call whose identity
// is unknown (Lean `Fw.Ops.Identity.who`: an agent_id with an empty or missing agent_type, e.g. a forked internal
// agent) gets no capability and is blocked with exit 2 and a one-line reason on stderr (fail closed; never minted
// as the lead). One `pnpm fw` command per Bash call: redirects are dropped and a top-level ; & | or newline ends the command, so `pnpm fw x 2>&1 | tail` is covered as `pnpm fw x`.
// Every refusal to mint has exactly one reason, decided in Lean (`Fw.Ops.Identity.capDecide`, mirrored by `decideCap`):
// notFwPrefix or unknownActor. A trailing filter pipe or redirect is not a reason: `lex` drops it (Lean `capDecide_pipe_invariant`). A reason that is not blocked here is written to .fw-console/capmiss.jsonl,
// and console-api puts it into the 403 that `pnpm fw` then gets, so the miss says why.
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { appendLine, capMac, consoleDir, readPayload, secret, sha256 } from "./lib.mjs";

/** Lex a Bash input into Lean `Tok`s: a string is a word; {redir} is a redirect with its target (`2>&1`, `>f`, `>>f`,
 *  `2>/dev/null`, `<in`, `&>f`); {stop} is a top-level control operator (`|`, `||`, `;`, `&`, `&&`, newline) that ends the
 *  first simple command (lexing stops there). Quotes and backslashes are honoured. I/O glue: the decision is Lean's. */
export function lex(cmd) {
  const out = [];
  let cur = null, q = null, target = false;
  const flush = () => {
    if (cur === null) return;
    out.push(target ? { redir: true } : cur);
    cur = null; target = false;
  };
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
    const amp = c === "&" && cmd[i + 1] === ">"; // `&>file`
    if (c === ">" || c === "<" || amp) {
      if (cur !== null && /^[0-9]+$/.test(cur)) cur = null; // the fd of `2>`
      else flush();
      if (amp) i++;
      while (cmd[i + 1] === ">" || cmd[i + 1] === "<") i++; // `>>`, `<<`
      if (cmd[i + 1] === "&" && !amp) { // `2>&1`, `>&2`, `<&0`: no separate target
        i++;
        while (/[0-9-]/.test(cmd[i + 1] ?? "")) i++;
        out.push({ redir: true });
      } else target = true;
      continue;
    }
    if (c === ";" || c === "&" || c === "|" || c === "\n") { flush(); if (target) out.push({ redir: true }); out.push({ stop: true }); return out; }
    if (/\s/.test(c)) { flush(); continue; }
    cur = (cur ?? "") + c;
  }
  flush();
  if (target) out.push({ redir: true });
  return out;
}

/** MIRROR of Lean `cmdWords`: redirects dropped, a stop ends the command. These words are what `fw` sees as argv. */
export function cmdWords(toks) {
  const out = [];
  for (const t of toks) {
    if (typeof t === "string") out.push(t);
    else if (t.stop) break;
  }
  return out;
}

/** The words of the first simple command of a Bash input. */
export const tokens = (cmd) => cmdWords(lex(cmd));

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

/** The capability decision: MIRROR of Lean `Fw.Ops.Identity.capDecide` (golden `ops.cap`, hooks.test.ts). `toks` are the
 *  words of the first simple command (`cmdWords`). Returns {decision:"mint", actor, argv} or {decision:"noMint", reason}. */
export function decideCap(agentId, agentType, toks) {
  if (toks[0] !== "pnpm" || toks[1] !== "fw") return { decision: "noMint", reason: "notFwPrefix" };
  const argv = toks.slice(2);
  const id = identity(agentId, agentType);
  if (!id.actor) return { decision: "noMint", reason: "unknownActor", error: id.error };
  return { decision: "mint", actor: id.actor, argv };
}

/** What `pnpm fw` prints for each reason (text only; the decision is `decideCap`). */
export const reasonText = {
  notFwPrefix: "the Bash command must START with `pnpm fw` (no leading `cd`, no `pnpm -s fw`, no env prefix)",
  unknownActor: "unknown identity (agent_id without agent_type)",
};

/** Does the command text look like it runs `pnpm fw` somewhere (so a miss deserves a note)? */
export const mentionsFw = (cmd) => /\bpnpm\b[^\n]*\bfw\b/.test(cmd);

/** `fw` reconstructs process.argv.slice(2).join(" "); both sides hash exactly this string. */
export const cmdHash = (argv) => sha256(argv.join(" "));

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    const p = readPayload();
    const cmd = p && p.tool_name === "Bash" && typeof p.tool_input?.command === "string" ? p.tool_input.command : null;
    const argv = cmd ? fwArgv(cmd) : null;
    const dir = cmd && typeof p.tool_use_id === "string" ? consoleDir(p.cwd) : null;
    if (cmd && dir && !argv && mentionsFw(cmd)) {
      // `pnpm fw` somewhere but not first (a leading cd, `pnpm -s fw`): nothing is minted, and the reason is kept for the 403
      const d = decideCap(p.agent_id, p.agent_type, tokens(cmd));
      if (d.decision === "noMint") appendLine(join(dir, "capmiss.jsonl"), { ts: Date.now(), tool_use_id: p.tool_use_id, reason: d.reason, message: reasonText[d.reason] });
    } else if (argv && dir) {
      const d = decideCap(p.agent_id, p.agent_type, tokens(p.tool_input.command));
      if (d.decision === "noMint") {
        process.stderr.write(`cap: no capability minted for \`pnpm fw\` (${d.reason}): ${d.error ?? reasonText[d.reason]}; console-api will refuse this call\n`);
        process.exit(2);
      }
      const id = identity(p.agent_id, p.agent_type);
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
