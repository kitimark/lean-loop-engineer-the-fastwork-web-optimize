// preview-login-return: an unauthenticated HTML request to a preview origin is sent to the console login with a return
// reference, and after the login lands on the exact same link. The decisions are Lean `console.loginReturn` (fwcore);
// this file drives real listeners (the local port is read from the socket) and checks the HTTP behaviour.
import { mkdtempSync } from "node:fs";
import { request, type IncomingHttpHeaders, type Server } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { serve } from "@hono/node-server";
import { createApp } from "../src/app.ts";
import { selectCore } from "../src/core/index.ts";
import { Store } from "../src/store.ts";
import { OwnerAuth } from "../src/preview/owner.ts";
import { LoginGuard } from "../src/preview/login.ts";
import { createPreviewApp } from "../src/preview/preview-app.ts";
import { createArmApp } from "../src/preview/arm-app.ts";
import { Grants } from "../src/preview/grants.ts";
import { ReturnStore } from "../src/preview/return.ts";
import type { PreviewManager } from "../src/preview/manager.ts";

const FAKE = "fake-pass-for-tests-only";
const LINK = "/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped";
const HTML = { accept: "text/html" };

type Raw = { status: number; headers: IncomingHttpHeaders; text: string };
const raw = (port: number, path: string, headers: Record<string, string> = {}, method = "GET", body?: string) => new Promise<Raw>((resolve, reject) => {
  const req = request({ host: "127.0.0.1", port, path, headers, method }, (res) => {
    const cs: Buffer[] = [];
    res.on("data", (c) => cs.push(c));
    res.on("end", () => resolve({ status: res.statusCode!, headers: res.headers, text: Buffer.concat(cs).toString() }));
  });
  req.on("error", reject);
  req.end(body);
});

let stores: Store[] = [];
let servers: Server[] = [];
afterEach(async () => {
  stores.forEach((s) => s.close()); stores = [];
  await Promise.all(servers.map((s) => new Promise((r) => { s.close(() => r(null)); s.closeAllConnections?.(); }))); servers = [];
});

type Rig = Awaited<ReturnType<typeof rig>>;
async function rig() {
  const core = selectCore();
  const s = await Store.open(join(mkdtempSync(join(tmpdir(), "fw-lr-")), ".fw-console"), core);
  stores.push(s);
  const owner = new OwnerAuth();
  let table: Array<{ id: string; task: string; rp: number; op: number; started: number }> = [];
  const pm = {
    serving: (id: string) => (table.some((e) => e.id === id) ? { id, brp: 1, bop: 1, phase: "serving" } : null),
    touch: () => undefined, liveTable: () => table, list: () => ({ previews: [] }),
  } as unknown as PreviewManager;
  const returns = new ReturnStore(core, owner, () => table);
  const grants = new Grants(core, () => undefined);
  const lis = (fetchFn: (r: Request, e?: unknown) => unknown) => new Promise<Server>((r) => { const x = serve({ fetch: fetchFn as never, port: 0, hostname: "127.0.0.1" }, () => r(x as unknown as Server)); });
  const consoleApp = createApp(s, undefined, undefined, pm, owner, undefined, { login: new LoginGuard(core, FAKE), lan: false, returns });
  const previewApp = createPreviewApp(core, owner, pm, { lan: false, grants, returns });
  const armApp = createArmApp(core, owner, pm, { lan: false, grants, returns });
  const cs = await lis(consoleApp.fetch); const ps = await lis(previewApp.fetch); const a1 = await lis(armApp.fetch); const a2 = await lis(armApp.fetch);
  servers.push(cs, ps, a1, a2);
  const port = (x: Server) => (x.address() as { port: number }).port;
  const ports = { console: port(cs), preview: port(ps), rp: port(a1), op: port(a2) };
  owner.setPorts(ports.console, ports.preview);
  table = [{ id: "p1", task: "t", rp: ports.rp, op: ports.op, started: 0 }];
  const origin = `http://127.0.0.1:${ports.console}`;
  const login = (r?: string) => raw(ports.console, "/owner/login", { "content-type": "application/json", origin, host: `127.0.0.1:${ports.console}` }, "POST",
    JSON.stringify({ passphrase: FAKE, ...(r === undefined ? {} : { r }) }));
  return { ports, owner, returns, stop: () => { table = []; }, login, origin };
}
const nonceOf = (loc: string) => new URL(loc).searchParams.get("r");

