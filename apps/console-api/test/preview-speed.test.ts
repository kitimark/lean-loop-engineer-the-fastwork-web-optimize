import { mkdirSync, mkdtempSync, readFileSync, rmSync, utimesSync, writeFileSync } from "node:fs";
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { brotliDecompressSync, gunzipSync } from "node:zlib";
import { Hono } from "hono";
import { afterEach, describe, expect, it } from "vitest";
import { cachePolicy, etagMatches, etagOf, pickEncoding } from "../src/preview/cache-policy.ts";
import { mountPreviewProxy } from "../src/preview/proxy.ts";
import { handler } from "../src/preview/serve-child.ts";
import type { PreviewManager } from "../src/preview/manager.ts";

const GOLDEN = join(dirname(fileURLToPath(import.meta.url)), "../../../packages/contracts/golden/console/console.previewCache.jsonl");
const IMMUTABLE = "public, max-age=31536000, immutable";

let servers: Server[] = [];
let dirs: string[] = [];
afterEach(() => {
  servers.forEach((s) => s.close()); servers = [];
  dirs.forEach((d) => rmSync(d, { recursive: true, force: true })); dirs = [];
});

const listen = (s: Server) => new Promise<number>((r) => { servers.push(s); s.listen(0, "127.0.0.1", () => r((s.address() as AddressInfo).port)); });
function site(files: Record<string, string>) {
  const root = mkdtempSync(join(tmpdir(), "fw-speed-"));
  dirs.push(root);
  const put = (rel: string, body: string) => { mkdirSync(dirname(join(root, rel)), { recursive: true }); writeFileSync(join(root, rel), body); };
  for (const [k, v] of Object.entries(files)) put(k, v);
  return { root, put };
}
const body = (n: number) => "<p>hello preview</p>".repeat(n);

describe("cache policy: TS stand-in equals the Lean golden", () => {
  const lines = readFileSync(GOLDEN, "utf8").trim().split("\n").map((l) => JSON.parse(l) as { name: string; request: { path?: string; manifest?: string[] }; response: Record<string, unknown> });
  it("has cases", () => expect(lines.length).toBeGreaterThan(10));
  for (const l of lines.filter((x) => x.request.path !== undefined && x.response.error === undefined)) {
    it(l.name, () => expect(cachePolicy(l.request.path!, new Set(l.request.manifest ?? []))).toEqual(l.response));
  }
  it("only hashed files are immutable", () => {
    for (const l of lines) if (l.response.cacheControl === IMMUTABLE) expect(l.response.kind).toBe("hashed");
  });
});

describe("validators and encodings", () => {
  it("etagMatches: lists, weak tags, star", () => {
    const e = etagOf("abc");
    expect(etagMatches(e, e)).toBe(true);
    expect(etagMatches(`"x", W/${e}`, e)).toBe(true);
    expect(etagMatches("*", e)).toBe(true);
    expect(etagMatches(`"other"`, e)).toBe(false);
    expect(etagMatches(undefined, e)).toBe(false);
  });
  it("different bytes, different etag; encodings differ", () => {
    expect(etagOf("a")).not.toBe(etagOf("b"));
    expect(etagOf("a", "br")).not.toBe(etagOf("a", "gzip"));
  });
  it("pickEncoding prefers br, honours q=0", () => {
    expect(pickEncoding("gzip, deflate, br")).toBe("br");
    expect(pickEncoding("gzip")).toBe("gzip");
    expect(pickEncoding("br;q=0, gzip")).toBe("gzip");
    expect(pickEncoding("identity")).toBe("identity");
    expect(pickEncoding(undefined)).toBe("identity");
  });
});

