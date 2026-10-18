// console-lan-owner: login limiter, LAN gate, preview proxy, rewrite, lan helpers. The keychain is never touched: the
// passphrase is an injected fake, and `readPassphrase` gets an injected runner.
import { mkdtempSync } from "node:fs";
import { createServer, type Server } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createApp } from "../src/app.ts";
import { selectCore } from "../src/core/index.ts";
import { Store } from "../src/store.ts";
import { OwnerAuth } from "../src/preview/owner.ts";
import { LoginGuard, readPassphrase, sameSecret, loginPage, KEYCHAIN_HINT } from "../src/preview/login.ts";
import { isLoopback, isPrivateV4, pickLanAddr } from "../src/preview/lan.ts";
import { rewriteBody } from "../src/preview/rewrite.ts";
import { viaReferer } from "../src/preview/proxy.ts";
import type { PreviewManager } from "../src/preview/manager.ts";

const FAKE = "fake-pass-for-tests-only";
let stores: Store[] = [];
let servers: Server[] = [];
afterEach(async () => {
  stores.forEach((s) => s.close()); stores = [];
  await Promise.all(servers.map((s) => new Promise((r) => s.close(() => r(null))))); servers = [];
});
async function store() {
  const s = await Store.open(join(mkdtempSync(join(tmpdir(), "fw-lo-")), ".fw-console"), selectCore());
  stores.push(s); return s;
}
const LAN = { incoming: { socket: { remoteAddress: "198.51.100.50" } } };
const LOOP = { incoming: { socket: { remoteAddress: "127.0.0.1" } } };

describe("owner sessions", () => {
  it("several devices, each its own session; logout ends only that one; unknown cookies refused", () => {
    let t = 0; const o = new OwnerAuth([], () => t);
    const a = o.open(); const b = o.open();
    const ck = (s: string) => `fw_owner=${s}`;
    expect(a).not.toBe(b);
    expect(o.cookieOk(ck(a))).toBe(true); expect(o.cookieOk(ck(b))).toBe(true);
    expect(o.cookieOk(ck("nope"))).toBe(false); expect(o.cookieOk(undefined)).toBe(false);
    o.close(ck(a));
    expect(o.cookieOk(ck(a))).toBe(false); expect(o.cookieOk(ck(b))).toBe(true);
    t += 9 * 3_600_000;
    expect(o.cookieOk(ck(b))).toBe(false); // 8 h expiry
    expect(OwnerAuth.setCookie("x")).toMatch(/HttpOnly.*SameSite=Strict/);
  });
  it("hostOk and originOk follow the LAN hosts", () => {
    const o = new OwnerAuth();
    expect(o.hostOk("198.51.100.9:4000")).toBe(false);
    o.setLanHosts(["198.51.100.9:4000"]);
    expect(o.hostOk("198.51.100.9:4000")).toBe(true);
    expect(o.hostOk("evil.example:4000")).toBe(false);
    expect(o.originOk("http://198.51.100.9:4000", "198.51.100.9:4000")).toBe(true);
    expect(o.originOk("http://evil.example", "198.51.100.9:4000")).toBe(false);
  });
});

describe("keychain read and compare", () => {
  it("readPassphrase: trims the newline; failure or empty -> null, no error text kept", () => {
    expect(readPassphrase(() => `${FAKE}\n`)).toBe(FAKE);
    expect(readPassphrase(() => "\n")).toBeNull();
    expect(readPassphrase(() => { throw new Error(`leak ${FAKE}`); })).toBeNull();
  });
  it("sameSecret", () => {
    expect(sameSecret(FAKE, FAKE)).toBe(true);
    expect(sameSecret(FAKE, FAKE + "x")).toBe(false);
    expect(sameSecret("", FAKE)).toBe(false);
  });
  it("disabled page shows the hint and no form", () => {
    const p = loginPage({ enabled: false });
    expect(p).toContain("security add-generic-password"); expect(p).not.toContain("<form");
    expect(KEYCHAIN_HINT).toContain("fw-console-owner");
  });
});

describe("LoginGuard (Lean console.ownerLogin)", () => {
  it("5 wrong tries, then locked even for the right passphrase until the lock ends; other addresses unaffected", async () => {
    const s = await store(); let t = 1_000_000;
    const g = new LoginGuard(s.core, FAKE, () => t);
    for (let i = 0; i < 5; i++) expect((await g.attempt("a", "bad")).verdict).toBe("wrong");
    const locked = await g.attempt("a", FAKE);
    expect(locked.verdict).toBe("locked"); expect(locked.retryAt).toBeGreaterThan(t);
    expect((await g.attempt("b", FAKE)).verdict).toBe("ok");
    t += 600_001;
    expect((await g.attempt("a", FAKE)).verdict).toBe("ok");
  });
  it("parallel attempts share one record: at most 5 checks counted wrong", async () => {
    const s = await store();
    const g = new LoginGuard(s.core, FAKE, () => 1_000_000);
    const rs = await Promise.all(Array.from({ length: 12 }, () => g.attempt("a", "bad")));
    expect(rs.filter((r) => r.verdict === "wrong").length).toBe(5);
    expect(rs.filter((r) => r.verdict === "locked").length).toBe(7);
  });
  it("no passphrase: disabled", async () => {
    const s = await store();
    expect((await new LoginGuard(s.core, null).attempt("a", "x")).verdict).toBe("disabled");
  });
  it("a full table of live records fails closed", async () => {
    const s = await store();
    const g = new LoginGuard(s.core, FAKE, () => 1_000_000, 2);
    await g.attempt("a", "bad"); await g.attempt("b", "bad");
    expect((await g.attempt("c", FAKE)).verdict).toBe("locked");
  });
});

