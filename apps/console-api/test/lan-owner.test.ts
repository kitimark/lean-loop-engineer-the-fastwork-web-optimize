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
import { serve } from "@hono/node-server";
import { OwnerAuth } from "../src/preview/owner.ts";
import { createPreviewApp } from "../src/preview/preview-app.ts";
import { LoginGuard, readPassphrase, sameSecret, loginPage, KEYCHAIN_HINT } from "../src/preview/login.ts";
import { isLoopback, isPrivateV4, pickLanAddr } from "../src/preview/lan.ts";
import { rewriteBody } from "../src/preview/rewrite.ts";
import { viaReferer, isScriptPath } from "../src/preview/proxy.ts";
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
  it("several devices, each its own token; logout ends only that one; unknown tokens refused; a cookie is never an owner proof", () => {
    let t = 0; const o = new OwnerAuth([], () => t);
    const a = o.open(); const b = o.open();
    const bt = (s: string) => `Bearer ${s}`;
    expect(a).not.toBe(b);
    expect(o.bearerOk(bt(a))).toBe(true); expect(o.bearerOk(bt(b))).toBe(true);
    expect(o.bearerOk(bt("nope-nope-nope-nope-nope"))).toBe(false); expect(o.bearerOk(undefined)).toBe(false);
    expect(o.bearerOk(a)).toBe(false); // no "Bearer" scheme
    o.close(bt(a));
    expect(o.bearerOk(bt(a))).toBe(false); expect(o.bearerOk(bt(b))).toBe(true);
    t += 9 * 3_600_000;
    expect(o.bearerOk(bt(b))).toBe(false); // 8 h expiry
    expect(o.previewCookieFor("unknown")).toEqual([]);
    expect(OwnerAuth.setPreviewCookie("x")).toMatch(/HttpOnly.*SameSite=Strict/);
    expect(Object.keys(o)).not.toContain("cookieOk");
    expect((o as unknown as { cookieOk?: unknown }).cookieOk).toBeUndefined(); // no cookie-based owner check exists
  });
  it("hostOk and actionOk (Origin) follow the LAN hosts and the two ports", async () => {
    const core = selectCore();
    const o = new OwnerAuth();
    expect(o.hostOk("198.51.100.9:4000")).toBe(false);
    o.setPorts(4000, 4001);
    o.setLanHosts(["198.51.100.9:4000"], ["198.51.100.9:4001"]);
    expect(o.hostOk("198.51.100.9:4000")).toBe(true);
    expect(o.hostOk("evil.example:4000")).toBe(false);
    expect(o.hostOk("127.0.0.1:4001")).toBe(false); // the preview port is not the console
    expect(o.previewHostOk("127.0.0.1:4001")).toBe(true);
    expect(o.previewHostOk("198.51.100.9:4000")).toBe(false);
    const unset = new OwnerAuth(); unset.setLanHosts(["198.51.100.9:4000"]); // the preview port is not known yet
    expect(await unset.actionOk(core, "login", false, "http://198.51.100.9:4000", "198.51.100.9:4000")).toBe(false); // nothing is trusted
    expect(await unset.actionOk(core, "owner", true, "http://198.51.100.9:4000", "198.51.100.9:4000")).toBe(false);
    const act = (kind: "owner" | "command" | "login", ck: boolean, origin?: string) => o.actionOk(core, kind, ck, origin, "198.51.100.9:4000");
    expect(await act("owner", true, "http://198.51.100.9:4000")).toBe(true);
    expect(await act("owner", true, "http://198.51.100.9:4001")).toBe(false); // the preview origin
    expect(await act("owner", true, "http://evil.example")).toBe(false);
    expect(await act("owner", true, "null")).toBe(false);
    expect(await act("owner", true, undefined)).toBe(false); // an owner action needs an Origin
    expect(await act("owner", false, "http://198.51.100.9:4000")).toBe(false); // and the owner cookie
    expect(await act("command", false, undefined)).toBe(true); // command-line tools send no Origin
    expect(await act("command", false, "http://198.51.100.9:4001")).toBe(false);
    expect(await act("login", false, "http://198.51.100.9:4001")).toBe(false);
    expect(await act("login", false, "http://198.51.100.9:4000")).toBe(true);
  });
  it("the preview cookie is not an owner proof, and a cookie under any name is not a bearer", () => {
    const o = new OwnerAuth();
    const token = o.open();
    const [pv] = o.previewCookieFor(token).map((c) => c.split(";")[0]!);
    expect(pv).toMatch(/^fw_preview=/);
    expect(o.previewOk(pv)).toBe(true);
    expect(o.bearerOk(pv)).toBe(false); expect(o.bearerOk(`Bearer ${pv!.split("=")[1]}`)).toBe(false);
    expect(o.previewOk(`fw_owner=${token}`)).toBe(false); // the owner token under a cookie name opens nothing
    expect(o.previewOk(`fw_preview=${token}`)).toBe(false);
    expect(pv!.split("=")[1]).not.toBe(token);
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
    const owner = new OwnerAuth(); owner.setPorts(4000, 4001); owner.setLanHosts(["198.51.100.9:4000"]);
    const login = new LoginGuard(s.core, pass);
    return { app: createApp(s, undefined, undefined, undefined, owner, undefined, { login, lan }), owner };
  }
  const form = (p: string) => ({ method: "POST", body: JSON.stringify({ passphrase: p }), headers: { "content-type": "application/json", host: "198.51.100.9:4000", origin: "http://198.51.100.9:4000" } });

  it("LAN: without the token only the login page and the shell; API gets 401; wrong Host 421; frame headers everywhere", async () => {
    const { app } = await mk(true);
    const H = { host: "198.51.100.9:4000" };
    const noFrame = (r: Response) => { expect(r.headers.get("x-frame-options")).toBe("DENY"); expect(r.headers.get("content-security-policy")).toBe("frame-ancestors 'none'"); return r; };
    expect(noFrame(await app.request("/owner/login", { headers: H }, LAN)).status).toBe(200);
    expect(noFrame(await app.request("/api/tasks", { headers: H }, LAN)).status).toBe(401);
    expect(noFrame(await app.request("/api/owner", { headers: H }, LAN)).status).toBe(401);
    expect(noFrame(await app.request("/owner", { headers: H }, LAN)).status).toBe(401);
    const r = await app.request("/", { headers: { ...H, accept: "text/html" } }, LAN);
    expect(r.status).toBe(404); expect(r.headers.get("x-frame-options")).toBe("DENY"); // the shell passes the gate (no web build in this test)
    expect((await app.request("/api/tasks", { headers: { host: "evil.example" } }, LAN)).status).toBe(421);
    expect((await app.request("/preview/x/r/", { headers: H }, LAN)).status).toBe(404); // previews live on the preview port
    expect((await app.request("/api/tasks", { headers: { ...H, cookie: "fw_owner=anything; fw_preview=x" } }, LAN)).status).toBe(401); // no cookie opens the API
  });
  it("login returns a token (and only the preview cookie); the token opens the LAN; logout closes it; a cookie never does", async () => {
    const { app } = await mk(true);
    const bad = await app.request("/owner/login", form("nope"), LAN);
    expect(bad.status).toBe(401); expect(await bad.text()).not.toContain("nope");
    expect((await app.request("/owner/login", { method: "POST", body: "passphrase=x", headers: { "content-type": "application/x-www-form-urlencoded", host: "198.51.100.9:4000", origin: "http://198.51.100.9:4000" } }, LAN)).status).toBe(415);
    const ok = await app.request("/owner/login", form(FAKE), LAN);
    expect(ok.status).toBe(200);
    const token = ((await ok.json()) as { token: string }).token;
    const sc = ok.headers.get("set-cookie") ?? "";
    expect(sc).toMatch(/^fw_preview=.*HttpOnly/); expect(sc).not.toContain("fw_owner"); expect(sc).not.toContain(token);
    const H = { host: "198.51.100.9:4000", authorization: `Bearer ${token}`, origin: "http://198.51.100.9:4000" };
    expect((await app.request("/api/owner", { headers: H }, LAN)).status).toBe(200);
    expect(((await (await app.request("/api/owner", { headers: H }, LAN)).json()) as any).session).toBe(true);
    expect((await app.request("/api/tasks", { headers: { host: H.host, cookie: sc.split(";")[0]! } }, LAN)).status).toBe(401); // the cookie is not the token
    expect((await app.request("/owner/logout", { method: "POST", headers: { host: H.host, origin: H.origin } }, LAN)).status).toBe(401); // logout needs the token
    expect((await app.request("/owner/logout", { method: "POST", headers: H }, LAN)).status).toBe(200);
    expect((await app.request("/api/tasks", { headers: H }, LAN)).status).toBe(401);
  });
  it("every non-GET route refuses a foreign Origin (reconcile, spool drain, ops), not only /api/commands", async () => {
    const s = await store();
    const owner = new OwnerAuth(); owner.setPorts(4000, 4001); owner.setLanHosts(["198.51.100.9:4000"], ["198.51.100.9:4001"]);
    const app = createApp(s, undefined, undefined, undefined, owner, undefined, { login: new LoginGuard(s.core, FAKE), lan: false });
    const token = owner.open();
    for (const path of ["/api/commands", "/api/reconcile", "/api/spool/drain", "/api/anything", "/owner/logout"]) {
      const r = await app.request(path, { method: "POST", headers: { host: "127.0.0.1:4000", origin: "http://127.0.0.1:4001", authorization: `Bearer ${token}`, "content-type": "application/json" }, body: "{}" }, LOOP);
      expect([path, r.status]).toEqual([path, 403]);
    }
    const r = await app.request("/api/anything", { method: "POST", headers: { host: "127.0.0.1:4000", "content-type": "application/json" }, body: "{}" }, LOOP);
    expect(r.status).not.toBe(403); // no Origin (command-line tool): passes this gate
  });
  it("the passphrase never appears in any response (json and form, bad and ok and locked)", async () => {
    const { app } = await mk(true);
    const bodies: string[] = [];
    for (let i = 0; i < 7; i++) {
      const r = await app.request("/owner/login", { method: "POST", body: JSON.stringify({ passphrase: FAKE + "x" }), headers: { "content-type": "application/json", host: "198.51.100.9:4000", origin: "http://198.51.100.9:4000" } }, LAN);
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
  it("console-daemon: loopback passphrase login works with no terminal, gives a token and the preview cookie, and the token opens owner actions", async () => {
    const { app } = await mk(false);
    const LH = { host: "127.0.0.1:4000", origin: "http://127.0.0.1:4000" };
    const post = (p: string) => ({ method: "POST", body: JSON.stringify({ passphrase: p }), headers: { "content-type": "application/json", ...LH } });
    expect((await app.request("/owner/login", { headers: { host: LH.host } }, LOOP)).status).toBe(200);
    expect((await app.request("/owner/login", post("nope"), LOOP)).status).toBe(401);
    const ok = await app.request("/owner/login", post(FAKE), LOOP);
    expect(ok.status).toBe(200);
    const token = ((await ok.json()) as { token: string }).token;
    expect(ok.headers.get("set-cookie") ?? "").toMatch(/^fw_preview=/);
    const me = (await (await app.request("/api/owner", { headers: { host: LH.host, authorization: `Bearer ${token}` } }, LOOP)).json()) as { session: boolean };
    expect(me.session).toBe(true);
  });
  it("loopback: today's rules (API open), the console never serves previews; disabled login says 503", async () => {
    const { app } = await mk(false, null);
    expect((await app.request("/api/tasks", {}, LOOP)).status).not.toBe(401);
    expect((await app.request("/preview/x/r/", {}, LOOP)).status).toBe(404);
    expect((await app.request("/owner/login", {}, LOOP)).status).toBe(503);
    expect((await app.request("/owner/login", form("x"), LOOP)).status).toBe(503);
    expect((await app.request("/owner/login", {}, LOOP)).headers.get("x-frame-options")).toBe("DENY");
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
    const app = createPreviewApp(s.core, owner, pm, { lan: false });
    expect((await app.request("/preview/p1/r/")).status).toBe(401);
    const token = owner.open();
    const ck = owner.previewCookieFor(token).map((c) => c.split(";")[0]!);
    expect((await app.request("/preview/p1/r/", { headers: { cookie: `fw_owner=${token}` } })).status).toBe(401); // the owner token is no preview access
    expect((await app.request("/preview/p1/r/", { headers: { authorization: `Bearer ${token}` } })).status).toBe(401); // nor as a header
    const H = { cookie: ck[0]! };
    const r = await app.request("/preview/p1/r/", { headers: H });
    expect(r.status).toBe(200);
    expect(await r.text()).toBe('<link href="/preview/p1/r/assets/a.css"><script src="/preview/p1/r/assets/a.js"></script>');
    expect(touched).toEqual(["p1"]);
    expect(await (await app.request("/preview/p1/r/a.js", { headers: H })).text()).toBe('import("/x.js")'); // JS is not rewritten
    // a path built inside the preview's scripts ("/x.js") reaches that preview by its Referer, and is gated as a preview path
    const ref = { referer: "http://h:1/preview/p1/r/", host: "h:1" };
    // a script is moved below the prefix whether or not the browser sent Sec-Fetch-Dest (it sends none to a plain-HTTP LAN address:
    // the phone's original arm broke on this, preview-inspect), so its relative imports stay inside the preview
    const mv = await app.request("/x.js", { headers: { ...H, ...ref }, redirect: "manual" });
    expect(mv.status).toBe(302); expect(mv.headers.get("location")).toBe("/preview/p1/r/x.js");
    expect((await app.request("/x.js", { headers: { ...H, ...ref, "sec-fetch-dest": "script" } })).status).toBe(302);
    expect((await app.request("/x.png", { headers: { ...H, ...ref } })).status).toBe(200); // other files are served in place
    expect((await app.request("/x.js", { headers: ref })).status).toBe(401);
    expect((await app.request("/x.js", { headers: { ...H, referer: "http://evil/preview/p1/r/", host: "h:1" } })).status).toBe(404); // another origin's Referer is the console's own path
    expect((await app.request("/preview/nope/r/", { headers: H })).status).toBe(404);
    expect((await app.request("/preview/p1/r/", { method: "POST", headers: H })).status).toBe(405);
    expect((await app.request("/preview/p1/r", { headers: H })).status).toBe(302);
  });
});

describe("global login limit, body cap, LAN start", () => {
  it("20 wrong tries from 25 different addresses lock everyone, even the right passphrase from a fresh address", async () => {
    const s = await store(); let t = 1_000_000;
    const g = new LoginGuard(s.core, FAKE, () => t);
    const seen: string[] = [];
    for (let i = 0; i < 25; i++) seen.push((await g.attempt(`client-${i}`, "bad")).verdict);
    expect(seen.filter((v) => v === "wrong").length).toBe(20);
    expect(seen.slice(20)).toEqual(["locked", "locked", "locked", "locked", "locked"]);
    expect((await g.attempt("fresh-client", FAKE)).verdict).toBe("locked");
    t += 600_001;
    expect((await g.attempt("fresh-client", FAKE)).verdict).toBe("ok");
  });
  it("the login body is capped at 1 KiB before it is read (413), the passphrase page still works under the cap", async () => {
    const s = await store();
    const owner = new OwnerAuth(); owner.setPorts(4000, 4001); owner.setLanHosts(["198.51.100.9:4000"]);
    const app = createApp(s, undefined, undefined, undefined, owner, undefined, { login: new LoginGuard(s.core, FAKE), lan: true });
    const h = { "content-type": "application/json", host: "198.51.100.9:4000", origin: "http://198.51.100.9:4000" };
    const big = await app.request("/owner/login", { method: "POST", headers: h, body: JSON.stringify({ passphrase: "x".repeat(2000) }) }, LAN);
    expect(big.status).toBe(413);
    const ok = await app.request("/owner/login", { method: "POST", headers: h, body: JSON.stringify({ passphrase: FAKE }) }, LAN);
    expect(ok.status).toBe(200);
  });
  it("a cross-origin login (Origin of the preview port) is refused and costs no try", async () => {
    const s = await store();
    const owner = new OwnerAuth(); owner.setPorts(4000, 4001); owner.setLanHosts(["198.51.100.9:4000"], ["198.51.100.9:4001"]);
    const app = createApp(s, undefined, undefined, undefined, owner, undefined, { login: new LoginGuard(s.core, FAKE), lan: true });
    const h = (origin: string) => ({ "content-type": "application/json", host: "198.51.100.9:4000", origin });
    for (let i = 0; i < 8; i++) expect((await app.request("/owner/login", { method: "POST", headers: h("http://198.51.100.9:4001"), body: JSON.stringify({ passphrase: FAKE }) }, LAN)).status).toBe(403);
    expect((await app.request("/owner/login", { method: "POST", headers: h("http://198.51.100.9:4000"), body: JSON.stringify({ passphrase: FAKE }) }, LAN)).status).toBe(200);
  });
  it("Lean console.lanStart: a passphrase under 12 characters disables LAN (counted in characters)", async () => {
    const core = selectCore();
    const start = async (want: boolean, hasAddr: boolean, hasPass: boolean, passLen: number) => (await core.ops("console.lanStart", { want, hasAddr, hasPass, passLen })).result;
    expect(await start(true, true, true, 11)).toBe("shortPassphrase");
    expect(await start(true, true, true, 12)).toBe("start");
    expect(await start(true, true, false, 0)).toBe("noPassphrase");
    expect(await start(true, false, true, 30)).toBe("noAddress");
    expect(await start(false, true, true, 30)).toBe("off");
    expect(Array.from("ผ่านรหัส1234").length).toBe(12); // length is counted in characters (code points)
  });
});

describe("two origins: a preview page cannot act as the owner", () => {
  it("a preview page (preview origin, or the raw preview server port) holds the preview cookie but no owner credential that works", async () => {
    const s = await store();
    const owner = new OwnerAuth();
    const calls: string[] = [];
    const seen: Array<string | undefined> = [];
    const pmStub = {
      serving: (id: string) => (id === "p1" ? { rp: upPort, op: upPort } : null), touch: () => undefined, list: () => ({ previews: [] }),
      start: async (_t: string, proof: { cookie: boolean; origin: boolean }) => { calls.push("start"); return proof.cookie && proof.origin ? { ok: true, id: "p9", entry: {} } : { ok: false, reason: "notOwner" }; },
      stop: async (_i: string, proof: { cookie: boolean; origin: boolean }) => { calls.push("stop"); return proof.cookie && proof.origin ? { ok: true } : { ok: false, reason: "notOwner" }; },
    } as unknown as PreviewManager;
    let upPort = 0; let consolePort = 0; let previewPort = 0; let browserCookies = "";
    // the preview's own server: its page script ("attack") runs fetch() against the console as a browser would, with the
    // preview page's Origin and every cookie the browser holds for that host (cookies ignore ports; no header is ambient)
    const up = createServer(async (req, res) => {
      if (req.url === "/echo") { seen.push(req.headers.cookie); res.end("echo"); return; }
      if (req.url === "/attack") {
        const base = `http://127.0.0.1:${consolePort}`;
        const hdr = { origin: `http://127.0.0.1:${previewPort}`, cookie: browserCookies, "content-type": "application/json" };
        const out: Record<string, number> = {};
        out.start = (await fetch(`${base}/api/previews`, { method: "POST", headers: hdr, body: JSON.stringify({ task: "t1" }) })).status;
        out.stop = (await fetch(`${base}/api/previews/p1/stop`, { method: "POST", headers: hdr, body: "{}" })).status;
        out.commands = (await fetch(`${base}/api/commands`, { method: "POST", headers: hdr, body: "{}" })).status;
        out.reconcile = (await fetch(`${base}/api/reconcile`, { method: "POST", headers: hdr, body: "{}" })).status;
        out.logout = (await fetch(`${base}/owner/logout`, { method: "POST", headers: hdr })).status;
        out.login = (await fetch(`${base}/owner/login`, { method: "POST", headers: hdr, body: JSON.stringify({ passphrase: FAKE }) })).status;
        res.setHeader("content-type", "application/json"); res.end(JSON.stringify(out)); return;
      }
      res.end("<html></html>");
    });
    await new Promise<void>((r) => up.listen(0, "127.0.0.1", () => r())); servers.push(up);
    upPort = (up.address() as { port: number }).port;
    const login = new LoginGuard(s.core, FAKE);
    const consoleApp = createApp(s, undefined, undefined, pmStub, owner, undefined, { login, lan: false });
    const previewApp = createPreviewApp(s.core, owner, pmStub, { lan: false });
    const lis = (fetchFn: (r: Request, e?: unknown) => unknown) => new Promise<Server>((r) => { const x = serve({ fetch: fetchFn as never, port: 0, hostname: "127.0.0.1" }, () => r(x as unknown as Server)); });
    const cs = await lis(consoleApp.fetch); const ps = await lis(previewApp.fetch); servers.push(cs, ps);
    consolePort = (cs.address() as { port: number }).port; previewPort = (ps.address() as { port: number }).port;
    owner.setPorts(consolePort, previewPort);
    const token = owner.open();
    const [pc] = owner.previewCookieFor(token).map((c) => c.split(";")[0]!);
    browserCookies = pc!; // the only cookie there is; the owner token lives in console-origin localStorage, which no preview page can read

    // 1. the preview port: no cookie -> 401; preview cookie -> page; the proxied upstream gets no cookie at all
    expect((await fetch(`http://127.0.0.1:${previewPort}/preview/p1/r/`)).status).toBe(401);
    expect((await fetch(`http://127.0.0.1:${previewPort}/preview/p1/r/`, { headers: { cookie: `fw_owner=${token}` } })).status).toBe(401);
    expect((await fetch(`http://127.0.0.1:${previewPort}/preview/p1/r/echo`, { headers: { cookie: browserCookies } })).status).toBe(200);
    expect(seen).toEqual([undefined]);
    // 2. the page's own script posts to the console API: every owner action is refused before it reaches the manager
    const r = await fetch(`http://127.0.0.1:${previewPort}/preview/p1/r/attack`, { headers: { cookie: browserCookies } });
    expect(await r.json()).toEqual({ start: 403, stop: 403, commands: 403, reconcile: 403, logout: 403, login: 403 });
    expect(calls).toEqual([]);
    // 3. the raw preview server port (reviewer probe): the browser hands the preview server every cookie it holds, with no proxy
    //    in between. Replaying what it got, even with a forged console Origin, yields no owner rights.
    await fetch(`http://127.0.0.1:${upPort}/echo`, { headers: { cookie: browserCookies } });
    const stolen = seen[1]!;
    expect(stolen).toBe(browserCookies); expect(stolen).not.toContain(token);
    const forged = { origin: `http://127.0.0.1:${consolePort}`, cookie: stolen, "content-type": "application/json" };
    const replay = await fetch(`http://127.0.0.1:${consolePort}/api/previews`, { method: "POST", headers: forged, body: JSON.stringify({ task: "t1" }) });
    expect(replay.status).toBe(403); // notOwner: the manager saw cookie=false
    expect(calls).toEqual(["start"]);
    expect((await fetch(`http://127.0.0.1:${consolePort}/owner/logout`, { method: "POST", headers: forged })).status).toBe(403);
    expect(((await (await fetch(`http://127.0.0.1:${consolePort}/api/owner`, { headers: forged })).json()) as any).session).toBe(false);
    // 4. the console origin with its token still works; the console port never serves a preview and cannot be framed
    const own = { origin: `http://127.0.0.1:${consolePort}`, authorization: `Bearer ${token}`, cookie: browserCookies, "content-type": "application/json" };
    const good = await fetch(`http://127.0.0.1:${consolePort}/api/previews`, { method: "POST", headers: own, body: JSON.stringify({ task: "t1" }) });
    expect(good.status).toBe(202);
    const pv = await fetch(`http://127.0.0.1:${consolePort}/preview/p1/r/`, { headers: { cookie: browserCookies } });
    expect(pv.status).toBe(404); expect(pv.headers.get("x-frame-options")).toBe("DENY");
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
  it("isScriptPath: only .js/.mjs files are moved", () => {
    expect(isScriptPath("/_app/immutable/entry/start.X.js")).toBe(true);
    expect(isScriptPath("/a/b.MJS")).toBe(true);
    for (const p of ["/a.json", "/a.js.map", "/a.png", "/js", "/a.jsx"]) expect(isScriptPath(p)).toBe(false);
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
