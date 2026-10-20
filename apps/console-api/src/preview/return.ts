// The login return link (task preview-login-return). A refused HTML request on a preview origin is sent to the console login;
// the requested link (local port, path and query, read from the request itself) is held server-side under a random nonce, and
// only the nonce travels (`/owner/login?r=<nonce>`, then the login body). Which links are held, where the redirect goes and
// where the owner lands after the login are decided by Lean `console.loginReturn` (`Fw.Console.Preview.Return.redirect`,
// `landing`; proved: no accepted-link-free redirect, `landing_sound`). This file keeps the map and reads the facts.
import { randomBytes } from "node:crypto";
import type { Core } from "../core/index.ts";
import type { OwnerAuth } from "./owner.ts";

type Held = { port: number; path: string; issuedAt: number };

/** A nonce as the login page may carry it (the Lean `nonceOk` shape). */
export const NONCE = /^[A-Za-z0-9_-]{16,64}$/;

/** The host name of a Host header, without its port. */
export const hostName = (host: string | undefined): string | null => (host ? host.replace(/:\d+$/, "") : null);

/** Housekeeping bound only (Lean `ttl`): expired entries are dropped from the map; Lean decides expiry on landing. */
const TTL_MS = 600000;

export class ReturnStore {
  private held = new Map<string, Held>();
  private readonly core: Core; private readonly owner: OwnerAuth; private readonly live: () => unknown[]; private readonly clock: () => number;

  constructor(core: Core, owner: OwnerAuth, live: () => unknown[], clock: () => number = Date.now) {
    this.core = core; this.owner = owner; this.live = live; this.clock = clock;
  }

  get size(): number { return this.held.size; }

  private base() {
    const consolePort = this.owner.consolePort;
    return consolePort === null ? null : { consolePort, previewPort: this.owner.previewPort, live: this.live(), hosts: this.owner.hostNames };
  }

  /** The login address a refused request is redirected to, or null (the caller keeps its own refusal). */
  async redirectFor(o: { method: string; html: boolean; host: string | undefined; port: number | undefined; pathq: string }): Promise<string | null> {
    const b = this.base(); const host = hostName(o.host);
    if (!b || !host || o.port === undefined) return null;
    const nonce = randomBytes(18).toString("base64url");
    const now = this.clock();
    for (const [k, v] of this.held) if (v.issuedAt + TTL_MS < now) this.held.delete(k); // housekeeping; Lean re-checks expiry on landing
    const r = await this.core.ops("console.loginReturn", { kind: "redirect", method: o.method, html: o.html, heldCount: this.held.size, host, nonce, port: o.port, path: o.pathq, ...b });
    if (r.act !== "login" || typeof r.location !== "string") return null;
    if (r.keep === true) this.held.set(nonce, { port: o.port, path: o.pathq, issuedAt: now });
    return r.location;
  }

  /** Where the owner goes after a successful login: the held link if still accepted, else the Builds tab or the console home. */
  async landing(nonce: unknown, host: string | undefined): Promise<string> {
    const key = typeof nonce === "string" && NONCE.test(nonce) ? nonce : null;
    const h = key ? this.held.get(key) : undefined;
    if (key) this.held.delete(key);
    const b = this.base(); const name = hostName(host);
    if (!b || !name || !this.owner.hostOk(host)) return "/";
    const r = await this.core.ops("console.loginReturn", { kind: "land", host: name, now: this.clock(), ...(h ? { held: { port: h.port, path: h.path, issuedAt: h.issuedAt } } : {}), ...b });
    return typeof r.next === "string" ? r.next : "/";
  }
}