describe("preview-login-return", () => {
  let t: Rig;
  beforeEach(async () => { t = await rig(); });

  it("a full round trip: arm link -> login with a nonce -> the exact same link, with the preview cookie set", async () => {
    const first = await raw(t.ports.rp, LINK, HTML);
    expect(first.status).toBe(303);
    const loc = first.headers.location!;
    expect(loc.startsWith(`http://127.0.0.1:${t.ports.console}/owner/login?r=`)).toBe(true);
    expect(loc).not.toContain("preset"); // only the nonce travels
    const page = await raw(t.ports.console, new URL(loc).pathname + new URL(loc).search, HTML);
    expect(page.text).toContain(`data-r="${nonceOf(loc)}"`);
    const ok = await t.login(nonceOf(loc)!);
    const j = JSON.parse(ok.text) as { ok: boolean; token: string; next: string };
    expect(ok.status).toBe(200);
    expect(j.next).toBe(`http://127.0.0.1:${t.ports.rp}${LINK}`);
    const cookie = (ok.headers["set-cookie"] ?? []).map((c) => c.split(";")[0]!).join("; ");
    const arrived = await raw(t.ports.rp, LINK, { ...HTML, cookie });
    expect([401, 303]).not.toContain(arrived.status); // the gate lets the owner through (no backend runs here: 502)
    // the reference is single-use
    const again = JSON.parse((await t.login(nonceOf(loc)!)).text) as { next: string };
    expect(again.next).toBe("/");
  });

  it("the original arm and a live preview path on the preview port are returned to as well", async () => {
    const o = await raw(t.ports.op, "/selling/x?v=1", HTML);
    expect(nonceOf(o.headers.location!)).not.toBeNull();
    const p = await raw(t.ports.preview, "/preview/p1/compare?x=1", HTML);
    const n = nonceOf(p.headers.location!)!;
    expect((JSON.parse((await t.login(n)).text) as { next: string }).next).toBe(`http://127.0.0.1:${t.ports.preview}/preview/p1/compare?x=1`);
  });

  it("an API request keeps its 401 and gets no redirect", async () => {
    const r = await raw(t.ports.rp, LINK, { accept: "application/json" });
    expect(r.status).toBe(401); expect(r.headers.location).toBeUndefined();
    const p = await raw(t.ports.preview, "/preview/p1/compare", { accept: "application/json" });
    expect(p.status).toBe(401); expect(p.headers.location).toBeUndefined();
    expect((await raw(t.ports.rp, LINK, { ...HTML }, "POST")).headers.location).toBeUndefined(); // not a GET: no page request
  });

  it("HEAD keeps 401 with no Location and holds no reference; a full store logs in plain (Lean decides)", async () => {
    for (const port of [t.ports.rp, t.ports.preview]) {
      const path = port === t.ports.rp ? LINK : "/preview/p1/compare";
      const h = await raw(port, path, { ...HTML }, "HEAD");
      expect(h.status).toBe(401); expect(h.headers.location).toBeUndefined();
    }
    expect(t.returns.size).toBe(0);
    for (let i = 0; i < 256; i++) await raw(t.ports.rp, LINK, HTML);
    expect(t.returns.size).toBe(256);
    const full = await raw(t.ports.rp, LINK, HTML);
    expect(full.status).toBe(303);
    expect(full.headers.location).toBe(`http://127.0.0.1:${t.ports.console}/owner/login`);
    expect(t.returns.size).toBe(256);
  });

  it("links outside the allowlist go to the login without a return reference", async () => {
    for (const path of ["/%0d%0aSet-Cookie:a=1", "/a%0D%0Ab", "/" + "a".repeat(2100)]) {
      const r = await raw(t.ports.rp, path, HTML);
      if (r.status === 303) expect(r.headers.location).toBe(`http://127.0.0.1:${t.ports.console}/owner/login`);
      else expect(r.status).toBeGreaterThanOrEqual(400); // refused by the server before the app
    }
    // the server reads a `//host/path` request target as host evil.example and path /x: the held link is that path, on this arm
    const rel = await raw(t.ports.rp, "//evil.example/x", HTML);
    const n = nonceOf(rel.headers.location!);
    const next = n ? (JSON.parse((await t.login(n)).text) as { next: string }).next : `http://127.0.0.1:${t.ports.rp}/x`;
    expect(next).toBe(`http://127.0.0.1:${t.ports.rp}/x`);
    const stopped = await raw(t.ports.preview, "/preview/zz/compare", HTML); // a preview that is not live
    expect(stopped.headers.location).toBe(`http://127.0.0.1:${t.ports.console}/owner/login`);
    const other = await raw(t.ports.preview, "/anything", HTML); // the preview port without a preview path
    expect(other.headers.location).toBe(`http://127.0.0.1:${t.ports.console}/owner/login`);
  });

  it("a foreign Host or userinfo in Host gets no redirect (and so no Location built from it)", async () => {
    for (const host of ["evil.example", `evil.example:${t.ports.rp}`, `evil@127.0.0.1:${t.ports.rp}`, `127.0.0.1:${t.ports.op}`]) {
      const r = await raw(t.ports.rp, LINK, { ...HTML, host });
      expect([400, 401]).toContain(r.status); expect(r.headers.location).toBeUndefined();
    }
  });

  it("direct decisions: javascript:, other port, console port, userinfo host", async () => {
    const f = (o: Partial<{ method: string; host: string; port: number; pathq: string }>) =>
      t.returns.redirectFor({ method: "GET", html: true, host: `127.0.0.1:${t.ports.rp}`, port: t.ports.rp, pathq: LINK, ...o });
    const plain = `http://127.0.0.1:${t.ports.console}/owner/login`;
    expect(await f({ pathq: "javascript:alert(1)" })).toBe(plain);
    expect(await f({ pathq: "\\\\evil.example" })).toBe(plain);
    expect(await f({ port: t.ports.rp + 7 })).toBe(plain);
    expect(await f({ port: t.ports.console })).toBe(plain);
    expect(await f({ host: "evil@127.0.0.1:1" })).toBeNull();
    expect(await f({ host: "evil.example" })).toBeNull(); // well formed, but not one of the console's hosts (Lean)
    expect(await f({ method: "HEAD" })).toBeNull();
    expect(await f({ host: undefined })).toBeNull();
    expect(await f({ port: undefined })).toBeNull();
    expect((await f({}))!.startsWith(`${plain}?r=`)).toBe(true);
  });

  it("a forged, unknown, malformed or missing nonce lands on the console home", async () => {
    for (const r of ["A".repeat(24), "../../etc", "x", "a b", ""]) {
      expect((JSON.parse((await t.login(r)).text) as { next: string }).next).toBe("/");
    }
    expect((JSON.parse((await t.login()).text) as { next: string }).next).toBe("/");
  });

  it("a preview that stopped between the request and the login lands on the Builds tab with the note", async () => {
    const first = await raw(t.ports.rp, LINK, HTML);
    t.stop();
    const j = JSON.parse((await t.login(nonceOf(first.headers.location!)!)).text) as { next: string };
    expect(j.next).toBe("/?tab=builds&note=stopped");
  });

  it("a wrong passphrase keeps the reference for the next try; the login page ignores a malformed r", async () => {
    const first = await raw(t.ports.rp, LINK, HTML);
    const n = nonceOf(first.headers.location!)!;
    const bad = await raw(t.ports.console, "/owner/login", { "content-type": "application/json", origin: t.origin, host: `127.0.0.1:${t.ports.console}` }, "POST",
      JSON.stringify({ passphrase: "nope", r: n }));
    expect(bad.status).toBe(401);
    expect((JSON.parse((await t.login(n)).text) as { next: string }).next).toBe(`http://127.0.0.1:${t.ports.rp}${LINK}`);
    const page = await raw(t.ports.console, `/owner/login?r=${encodeURIComponent('"><script>x</script>')}`, HTML);
    expect(page.text).not.toContain("data-r");
  });

  it("a login from a console Host that is not ours returns home", async () => {
    const first = await raw(t.ports.rp, LINK, HTML);
    const r = await t.returns.landing(nonceOf(first.headers.location!), "evil.example");
    expect(r).toBe("/");
  });
});
