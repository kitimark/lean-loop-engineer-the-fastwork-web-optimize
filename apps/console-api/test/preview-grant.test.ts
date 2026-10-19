// preview-inspect: the loopback-only inspect grant. The decisions are Lean `console.previewGrant` and `console.ownerGate` (goldens in
// packages/contracts/golden/console); this checks the glue: the tables, the cookie, the audit lines and the two ports.
import { mkdtempSync } from "node:fs";
import { createServer, type Server } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createApp } from "../src/app.ts";
import { selectCore } from "../src/core/index.ts";
import { Store } from "../src/store.ts";
import { OwnerAuth } from "../src/preview/owner.ts";
import { Grants } from "../src/preview/grants.ts";
import { LoginGuard } from "../src/preview/login.ts";
import { createPreviewApp } from "../src/preview/preview-app.ts";
import type { PreviewManager } from "../src/preview/manager.ts";

const LAN = { incoming: { socket: { remoteAddress: "198.51.100.50" } } };
const LOOP = { incoming: { socket: { remoteAddress: "127.0.0.1" } } };
const JSON_H = { "content-type": "application/json", host: "127.0.0.1:4000" };
const LANHOST = "198.51.100.9:4001";

let stores: Store[] = [];
let servers: Server[] = [];
afterEach(async () => {
  stores.forEach((s) => s.close()); stores = [];
  await Promise.all(servers.map((s) => new Promise((r) => s.close(() => r(null))))); servers = [];
});

async function rig(lan: boolean) {
  const s = await Store.open(join(mkdtempSync(join(tmpdir(), "fw-pg-")), ".fw-console"), selectCore());
  stores.push(s);
  const up = createServer((req, res) => { res.setHeader("content-type", req.url?.endsWith(".js") ? "application/javascript" : "text/plain"); res.end(`up:${req.url}`); });
  await new Promise<void>((r) => up.listen(0, "127.0.0.1", () => r())); servers.push(up);
  const port = (up.address() as { port: number }).port;
  const pm = { serving: (id: string) => (id === "p1" ? { rp: port, op: port } : null), touch: () => undefined } as unknown as PreviewManager;
  const owner = new OwnerAuth(); owner.setPorts(4000, 4001);
  if (lan) owner.setLanHosts(["198.51.100.9:4000"], [LANHOST]);
  let t = 1_000_000;
  const audit: Record<string, unknown>[] = [];
  const grants = new Grants(s.core, (r) => audit.push(r), () => t);
  const app = createApp(s, undefined, undefined, pm, owner, undefined, { login: new LoginGuard(s.core, null), lan, grants });
  const pv = createPreviewApp(s.core, owner, pm, { lan, grants });
  const issue = async (body: unknown, env: object = LOOP) =>
    app.request("/api/preview/grant", { method: "POST", headers: JSON_H, body: JSON.stringify(body) }, env);
  const urlOf = async (body: unknown) => { const j = (await (await issue(body)).json()) as { url: string }; return new URL(j.url); };
  return { app, pv, owner, grants, audit, issue, urlOf, advance: (ms: number) => { t += ms; } };
}

