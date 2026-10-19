// The rig of the preview e2e suite: the real console-api request handlers (app.ts, preview-app.ts, the Lean gate through fwcore)
// on spare ports, the real preview server process (serve-child.ts, started with the arguments PreviewManager gives it), and a
// fixture preview: the unmodified snapshot as the original arm and a small built rewrite (fixture/dist) as the task arm.
// Only the PreviewManager is a stand-in: its `serving`/`touch` answers (what the proxy asks of it) come from the one fixture
// entry, because a real manager builds a git worktree per preview. No keychain is read: the owner passphrase is a test value
// handed to the LoginGuard. Nothing here is a decision; the gate verdicts come from fwcore.
import { spawn } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { createServer, request as httpRequest } from "node:http";
import { createRequire } from "node:module";
import { networkInterfaces, tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
export const REPO = join(here, "../../..");
const API = join(REPO, "apps/console-api");
export const FIXTURE_DIST = join(here, "../fixture/dist");
export const SNAPSHOT = join(REPO, "snapshot/site");
export const PREVIEW_ID = "e2e-fixture";
/** The test passphrase of the LAN-mode login (>= 12 characters like the real rule; a value of this file, not a secret). */
export const TEST_PASSPHRASE = "preview-e2e-test-passphrase";
/** A host name that is not potentially trustworthy (WHATWG secure contexts: only localhost, *.localhost, 127/8 and ::1 are). */
export const PLAIN_HOST = "fw-phone.test";

const imp = (rel) => import(pathToFileURL(join(API, rel)).href);

async function freePort(host = "127.0.0.1") {
  return await new Promise((resolve, reject) => {
    const s = createServer();
    s.on("error", reject);
    s.listen(0, host, () => { const p = s.address().port; s.close(() => resolve(p)); });
  });
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
    const up = httpRequest({ host: "127.0.0.1", port: Number(u.port || 80), path: u.pathname + u.search, method: req.method, headers: req.headers }, (r) => {
      res.writeHead(r.statusCode ?? 502, r.headers);
      r.pipe(res);
    });
    up.on("error", () => { res.writeHead(502); res.end("upstream down"); });
    req.pipe(up);
  });
  srv.on("connect", (_req, sock) => sock.destroy()); // no CONNECT: the suite is plain HTTP
  return new Promise((resolve) => srv.listen(0, "127.0.0.1", () => resolve(srv)));
}

/** Module-evaluation counter: a tiny HTTP server in front of one preview server port. It forwards every request and prepends one
 *  statement to each module under `/_app/` (`__fwEvals.push(import.meta.url)`), so the page can say at which URLs a module was
 *  evaluated. It sits behind the console's preview proxy, so the browser still talks to the unmodified proxy path. */
const EVAL_MARK = "(globalThis.__fwEvals ||= []).push(import.meta.url);\n";
function startTap(port) {
  const srv = createServer((req, res) => {
    const headers = { ...req.headers, "accept-encoding": "identity" };
    delete headers["if-none-match"];
    const up = httpRequest({ host: "127.0.0.1", port, path: req.url, method: req.method, headers }, (r) => {
      const isModule = /^\/_app\/.+\.m?js$/.test((req.url ?? "").split("?")[0]) && r.statusCode === 200;
      if (!isModule) { res.writeHead(r.statusCode ?? 502, r.headers); return r.pipe(res); }
      const chunks = [];
      r.on("data", (c) => chunks.push(c));
      r.on("end", () => {
        const body = Buffer.concat([Buffer.from(EVAL_MARK), ...chunks]);
        const h = { ...r.headers, "content-length": String(body.length) };
        delete h.etag; delete h["content-encoding"]; h["cache-control"] = "no-store";
        res.writeHead(200, h); res.end(req.method === "HEAD" ? undefined : body);
      });
    });
    up.on("error", () => { res.writeHead(502); res.end("upstream down"); });
    req.pipe(up);
  });
  return new Promise((resolve) => srv.listen(0, "127.0.0.1", () => resolve(srv)));
}

