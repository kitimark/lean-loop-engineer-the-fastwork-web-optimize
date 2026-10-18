// Owner proof for the console and the preview port. Two ways to become the owner in a browser, both ending in a session
// (two cookies, HttpOnly, SameSite=Strict):
//   1. the one-time owner link, written at startup to the controlling terminal only (`link.ts`; Lean `no_file_sink`);
//   2. `POST /owner/login` with the owner passphrase read from the macOS keychain (`login.ts`; rate limits decided by Lean
//      `Fw.Console.Preview.Owner.attempt`, per address and across all addresses).
// A session is a random id kept server side (any number of devices at once, 8 h each). It has TWO cookie values:
//   fw_owner   the owner proof of the console origin (owner actions; never accepted by the preview port)
//   fw_preview the preview-access cookie (the preview port only; grants viewing, never an owner action; Lean
//              `preview_cookie_no_owner`). The console port ignores it.
// Cookies are not isolated by port, so a browser sends both to both ports; each port reads only its own name, and the
// preview port forwards no cookie to a preview server. Previews run on their own port (another origin: Lean
// `preview_origin_ne_console`); an owner action needs `Origin` = a console origin (Lean `owner_action_requires_console_origin`).
//
// What this stops (CONFIRMED by test): a request without the cookie (any local process that merely knows the port, an
// agent's curl, a LAN device), a cross-origin page including preview JavaScript (SameSite does not help: a different port
// is the same site, so the cookie is sent; the Origin check refuses it), and the runner's own tools (secret header).
// What it cannot stop (INFERRED, stated limits): a process of the same OS user that steals the cookie from the browser
// profile, reads the keychain item, or ptraces the console; a passive sniffer on the Wi-Fi (the LAN link is plain HTTP, so
// the passphrase and the cookies cross it unencrypted); the preview servers' own loopback ports, which any local process
// can open without a session; one that signals the console: it can only make it print a fresh link to the user's own
// terminal, at most once a minute (Lean `mayReissue`). Nothing here is written to .fw-console or any file an agent reads.
import { randomBytes, timingSafeEqual } from "node:crypto";
import type { Core } from "../core/index.ts";

export const COOKIE = "fw_owner";
export const PREVIEW_COOKIE = "fw_preview";
const LOOPBACK_HOST = /^(127\.0\.0\.1|localhost|\[::1\])(:\d+)?$/;
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
  private sessions = new Map<string, Session>(); // owner cookie value -> expiry and its preview-access cookie value
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

  /** A new session (random ids, server side); returns the owner cookie value. */
  open(): string {
    const now = this.clock();
    for (const [k, s] of this.sessions) if (s.exp <= now) this.sessions.delete(k);
    const id = randomBytes(32).toString("base64url");
    this.sessions.set(id, { exp: now + SESSION_MS, pv: randomBytes(32).toString("base64url") });
    return id;
  }

  /** Exchange the link token for the session value of the cookie (single use); null when wrong or already used. */
  redeem(t: string | undefined): string | null {
    if (this.link === null || !t || !same(t, this.link)) return null;
    this.link = null;
    return this.open();
  }

  /** The Set-Cookie values of a session: the owner cookie and the preview-access cookie. */
  cookiesFor(session: string): string[] {
    const s = this.sessions.get(session);
    return [OwnerAuth.setCookie(session), ...(s ? [OwnerAuth.setPreviewCookie(s.pv)] : [])];
  }

  /** The Set-Cookie value of an owner session. */
  static setCookie(session: string): string {
    return `${COOKIE}=${session}; HttpOnly; SameSite=Strict; Path=/; Max-Age=${SESSION_MS / 1000}`;
  }
  static setPreviewCookie(value: string): string {
    return `${PREVIEW_COOKIE}=${value}; HttpOnly; SameSite=Strict; Path=/; Max-Age=${SESSION_MS / 1000}`;
  }
  static clearCookie(): string { return `${COOKIE}=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0`; }
  static clearCookies(): string[] { return [OwnerAuth.clearCookie(), `${PREVIEW_COOKIE}=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0`]; }

  private cookieValue(header: string | undefined, name: string): string | null {
    if (!header) return null;
    for (const part of header.split(";")) {
      const i = part.indexOf("=");
      if (i > 0 && part.slice(0, i).trim() === name) return part.slice(i + 1).trim();
    }
    return null;
  }

  /** The owner cookie of this header names a live session. */
  cookieOk(header: string | undefined): boolean {
    const v = this.cookieValue(header, COOKIE);
    if (v === null || v === "") return false;
    const now = this.clock();
    let ok = false;
    for (const [k, s] of this.sessions) if (same(v, k) && s.exp > now) ok = true; // no early exit
    return ok;
  }

  /** The preview-access cookie of this header names a live session. It never counts as an owner proof (`cookieOk`). */
  previewOk(header: string | undefined): boolean {
    const v = this.cookieValue(header, PREVIEW_COOKIE);
    if (v === null || v === "") return false;
    const now = this.clock();
    let ok = false;
    for (const s of this.sessions.values()) if (same(v, s.pv) && s.exp > now) ok = true; // no early exit
    return ok;
  }

  /** Drop the session of this cookie header (logout); true when there was one. */
  close(header: string | undefined): boolean {
    const v = this.cookieValue(header, COOKIE);
    if (v === null) return false;
    for (const k of [...this.sessions.keys()]) if (same(v, k)) return this.sessions.delete(k);
    return false;
  }

  get sessionCount(): number { return this.sessions.size; }

  /** The origins that count as the console's own for a request with this Host: its own origin (when the Host names this
   *  console) and the configured web origins (never an origin of the preview port). */
  trusted(host: string | undefined): Org[] {
    const own = this.hostOk(host) ? parseOrigin(`http://${host}`) : null;
    const extra = this.extraOrigins.map((o) => parseOrigin(o));
    return [own, ...extra].filter((o): o is Org => o !== null && o.port !== this.ports?.preview);
  }

  /** May this request act as the owner (Lean `console.ownerAction`): `kind` owner needs the owner cookie and an `Origin`
   *  of the console, `login` an `Origin` of the console, `command` an `Origin` of the console when it sends one. */
  async actionOk(core: Core, kind: ActionKind, ownerCookie: boolean, origin: string | undefined, host: string | undefined): Promise<boolean> {
    // a header that is no http origin (e.g. "null") is sent as an origin that matches nothing: Lean refuses it
    const o = origin === undefined ? undefined : (parseOrigin(origin) ?? { host: "-", port: 0 });
    const r = await core.ops("console.ownerAction", { kind, ownerCookie, trusted: this.trusted(host), ...(o ? { origin: o } : {}) });
    return r.allow === true;
  }
}
