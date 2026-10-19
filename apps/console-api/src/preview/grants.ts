// Inspect grants (preview-inspect): a loopback-only, single-use, short-lived way for the lead and agents to open a preview
// without the owner's login. Lean `console.previewGrant` decides issue and redeem (`issueAllowed`, `redeem`: loopback only,
// known token, once, ten minutes); `console.ownerGate` with `grant` decides what the cookie opens (`allowGrant`: preview
// paths and Referer-routed ones, sixty minutes, never /api or /owner). This file keeps the tables and draws random values.
// A grant is no owner proof and no session: it has no entry in OwnerAuth, so `bearerOk` and `previewOk` never see it.
// Tokens and cookie values are random, held in memory only, and keyed by their SHA-256; the audit lines carry the grant id
// (the first 8 hex digits of that hash of a separate random id), never a token.
import { createHash, randomBytes } from "node:crypto";
import type { Core } from "../core/index.ts";

export const GRANT_COOKIE = "fw_grant";
const COOKIE_MS = 3_600_000; // mirrors Lean grantCookieTtl (pruning only; Lean decides admission)
const sha = (s: string): string => createHash("sha256").update(s).digest("hex");

type Tok = { id: string; issuedAt: number; used: boolean; next: string | null };
type Ck = { id: string; started: number; uses: number };
export type Audit = (rec: Record<string, unknown>) => void;
export type RedeemResult = { ok: true; cookie: string; maxAgeSec: number; next: string | null } | { ok: false; verdict: string };

export class Grants {
  private tokens = new Map<string, Tok>();
  private cookies = new Map<string, Ck>();
  private readonly core: Core;
  private readonly audit: Audit;
  private readonly clock: () => number;
  constructor(core: Core, audit: Audit, clock: () => number = Date.now) { this.core = core; this.audit = audit; this.clock = clock; }

  /** Issue a token if Lean allows it for this request (`lan`: not from loopback). `next`: where the redeemed link leads. */
  async issue(lan: boolean, next: string | null): Promise<{ ok: true; token: string; ttlMs: number } | { ok: false }> {
    const r = await this.core.ops("console.previewGrant", { kind: "issue", lan });
    if (r.allow !== true) { this.audit({ ev: "grant.refused", kind: "issue" }); return { ok: false }; }
    const now = this.clock();
    this.pruneCookies();
    for (const [k, t] of this.tokens) if (t.issuedAt + Number(r.ttlMs) <= now) this.tokens.delete(k); // expired ones are forgotten
    const token = randomBytes(32).toString("base64url");
    const id = randomBytes(4).toString("hex");
    this.tokens.set(sha(token), { id, issuedAt: now, used: false, next });
    this.audit({ ev: "grant.issue", grant: id, next });
    return { ok: true, token, ttlMs: Number(r.ttlMs) };
  }

  /** Present a token. A good one is marked used before anything else (single use), and yields the cookie value. */
  async redeem(lan: boolean, token: string | undefined): Promise<RedeemResult> {
    const key = token ? sha(token) : "";
    const t = this.tokens.get(key);
    const now = this.clock();
    // Claim before any await: a second redeem of the same token, even a concurrent one, then reads used=true. A refused token stays consumed.
    const wasUsed = t?.used ?? false;
    if (t) t.used = true;
    const r = await this.core.ops("console.previewGrant", { kind: "redeem", lan, known: t !== undefined, used: wasUsed, issuedAt: t?.issuedAt ?? 0, now });
    if (r.allow !== true || !t) { this.audit({ ev: "grant.refused", kind: "redeem", verdict: r.verdict, ...(t ? { grant: t.id } : {}) }); return { ok: false, verdict: String(r.verdict) }; }
    const cookie = randomBytes(32).toString("base64url");
    this.cookies.set(sha(cookie), { id: t.id, started: now, uses: 0 });
    this.audit({ ev: "grant.redeem", grant: t.id });
    return { ok: true, cookie, maxAgeSec: Math.floor(Number(r.cookieMs) / 1000), next: t.next };
  }

  /** Forget cookies past their sixty minutes (Lean `grantCookieTtl`); Lean still judges the age of any it sees. */
  private pruneCookies(): void {
    const now = this.clock();
    for (const [k, c] of this.cookies) if (c.started + COOKIE_MS <= now) this.cookies.delete(k);
  }

  now(): number { return this.clock(); }

  static setCookie(value: string, maxAgeSec: number): string {
    return `${GRANT_COOKIE}=${value}; HttpOnly; SameSite=Strict; Path=/; Max-Age=${maxAgeSec}`;
  }

  /** What the Cookie header says about a grant: `known` (this console opened it) and when. Lean judges the age. */
  lookup(header: string | undefined): { known: boolean; started: number; id: string | null } {
    this.pruneCookies();
    const v = cookieValue(header, GRANT_COOKIE);
    const c = v ? this.cookies.get(sha(v)) : undefined;
    return c ? { known: true, started: c.started, id: c.id } : { known: false, started: 0, id: null };
  }

  /** Write the audit line of a request a grant opened: the first use of each cookie, then every 50th (never a token). */
  used(id: string, path: string): void {
    for (const c of this.cookies.values()) {
      if (c.id !== id) continue;
      if (c.uses % 50 === 0) this.audit({ ev: "grant.use", grant: id, n: c.uses + 1, path: path.slice(0, 80) });
      c.uses++;
    }
  }
}

function cookieValue(header: string | undefined, name: string): string | null {
  if (!header) return null;
  for (const part of header.split(";")) {
    const i = part.indexOf("=");
    if (i > 0 && part.slice(0, i).trim() === name) return part.slice(i + 1).trim();
  }
  return null;
}
