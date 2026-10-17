import { appendFileSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { serve } from "@hono/node-server";
import { createApp } from "./app.ts";
import { selectCore } from "./core/index.ts";
import { Store, consoleDir } from "./store.ts";

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
const app = createApp(store, join(here, "../../console-web/dist"));

setInterval(() => { void app.drain.run().catch((e) => console.error("spool drain failed:", e)); }, 2000).unref();

// port 0 = the OS picks a free port (override with PORT); printed and written to api.json
const server = serve({ fetch: app.fetch, port: Number(process.env.PORT ?? 0), hostname: "127.0.0.1" }, (info) => {
  writeFileSync(join(dir, "api.json"), JSON.stringify({ port: info.port, pid: process.pid }));
  console.log(`console-api listening on http://127.0.0.1:${info.port}  (core: ${core.name}, log: ${join(dir, "events.jsonl")}, ${store.seq} events)`);
});

const stop = () => {
  rmSync(join(dir, "api.json"), { force: true });
  store.close();
  server.close();
  process.exit(0);
};
process.on("SIGINT", stop);
process.on("SIGTERM", stop);