describe("inspect grant", () => {
  it("issue: loopback only, a running preview only, a console Origin only", async () => {
    const r = await rig(true);
    expect((await r.issue({}, LAN)).status).toBe(401); // the console gate refuses a LAN request without the owner token
    const { app } = r;
    const lanOwner = r.owner.open();
    const viaLan = await app.request("/api/preview/grant", { method: "POST", headers: { "content-type": "application/json", host: "198.51.100.9:4000", authorization: `Bearer ${lanOwner}`, origin: "http://198.51.100.9:4000" }, body: "{}" }, LAN);
    expect(viaLan.status).toBe(403); // even the owner's own LAN device gets none: Lean issue_requires_loopback
    expect((await r.issue({ id: "nope" })).status).toBe(404);
    expect((await r.issue({ id: "BAD ID" })).status).toBe(400);
    const foreign = await app.request("/api/preview/grant", { method: "POST", headers: { ...JSON_H, origin: "http://127.0.0.1:4001" }, body: "{}" }, LOOP);
    expect(foreign.status).toBe(403); // a preview page may not ask
    const ok = await r.issue({ id: "p1" });
    expect(ok.status).toBe(200);
    const j = (await ok.json()) as { url: string; expiresInSec: number };
    expect(j.url).toMatch(/^http:\/\/127\.0\.0\.1:4001\/__grant\?t=[A-Za-z0-9_-]{40,}$/); expect(j.expiresInSec).toBe(600);
  });

  it("redeem: once, within ten minutes, from loopback; the cookie opens previews and nothing else", async () => {
    const r = await rig(true);
    const u = await r.urlOf({ id: "p1", arm: "o" });
    const first = await r.pv.request(u.pathname + u.search, { headers: { host: "127.0.0.1:4001" }, redirect: "manual" }, LOOP);
    expect(first.status).toBe(302); expect(first.headers.get("location")).toBe("/preview/p1/o/");
    const sc = first.headers.get("set-cookie") ?? "";
    expect(sc).toMatch(/^fw_grant=[A-Za-z0-9_-]+; HttpOnly; SameSite=Strict; Path=\/; Max-Age=3600$/);
    const ck = sc.split(";")[0]!;
    const again = await r.pv.request(u.pathname + u.search, { headers: { host: "127.0.0.1:4001" } }, LOOP);
    expect(again.status).toBe(403); // single use
    const H = { host: "127.0.0.1:4001", cookie: ck };
    expect((await r.pv.request("/preview/p1/o/", { headers: H }, LOOP)).status).toBe(200);
    expect((await r.pv.request("/preview/p1/o/", { headers: { host: "127.0.0.1:4001" } }, LOOP)).status).toBe(401);
    // a root-absolute path read below the preview by its Referer (the phone's script requests)
    const ref = { ...H, referer: "http://127.0.0.1:4001/preview/p1/o/" };
    expect((await r.pv.request("/_app/x.png", { headers: ref }, LOOP)).status).toBe(200);
    expect((await r.pv.request("/_app/x.png", { headers: H }, LOOP)).status).toBe(401); // no Referer: a shell path
    for (const p of ["/api/tasks", "/owner/logout", "/owner/login"]) expect([p, (await r.pv.request(p, { headers: ref }, LOOP)).status]).toEqual([p, 401]);
    // the console port ignores it
    const lanH = { host: "198.51.100.9:4000", cookie: ck };
    expect((await r.app.request("/api/tasks", { headers: lanH }, LAN)).status).toBe(401);
    expect((await r.app.request("/api/owner", { headers: lanH }, LAN)).status).toBe(401);
    expect(r.owner.bearerOk(`Bearer ${ck.split("=")[1]}`)).toBe(false);
    expect(r.owner.previewOk(ck)).toBe(false);
  });

  it("expiry: the link after ten minutes, the cookie after sixty", async () => {
    const r = await rig(false);
    const late = await r.urlOf({});
    r.advance(600_000);
    expect((await r.pv.request(late.pathname + late.search, { headers: { host: "127.0.0.1:4001" } }, LOOP)).status).toBe(403);
    const u = await r.urlOf({ id: "p1" });
    const res = await r.pv.request(u.pathname + u.search, { headers: { host: "127.0.0.1:4001" }, redirect: "manual" }, LOOP);
    const ck = (res.headers.get("set-cookie") ?? "").split(";")[0]!;
    const H = { host: "127.0.0.1:4001", cookie: ck };
    r.advance(3_599_000);
    expect((await r.pv.request("/preview/p1/r/", { headers: H }, LOOP)).status).toBe(200);
    r.advance(1_000);
    expect((await r.pv.request("/preview/p1/r/", { headers: H }, LOOP)).status).toBe(401);
  });

  it("redeem from a LAN address is refused; a granted cookie still works through the LAN host (the phone's path)", async () => {
    const r = await rig(true);
    const u = await r.urlOf({});
    const viaLan = await r.pv.request(u.pathname + u.search, { headers: { host: LANHOST } }, LAN);
    expect(viaLan.status).toBe(403);
    const burnt = await r.pv.request(u.pathname + u.search, { headers: { host: "127.0.0.1:4001" } }, LOOP);
    expect(burnt.status).toBe(403); // a refused token stays consumed (claimed before the Lean call): ask for a new link
    const u2 = await r.urlOf({});
    const again = await r.pv.request(u2.pathname + u2.search, { headers: { host: "127.0.0.1:4001" }, redirect: "manual" }, LOOP);
    expect(again.status).toBe(200);
    const ck = (again.headers.get("set-cookie") ?? "").split(";")[0]!;
    expect((await r.pv.request("/preview/p1/o/", { headers: { host: LANHOST, cookie: ck } }, LAN)).status).toBe(200);
    expect((await r.pv.request("/preview/p1/o/", { headers: { host: "evil.example", cookie: ck } }, LAN)).status).toBe(421);
    expect((await r.pv.request("/__grant?t=x", { headers: { host: "evil.example" } }, LAN)).status).toBe(421);
  });

  it("concurrent double redeem of one token: exactly one success, one 403 used", async () => {
    const r = await rig(false);
    const u = await r.urlOf({ id: "p1" });
    const tokPath = "/__grant?t=" + u.searchParams.get("t")!;
    const res = await Promise.all([r.pv.request(tokPath, { headers: { host: "127.0.0.1:4001" }, redirect: "manual" }, LOOP), r.pv.request(tokPath, { headers: { host: "127.0.0.1:4001" }, redirect: "manual" }, LOOP)]);
    expect(res.map((x) => x.status).sort()).toEqual([302, 403]);
    const bad = res.find((x) => x.status === 403)!;
    expect(await bad.text()).toMatch(/used/);
    expect(r.audit.filter((a) => a.ev === "grant.redeem")).toHaveLength(1);
  });

  it("audit lines name the grant, never a token or a cookie value", async () => {
    const r = await rig(false);
    const j = (await (await r.issue({ id: "p1" })).json()) as { url: string };
    const token = new URL(j.url).searchParams.get("t")!;
    const res = await r.pv.request(new URL(j.url).pathname + new URL(j.url).search, { headers: { host: "127.0.0.1:4001" }, redirect: "manual" }, LOOP);
    const ck = (res.headers.get("set-cookie") ?? "").split(";")[0]!;
    await r.pv.request("/preview/p1/r/", { headers: { host: "127.0.0.1:4001", cookie: ck } }, LOOP);
    await r.pv.request(new URL(j.url).pathname + new URL(j.url).search, { headers: { host: "127.0.0.1:4001" } }, LOOP);
    expect(r.audit.map((a) => a.ev)).toEqual(["grant.issue", "grant.redeem", "grant.use", "grant.refused"]);
    const text = JSON.stringify(r.audit);
    expect(text).not.toContain(token); expect(text).not.toContain(ck.split("=")[1]!);
  });
});
