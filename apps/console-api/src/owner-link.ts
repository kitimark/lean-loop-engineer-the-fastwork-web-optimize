// `pnpm --filter @fw/console-api owner-link`: ask the running console for a fresh one-time owner link. The console writes
// the link to ITS controlling terminal (SIGUSR2 -> announceLink); this command prints no link, so nothing it prints, and
// nothing a background task captures from it, can contain the token. It signals only the pid the console recorded.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { consoleDir } from "./store.ts";

try {
  const { pid } = JSON.parse(readFileSync(join(consoleDir(), "api.json"), "utf8")) as { pid: number };
  if (!Number.isInteger(pid) || pid <= 1) throw new Error("bad pid");
  process.kill(pid, "SIGUSR2");
  console.log(`asked the console (pid ${pid}) for a new owner link: it appears in the terminal that console was started from`);
} catch {
  console.error("no running console found (.fw-console/api.json): start it with pnpm --filter @fw/console-api start");
  process.exitCode = 1;
}
