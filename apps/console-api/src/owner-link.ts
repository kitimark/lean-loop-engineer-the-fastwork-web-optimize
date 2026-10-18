// `pnpm --filter @fw/console-api owner-link`: ask the running console for a fresh one-time owner link. The console writes
// the link to ITS controlling terminal (SIGUSR2 -> announceLink); this command prints no link, so nothing it prints, and
// nothing a background task captures from it, can contain the token. It signals only a pid that answers as the console on
// the recorded port (a stale api.json, or a pid reused by another program, is refused), and the console issues at most one
// link a minute (Lean `mayReissue`).
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { consoleDir } from "./store.ts";
import { signalConsole } from "./preview/link.ts";

const MSG = {
  badInfo: "no running console found (.fw-console/api.json is missing or unreadable): start it with pnpm --filter @fw/console-api start",
  noAnswer: "api.json names a console that does not answer: it is not running (stale file); nothing was signalled",
  pidMismatch: "the process on the recorded port is not the console in api.json (stale file or reused pid); nothing was signalled",
} as const;

let info: { port: number; pid: number } = { port: 0, pid: 0 };
try { info = JSON.parse(readFileSync(join(consoleDir(), "api.json"), "utf8")) as { port: number; pid: number }; } catch { /* badInfo below */ }
const r = await signalConsole(info, {
  get: async (url) => {
    const res = await fetch(url, { signal: AbortSignal.timeout(2000) });
    return res.headers.get("x-fw-console-pid");
  },
  kill: (pid, sig) => process.kill(pid, sig),
});
if (r.ok) console.log(`asked the console (pid ${info.pid}) for a new owner link: it appears in the terminal that console was started from (at most one a minute)`);
else { console.error(MSG[r.reason]); process.exitCode = 1; }
