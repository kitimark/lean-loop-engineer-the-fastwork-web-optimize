import { appendFileSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { serve } from "@hono/node-server";
import { createApp } from "./app.ts";
import { selectCore } from "./core/index.ts";
import { Store, consoleDir } from "./store.ts";
import { Reconciler } from "./reconcile/reconciler.ts";
import { PreviewManager } from "./preview/manager.ts";
import { OwnerAuth } from "./preview/owner.ts";
import { announceLink } from "./preview/link.ts";

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
const store = await Store.open(dir, core);
const here = dirname(fileURLToPath(import.meta.url));
const reconciler = new Reconciler(store, dirname(dir));
reconciler.start();
const previews = new PreviewManager(dirname(dir), dir, core);
await previews.reapRecorded().catch((e) => console.error("preview reap failed:", e)); // previews a crashed run left behind
setInterval(() => { void previews.tick().catch((e) => console.error("preview tick failed:", e)); }, 30_000).unref();
const owner = new OwnerAuth((process.env.FW_CONSOLE_WEB_ORIGIN ?? "").split(",").filter(Boolean)); // e.g. the Vite dev origin
const app = createApp(store, join(here, "../../console-web/dist"), reconciler, previews, owner);

setInterval(() => { void app.drain.run().catch((e) => console.error("spool drain failed:", e)); }, 2000).unref();

// port 0 = the OS picks a free port (override with PORT); printed and written to api.json
const server = serve({ fetch: app.fetch, port: Number(process.env.PORT ?? 0), hostname: "127.0.0.1" }, (info) => {
  writeFileSync(join(dir, "api.json"), JSON.stringify({ port: info.port, pid: process.pid }));
  console.log(`console-api listening on http://127.0.0.1:${info.port}  (core: ${core.name}, log: ${join(dir, "events.jsonl")}, ${store.seq} events)`);
  // the one-time owner link goes to the controlling terminal only (Lean console.previewLink); with no terminal it is not printed
  const link = (t: string | null) => `http://127.0.0.1:${info.port}/owner?t=${t}`;
  void announceLink(core, () => link(owner.token()), (m) => console.error(`console-api: ${m}`)).catch((e) => console.error("owner link failed:", (e as Error).message));
  // `owner-link` (apps/console-api/src/owner-link.ts) sends SIGUSR2: a fresh link, again to this console's own terminal
  process.on("SIGUSR2", () => { void announceLink(core, () => link(owner.reissue()), (m) => console.error(`console-api: ${m}`)).catch(() => undefined); });
});

const stop = async () => {
  reconciler.stop();
  await previews.shutdown().catch(() => undefined); // only the process groups in its own table
  rmSync(join(dir, "api.json"), { force: true });
  store.close();
  server.close();
  process.exit(0);
};
process.on("SIGINT", stop);
process.on("SIGTERM", stop);