describe("serve-child file serving", () => {
  const start = async (root: string) => {
    const port = await listen(createServer(handler({ root })));
    // raw http: fetch would decode the body and hide the encoding
    const get = (path: string, headers: Record<string, string> = {}, method = "GET") => fetch(`http://127.0.0.1:${port}${path}`, { method, headers: { "accept-encoding": "identity", ...headers } });
    return { port, get };
  };

  it("hashed names are immutable, html and plain files revalidate with a strong etag", async () => {
    const manifest = { "src/e.tsx": { file: "assets/index-BxK3a9Qz.js", css: ["assets/e-AbC12345.css"], assets: ["assets/pic-Zy98xw76.png"] } };
    const s = site({ "index.html": "<h1>x</h1>", "assets/index-BxK3a9Qz.js": "export{}", "assets/e-AbC12345.css": "a{}", "assets/pic-Zy98xw76.png": "p", "mui.b3bea9d9.css": "m{}",
      "fonts/Roboto-SemiBold.woff2": "f", "img/og-1200x630.png": "o", "icons/icon-darkMode.svg": "<svg/>", "assets/other-Qw3Er4Ty.js": "x",
      ".vite/manifest.json": JSON.stringify(manifest), "_app/immutable/chunks/x.js": "1", "plain/app.js": "2", "fonts/a.woff2": "font" });
    const { get } = await start(s.root);
    const h = async (p: string) => (await get(p)).headers;
    expect((await h("/assets/index-BxK3a9Qz.js")).get("cache-control")).toBe(IMMUTABLE);
    expect((await h("/_app/immutable/chunks/x.js")).get("cache-control")).toBe(IMMUTABLE);
    for (const p of ["/assets/e-AbC12345.css", "/assets/pic-Zy98xw76.png", "/mui.b3bea9d9.css"]) expect((await h(p)).get("cache-control")).toBe(IMMUTABLE);
    for (const p of ["/", "/plain/app.js", "/fonts/a.woff2", "/fonts/Roboto-SemiBold.woff2", "/img/og-1200x630.png", "/icons/icon-darkMode.svg", "/assets/other-Qw3Er4Ty.js"]) {
      const hd = await h(p);
      expect(hd.get("cache-control")).toBe("no-cache");
      expect(hd.get("etag")).toMatch(/^"[A-Za-z0-9_-]{43}"$/);
    }
  });

  it("a rebuilt manifest is re-read: a name that leaves it revalidates", async () => {
    const s = site({ "assets/a-Zq12Wx34.js": "1", ".vite/manifest.json": JSON.stringify({ e: { file: "assets/a-Zq12Wx34.js" } }) });
    const { get } = await start(s.root);
    expect((await get("/assets/a-Zq12Wx34.js")).headers.get("cache-control")).toBe(IMMUTABLE);
    s.put(".vite/manifest.json", JSON.stringify({ e: { file: "assets/b-Zq12Wx34.js" } }) + " ");
    expect((await get("/assets/a-Zq12Wx34.js")).headers.get("cache-control")).toBe("no-cache");
  });

  it("a file above the keep limit hashes the bytes it sends", async () => {
    const s = site({ "big.bin": "a".repeat(4 * 1024 * 1024 + 1) });
    const { get } = await start(s.root);
    const r1 = await get("/big.bin");
    const e1 = r1.headers.get("etag")!;
    expect(e1).toBe(etagOf(Buffer.from("a".repeat(4 * 1024 * 1024 + 1))));
    s.put("big.bin", "b".repeat(4 * 1024 * 1024 + 1));
    expect((await get("/big.bin", { "if-none-match": e1 })).status).toBe(200);
  });

  it("a request path that climbs out of _app/immutable is judged by the file it resolves to", async () => {
    const s = site({ "x.js": "1", "_app/immutable/y.js": "2" });
    const { port } = await start(s.root);
    const { get } = await import("node:http");
    const cc = await new Promise((resolve, reject) => { get({ host: "127.0.0.1", port, path: "/_app/immutable/%2e%2e/..//x.js" }, (r) => { r.resume(); resolve(r.headers["cache-control"]); }).on("error", reject); });
    expect(cc).toBe("no-cache");
  });

  it("If-None-Match answers 304 without a body", async () => {
    const s = site({ "index.html": "<h1>x</h1>", "assets/app.4f3a9c1d.css": "a{}" });
    const { get } = await start(s.root);
    for (const p of ["/", "/assets/app.4f3a9c1d.css"]) {
      const first = await get(p);
      const etag = first.headers.get("etag")!;
      const again = await get(p, { "if-none-match": etag });
      expect(again.status).toBe(304);
      expect(await again.text()).toBe("");
      expect(again.headers.get("etag")).toBe(etag);
      expect(again.headers.get("cache-control")).toBe(first.headers.get("cache-control"));
      expect((await get(p, { "if-none-match": '"stale"' })).status).toBe(200);
    }
  });

  it("text types are compressed by Accept-Encoding, binary types are not", async () => {
    const s = site({ "index.html": body(400), "a.png": body(400) });
    const { port } = await start(s.root);
    const raw = (path: string, enc: string) => new Promise<{ enc?: string; bytes: Buffer; vary?: string }>((resolve, reject) => {
      import("node:http").then(({ get }) => get({ host: "127.0.0.1", port, path, headers: { "accept-encoding": enc } }, (r) => {
        const cs: Buffer[] = [];
        r.on("data", (c) => cs.push(c));
        r.on("end", () => resolve({ enc: r.headers["content-encoding"], bytes: Buffer.concat(cs), vary: r.headers.vary }));
      }).on("error", reject));
    });
    const br = await raw("/", "gzip, br");
    expect(br.enc).toBe("br");
    expect(br.vary).toBe("accept-encoding");
    expect(brotliDecompressSync(br.bytes).toString()).toBe(body(400));
    expect(br.bytes.length).toBeLessThan(body(400).length / 10);
    const gz = await raw("/", "gzip");
    expect(gz.enc).toBe("gzip");
    expect(gunzipSync(gz.bytes).toString()).toBe(body(400));
    const none = await raw("/", "identity");
    expect(none.enc).toBeUndefined();
    expect(none.bytes.toString()).toBe(body(400));
    expect((await raw("/a.png", "gzip, br")).enc).toBeUndefined();
  });

  it("each encoding has its own etag", async () => {
    const s = site({ "index.html": body(50) });
    const { get } = await start(s.root);
    const a = (await get("/", { "accept-encoding": "gzip" })).headers.get("etag");
    const b = (await get("/", { "accept-encoding": "br" })).headers.get("etag");
    const c = (await get("/")).headers.get("etag");
    expect(new Set([a, b, c]).size).toBe(3);
  });

  it("a rebuilt file is never served stale (new size, and same size with the old mtime)", async () => {
    const s = site({ "index.html": "<h1>one</h1>", "app.js": "console.log(1)" });
    const { get } = await start(s.root);
    const first = await get("/");
    const etag1 = first.headers.get("etag")!;
    expect(await first.text()).toBe("<h1>one</h1>");
    s.put("index.html", "<h1>two, longer</h1>");
    const second = await get("/", { "if-none-match": etag1 });
    expect(second.status).toBe(200);
    expect(await second.text()).toBe("<h1>two, longer</h1>");
    expect(second.headers.get("etag")).not.toBe(etag1);
    const j1 = await get("/app.js");
    const jetag = j1.headers.get("etag")!;
    await j1.text();
    const before = (await import("node:fs")).statSync(join(s.root, "app.js"));
    s.put("app.js", "console.log(2)");
    utimesSync(join(s.root, "app.js"), before.atime, before.mtime);
    const j2 = await get("/app.js", { "if-none-match": jetag });
    expect(j2.status).toBe(200);
    expect(await j2.text()).toBe("console.log(2)");
    expect(j2.headers.get("etag")).not.toBe(jetag);
  });

  it("the stub analytics, 404 and the compare page stay uncacheable", async () => {
    const s = site({ "index.html": "x" });
    const port = await listen(createServer(handler({ root: s.root, compare: { rp: 1, op: 2, prefix: "/preview/a" } })));
    for (const p of ["/analytics.js", "/missing.txt", "/__fw/compare"]) expect((await fetch(`http://127.0.0.1:${port}${p}`)).headers.get("cache-control")).toBe("no-store");
  });
});

