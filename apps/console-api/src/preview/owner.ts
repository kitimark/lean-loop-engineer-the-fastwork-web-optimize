// Owner proof for the console. There is NO ambient owner credential: no cookie ever carries owner rights (Lean
// `owner_requires_bearer`, `cookie_never_owner`, `owner_independent_of_cookie`). Two ways to get an owner token, both ending in
// a session kept server side (any number of devices at once, 8 h each):
//   1. the one-time owner link, written at startup to the controlling terminal only (`link.ts`; Lean `no_file_sink`); it
//      redirects to `/#owner=<token>`, which the console web moves into localStorage and removes from the address bar;
//   2. `POST /owner/login` with the owner passphrase read from the macOS keychain (`login.ts`; rate limits decided by Lean
//      `Fw.Console.Preview.Owner.attempt`, per address and across all addresses); the JSON reply holds the token.
// The console web keeps the token in localStorage of the console origin (origin = scheme, host AND port, so a preview origin
// cannot read it) and sends it as `Authorization: Bearer`. The server accepts owner rights only from that header.
// The one cookie, `fw_preview` (HttpOnly, SameSite=Strict), is the preview-access cookie: it opens the preview port and nothing
// else (Lean `allowPreview`, `preview_requires_cookie`). Cookies ignore ports, so a preview page's own requests carry it, which
// is accepted: it grants preview viewing only. The preview port forwards no cookie to a preview server (proxy.ts).
// An owner action also needs `Origin` = a console origin; that list is computed in Lean from the Host, the configured web
// origins and the preview port (Lean `trustedOrigins`, `computed_trusted_refuses_preview`).
//
// What this stops (CONFIRMED by test): a request without the token (any local process that merely knows the port, an agent's
// curl, a LAN device), JavaScript on any preview page, on the preview origin or a raw preview server port (it holds no token
// and cannot read the console origin's localStorage), and the runner's own tools (secret header). Console responses carry
// X-Frame-Options: DENY and CSP frame-ancestors 'none', so a preview cannot frame the console.
// What it cannot stop (stated limits): a process of the same OS user that reads the browser profile, the keychain item or
// ptraces the console; a passive sniffer on the Wi-Fi (the LAN link is plain HTTP, so the passphrase and the token cross it
// unencrypted); the preview servers' own loopback ports, which any local process can open; a preview page that locks the owner
// out for 10 minutes with 20 wrong logins (global limit); the preview cookie leaking to a preview server (preview viewing only);
// one that signals the console: it can only make it print a fresh link to the user's own terminal, at most once a minute (Lean
// `mayReissue`). Nothing here is written to .fw-console or any file an agent reads.
import { randomBytes, timingSafeEqual } from "node:crypto";
import type { Core } from "../core/index.ts";

export const PREVIEW_COOKIE = "fw_preview";
export const LOOPBACK_HOST = /^(127\.0\.0\.1|localhost|\[::1\])(:\d+)?$/;
export const SESSION_MS = 8 * 3600_000;

export type Org = { host: string; port: number };
export type ActionKind = "owner" | "command" | "login";

/** `http://host[:port]` as an origin (lower case, default port 80), or null for anything else (other scheme, a path, null). */
export function parseOrigin(s: string | undefined): Org | null {
  const m = s ? /^http:\/\/(\[[0-9a-f:]+\]|[a-z0-9.-]+)(?::(\d{1,5}))?$/i.exec(s) : null;
  return m ? { host: m[1]!.toLowerCase(), port: m[2] ? Number(m[2]) : 80 } : null;
}

const same = (a: string, b: string): boolean => {
  const x = Buffer.from(a); const y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
};

type Session = { exp: number; pv: string };

export class OwnerAuth {
  private link: string | null = randomBytes(24).toString("base64url");
  private sessions = new Map<string, Session>(); // owner token -> expiry and its preview-access cookie value
  private readonly extraOrigins: string[];
  private lanHosts: string[] = [];
  private lanPreviewHosts: string[] = [];
  private ports: { console: number; preview: number } | null = null;
  private readonly clock: () => number;

  /** `extraOrigins`: web origins besides the console's own, e.g. the Vite dev server (`FW_CONSOLE_WEB_ORIGIN`). */
  constructor(extraOrigins: string[] = [], clock: () => number = Date.now) { this.extraOrigins = extraOrigins; this.clock = clock; }

  /** The console port and the preview port (set once both listen). With them, a loopback Host must name the right port. */
  setPorts(consolePort: number, previewPort: number): void { this.ports = { console: consolePort, preview: previewPort }; }
  get previewPort(): number | null { return this.ports?.preview ?? null; }

