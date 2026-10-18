import { appendFileSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { serve } from "@hono/node-server";
import { createApp } from "./app.ts";
import { selectCore } from "./core/index.ts";
import { Store, consoleDir } from "./store.ts";
import { Reconciler } from "./reconcile/reconciler.ts";
import { execFileSync } from "node:child_process";
import { buildBase } from "./core/build-base.ts";

/** HEAD of the checkout the code runs from (null when git is unavailable). */
function codeCommit(root: string): string | null {
  try { return execFileSync("git", ["rev-parse", "HEAD"], { cwd: root, encoding: "utf8", timeout: 3000 }).trim() || null; } catch { return null; }
}

const startedAt = Date.now(); // first statement of main.ts; the imported modules were loaded just before it (informational: staleness uses the start commit, not this time)
const dir = consoleDir();
mkdirSync(dir, { recursive: true });
let core;
try {
  core = selectCore(process.env, undefined, (i) => {
    console.error("fwcore incident:", JSON.stringify(i));
    appendFileSync(join(dir, "incidents.jsonl"), JSON.stringify(i) + "\n");
  });
} catch (e) {
  console.error(`console-api: cannot start. ${(e as Error).message}`);
  process.exit(1);
}
// What actually runs: console-api's own code (the commit it started from) and its ONE long-lived fwcore child, spawned
// from the binary on disk at that moment. At every spawn the child's build commit is recorded in api.json (`coreCommit`,
// or `coreUnknown` with the reason when the binary's commit cannot be identified: `fw watch` raises svc.unknown). A
// rebuild on disk changes neither until the child respawns or console-api restarts (Fw.Obs.Stack).
const root = dirname(dir);
const service = { commit: codeCommit(root), startedAt };
let coreInfo: { coreCommit?: string; coreUnknown?: string } = {};
let listening: { port: number } | null = null;
const writeApi = () => {
  if (listening) writeFileSync(join(dir, "api.json"), JSON.stringify({ port: listening.port, pid: process.pid, ...service, ...coreInfo }));
};
core.onSpawn = (binPath) => {
  const b = buildBase(root, binPath);
  coreInfo = "sha" in b ? { coreCommit: b.sha } : { coreUnknown: b.unknown };
  writeApi();
};
const store = await Store.open(dir, core);
const here = dirname(fileURLToPath(import.meta.url));
const reconciler = new Reconciler(store, root);
reconciler.start();
const app = createApp(store, join(here, "../../console-web/dist"), reconciler, service);

setInterval(() => { void app.drain.run().catch((e) => console.error("spool drain failed:", e)); }, 2000).unref();

// port 0 = the OS picks a free port (override with PORT); printed and written to api.json
const server = serve({ fetch: app.fetch, port: Number(process.env.PORT ?? 0), hostname: "127.0.0.1" }, (info) => {
  listening = { port: info.port };
  if (!coreInfo.coreCommit && !coreInfo.coreUnknown) core.onSpawn?.(core.binPath); // no child spawned yet: the binary it will spawn from
  writeApi();
  console.log(`console-api listening on http://127.0.0.1:${info.port}  (core: ${core.name}, log: ${join(dir, "events.jsonl")}, ${store.seq} events)`);
});

const stop = () => {
  reconciler.stop();
  rmSync(join(dir, "api.json"), { force: true });
  store.close();
  server.close();
  process.exit(0);
};
process.on("SIGINT", stop);
process.on("SIGTERM", stop);