/** Start everything. `lan`: also listen on the LAN address and turn LAN mode on (needs an address; null = loopback only). */
export async function startRig({ lan = null } = {}) {
  const req = createRequire(join(API, "package.json"));
  const { serve } = await import(pathToFileURL(req.resolve("@hono/node-server")).href);
  const [{ createApp }, { selectCore }, { Store }, { OwnerAuth }, { Grants }, { LoginGuard }, { createPreviewApp }] = await Promise.all([
    imp("src/app.ts"), imp("src/core/index.ts"), imp("src/store.ts"), imp("src/preview/owner.ts"), imp("src/preview/grants.ts"),
    imp("src/preview/login.ts"), imp("src/preview/preview-app.ts"),
  ]);
  const tmp = mkdtempSync(join(tmpdir(), "fw-e2e-preview-"));
  const closers = [];
  const rp = await freePort(), op = await freePort();

  // the preview server process, as PreviewManager.defaultHooks.serve starts it
  const child = spawn(process.execPath, [join(API, "src/preview/serve-child.ts"), "--serve", `--fw-preview=${PREVIEW_ID}`, "--rewrite", FIXTURE_DIST,
    "--original", SNAPSHOT, "--media", SNAPSHOT, "--rp", String(rp), "--op", String(op), "--prefix", `/preview/${PREVIEW_ID}`],
  { stdio: ["ignore", "pipe", "pipe"] });
  closers.push(() => { try { child.kill("SIGTERM"); } catch { /* gone */ } });
  await new Promise((resolve, reject) => {
    let out = "";
    const t = setTimeout(() => reject(new Error(`preview server did not start: ${out.slice(-300)}`)), 15_000);
    child.stdout.on("data", (b) => { out += b; if (out.includes('"ready"')) { clearTimeout(t); resolve(); } });
    child.stderr.on("data", (b) => { out += b; });
    child.on("exit", (c) => { clearTimeout(t); reject(new Error(`preview server exited ${c}: ${out.slice(-300)}`)); });
  });

  const [tapR, tapO] = await Promise.all([startTap(rp), startTap(op)]);
  closers.push(() => tapR.close(), () => tapO.close());
  const core = selectCore();
  const store = await Store.open(join(tmp, ".fw-console"), core);
  closers.push(() => store.close());
  const touched = [];
  const pm = {
    serving: (id) => (id === PREVIEW_ID ? { rp: tapR.address().port, op: tapO.address().port } : null),
    touch: (id) => { touched.push(id); },
    list: () => ({ previews: [], failed: [] }),
  };
  const consolePort = await freePort(), previewPort = await freePort();
  const owner = new OwnerAuth();
  owner.setPorts(consolePort, previewPort);
  const audit = [];
  const grants = new Grants(core, (r) => audit.push(r));
  const isLan = lan !== null;
  const login = new LoginGuard(core, TEST_PASSPHRASE);
  const app = createApp(store, undefined, undefined, pm, owner, undefined, { login, lan: isLan, grants });
  const previewApp = createPreviewApp(core, owner, pm, { lan: isLan, grants });
  /** What the preview port saw, per request (observation only): path, Sec-Fetch-Dest, status. */
  const seen = [];
  const observed = async (req, env) => {
    const res = await previewApp.fetch(req, env);
    const u = new URL(req.url);
    seen.push({ method: req.method, path: u.pathname, host: req.headers.get("host"), dest: req.headers.get("sec-fetch-dest"), status: res.status });
    return res;
  };
  const listen = (fetch, port, hostname) => new Promise((resolve, reject) => {
    const srv = serve({ fetch, port, hostname }, () => resolve(srv));
    srv.on("error", reject);
  });
  closers.push(...(await Promise.all([listen(app.fetch, consolePort, "127.0.0.1"), listen(observed, previewPort, "127.0.0.1")])).map((s) => () => s.close()));
  if (isLan) {
    owner.setLanHosts([`${lan}:${consolePort}`], [`${lan}:${previewPort}`]);
    closers.push(...(await Promise.all([listen(app.fetch, consolePort, lan), listen(observed, previewPort, lan)])).map((s) => () => s.close()));
  }
  const proxy = await startHostProxy();
  closers.push(() => proxy.close());

  const consoleOrigin = `http://127.0.0.1:${consolePort}`;
  /** A one-time grant link for the preview, asked of the console like the lead does (loopback POST, console Origin). */
  async function grantLink(arm = "o") {
    const r = await fetch(`${consoleOrigin}/api/preview/grant`, {
      method: "POST", headers: { "content-type": "application/json", origin: consoleOrigin }, body: JSON.stringify({ id: PREVIEW_ID, arm }),
    });
    if (!r.ok) throw new Error(`grant refused: ${r.status}`);
    return new URL((await r.json()).url);
  }
  return {
    ports: { console: consolePort, preview: previewPort, rp, op, proxy: proxy.address().port },
    consoleOrigin, lan, audit, touched, seen,
    hosts: {
      loopback: { name: "loopback", origin: `http://127.0.0.1:${previewPort}`, trustworthy: true },
      plain: { name: "plain-http", origin: `http://${PLAIN_HOST}:${previewPort}`, trustworthy: false },
      ...(isLan ? { lan: { name: "lan", origin: `http://${lan}:${previewPort}`, consoleOrigin: `http://${lan}:${consolePort}`, trustworthy: false } } : {}),
    },
    /** `{ url, token }` of a grant link redeemed on `origin` (the link itself names loopback; its token is moved to `origin`). */
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
