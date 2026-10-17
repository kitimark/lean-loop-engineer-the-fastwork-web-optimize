// Capability check for `pnpm fw` requests (PLAN 3.2 "agent -> console-api"). The hook (apps/runner/hooks/cap.mjs)
// appends caps.jsonl; here the MAC is verified and the capability consumed exactly once. The HMAC is crypto I/O and
// stays in TS. WHAT an actor may do is NOT decided here: the stamped actor goes through the Lean authority table
// (`may`) in the reducer. This file only maps "who held the capability" to an identity.
import { createHmac, createHash, randomBytes, timingSafeEqual } from "node:crypto";
import { closeSync, existsSync, fsyncSync, mkdirSync, openSync, readFileSync, writeFileSync, writeSync } from "node:fs";
import { join } from "node:path";
import { CapRecord, Command, type Actor } from "@fw/contracts";

export const CAP_TTL_MS = 10 * 60_000;

export const sha256 = (s: string) => createHash("sha256").update(s).digest("hex");
/** Same formula as hooks/lib.mjs capMac (a test pins the two together). */
export const capMac = (secret: string, agentType: string, toolUseId: string, cmdHash: string) =>
  createHmac("sha256", secret).update(`${agentType}\0${toolUseId}\0${cmdHash}`).digest("hex");

/** Identity of the capability holder -> actor. Never `user`, `script` or `git`: the socket cannot produce them. */
export function actorFor(agentType: string): Actor {
  if (agentType === "main") return "lead";
  return /review/i.test(agentType) ? "reviewer" : "owner";
}

export type Stamp = { actor: Actor; signedBy: string; toolUseId: string };

export class CapStore {
  private chain: Promise<unknown> = Promise.resolve();
  private dir: string;
  private clock: () => number;
  constructor(dir: string, clock: () => number = Date.now) { this.dir = dir; this.clock = clock; }

  private secret(): string | null {
    const f = join(this.dir, "secret");
    return existsSync(f) ? readFileSync(f, "utf8").trim() : null;
  }
  /** Console-api creates the secret at start so the hook only ever reads it. */
  ensureSecret() {
    mkdirSync(this.dir, { recursive: true });
    const f = join(this.dir, "secret");
    if (!existsSync(f)) writeFileSync(f, randomBytes(32).toString("hex"), { mode: 0o600, flag: "wx" });
  }

  private lines(name: string): unknown[] {
    const f = join(this.dir, name);
    if (!existsSync(f)) return [];
    return readFileSync(f, "utf8").split("\n").filter(Boolean).flatMap((l) => { try { return [JSON.parse(l)]; } catch { return []; } });
  }

  /** Find the oldest unused, authentic, fresh capability for this command, and consume it. Serialised. */
  consume(argv: string[]): Promise<Stamp | null> {
    const run = this.chain.then(() => this.consumeNow(argv));
    this.chain = run.catch(() => undefined);
    return run;
  }

  private consumeNow(argv: string[]): Stamp | null {
    const sec = this.secret();
    if (!sec) return null;
    const used = new Set(this.lines("caps.used.jsonl").map((u) => (u as { tool_use_id?: string }).tool_use_id));
    const want = sha256(argv.join(" "));
    const now = this.clock();
    for (const raw of this.lines("caps.jsonl")) {
      const p = CapRecord.safeParse(raw);
      if (!p.success) continue;
      const c = p.data;
      if (used.has(c.tool_use_id) || c.cmd_hash !== want || now - c.ts > CAP_TTL_MS || c.ts - now > 60_000) continue;
      const exp = Buffer.from(capMac(sec, c.agent_type, c.tool_use_id, c.cmd_hash), "hex");
      const got = Buffer.from(c.mac, "hex");
      if (exp.length !== got.length || !timingSafeEqual(exp, got)) continue;
      const fd = openSync(join(this.dir, "caps.used.jsonl"), "a");
      try { writeSync(fd, JSON.stringify({ tool_use_id: c.tool_use_id, ts: now }) + "\n"); fsyncSync(fd); } finally { closeSync(fd); }
      return { actor: actorFor(c.agent_type), signedBy: c.agent_id ?? c.agent_type, toolUseId: c.tool_use_id };
    }
    return null;
  }
}

/** Put the stamp on a request body: actor always, signedBy on reviews. Any actor the client sent is overwritten. */
export function stamp(body: unknown, s: Stamp): ReturnType<typeof Command.safeParse> {
  const o = typeof body === "object" && body !== null ? { ...(body as Record<string, unknown>) } : {};
  o.actor = s.actor;
  if (o.type === "card.review") o.signedBy = s.signedBy;
  return Command.safeParse(o);
}
