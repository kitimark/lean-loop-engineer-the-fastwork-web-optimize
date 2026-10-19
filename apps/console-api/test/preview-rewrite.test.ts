// The preview rewrite never changes an inline <script> body (the original's CSP allows its boot script by hash only), and
// the manifest link asks for credentials. TS stand-in: the rewrite rules are I/O glue, not Lean-specified.
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { rewriteBody } from "../src/preview/rewrite.ts";
import { viaReferer } from "../src/preview/proxy.ts";

const P = "/preview/a/o";
const inlineBodies = (h: string) => [...h.matchAll(/<script\b((?:[^>"']|"[^"]*"|'[^']*')*)>([\s\S]*?)<\/script\s*>/gi)].filter((m) => !/\ssrc\s*=/i.test(m[1]!)).map((m) => m[2]!);

describe("preview rewrite keeps inline scripts", () => {
  it("table", () => {
    const boot = '<script>import("/_app/start.js"); fetch("/x"); var a=" src=\\"/y\\" ";</script>';
    expect(rewriteBody("text/html", `<a href="/p">${boot}<script src="/s.js"></script><img src="/i.png">`, P))
      .toBe(`<a href="${P}/p">${boot}<script src="${P}/s.js"></script><img src="${P}/i.png">`);
    expect(rewriteBody("text/html", '<script type="application/ld+json">{"u":"/a","css":"url(/b)"}</script>', P)).toBe('<script type="application/ld+json">{"u":"/a","css":"url(/b)"}</script>');
    expect(rewriteBody("text/html", '<SCRIPT>x("/a")</SCRIPT><a href="/b">', P)).toBe(`<SCRIPT>x("/a")</SCRIPT><a href="${P}/b">`);
  });
  it("manifest link carries credentials", () => {
    expect(rewriteBody("text/html", '<link rel="manifest" href="/site.webmanifest"/>', P)).toBe(`<link rel="manifest" href="${P}/site.webmanifest" crossorigin="use-credentials"/>`);
    expect(rewriteBody("text/html", '<link rel="manifest" href="/m" crossorigin>', P)).toBe(`<link rel="manifest" href="${P}/m" crossorigin>`);
    expect(rewriteBody("text/html", '<link rel="icon" href="/i.png">', P)).toBe(`<link rel="icon" href="${P}/i.png">`);
  });
  it("a dynamic import from the boot script resolves to its arm through the Referer", () => {
    expect(viaReferer("/_app/immutable/entry/start.js", "http://h:1/preview/p1/o/", "h:1")).toBe("/preview/p1/o/_app/immutable/entry/start.js");
    expect(viaReferer("/_app/immutable/entry/start.js", "http://h:1/preview/p1/r/", "h:1")).toBe("/preview/p1/r/_app/immutable/entry/start.js");
  });
  it("real snapshot: inline bodies equal, every CSP hash matches", () => {
    const orig = readFileSync(new URL("../../../snapshot/site/index.html", import.meta.url), "utf8");
    const out = rewriteBody("text/html; charset=utf-8", orig, P)!;
    expect(out).not.toBe(orig);
    expect(inlineBodies(out)).toEqual(inlineBodies(orig));
    expect(inlineBodies(out).length).toBeGreaterThan(0);
    const csp = /http-equiv="content-security-policy"\s+content="([^"]*)"/i.exec(out)![1]!;
    const hashes = [...csp.matchAll(/'sha256-([^']+)'/g)].map((m) => m[1]!);
    const have = inlineBodies(out).map((b) => createHash("sha256").update(b).digest("base64"));
    expect(hashes.length).toBeGreaterThan(0);
    for (const h of hashes) expect(have).toContain(h);
  });
});

describe("module imports through the Referer", () => {
  it("a script-destination request from a preview page is sent below the arm; other requests are served in place", async () => {
    const { createServer } = await import("node:http");
    const { createPreviewApp } = await import("../src/preview/preview-app.ts");
    const { OwnerAuth } = await import("../src/preview/owner.ts");
    const { selectCore } = await import("../src/core/index.ts");
    const up = createServer((_q, res) => { res.setHeader("content-type", "text/plain"); res.end("up"); });
    await new Promise<void>((r) => up.listen(0, "127.0.0.1", () => r()));
    try {
      const port = (up.address() as { port: number }).port;
      const pm = { serving: (id: string) => (id === "p1" ? { rp: port, op: port } : null), touch: () => undefined } as never;
      const owner = new OwnerAuth();
      const app = createPreviewApp(selectCore(process.env, undefined, () => undefined), owner, pm, { lan: false });
      const cookie = owner.previewCookieFor(owner.open())[0]!.split(";")[0]!;
      const ref = "http://h:1/preview/p1/o/";
      const imp = await app.request("/_app/immutable/entry/start.js?v=1", { headers: { cookie, referer: ref, host: "h:1", "sec-fetch-dest": "script" } });
      expect(imp.status).toBe(302);
      expect(imp.headers.get("location")).toBe("/preview/p1/o/_app/immutable/entry/start.js?v=1");
      const img = await app.request("/x.png", { headers: { cookie, referer: ref, host: "h:1", "sec-fetch-dest": "image" } });
      expect(img.status).toBe(200);
    } finally { up.close(); }
  });
});