describe("proxy", () => {
  async function rig(rewriteFiles: Record<string, string>, originalFiles: Record<string, string> = rewriteFiles) {
    const r = site(rewriteFiles), o = site(originalFiles);
    const rp = await listen(createServer(handler({ root: r.root, compare: { rp: 0, op: 0, prefix: "/preview/p1" } })));
    const op = await listen(createServer(handler({ root: o.root })));
    const entry = { id: "p1", rp, op, phase: "serving" };
    const app = new Hono();
    mountPreviewProxy(app, { serving: (id: string) => (id === "p1" ? entry : null), touch() {} } as unknown as PreviewManager);
    const pp = await listen(createServer(async (req, res) => {
      const headers = new Headers();
      for (const [k, v] of Object.entries(req.headers)) if (typeof v === "string") headers.set(k, v);
      const out = await app.fetch(new Request(`http://127.0.0.1${req.url}`, { method: req.method, headers }));
      const h: Record<string, string> = {};
      out.headers.forEach((v, k) => { h[k] = v; });
      res.writeHead(out.status, h);
      res.end(Buffer.from(await out.arrayBuffer()));
    }));
    const raw = (path: string, headers: Record<string, string> = {}) => new Promise<{ status: number; headers: Record<string, string | string[] | undefined>; bytes: Buffer }>((resolve, reject) => {
      import("node:http").then(({ get }) => get({ host: "127.0.0.1", port: pp, path, headers }, (res) => {
        const cs: Buffer[] = [];
        res.on("data", (c) => cs.push(c));
        res.on("end", () => resolve({ status: res.statusCode!, headers: res.headers, bytes: Buffer.concat(cs) }));
      }).on("error", reject));
    });
    return { r, o, raw };
  }
  const HTML = (n: string) => `<!doctype html><link rel="stylesheet" href="/assets/app.4f3a9c1d.css"><img src="/a.png"><p>${n}</p>${body(200)}`;

  it("rewritten html: prefix applied, own etag, 304 on revalidation, compressed", async () => {
    const { raw } = await rig({ "index.html": HTML("one"), "assets/app.4f3a9c1d.css": "a{background:url(/b.png)}", "a.png": "png" });
    const first = await raw("/preview/p1/r/", { "accept-encoding": "br" });
    expect(first.status).toBe(200);
    expect(first.headers["content-encoding"]).toBe("br");
    expect(first.headers["cache-control"]).toBe("no-cache");
    const text = brotliDecompressSync(first.bytes).toString();
    expect(text).toContain('href="/preview/p1/r/assets/app.4f3a9c1d.css"');
    expect(first.bytes.length).toBeLessThan(text.length / 10);
    const etag = first.headers.etag as string;
    const again = await raw("/preview/p1/r/", { "accept-encoding": "br", "if-none-match": etag });
    expect(again.status).toBe(304);
    expect(again.bytes.length).toBe(0);
    const gz = await raw("/preview/p1/r/", { "accept-encoding": "gzip" });
    expect(gunzipSync(gz.bytes).toString()).toBe(text);
    expect(gz.headers.etag).not.toBe(etag);
    const plain = await raw("/preview/p1/r/");
    expect(plain.headers["content-encoding"]).toBeUndefined();
    expect(plain.bytes.toString()).toBe(text);
  });

  it("the original and the rewrite arm get different bodies and different etags for the same source", async () => {
    const { raw } = await rig({ "index.html": HTML("x") });
    const a = await raw("/preview/p1/r/"), b = await raw("/preview/p1/o/");
    expect(a.headers.etag).not.toBe(b.headers.etag);
    expect(b.bytes.toString()).toContain("/preview/p1/o/assets/");
  });

  it("a rebuilt html is never served stale through the proxy", async () => {
    const { raw, r } = await rig({ "index.html": HTML("one") });
    const first = await raw("/preview/p1/r/");
    const etag = first.headers.etag as string;
    expect(first.bytes.toString()).toContain("<p>one</p>");
    r.put("index.html", HTML("two"));
    const second = await raw("/preview/p1/r/", { "if-none-match": etag });
    expect(second.status).toBe(200);
    expect(second.bytes.toString()).toContain("<p>two</p>");
    expect(second.headers.etag).not.toBe(etag);
    const third = await raw("/preview/p1/r/", { "if-none-match": second.headers.etag as string });
    expect(third.status).toBe(304);
  });

  it("css is rewritten and cached; hashed files pass through immutable; other files revalidate", async () => {
    const { raw } = await rig({ "index.html": HTML("x"), "assets/app.4f3a9c1d.css": "a{background:url(/b.png)}", "a.png": "png", "assets/index-BxK3a9Qz.js": body(100),
      ".vite/manifest.json": JSON.stringify({ e: { file: "assets/index-BxK3a9Qz.js", css: ["assets/app.4f3a9c1d.css"] } }) });
    const css = await raw("/preview/p1/r/assets/app.4f3a9c1d.css");
    expect(css.bytes.toString()).toBe("a{background:url(/preview/p1/r/b.png)}");
    expect(css.headers["cache-control"]).toBe(IMMUTABLE);
    expect((await raw("/preview/p1/r/assets/app.4f3a9c1d.css", { "if-none-match": css.headers.etag as string })).status).toBe(304);
    const js = await raw("/preview/p1/r/assets/index-BxK3a9Qz.js", { "accept-encoding": "gzip" });
    expect(js.headers["cache-control"]).toBe(IMMUTABLE);
    expect(js.headers["content-encoding"]).toBe("gzip");
    expect(gunzipSync(js.bytes).toString()).toBe(body(100));
    const png = await raw("/preview/p1/r/a.png");
    expect(png.headers["cache-control"]).toBe("no-cache");
    const re = await raw("/preview/p1/r/a.png", { "if-none-match": png.headers.etag as string });
    expect(re.status).toBe(304);
    expect(re.bytes.length).toBe(0);
  });

  it("a rebuilt passthrough file is refetched", async () => {
    const { raw, r } = await rig({ "index.html": "x", "a.png": "png-one" });
    const first = await raw("/preview/p1/r/a.png");
    r.put("a.png", "png-two!");
    const second = await raw("/preview/p1/r/a.png", { "if-none-match": first.headers.etag as string });
    expect(second.status).toBe(200);
    expect(second.bytes.toString()).toBe("png-two!");
  });

  it("the compare page and a missing file stay no-store", async () => {
    const { raw } = await rig({ "index.html": "x" });
    const cmp = await raw("/preview/p1/compare");
    expect(cmp.status).toBe(200);
    expect(cmp.headers["cache-control"]).toBe("no-store");
    expect(cmp.headers.etag).toBeUndefined();
    const miss = await raw("/preview/p1/r/nope.txt");
    expect(miss.status).toBe(404);
    expect(miss.headers["cache-control"]).toBe("no-store");
  });
});
