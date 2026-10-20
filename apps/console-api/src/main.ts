import { appendFileSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { serve } from "@hono/node-server";
import { createApp } from "./app.ts";
import { selectCore } from "./core/index.ts";
import { Store, consoleDir } from "./store.ts";
import { Reconciler } from "./reconcile/reconciler.ts";
import { execFileSync } from "node:child_process";
import { buildBase } from "./core/build-base.ts";
import { PreviewManager } from "./preview/manager.ts";
import { OwnerAuth } from "./preview/owner.ts";
import { Grants } from "./preview/grants.ts";
import { announceLink, reissueLink, type LinkClock } from "./preview/link.ts";
import { networkInterfaces } from "node:os";
import { LoginGuard, readPassphrase, KEYCHAIN_HINT } from "./preview/login.ts";
import { pickLanAddr } from "./preview/lan.ts";
import { createPreviewApp } from "./preview/preview-app.ts";
import { createArmApp } from "./preview/arm-app.ts";
import { ArmServers } from "./preview/arm-servers.ts";

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
// or `coreUnknown` with the reason when no build record of scripts/fwcore-build.sh matches the binary: `fw watch` raises
// svc.unknown). Both are judged for the checkout the code runs from (codeRoot), never for another one. A
// rebuild on disk changes neither until the child respawns or console-api restarts (Fw.Obs.Stack).
const root = dirname(dir); // the main checkout: owns .fw-console and the reconciler
const here = dirname(fileURLToPath(import.meta.url));
const codeRoot = resolve(here, "../../.."); // the checkout this code runs from (it can be a linked worktree)
const service = { commit: codeCommit(codeRoot), startedAt };
let coreInfo: { coreCommit?: string; coreUnknown?: string } = {};
let listening: { port: number } | null = null;
const writeApi = () => {
  if (listening) writeFileSync(join(dir, "api.json"), JSON.stringify({ port: listening.port, pid: process.pid, lan: lanAddr !== null, ...service, ...coreInfo }));
};
core.onSpawn = (binPath) => {
  const b = buildBase(codeRoot, binPath);
  coreInfo = "sha" in b ? { coreCommit: b.sha } : { coreUnknown: b.unknown };
  writeApi();
};
const store = await Store.open(dir, core);
const reconciler = new Reconciler(store, root);
reconciler.start();
const previews = new PreviewManager(dirname(dir), dir, core);
await previews.reapRecorded().catch((e) => console.error("preview reap failed:", e)); // previews a crashed run left behind
setInterval(() => { void previews.tick().catch((e) => console.error("preview tick failed:", e)); }, 30_000).unref();
const owner = new OwnerAuth((process.env.FW_CONSOLE_WEB_ORIGIN ?? "").split(",").filter(Boolean)); // e.g. the Vite dev origin
// Owner login: the passphrase of the keychain item `fw-console-owner`, read once here and held in memory only (never printed).
const passphrase = process.env.FW_CONSOLE_KEYCHAIN === "off" ? null : readPassphrase(); // "off": tests never touch the real keychain
const wantLan = process.env.FW_CONSOLE_LAN === "1";
const foundAddr = wantLan ? pickLanAddr(networkInterfaces()) : null; // found now, never stored
if (!passphrase) console.error(`console-api: no owner passphrase in the keychain (service fw-console-owner): login is disabled. Create it once with:\n  ${KEYCHAIN_HINT}`);
// LAN mode starts only with a long passphrase (Lean console.lanStart, proved lan_start_requires_long). Neither the passphrase nor its length is printed.
const lanDecision = await core.ops("console.lanStart", { want: wantLan, hasAddr: foundAddr !== null, hasPass: passphrase !== null, passLen: passphrase === null ? 0 : Array.from(passphrase).length });
const lanAddr = lanDecision.start === true ? foundAddr : null;
if (wantLan && lanAddr === null) {
  const why: Record<string, string> = {
    noAddress: "no private LAN address was found",
    noPassphrase: "no owner passphrase in the keychain",
    shortPassphrase: "the owner passphrase in the keychain is too short for LAN mode (it needs at least 12 characters)",
  };
  console.error(`console-api: LAN mode is disabled (${why[String(lanDecision.result)] ?? "not allowed"}); staying on loopback only. Set a longer passphrase with:\n  ${KEYCHAIN_HINT}`);
}
const login = new LoginGuard(core, passphrase);
const grants = new Grants(core, (rec) => previews.audit(rec));
const app = createApp(store, join(here, "../../console-web/dist"), reconciler, previews, owner, service, { login, lan: lanAddr !== null, grants });
const previewApp = createPreviewApp(core, owner, previews, { lan: lanAddr !== null, grants });
// every arm of a preview has its own origin: one listener per arm port, opened when the preview begins serving (manager.ts)
const armApp = createArmApp(core, owner, previews, { lan: lanAddr !== null, lanAddr, grants });
previews.useArms(new ArmServers(armApp.fetch, lanAddr));

setInterval(() => { void app.drain.run().catch((e) => console.error("spool drain failed:", e)); }, 2000).unref();

// port 0 = the OS picks a free port (override with PORT); printed and written to api.json
// The previews are served on their own port (console port + 1, else any free one), bound like the console: another origin.
const lanServers: { close(): unknown }[] = [];
const listenOn = (fetch: (r: Request, e?: unknown) => unknown, port: number, hostname: string, fallback: boolean): Promise<{ port: number; srv: { close(): unknown } }> =>
  new Promise((resolveP, reject) => {
    const srv = serve({ fetch: fetch as never, port, hostname }, (info) => resolveP({ port: info.port, srv }));
    srv.on("error", (e: NodeJS.ErrnoException) => {
      if (fallback && e.code === "EADDRINUSE" && port !== 0) { void listenOn(fetch, 0, hostname, false).then(resolveP, reject); } else reject(e);
    });
  });
const server = serve({ fetch: app.fetch, port: Number(process.env.PORT ?? 0), hostname: "127.0.0.1" }, async (info) => {
  listening = { port: info.port };
  const pv = await listenOn(previewApp.fetch, info.port + 1, "127.0.0.1", true);
  lanServers.push(pv.srv);
  owner.setPorts(info.port, pv.port);
  if (!coreInfo.coreCommit && !coreInfo.coreUnknown) core.onSpawn?.(core.binPath); // no child spawned yet: the binary it will spawn from
  writeApi();
  if (lanAddr) {
    // the same handlers on the LAN address, the same two ports; every request from there passes the Lean owner gate
    owner.setLanHosts([`${lanAddr}:${info.port}`], [`${lanAddr}:${pv.port}`]);
    const lanServer = serve({ fetch: app.fetch, port: info.port, hostname: lanAddr }, () => {
      console.log(`console-api LAN login: http://${lanAddr}:${info.port}/owner/login  (previews on :${pv.port})`);
    });
    lanServer.on("error", (e) => { console.error(`console-api: cannot listen on the LAN address: ${(e as Error).message}`); owner.setLanHosts([], []); });
    lanServers.push(lanServer);
    listenOn(previewApp.fetch, pv.port, lanAddr, false).then((l) => lanServers.push(l.srv), (e) => console.error(`console-api: cannot serve previews on the LAN address: ${(e as Error).message}`));
  }
  console.log(`console-api listening on http://127.0.0.1:${info.port}  (previews on :${pv.port}, core: ${core.name}, log: ${join(dir, "events.jsonl")}, ${store.seq} events)`);
  // the one-time owner link goes to the controlling terminal only (Lean console.previewLink); with no terminal it is not printed
  const link = (t: string | null) => `http://127.0.0.1:${info.port}/owner?t=${t}`;
  const clock: LinkClock = { last: null };
  void announceLink(core, () => link(owner.token()), (m) => console.error(`console-api: ${m}`)).then((w) => { if (w === "tty") clock.last = Date.now(); }).catch((e) => console.error("owner link failed:", (e as Error).message));
  // `owner-link` (apps/console-api/src/owner-link.ts) sends SIGUSR2: a fresh link, again to this console's own terminal
  // (at most one a minute, Lean mayReissue; a refused request changes nothing, the old link stays valid)
  process.on("SIGUSR2", () => { void reissueLink(core, clock, Date.now(), () => link(owner.reissue()), (m) => console.error(`console-api: ${m}`)).catch(() => undefined); });
});

const stop = async () => {
  reconciler.stop();
  await previews.shutdown().catch(() => undefined); // only the process groups in its own table
  rmSync(join(dir, "api.json"), { force: true });
  store.close();
  server.close();
  for (const l of lanServers) l.close();
  process.exit(0);
};
process.on("SIGINT", stop);
process.on("SIGTERM", stop);
