// Preview load bench (I/O only, no decisions): serve the rewrite build (r) and the snapshot (o) the way PreviewManager does
// (defaultHooks(...).serve spawns serve-child.ts with --prefix), put the console's preview proxy in front (mountPreviewProxy),
// and load /preview/<id>/r/ and /preview/<id>/o/ in headless Chrome under CDP Network.emulateNetworkConditions
// (default 20 Mbit/s, 20 ms RTT): a first load, then a reload. Prints one JSON object per arm and load.
//   node scripts/preview-bench.mjs --src <apps/console-api dir whose src/preview is measured> --dist <apps/site/dist/aot>
//        --snap <snapshot/site> [--mbit 20] [--rtt 20] [--label after] [--viewport 1280x800]
// `--src` is how "before" (a checkout of main) and "after" (this branch) run the same harness over different code.
// Not wired: the gate (cookie, Host) and the manager's build step; the proxy gets a manager-shaped stub like test/preview-speed.test.ts.
import { createServer } from "node:http";
import { createRequire } from "node:module";
import { mkdirSync, mkdtempSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const arg = (n, d) => { const i = process.argv.indexOf(n); return i >= 0 ? process.argv[i + 1] : d; };
const here = dirname(new URL(import.meta.url).pathname);
const src = resolve(arg("--src", join(here, "..")));
const dist = resolve(arg("--dist"));
const snap = resolve(arg("--snap"));
const mbit = Number(arg("--mbit", "20")), rtt = Number(arg("--rtt", "20"));
const label = arg("--label", "run");
const [vw, vh] = arg("--viewport", "1280x800").split("x").map(Number);
const chrome = arg("--chrome", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome");
const pwDir = arg("--playwright", join(here, "../../../node_modules/.pnpm/playwright-core@1.64.1/node_modules/playwright-core"));

const imp = (rel) => import(pathToFileURL(join(src, rel)).href);
const { defaultHooks } = await imp("src/preview/manager.ts");
const { mountPreviewProxy } = await imp("src/preview/proxy.ts");
const { Hono } = await import(pathToFileURL(createRequire(join(src, "package.json")).resolve("hono")).href);
const { chromium } = createRequire(import.meta.url)(pwDir);

const tree = mkdtempSync(join(tmpdir(), "fw-bench-"));
mkdirSync(join(tree, "apps/site/dist"), { recursive: true });
mkdirSync(join(tree, "snapshot"), { recursive: true });
symlinkSync(dist, join(tree, "apps/site/dist/aot"));
symlinkSync(snap, join(tree, "snapshot/site"));
const base = 47300 + Math.floor(Math.random() * 400) * 2;
const entry = { id: "bench", task: "bench", tree, rp: base, op: base + 1, phase: "serving", pstart: null };
const hooks = defaultHooks(tree, tree);
let pid = null;
pid = await hooks.serve(entry, (p) => { pid = p; });

const app = new Hono();
mountPreviewProxy(app, { serving: (id) => (id === "bench" ? entry : null), touch() {} });
const proxy = createServer(async (req, res) => {
  const headers = new Headers();
  for (const [k, v] of Object.entries(req.headers)) if (typeof v === "string") headers.set(k, v);
  const out = await app.fetch(new Request(`http://127.0.0.1${req.url}`, { method: req.method, headers }));
  const h = {};
  out.headers.forEach((v, k) => { h[k] = v; });
  res.writeHead(out.status, h);
  res.end(Buffer.from(await out.arrayBuffer()));
});
proxy.keepAliveTimeout = 65_000;
await new Promise((r) => proxy.listen(0, "127.0.0.1", r));
const port = proxy.address().port;

const browser = await chromium.launch({ executablePath: chrome, headless: true,
  args: ["--host-resolver-rules=MAP * ~NOTFOUND , EXCLUDE 127.0.0.1", "--no-first-run", "--disable-extensions"] });

async function loadTwice(arm) {
  const ctx = await browser.newContext({ viewport: { width: vw, height: vh } }); // fresh profile: empty HTTP cache
  const page = await ctx.newPage();
  const cdp = await ctx.newCDPSession(page);
  await cdp.send("Network.enable");
  await cdp.send("Network.emulateNetworkConditions", { offline: false, latency: rtt, downloadThroughput: (mbit * 1e6) / 8, uploadThroughput: (mbit * 1e6) / 8 });
  let reqs = new Map();
  cdp.on("Network.requestWillBeSent", (e) => { if (!reqs.has(e.requestId)) reqs.set(e.requestId, { url: e.request.url, bytes: 0 }); });
  cdp.on("Network.responseReceived", (e) => { const r = reqs.get(e.requestId); if (r) Object.assign(r, { status: e.response.status, fromCache: !!(e.response.fromDiskCache || e.response.fromPrefetchCache), type: e.type }); });
  cdp.on("Network.requestServedFromCache", (e) => { const r = reqs.get(e.requestId); if (r) r.memCache = true; }); // a fresh copy: no request left the browser
  cdp.on("Network.loadingFinished", (e) => { const r = reqs.get(e.requestId); if (r) r.bytes = e.encodedDataLength; });
  cdp.on("Network.loadingFailed", (e) => { const r = reqs.get(e.requestId); if (r) r.failed = true; });
  const url = `http://127.0.0.1:${port}/preview/bench/${arm}/`;
  const out = [];
  for (const phase of ["first", "reload"]) {
    reqs = new Map();
    const t0 = Date.now();
    if (phase === "first") await page.goto(url, { waitUntil: "load", timeout: 120_000 });
    else await page.reload({ waitUntil: "load", timeout: 120_000 });
    const loadMs = Date.now() - t0;
    await page.waitForLoadState("networkidle", { timeout: 120_000 }).catch(() => {});
    const idleMs = Date.now() - t0;
    const rs = [...reqs.values()].filter((r) => r.url.startsWith(`http://127.0.0.1:${port}`));
    const ok = rs.filter((r) => !r.failed);
    out.push({
      label, arm, phase, mbit, rtt, loadMs, idleMs, requests: ok.length,
      kb: Math.round(ok.reduce((a, r) => a + r.bytes, 0) / 102.4) / 10,
      status: ok.reduce((a, r) => { const k = r.fromCache || r.memCache ? "cache" : String(r.status); a[k] = (a[k] ?? 0) + 1; return a; }, {}),
      non304: phase === "reload" ? ok.filter((r) => !r.fromCache && !r.memCache && r.status !== 304).map((r) => `${r.status} ${r.url.replace(`http://127.0.0.1:${port}`, "")} ${r.bytes}B`) : undefined,
    });
  }
  await ctx.close();
  return out;
}

try {
  for (const arm of ["r", "o"]) for (const row of await loadTwice(arm)) console.log(JSON.stringify(row));
} finally {
  await browser.close();
  proxy.close();
  if (pid) hooks.killGroup(pid);
  rmSync(tree, { recursive: true, force: true });
  process.exit(0);
}
