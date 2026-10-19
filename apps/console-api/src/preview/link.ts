// Where the one-time owner link may be written. The decision is Lean (`console.previewLink`: `linkPlan`, `linkSink`;
// theorems `no_file_sink`, `no_nontty_sink`, `linkPlan_ok`): only the controlling terminal. This file is I/O: open
// /dev/tty, write the link, close. The token never goes to stdout, stderr, a log, the event store or a file: a console
// started as a background task has its stdout in a file any agent can read, but no controlling terminal.
// Stated limit (MEASURED in review): /dev/tty proves only that some terminal exists, not that it is the user's. A
// same-UID process can start the console under a pseudo-terminal it allocates (script, python pty, expect) and read
// the link. This stops accidental capture from background output, not a deliberate same-UID process.
import { closeSync, openSync, writeSync } from "node:fs";
import type { Core } from "../core/index.ts";

export type Tty = { write(s: string): void; close(): void };

/** The controlling terminal of this process, or null when there is none (no tty, e.g. a background task). */
export function openTty(): Tty | null {
  try {
    const fd = openSync("/dev/tty", "w");
    return { write: (s) => { writeSync(fd, s); }, close: () => closeSync(fd) };
  } catch { return null; }
}

export const NO_TTY_MESSAGE =
  "no controlling terminal: no owner link is printed. Sign in with the owner passphrase at /owner/login (loopback or LAN), and previews work after that; " +
  "or start the console from your own terminal (pnpm --filter @fw/console-api start) and run owner-link from it.";

/**
 * Write the owner link to the terminal when Lean says so. Returns where it went ("tty") or "none" (nothing was written
 * anywhere; `NO_TTY_MESSAGE` goes to `say`, which never receives the link).
 */
export async function announceLink(core: Pick<Core, "ops">, url: () => string, say: (s: string) => void, open: () => Tty | null = openTty): Promise<"tty" | "none"> {
  const tty = open();
  const r = await core.ops("console.previewLink", { hasTty: tty !== null });
  if (r.sink === "tty" && tty) {
    try { tty.write(`\nowner link (open once, in your browser): ${url()}\n`); } finally { tty.close(); }
    return "tty";
  }
  tty?.close();
  say(NO_TTY_MESSAGE);
  return "none";
}

/** When the last owner link was written to the terminal (ms); the minimum gap between two is Lean `mayReissue`. */
export type LinkClock = { last: number | null };

export const TOO_SOON_MESSAGE = "an owner link was issued less than a minute ago: wait, then run owner-link again";

/**
 * A reissue request (SIGUSR2 from `owner-link`): Lean `console.previewLink` says whether a new link may be issued now
 * (`mayReissue`: one per minute, so a same-user process cannot keep invalidating the link the user has not opened yet).
 * Returns where the link went, "tooSoon" (nothing changed: the old link stays valid) or "none".
 */
export async function reissueLink(core: Pick<Core, "ops">, clock: LinkClock, now: number, url: () => string, say: (s: string) => void, open: () => Tty | null = openTty): Promise<"tty" | "none" | "tooSoon"> {
  const r = await core.ops("console.previewLink", { hasTty: true, now, ...(clock.last === null ? {} : { last: clock.last }) });
  if (r.reissue !== true) { say(TOO_SOON_MESSAGE); return "tooSoon"; }
  const where = await announceLink(core, url, say, open);
  if (where === "tty") clock.last = now;
  return where;
}

/**
 * `owner-link`: signal the console recorded in api.json only after it proves to be the console. `api.json` can be stale (a
 * crashed console, the pid reused by another program: SIGUSR2 would kill it), so the port must answer `GET /api/health`
 * with the same pid in the `x-fw-console-pid` header. A mismatch or no answer: refuse and signal nothing.
 */
export async function signalConsole(
  info: { port: number; pid: number },
  io: { get: (url: string) => Promise<string | null>; kill: (pid: number, sig: "SIGUSR2") => void },
): Promise<{ ok: true } | { ok: false; reason: "badInfo" | "noAnswer" | "pidMismatch" }> {
  if (!Number.isInteger(info.pid) || info.pid <= 1 || !Number.isInteger(info.port) || info.port <= 0) return { ok: false, reason: "badInfo" };
  const answered = await io.get(`http://127.0.0.1:${info.port}/api/health`).catch(() => null);
  if (answered === null) return { ok: false, reason: "noAnswer" };
  if (Number(answered) !== info.pid) return { ok: false, reason: "pidMismatch" };
  io.kill(info.pid, "SIGUSR2");
  return { ok: true };
}