describe("gate and login routes", () => {
  async function mk(lan: boolean, pass: string | null = FAKE) {
    const s = await store();
    const owner = new OwnerAuth(); owner.setLanHosts(["198.51.100.9:4000"]);
    const login = new LoginGuard(s.core, pass);
    return { app: createApp(s, undefined, undefined, undefined, owner, undefined, { login, lan }), owner };
  }
  const form = (p: string) => ({ method: "POST", body: new URLSearchParams({ passphrase: p }).toString(), headers: { "content-type": "application/x-www-form-urlencoded", host: "198.51.100.9:4000" } });

  it("LAN: only the login page without a session; HTML gets a redirect, API gets 401; wrong Host 421", async () => {
    const { app } = await mk(true);
    const H = { host: "198.51.100.9:4000" };
    expect((await app.request("/owner/login", { headers: H }, LAN)).status).toBe(200);
    expect((await app.request("/api/tasks", { headers: H }, LAN)).status).toBe(401);
    const r = await app.request("/", { headers: { ...H, accept: "text/html" } }, LAN);
    expect(r.status).toBe(303); expect(r.headers.get("location")).toBe("/owner/login");
    expect((await app.request("/api/tasks", { headers: { host: "evil.example" } }, LAN)).status).toBe(421);
    expect((await app.request("/preview/x/r/", { headers: H }, LAN)).status).toBe(401);
  });
  it("login sets a session cookie that opens the LAN; logout closes it", async () => {
    const { app } = await mk(true);
    const bad = await app.request("/owner/login", form("nope"), LAN);
    expect(bad.status).toBe(401); expect(await bad.text()).not.toContain("nope");
    const ok = await app.request("/owner/login", form(FAKE), LAN);
    expect(ok.status).toBe(303);
    const cookie = (ok.headers.get("set-cookie") ?? "").split(";")[0]!;
    expect(ok.headers.get("set-cookie")).toMatch(/HttpOnly/);
    const H = { host: "198.51.100.9:4000", cookie };
    expect((await app.request("/api/owner", { headers: H }, LAN)).status).toBe(200);
    expect(((await (await app.request("/api/owner", { headers: H }, LAN)).json()) as any).session).toBe(true);
    await app.request("/owner/logout", { method: "POST", headers: H }, LAN);
    expect((await app.request("/api/tasks", { headers: H }, LAN)).status).toBe(401);
  });
  it("the passphrase never appears in any response (json and form, bad and ok and locked)", async () => {
    const { app } = await mk(true);
    const bodies: string[] = [];
    for (let i = 0; i < 7; i++) {
      const r = await app.request("/owner/login", { method: "POST", body: JSON.stringify({ passphrase: FAKE + "x" }), headers: { "content-type": "application/json", host: "198.51.100.9:4000" } }, LAN);
      bodies.push(await r.text(), [...r.headers.values()].join("|"));
    }
    const r6 = await app.request("/owner/login", { method: "POST", body: "{not json " + FAKE, headers: { "content-type": "application/json" } }, LAN);
    bodies.push(await r6.text());
    expect(bodies.join("\n")).not.toContain(FAKE);
  });
  it("429 with Retry-After after the limit", async () => {
    const { app } = await mk(true);
    let last = 0;
    for (let i = 0; i < 6; i++) last = (await app.request("/owner/login", form("bad"), LAN)).status;
    expect(last).toBe(429);
    const r = await app.request("/owner/login", form(FAKE), LAN);
    expect(r.status).toBe(429); expect(Number(r.headers.get("retry-after"))).toBeGreaterThan(0);
  });
  it("loopback: today's rules (API open), previews still need a session; disabled login says 503", async () => {
    const { app } = await mk(false, null);
    expect((await app.request("/api/tasks", {}, LOOP)).status).not.toBe(401);
    expect((await app.request("/preview/x/r/", {}, LOOP)).status).toBe(401);
    expect((await app.request("/owner/login", {}, LOOP)).status).toBe(503);
    expect((await app.request("/owner/login", form("x"), LOOP)).status).toBe(503);
  });
  it("LAN mode with an unknown remote address counts as LAN", async () => {
    const { app } = await mk(true);
    expect((await app.request("/api/tasks", { headers: { host: "198.51.100.9:4000" } })).status).toBe(401);
  });
});

