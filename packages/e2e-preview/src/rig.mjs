// The rig of the preview e2e suite: the real console-api request handlers (app.ts, preview-app.ts, arm-app.ts and the arm
// listeners of arm-servers.ts; the Lean gate and arm routing through fwcore) on spare ports, the real preview server process
// (serve-child.ts, started with the arguments PreviewManager gives it), and a fixture preview: the unmodified snapshot as the
// original arm and a small built rewrite (fixture/site) as the task arm. Each arm is its own origin (its own port).
// Only the PreviewManager is a stand-in: its `serving`/`touch`/`liveTable` answers (what the proxies ask of it) come from the
// one fixture entry, because a real manager builds a worktree per preview. No keychain is read: the owner passphrase is a test
// value handed to the LoginGuard. Nothing here is a decision; the gate and routing verdicts come from fwcore.
import { spawn } from "node:child_process";
import { existsSync, mkdtempSync, rmSync } from "node:fs";
import { createServer, request as httpRequest } from "node:http";
import { createRequire } from "node:module";
import { networkInterfaces, tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
export const REPO = join(here, "../../..");
const API = join(REPO, "apps/console-api");
export const FIXTURE_DIST = join(here, "../fixture/site");
export const SNAPSHOT = join(REPO, "snapshot/site");
export const PREVIEW_ID = "e2e-fixture";
/** The test passphrase of the LAN-mode login (>= 12 characters like the real rule; a value of this file, not a secret). */
export const TEST_PASSPHRASE = "preview-e2e-test-passphrase";
/** A host name that is not potentially trustworthy (WHATWG secure contexts: only localhost, *.localhost, 127/8 and ::1 are). */
export const PLAIN_HOST = "fw-phone.test";
/** Lean `Arm.backendOff`: an arm's private preview-server port is its public port plus this. */
export const BACKEND_OFF = 1000;

/** console-api decides every request through the Lean binary (`fwcore`): the owner gate, the grants and the arm routing. Build it
 *  first (`sh scripts/fwcore-build.sh`); the land lane and the preview-e2e workflow build it before this package runs. */
export const FWCORE_BIN = join(REPO, "lean/.lake/build/bin/fwcore");

/** Close a server and wait until its port is released (open connections are cut). */
const stopSrv = (s) => new Promise((res) => { s.close(() => res()); s.closeAllConnections?.(); });

const imp = (rel) => import(pathToFileURL(join(API, rel)).href);

/** Ports to listen on, chosen at run time: the OS hands out `n` distinct free ports and keeps every one bound until all `n` are
 *  known, so no two of them are equal and none is a port another run is using (a probe that closed at once could hand the same
 *  port out twice). `release()` frees them all together, right before the caller binds. */
async function holdPorts(n, { max = 65535 - BACKEND_OFF, host = "127.0.0.1" } = {}) {
  const held = [];
  const release = () => Promise.all(held.map((s) => new Promise((res) => s.close(() => res()))));
  try {
    for (let tries = 0; held.length < n; tries++) {
      if (tries > 400) throw new Error(`no ${n} free ports at or below ${max}`);
      const s = createServer();
      await new Promise((res, rej) => { s.once("error", rej); s.listen(0, host, res); });
      held.push(s);
      if (s.address().port > max) { held.pop(); await new Promise((res) => s.close(res)); }
    }
  } catch (e) { await release(); throw e; }
  return { ports: held.map((s) => s.address().port), release };
}

/** One run's ports: two public arm ports `rp`/`op` (their private ports +BACKEND_OFF stay <= 65535, within the Lean bound
 *  `portBase + portN + backendOff <= 65536`), where the preview server really listens, and the console and preview ports. All
 *  distinct and free at this moment; every one is bound again straight after `release()`. */
async function runPorts() {
  const arm = await holdPorts(2); // <= 64535, so the +BACKEND_OFF ports below exist
  const priv = [];
  const rest = await holdPorts(4, { max: 65535 });
  try {
    const own = arm.ports.map((p) => p + BACKEND_OFF);
    // the private ports must be free and unequal to the others: bind them too
    for (const p of own) {
      const s = createServer();
      await new Promise((res, rej) => { s.once("error", rej); s.listen(p, "127.0.0.1", res); });
      priv.push(s);
    }
  } catch (e) {
    await Promise.all(priv.map((s) => new Promise((res) => s.close(res))));
    await arm.release(); await rest.release();
    return runPorts(); // a private port was taken: draw again
  }
  const [rp, op] = arm.ports;
  const [rawRp, rawOp, consolePort, previewPort] = rest.ports;
  const release = async () => { await Promise.all(priv.map((s) => new Promise((res) => s.close(res)))); await arm.release(); await rest.release(); };
  return { rp, op, rawRp, rawOp, consolePort, previewPort, release };
}

/** The first private LAN IPv4 address (console-api's own picker), or null when the machine has none. */
export async function lanAddress() {
  const { pickLanAddr } = await imp("src/preview/lan.ts");
  return pickLanAddr(networkInterfaces());
}

/** A forward proxy on loopback that sends every request for `PLAIN_HOST:<port>` to 127.0.0.1:<port> and keeps the Host header.
 *  The browser then sees a plain-HTTP origin that is not potentially trustworthy (the phone's case) while the socket the
 *  console sees stays loopback. Used for engines that have no host-resolver flag (WebKit) and for Chromium alike. */
function startHostProxy() {
  const srv = createServer((req, res) => {
    let u;
    try { u = new URL(req.url); } catch { res.writeHead(400); return res.end("absolute URI expected"); }
    if (u.hostname !== PLAIN_HOST) { res.writeHead(502); return res.end(`proxy maps ${PLAIN_HOST} only`); }
    // hop-by-hop headers belong to one connection and are not forwarded; one upstream connection per request, torn down with the client's
    const hop = ["connection", "keep-alive", "proxy-connection", "transfer-encoding", "upgrade", "te", "trailer"];
    const strip = (h) => Object.fromEntries(Object.entries(h).filter(([k]) => !hop.includes(k.toLowerCase())));
    const up = httpRequest({ host: "127.0.0.1", port: Number(u.port || 80), path: u.pathname + u.search, method: req.method, headers: strip(req.headers), agent: false }, (r) => {
      res.writeHead(r.statusCode ?? 502, strip(r.headers));
      r.pipe(res);
      r.on("error", () => res.destroy());
    });
    up.on("error", () => { if (res.headersSent) return res.destroy(); res.writeHead(502); res.end("upstream down"); });
    res.on("close", () => { if (!res.writableFinished) up.destroy(); });
    req.pipe(up);
  });
  srv.on("connect", (_req, sock) => sock.destroy()); // no CONNECT: the suite is plain HTTP
  return new Promise((resolve) => srv.listen(0, "127.0.0.1", () => resolve(srv)));
}

/** Module-evaluation counter: a tiny HTTP server between an arm app and the preview server. It forwards every request and
 *  prepends one statement to each module under `/_app/` (`__fwEvals.push(import.meta.url)`), so the page can say at which URLs a
 *  module was evaluated. It listens on the arm's private port (public port + BACKEND_OFF), where the arm app expects the preview
 *  server; the browser still talks to the unmodified arm origin. `mode.tap` false: a plain pass-through. */
const EVAL_MARK = "(globalThis.__fwEvals ||= []).push(import.meta.url);\n";
/** SvelteKit's client `start(app, target, hydrate)` is the one async function of three parameters that begins by reading
 *  `globalThis.__sveltekit_<hash>.data`. The tap adds a call counter at its first statement (`__fwStarts`): how often the app was
 *  started, which the suite requires to be exactly 1. A module without that function passes through unchanged. */
const START_FN = /(async function \w+\(\w+,\w+,\w+\)\{)(if\(globalThis\.__sveltekit_\w+\.data\))/;
const START_MARK = "(globalThis.__fwStarts=(globalThis.__fwStarts||0)+1);";
export const instrumentModule = (text) => EVAL_MARK + text.replace(START_FN, `$1${START_MARK}$2`);
function startTap(listenPort, targetPort, mode) {
  const srv = createServer((req, res) => {
    const headers = mode.tap ? { ...req.headers, "accept-encoding": "identity" } : { ...req.headers };
    if (mode.tap) delete headers["if-none-match"];
    const up = httpRequest({ host: "127.0.0.1", port: targetPort, path: req.url, method: req.method, headers }, (r) => {
      const isModule = mode.tap && /^\/_app\/.+\.m?js$/.test((req.url ?? "").split("?")[0]) && r.statusCode === 200;
      if (!isModule) { res.writeHead(r.statusCode ?? 502, r.headers); return r.pipe(res); }
      const chunks = [];
      r.on("data", (c) => chunks.push(c));
      r.on("end", () => {
        const body = Buffer.from(instrumentModule(Buffer.concat(chunks).toString("utf8")));
        const h = { ...r.headers, "content-length": String(body.length) };
        delete h.etag; delete h["content-encoding"]; h["cache-control"] = "no-store";
        res.writeHead(200, h); res.end(req.method === "HEAD" ? undefined : body);
      });
    });
    up.on("error", () => { res.writeHead(502); res.end("upstream down"); });
    req.pipe(up);
  });
  return new Promise((resolve, reject) => { srv.on("error", reject); srv.listen(listenPort, "127.0.0.1", () => resolve(srv)); });
}

/** Start everything. `lan`: also listen on the LAN address and turn LAN mode on (needs an address; null = loopback only). */
export async function startRig({ lan = null } = {}) {
  if (!existsSync(FWCORE_BIN)) throw new Error(`fwcore binary not found at ${FWCORE_BIN}; build it with: sh scripts/fwcore-build.sh`);
  const req = createRequire(join(API, "package.json"));
  const { serve } = await import(pathToFileURL(req.resolve("@hono/node-server")).href);
  const [{ createApp }, { selectCore }, { Store }, { OwnerAuth }, { Grants }, { LoginGuard }, { createPreviewApp }, { createArmApp }, { ArmServers }] = await Promise.all([
    imp("src/app.ts"), imp("src/core/index.ts"), imp("src/store.ts"), imp("src/preview/owner.ts"), imp("src/preview/grants.ts"),
    imp("src/preview/login.ts"), imp("src/preview/preview-app.ts"), imp("src/preview/arm-app.ts"), imp("src/preview/arm-servers.ts"),
  ]);
  const tmp = mkdtempSync(join(tmpdir(), "fw-e2e-preview-"));
  const closers = [];
  // rp/op: the arms' public origins (the arm app reaches their servers at rp/op + BACKEND_OFF); rawRp/rawOp: where the preview
  // server process really listens. Chosen at run time, held together, released just before each is bound.
  const { rp, op, rawRp, rawOp, consolePort, previewPort, release: releasePorts } = await runPorts();
  await releasePorts();

  // the preview server process, as PreviewManager.defaultHooks.serve starts it (--rp/--op: where it listens, --arm-*: the arms' origins)
  const child = spawn(process.execPath, [join(API, "src/preview/serve-child.ts"), "--serve", `--fw-preview=${PREVIEW_ID}`, "--rewrite", FIXTURE_DIST,
    "--original", SNAPSHOT, "--media", SNAPSHOT, "--rp", String(rawRp), "--op", String(rawOp), "--arm-rp", String(rp), "--arm-op", String(op)],
  { stdio: ["ignore", "pipe", "pipe"] });
  const childExit = new Promise((res) => child.once("exit", res));
  closers.push(async () => { if (child.exitCode === null && child.signalCode === null) { try { child.kill("SIGTERM"); } catch { /* gone */ } await childExit; } });
  await new Promise((resolve, reject) => {
    let out = "";
    const t = setTimeout(() => reject(new Error(`preview server did not start: ${out.slice(-300)}`)), 15_000);
    child.stdout.on("data", (b) => { out += b; if (out.includes('"ready"')) { clearTimeout(t); resolve(); } });
    child.stderr.on("data", (b) => { out += b; });
    child.on("exit", (c) => { clearTimeout(t); reject(new Error(`preview server exited ${c}: ${out.slice(-300)}`)); });
  });

  /** `tap` true: the evaluation counter sits between the arm app and the preview server (the suite's arms); false: a plain
   *  pass-through (the control "arm without tap"). */
  const mode = { tap: true };
  const [tapR, tapO] = await Promise.all([startTap(rp + BACKEND_OFF, rawRp, mode), startTap(op + BACKEND_OFF, rawOp, mode)]);
  closers.push(() => stopSrv(tapR), () => stopSrv(tapO));
  const core = selectCore();
  const store = await Store.open(join(tmp, ".fw-console"), core);
  closers.push(() => store.close());
  const touched = [];
  const entry = { id: PREVIEW_ID, task: "e2e", rp, op, brp: rp + BACKEND_OFF, bop: op + BACKEND_OFF, phase: "serving" };
  const pm = {
    serving: (id) => (id !== PREVIEW_ID ? null : entry),
    touch: (id) => { touched.push(id); },
    list: () => ({ previews: [], failed: [] }),
    liveTable: () => [{ id: PREVIEW_ID, task: "e2e", rp, op, started: 0 }],
  };
  const owner = new OwnerAuth();
  owner.setPorts(consolePort, previewPort);
  const audit = [];
  const grants = new Grants(core, (r) => audit.push(r));
  const isLan = lan !== null;
  const login = new LoginGuard(core, TEST_PASSPHRASE);
  const app = createApp(store, undefined, undefined, pm, owner, undefined, { login, lan: isLan, grants });
  const previewApp = createPreviewApp(core, owner, pm, { lan: isLan, grants });
  const armApp = createArmApp(core, owner, pm, { lan: isLan, lanAddr: lan, grants });
  /** What the preview port and the arm ports saw, per request (observation only): port, path, Sec-Fetch-Dest, status. */
  const seen = [];
  const observe = (port) => async (request, env) => {
    const res = await (port === previewPort ? previewApp : armApp).fetch(request, env);
    const u = new URL(request.url);
    seen.push({ method: request.method, port: Number(request.headers.get("host")?.split(":").pop()), path: u.pathname, host: request.headers.get("host"), dest: request.headers.get("sec-fetch-dest"), status: res.status });
    return res;
  };
  const listen = (fetch, port, hostname) => new Promise((resolve, reject) => {
    const srv = serve({ fetch, port, hostname }, () => resolve(srv));
    srv.on("error", reject);
  });
  closers.push(...(await Promise.all([listen(app.fetch, consolePort, "127.0.0.1"), listen(observe(previewPort), previewPort, "127.0.0.1")])).map((s) => () => stopSrv(s)));
  const arms = new ArmServers(observe(0), lan);
  await arms.open({ id: PREVIEW_ID, rp, op });
  closers.push(() => arms.close(PREVIEW_ID));
  if (isLan) {
    owner.setLanHosts([`${lan}:${consolePort}`], [`${lan}:${previewPort}`]);
    closers.push(...(await Promise.all([listen(app.fetch, consolePort, lan), listen(observe(previewPort), previewPort, lan)])).map((s) => () => stopSrv(s)));
  }
  const proxy = await startHostProxy();
  closers.push(() => stopSrv(proxy));

  const consoleOrigin = `http://127.0.0.1:${consolePort}`;
  /** A one-time grant link for the preview, asked of the console like the lead does (loopback POST, console Origin). */
  async function grantLink(arm = "o") {
    const r = await fetch(`${consoleOrigin}/api/preview/grant`, {
      method: "POST", headers: { "content-type": "application/json", origin: consoleOrigin }, body: JSON.stringify({ id: PREVIEW_ID, arm }),
    });
    if (!r.ok) throw new Error(`grant refused: ${r.status}`);
    return new URL((await r.json()).url);
  }
  /** A host: `origin` is its preview port (the shell: entry hops and the side-by-side page); `arm.r` / `arm.o` are the two arm origins. */
  const host = (name, hostname, trustworthy, extra = {}) => ({
    name, origin: `http://${hostname}:${previewPort}`, trustworthy, arm: { r: `http://${hostname}:${rp}`, o: `http://${hostname}:${op}` }, ...extra,
  });
  return {
    ports: { console: consolePort, preview: previewPort, rp, op, brp: rp + BACKEND_OFF, bop: op + BACKEND_OFF, rawRp, rawOp, proxy: proxy.address().port },
    consoleOrigin, lan, audit, touched, seen,
    /** `useTap(false)`: the evaluation counter becomes a pass-through (control: the arm app without tap); `useTap(true)` restores. */
    useTap(on) { mode.tap = Boolean(on); },
    hosts: {
      loopback: host("loopback", "127.0.0.1", true),
      plain: host("plain-http", PLAIN_HOST, false),
      ...(isLan ? { lan: host("lan", lan, false, { consoleOrigin: `http://${lan}:${consolePort}` }) } : {}),
    },
    /** The URL of a grant link redeemed on `origin` (the link itself names loopback; its token is moved to `origin`). */
    async grantUrl(origin, arm = "o") {
      const u = await grantLink(arm);
      return `${origin}${u.pathname}${u.search}`;
    },
    async close() {
      for (const c of closers.reverse()) { try { await c(); } catch { /* closing */ } }
      rmSync(tmp, { recursive: true, force: true });
    },
  };
}
