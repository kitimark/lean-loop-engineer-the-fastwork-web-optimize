// Shared by emit.mjs and cap.mjs. Dependency-free, sync, never prints (a hook's stdout is read by Claude Code).
import { appendFileSync, closeSync, existsSync, mkdirSync, openSync, readFileSync, statSync, writeSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { createHash, createHmac, randomBytes } from "node:crypto";

export function readPayload() {
  try {
    const j = JSON.parse(readFileSync(0, "utf8"));
    return j && typeof j === "object" && !Array.isArray(j) ? j : null;
  } catch { return null; }
}

/** `.fw-console/` at the MAIN checkout (a worktree's `.git` is a file pointing into <main>/.git/worktrees/<n>). */
export function consoleDir(cwd) {
  if (process.env.FW_CONSOLE_DIR) return resolve(process.env.FW_CONSOLE_DIR);
  let d = typeof cwd === "string" && cwd ? resolve(cwd) : process.cwd();
  for (let i = 0; i < 40; i++) {
    const g = join(d, ".git");
    if (existsSync(g)) {
      if (statSync(g).isDirectory()) return join(d, ".fw-console");
      const m = /^gitdir:\s*(.+?)\s*$/m.exec(readFileSync(g, "utf8"));
      if (!m) return null;
      const gd = resolve(d, m[1]);
      const k = gd.lastIndexOf("/.git/worktrees/");
      return k >= 0 ? join(gd.slice(0, k), ".fw-console") : join(dirname(gd), ".fw-console");
    }
    const up = dirname(d);
    if (up === d) return null;
    d = up;
  }
  return null;
}

export const safeName = (s) => (typeof s === "string" && /^[A-Za-z0-9_-]{1,80}$/.test(s) ? s : "main");

export function appendLine(file, obj) {
  mkdirSync(dirname(file), { recursive: true });
  appendFileSync(file, JSON.stringify(obj) + "\n"); // one O_APPEND write per record
}

/** The capability secret: 32 random bytes, created once (mode 0600), never printed. */
export function secret(dir) {
  const f = join(dir, "secret");
  try { return readFileSync(f, "utf8").trim(); } catch { /* create */ }
  mkdirSync(dir, { recursive: true });
  try {
    const fd = openSync(f, "wx", 0o600);
    writeSync(fd, randomBytes(32).toString("hex"));
    closeSync(fd);
  } catch { /* lost a race: read the winner */ }
  return readFileSync(f, "utf8").trim();
}

export const sha256 = (s) => createHash("sha256").update(s).digest("hex");
/** HMAC(secret, agent_id || agent_type || tool_use_id || sha256(cmd)); NUL-separated so the parts cannot run together.
 *  agent_id is bound because it decides the lead (Lean `Fw.Ops.Identity.who`: no agent_id = lead); a null agent_id
 *  is hashed as "", and an empty agent_id is an unknown identity that is never minted nor accepted. */
export const capMac = (sec, agentId, agentType, toolUseId, cmdHash) =>
  createHmac("sha256", sec).update(`${agentId ?? ""}\0${agentType}\0${toolUseId}\0${cmdHash}`).digest("hex");