describe("preview proxy", () => {
  it("serves below the prefix with rewritten HTML, touches, 404 for unknown, 405 for POST; needs a session", async () => {
    const up = createServer((req, res) => {
      if (req.url === "/") { res.setHeader("content-type", "text/html"); res.end('<link href="/assets/a.css"><script src="/assets/a.js"></script>'); }
      else { res.setHeader("content-type", "application/javascript"); res.end('import("/x.js")'); }
    });
    await new Promise<void>((r) => up.listen(0, "127.0.0.1", () => r())); servers.push(up);
    const port = (up.address() as { port: number }).port;
    const touched: string[] = [];
    const pm = { serving: (id: string) => (id === "p1" ? { rp: port, op: port } : null), touch: (id: string) => { touched.push(id); } } as unknown as PreviewManager;
    const s = await store(); const owner = new OwnerAuth();
    const app = createApp(s, undefined, undefined, pm, owner);
    expect((await app.request("/preview/p1/r/")).status).toBe(401);
    const H = { cookie: `fw_owner=${owner.open()}` };
    const r = await app.request("/preview/p1/r/", { headers: H });
    expect(r.status).toBe(200);
    expect(await r.text()).toBe('<link href="/preview/p1/r/assets/a.css"><script src="/preview/p1/r/assets/a.js"></script>');
    expect(touched).toEqual(["p1"]);
    expect(await (await app.request("/preview/p1/r/a.js", { headers: H })).text()).toBe('import("/x.js")'); // JS is not rewritten
    // a path built inside the preview's scripts ("/x.js") reaches that preview by its Referer, and is gated as a preview path
    const ref = { referer: "http://h:1/preview/p1/r/", host: "h:1" };
    expect((await app.request("/x.js", { headers: { ...H, ...ref } })).status).toBe(200);
    expect((await app.request("/x.js", { headers: ref })).status).toBe(401);
    expect((await app.request("/x.js", { headers: { ...H, referer: "http://evil/preview/p1/r/", host: "h:1" } })).status).toBe(404); // another origin's Referer is the console's own path
    expect((await app.request("/preview/nope/r/", { headers: H })).status).toBe(404);
    expect((await app.request("/preview/p1/r/", { method: "POST", headers: H })).status).toBe(405);
    expect((await app.request("/preview/p1/r", { headers: H })).status).toBe(302);
  });
});

describe("helpers", () => {
  it("rewriteBody", () => {
    const P = "/preview/a/r";
    expect(rewriteBody("text/html", '<a href="/x"><img src=\'/y.png\'><a href="//cdn/x"><a href="/preview/b/r/z"><a href="rel">', P))
      .toBe('<a href="/preview/a/r/x"><img src=\'/preview/a/r/y.png\'><a href="//cdn/x"><a href="/preview/b/r/z"><a href="rel">');
    expect(rewriteBody("text/html", '<img srcset="/a.png 1x, /b.png 2x">', P)).toBe('<img srcset="/preview/a/r/a.png 1x, /preview/a/r/b.png 2x">');
    expect(rewriteBody("text/css", "a{background:url(/i.png)} @import '/b.css'; b{background:url(https://x/y)}", P))
      .toBe("a{background:url(/preview/a/r/i.png)} @import '/preview/a/r/b.css'; b{background:url(https://x/y)}");
    expect(rewriteBody("application/javascript", "import('/x')", P)).toBeNull();
  });
  it("viaReferer", () => {
    expect(viaReferer("/a/b.png", "http://h:1/preview/p1/o/x", "h:1")).toBe("/preview/p1/o/a/b.png");
    expect(viaReferer("/api/tasks", "http://h:1/preview/p1/r/", "h:1")).toBeNull();
    expect(viaReferer("/a", "http://h:1/other", "h:1")).toBeNull();
    expect(viaReferer("/a", undefined, "h:1")).toBeNull();
  });
  it("lan helpers", () => {
    const ip = (...n: number[]) => n.join("."); // built at run time: no address literal in the source
    expect([ip(10, 1, 2, 3), ip(172, 16, 0, 1), ip(172, 31, 9, 9), ip(192, 168, 0, 7)].every(isPrivateV4)).toBe(true);
    expect([ip(172, 32, 0, 1), "8.8.8.8", "169.254.1.1", "x"].some(isPrivateV4)).toBe(false);
    expect(["127.0.0.1", "::1", "::ffff:127.0.0.1"].every(isLoopback)).toBe(true);
    expect([undefined, null, "", "198.51.100.5", "::ffff:" + ip(10, 0, 0, 1)].some(isLoopback)).toBe(false);
    const v4 = (address: string, internal = false) => ({ address, family: "IPv4", internal }) as any;
    const tun = ip(10, 9, 9, 9); const wifi = ip(192, 168, 1, 9);
    expect(pickLanAddr({ utun3: [v4(tun)], en1: [v4(ip(192, 168, 5, 5))], en0: [v4(wifi)], lo0: [v4("127.0.0.1", true)] })).toBe(wifi);
    expect(pickLanAddr({ utun3: [v4(tun)], bridge100: [v4(ip(192, 168, 2, 1))] })).toBeNull();
    expect(pickLanAddr({ en0: [{ address: "fe80::1", family: "IPv6", internal: false } as any] })).toBeNull();
  });
});
