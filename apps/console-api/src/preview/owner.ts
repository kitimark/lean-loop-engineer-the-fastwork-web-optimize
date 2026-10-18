// Owner proof for the preview routes. Two ways to become the owner in a browser, both ending in a session cookie
// (HttpOnly, SameSite=Strict):
//   1. the one-time owner link, written at startup to the controlling terminal only (`link.ts`; Lean `no_file_sink`);
//   2. `POST /owner/login` with the owner passphrase read from the macOS keychain (`login.ts`; rate limit decided by Lean
//      `Fw.Console.Preview.Owner.attempt`).
// A session is a random id kept server side (any number of devices at once, 8 h each); the cookie holds the id, `close`
// drops it (logout). The routes pass three facts to Lean (`Fw.Console.Preview.Proof`): the console secret was shown, the
// owner cookie matched a live session, the Origin is an origin of this console. Lean admits a request only with cookie
// and origin and no secret.
//
// What this stops (CONFIRMED by test): a request without the cookie (any local process that merely knows the port,
// an agent's curl, a LAN device), a cross-site page (SameSite=Strict, Origin check), and the runner's own tools (secret
// header).
// What it cannot stop (INFERRED, stated limits): a process of the same OS user that steals the cookie from the browser
// profile, reads the keychain item, or ptraces the console; a passive sniffer on the Wi-Fi (the LAN link is plain HTTP, so
// the passphrase and the cookie cross it unencrypted); one that signals the console: it can only make it print a fresh link
// to the user's own terminal, at most once a minute (Lean `mayReissue`). Nothing here is written to .fw-console or any file
// an agent reads.
import { randomBytes, timingSafeEqual } from "node:crypto";

export const COOKIE = "fw_owner";
const LOOPBACK_HOST = /^(127\.0\.0\.1|localhost|\[::1\])(:\d+)?$/;
export const SESSION_MS = 8 * 3600_000;

const same = (a: string, b: string): boolean => {
  const x = Buffer.from(a); const y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
};

export class OwnerAuth {
  private link: string | null = randomBytes(24).toString("base64url");
  private sessions = new Map<string, number>(); // session id -> expiry (ms)
  private readonly extraOrigins: string[];
  private lanHosts: string[] = [];
  private readonly clock: () => number;

  /** `extraOrigins`: web origins besides the console's own, e.g. the Vite dev server (`FW_CONSOLE_WEB_ORIGIN`). */
  constructor(extraOrigins: string[] = [], clock: () => number = Date.now) { this.extraOrigins = extraOrigins; this.clock = clock; }

  /** LAN mode: the `host:port` strings this console answers to besides loopback (set at start, never persisted). */
  setLanHosts(hosts: string[]): void { this.lanHosts = hosts; }
  /** The Host header names this console: a loopback name or a configured LAN host. */
  hostOk(host: string | undefined): boolean { return !!host && (LOOPBACK_HOST.test(host) || this.lanHosts.includes(host)); }

  /** The token of the link, for writing once to the terminal; null after it was used. Never log it. */
  token(): string | null { return this.link; }

  /** A fresh one-time link (the old unused one stops working); existing sessions stay valid. */
  reissue(): string {
    this.link = randomBytes(24).toString("base64url");
    return this.link;
  }

  /** A new session (random id, server side); returns the cookie value. */
  open(): string {
    const now = this.clock();
    for (const [k, exp] of this.sessions) if (exp <= now) this.sessions.delete(k);
    const id = randomBytes(32).toString("base64url");
    this.sessions.set(id, now + SESSION_MS);
    return id;
  }

  /** Exchange the link token for the session value of the cookie (single use); null when wrong or already used. */
  redeem(t: string | undefined): string | null {
    if (this.link === null || !t || !same(t, this.link)) return null;
    this.link = null;
    return this.open();
  }

  /** The Set-Cookie value of a session. */
  static setCookie(session: string): string {
    return `${COOKIE}=${session}; HttpOnly; SameSite=Strict; Path=/; Max-Age=${SESSION_MS / 1000}`;
  }
  static clearCookie(): string { return `${COOKIE}=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0`; }

  private cookieValue(header: string | undefined): string | null {
    if (!header) return null;
    for (const part of header.split(";")) {
      const i = part.indexOf("=");
      if (i > 0 && part.slice(0, i).trim() === COOKIE) return part.slice(i + 1).trim();
    }
    return null;
  }

  /** The owner cookie of this header names a live session. */
  cookieOk(header: string | undefined): boolean {
    const v = this.cookieValue(header);
    if (v === null || v === "") return false;
    const now = this.clock();
    let ok = false;
    for (const [k, exp] of this.sessions) if (same(v, k) && exp > now) ok = true; // no early exit
    return ok;
  }

  /** Drop the session of this cookie header (logout); true when there was one. */
  close(header: string | undefined): boolean {
    const v = this.cookieValue(header);
    if (v === null) return false;
    for (const k of [...this.sessions.keys()]) if (same(v, k)) return this.sessions.delete(k);
    return false;
  }

  get sessionCount(): number { return this.sessions.size; }

  /** The Origin header is present and is this console's own origin (loopback or the LAN host) or a configured web origin. */
  originOk(origin: string | undefined, host: string | undefined): boolean {
    if (!origin) return false;
    if (this.extraOrigins.includes(origin)) return true;
    return this.hostOk(host) && origin === `http://${host}`;
  }
}
