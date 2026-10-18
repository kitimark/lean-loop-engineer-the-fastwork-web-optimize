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
/** Same formula as hooks/lib.mjs capMac (a test pins the two together). agent_id is bound: it decides the lead. */
export const capMac = (secret: string, agentId: string | null, agentType: string, toolUseId: string, cmdHash: string) =>
  createHmac("sha256", secret).update(`${agentId ?? ""}\0${agentType}\0${toolUseId}\0${cmdHash}`).digest("hex");

/** Identity of the capability holder -> actor, or null (unknown identity: refuse). MIRROR of Lean `ops.actor`
 *  (`Fw.Ops.Identity.capActor`), checked case by case against packages/contracts/golden/ops/ops.actor.jsonl
 *  (cap.test.ts). The lead is the record with NO agent_id (its agent_type is ignored); an agent_id needs a non-empty
 *  agent_type (a forked internal agent has ""), and then the actor is `reviewer` when the type contains "review"
 *  (ASCII case folded), else `owner`. Never `user`, `script`, `git` or `hook`: the socket cannot produce them.
 *  A teammate's agent_type is its NAME, not its role (SPK-c); resolving it needs a roster (open). */
export function actorFor(agentId: string | null | undefined, agentType: string | null | undefined): Actor | null {
  if (agentId === null || agentId === undefined) return "lead";
  if (agentId === "" || !agentType) return null;
  return agentType.replace(/[A-Z]/g, (c) => c.toLowerCase()).includes("review") ? "reviewer" : "owner";
}

/** The door without a capability (`POST /api/commands`): MIRROR of Lean `Fw.Ops.Identity.openDoor` (golden `ops.door`,
 *  cap.test.ts). A body that claims an agent actor (`lead`, `owner`, `reviewer`: exactly the actors a capability
 *  can be minted for) is accepted only when the caller shows the console secret; user, script, git and hook pass. */
export const isAgentActor = (a: Actor): boolean => a === "lead" || a === "owner" || a === "reviewer";
export const openDoor = (a: Actor, secret: boolean): boolean => !isAgentActor(a) || secret;

/** Header that carries the console secret for the door without a capability (the runner's own tools send it). */
export const SECRET_HEADER = "x-fw-secret";

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

  /** Constant-time check of a presented secret against `.fw-console/secret`. */
  secretMatches(presented: string | undefined | null): boolean {
    const s = this.secret();
    if (!s || !presented) return false;
    const a = Buffer.from(s), b = Buffer.from(presented);
    return a.length === b.length && timingSafeEqual(a, b);
  }

  /** The hook's reason for the latest miss (capmiss.jsonl, written by cap.mjs) if it is at most `maxAgeMs` old. */
  lastMiss(maxAgeMs = 2 * 60_000): { reason: string; message: string } | null {
    const l = this.lines("capmiss.jsonl").at(-1) as { ts?: number; reason?: string; message?: string } | undefined;
    if (!l || typeof l.ts !== "number" || typeof l.reason !== "string" || this.clock() - l.ts > maxAgeMs) return null;
    return { reason: l.reason, message: String(l.message ?? "") };
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
      const exp = Buffer.from(capMac(sec, c.agent_id, c.agent_type, c.tool_use_id, c.cmd_hash), "hex");
      const got = Buffer.from(c.mac, "hex");
      if (exp.length !== got.length || !timingSafeEqual(exp, got)) continue;
      const actor = actorFor(c.agent_id, c.agent_type);
      if (!actor) continue; // unknown identity: the hook never mints one; refuse, never fall back to the lead
      const fd = openSync(join(this.dir, "caps.used.jsonl"), "a");
      try { writeSync(fd, JSON.stringify({ tool_use_id: c.tool_use_id, ts: now }) + "\n"); fsyncSync(fd); } finally { closeSync(fd); }
      return { actor, signedBy: c.agent_id ?? c.agent_type, toolUseId: c.tool_use_id };
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