  /** LAN mode: the `host:port` strings this console (and its preview port) answers to besides loopback (set at start, never persisted). */
  setLanHosts(hosts: string[], previewHosts: string[] = []): void { this.lanHosts = hosts; this.lanPreviewHosts = previewHosts; }
  private loopbackOk(host: string, port: number | undefined): boolean {
    if (!LOOPBACK_HOST.test(host)) return false;
    return port === undefined || host.endsWith(`:${port}`);
  }
  /** The LAN address previews are served on, when LAN mode is on (read from the configured preview host, `addr:port`); else null. */
  get lanPreviewAddr(): string | null { const h = this.lanPreviewHosts[0]; return h ? h.slice(0, h.lastIndexOf(":")) : null; }
  /** The Host header names this console: a loopback name on the console port or a configured LAN host. */
  hostOk(host: string | undefined): boolean { return !!host && (this.loopbackOk(host, this.ports?.console) || this.lanHosts.includes(host)); }
  /** The Host header names the preview port. */
  previewHostOk(host: string | undefined): boolean { return !!host && (this.loopbackOk(host, this.ports?.preview) || this.lanPreviewHosts.includes(host)); }

  /** The token of the link, for writing once to the terminal; null after it was used. Never log it. */
  token(): string | null { return this.link; }

  /** A fresh one-time link (the old unused one stops working); existing sessions stay valid. */
  reissue(): string {
    this.link = randomBytes(24).toString("base64url");
    return this.link;
  }

  /** A new session (random ids, server side); returns the owner token (shown once to the client that logged in). */
  open(): string {
    const now = this.clock();
    for (const [k, s] of this.sessions) if (s.exp <= now) this.sessions.delete(k);
    const id = randomBytes(32).toString("base64url");
    this.sessions.set(id, { exp: now + SESSION_MS, pv: randomBytes(32).toString("base64url") });
    return id;
  }

  /** Exchange the link token for an owner token (single use); null when wrong or already used. */
  redeem(t: string | undefined): string | null {
    if (this.link === null || !t || !same(t, this.link)) return null;
    this.link = null;
    return this.open();
  }

  /** The Set-Cookie value of the preview-access cookie of a session (the only cookie; never an owner proof). */
  previewCookieFor(session: string): string[] {
    const s = this.sessions.get(session);
    return s ? [OwnerAuth.setPreviewCookie(s.pv)] : [];
  }

  static setPreviewCookie(value: string): string {
    return `${PREVIEW_COOKIE}=${value}; HttpOnly; SameSite=Strict; Path=/; Max-Age=${SESSION_MS / 1000}`;
  }
  static clearCookies(): string[] { return [`${PREVIEW_COOKIE}=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0`]; }

  private cookieValue(header: string | undefined, name: string): string | null {
    if (!header) return null;
    for (const part of header.split(";")) {
      const i = part.indexOf("=");
      if (i > 0 && part.slice(0, i).trim() === name) return part.slice(i + 1).trim();
    }
    return null;
  }

  /** The token of an `Authorization: Bearer <token>` header, else null. This header is the only owner credential. */
  static bearerOf(authorization: string | undefined): string | null {
    const m = authorization ? /^Bearer ([A-Za-z0-9_-]{16,128})$/.exec(authorization.trim()) : null;
    return m ? m[1]! : null;
  }

  /** The Authorization header carries a live owner token. */
  bearerOk(authorization: string | undefined): boolean {
    const v = OwnerAuth.bearerOf(authorization);
    if (v === null) return false;
    const now = this.clock();
    let ok = false;
    for (const [k, s] of this.sessions) if (same(v, k) && s.exp > now) ok = true; // no early exit
    return ok;
  }

  /** The preview-access cookie of this header names a live session. It never counts as an owner proof (`bearerOk`). */
  previewOk(header: string | undefined): boolean {
    const v = this.cookieValue(header, PREVIEW_COOKIE);
    if (v === null || v === "") return false;
    const now = this.clock();
    let ok = false;
    for (const s of this.sessions.values()) if (same(v, s.pv) && s.exp > now) ok = true; // no early exit
    return ok;
  }

  /** Drop the session of this Authorization header (logout); true when there was one. */
  close(authorization: string | undefined): boolean {
    const v = OwnerAuth.bearerOf(authorization);
    if (v === null) return false;
    for (const k of [...this.sessions.keys()]) if (same(v, k)) return this.sessions.delete(k);
    return false;
  }

  get sessionCount(): number { return this.sessions.size; }

  /** May this request act as the owner (Lean `console.ownerAction`, which also computes the trusted origins from the Host,
   *  the configured web origins and the preview port): `owner` needs the bearer token and an `Origin` of the console,
   *  `login` an `Origin` of the console, `command` an `Origin` of the console when it sends one. */
  async actionOk(core: Core, kind: ActionKind, bearer: boolean, origin: string | undefined, host: string | undefined): Promise<boolean> {
    // a header that is no http origin (e.g. "null") is sent as an origin that matches nothing: Lean refuses it
    const o = origin === undefined ? undefined : (parseOrigin(origin) ?? { host: "-", port: 0 });
    const own = this.hostOk(host) ? parseOrigin(`http://${host}`) : null;
    const extra = this.extraOrigins.map((x) => parseOrigin(x)).filter((x): x is Org => x !== null);
    const r = await core.ops("console.ownerAction", {
      kind, bearer, extra, host: own, previewPort: this.ports?.preview ?? null, ...(o ? { origin: o } : {}),
    });
    return r.allow === true;
  }
}
