// Owner proof for the preview routes. The console writes a one-time owner link at startup to the controlling terminal
// only (`link.ts`; Lean `no_file_sink`: never stdout, stderr, a log, the event store or a file): opening it in the user's browser exchanges the link token for a session cookie (HttpOnly, SameSite=Strict).
// The routes pass three facts to Lean (`Fw.Console.Preview.Proof`): the console secret was shown, the owner cookie
// matched, the Origin is an origin of this console. Lean admits a request only with cookie and origin and no secret.
//
// What this stops (CONFIRMED by test): a request without the cookie (any local process that merely knows the port,
// an agent's curl), a cross-site page (SameSite=Strict, Origin check), and the runner's own tools (secret header).
// What it cannot stop (INFERRED, a stated limit): a process of the same OS user that steals the cookie from the browser profile or the live session (same UID can read the browser's files, ptrace the console, or start the console under a pseudo-terminal it allocates and read the link written there), and one that signals the console: it can only make it print a fresh link to the user's own terminal, at most once a minute (Lean `mayReissue`). Nothing here is written to .fw-console or any file an agent reads.
import { randomBytes, timingSafeEqual } from "node:crypto";

export const COOKIE = "fw_owner";
const LOOPBACK_HOST = /^(127\.0\.0\.1|localhost|\[::1\])(:\d+)?$/;

const same = (a: string, b: string): boolean => {
  const x = Buffer.from(a); const y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
};

export class OwnerAuth {
  private link: string | null = randomBytes(24).toString("base64url");
  private session: string | null = null;
  private readonly extraOrigins: string[];

  /** `extraOrigins`: web origins besides the console's own, e.g. the Vite dev server (`FW_CONSOLE_WEB_ORIGIN`). */
  constructor(extraOrigins: string[] = []) { this.extraOrigins = extraOrigins; }

  /** The token of the link, for writing once to the terminal; null after it was used. Never log it. */
  token(): string | null { return this.link; }

  /** A fresh one-time link (the old unused one stops working); an existing session stays valid. */
  reissue(): string {
    this.link = randomBytes(24).toString("base64url");
    return this.link;
  }

  /** Exchange the link token for the session value of the cookie (single use); null when wrong or already used. */
  redeem(t: string | undefined): string | null {
    if (this.link === null || !t || !same(t, this.link)) return null;
    this.link = null;
    this.session = randomBytes(32).toString("base64url");
    return this.session;
  }

  /** The Set-Cookie value of a session. */
  static setCookie(session: string): string {
    return `${COOKIE}=${session}; HttpOnly; SameSite=Strict; Path=/; Max-Age=28800`;
  }

  /** The owner cookie of this header matches the session. */
  cookieOk(header: string | undefined): boolean {
    if (this.session === null || !header) return false;
    for (const part of header.split(";")) {
      const i = part.indexOf("=");
      if (i > 0 && part.slice(0, i).trim() === COOKIE) return same(part.slice(i + 1).trim(), this.session);
    }
    return false;
  }

  /** The Origin header is present and is the console's own loopback origin (or a configured web origin). */
  originOk(origin: string | undefined, host: string | undefined): boolean {
    if (!origin) return false;
    if (this.extraOrigins.includes(origin)) return true;
    return !!host && LOOPBACK_HOST.test(host) && origin === `http://${host}`;
  }
}
