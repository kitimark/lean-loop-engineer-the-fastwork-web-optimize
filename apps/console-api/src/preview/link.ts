// Where the one-time owner link may be written. The decision is Lean (`console.previewLink`: `linkPlan`, `linkSink`;
// theorems `no_file_sink`, `no_nontty_sink`, `linkPlan_ok`): only the controlling terminal. This file is I/O: open
// /dev/tty, write the link, close. The token never goes to stdout, stderr, a log, the event store or a file: a console
// started as a background task has its stdout in a file any agent can read, but no controlling terminal.
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
  "no controlling terminal: no owner link is printed and previews cannot be started from this console. " +
  "Start the console from your own terminal (pnpm --filter @fw/console-api start), or from it run: pnpm --filter @fw/console-api owner-link";

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
