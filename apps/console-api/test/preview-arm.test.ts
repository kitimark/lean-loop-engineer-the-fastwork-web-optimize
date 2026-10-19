// preview-proxy-direct: the arm origins. Each arm of a preview has its own port; the arm app (Lean `console.previewArm`
// through fwcore) maps the local port to that arm's private server, gated like the preview port. The goldens of the Lean
// verdicts are in packages/contracts (conformance test); here the I/O around them: real listeners, real sockets.
import { createServer, type Server } from "node:http";
import { afterEach, describe, expect, it } from "vitest";
import { armRig } from "./arm-rig.ts";
import { ArmServers } from "../src/preview/arm-servers.ts";
import { armHostOk } from "../src/preview/arm-app.ts";

const echo = (tag: string) => createServer((req, res) => {
  res.setHeader("content-type", "text/plain"); res.setHeader("set-cookie", "leak=1");
  res.end(`${tag} ${req.method} ${req.url} cookie=${req.headers.cookie ?? "-"} referer=${req.headers.referer ?? "-"}`);
});

let closers: Array<() => Promise<unknown>> = [];
afterEach(async () => { await Promise.all(closers.map((f) => f())); closers = []; });
const rig = async (opts: { lan?: boolean } = {}) => {
  const a = await armRig({ r: echo("R"), o: echo("O") }, opts);
  closers.push(() => a.close());
  return a;
};

describe("arm origins: routing (Lean Arm.route)", () => {
  it("each arm port reaches exactly its own server, the path unchanged (root-absolute module paths included), no redirect", async () => {
    const a = await rig();
    const path = "/_app/immutable/entry/start.X.js?v=1";
    const r = await a.raw(a.rp, path, { cookie: a.cookie });
    expect(r.status).toBe(200);
    expect(r.bytes.toString()).toBe(`R GET ${path} cookie=- referer=-`);
    const o = await a.raw(a.op, path, { cookie: a.cookie });
    expect(o.bytes.toString()).toBe(`O GET ${path} cookie=- referer=-`);
    expect(r.headers.location).toBeUndefined();
    expect(r.headers["set-cookie"]).toBeUndefined(); // the preview server cannot set a cookie on the console host
    expect(a.touched).toEqual(["p1", "p1"]);
  });

  it("a request carries nothing the page sent but Accept-Encoding and If-None-Match (no cookie, no Referer, no Host forwarded)", async () => {
    const a = await rig();
    const r = await a.raw(a.rp, "/x", { cookie: a.cookie, referer: `http://127.0.0.1:${a.op}/o`, "x-forwarded-for": "9.9.9.9" });
    expect(r.bytes.toString()).toBe("R GET /x cookie=- referer=-");
  });

  it("a Referer naming the other arm changes nothing: identity is the port, never inference", async () => {
    const a = await rig();
    const r = await a.raw(a.rp, "/same.png", { cookie: a.cookie, referer: `http://127.0.0.1:${a.op}/` });
    expect(r.bytes.toString().startsWith("R ")).toBe(true);
  });

  it("read-only: POST is 405 on both arms; after the preview stops the port answers 404", async () => {
    const a = await rig();
    expect((await a.raw(a.rp, "/x", { cookie: a.cookie }, "POST")).status).toBe(405);
    expect((await a.raw(a.op, "/x", { cookie: a.cookie }, "POST")).status).toBe(405);
    expect((await a.raw(a.rp, "/x", { cookie: a.cookie }, "HEAD")).status).toBe(200);
    a.stopServing();
    expect((await a.raw(a.rp, "/x", { cookie: a.cookie })).status).toBe(404);
  });

  it("a backend that is down is a 502, not a hang", async () => {
    const down = echo("R");
    const a = await armRig({ r: down, o: echo("O") });
    closers.push(() => a.close());
    await new Promise((r) => { down.close(() => r(null)); down.closeAllConnections(); });
    expect((await a.raw(a.rp, "/x", { cookie: a.cookie })).status).toBe(502);
    expect((await a.raw(a.op, "/x", { cookie: a.cookie })).status).toBe(200); // the other arm is unaffected
  });
});

describe("arm origins: the gate (Lean Arm.armServe = the preview port's gate for a preview path)", () => {
  it("no credential: 401 (json, or a page for a browser); an owner token is no preview access", async () => {
    const a = await rig();
    expect((await a.raw(a.rp, "/x")).status).toBe(401);
    const page = await a.raw(a.rp, "/x", { accept: "text/html" });
    expect(page.status).toBe(401); expect(page.headers["content-type"]).toContain("text/html");
    const token = a.owner.open();
    expect((await a.raw(a.rp, "/x", { cookie: `fw_owner=${token}` })).status).toBe(401);
    expect((await a.raw(a.rp, "/x", { authorization: `Bearer ${token}` })).status).toBe(401);
  });

  it("a live inspect grant cookie opens both arms; one that is unknown does not", async () => {
    const a = await rig();
    const issued = await a.grants.issue(false, null);
    if (!issued.ok) throw new Error("grant not issued");
    const redeemed = await a.grants.redeem(false, issued.token);
    if (!redeemed.ok) throw new Error("grant not redeemed");
    const ck = `fw_grant=${redeemed.cookie}`;
    expect((await a.raw(a.rp, "/x", { cookie: ck })).status).toBe(200);
    expect((await a.raw(a.op, "/x", { cookie: ck })).status).toBe(200);
    expect((await a.raw(a.rp, "/x", { cookie: "fw_grant=nope" })).status).toBe(401);
  });

  it("LAN mode: a request from loopback is judged as on the loopback listener (the Host rule applies to LAN peers; Lean arm_wrong_host)", async () => {
    const a = await rig({ lan: true });
    expect((await a.raw(a.rp, "/x", { cookie: a.cookie })).status).toBe(200);
    expect((await a.raw(a.rp, "/x")).status).toBe(401);
  });

  it("armHostOk: a loopback name or the LAN address, each with this arm's port, nothing else", () => {
    const lan = ["198", "51", "100", "9"].join(".");
    expect(armHostOk("127.0.0.1:5001", 5001, null)).toBe(true);
    expect(armHostOk("localhost:5001", 5001, null)).toBe(true);
    expect(armHostOk("127.0.0.1:5002", 5001, null)).toBe(false);
    expect(armHostOk("127.0.0.1", 5001, null)).toBe(false);
    expect(armHostOk(`${lan}:5001`, 5001, null)).toBe(false);
    expect(armHostOk(`${lan}:5001`, 5001, lan)).toBe(true);
    expect(armHostOk(`${lan}:5002`, 5001, lan)).toBe(false);
    expect(armHostOk("evil.example:5001", 5001, lan)).toBe(false);
    expect(armHostOk(undefined, 5001, lan)).toBe(false);
  });
});

describe("ArmServers (listeners of a preview's two arm ports)", () => {
  const free = (): Promise<number> => new Promise((res) => { const s: Server = createServer(); s.listen(0, "127.0.0.1", () => { const p = (s.address() as { port: number }).port; s.close(() => res(p)); }); });

  it("open listens on both ports; close frees them; a taken port fails the open and leaves nothing bound", async () => {
    const app = (r: Request) => new Response(`arm ${new URL(r.url).port}`);
    const arms = new ArmServers(app, null);
    const [rp, op] = [await free(), await free()];
    await arms.open({ id: "x", rp, op });
    expect(await (await fetch(`http://127.0.0.1:${rp}/`)).text()).toBe(`arm ${rp}`);
    expect(arms.open_ids).toEqual(["x"]);
    arms.close("x");
    await expect(fetch(`http://127.0.0.1:${op}/`)).rejects.toThrow();
    expect(arms.open_ids).toEqual([]);
    // a taken op port: the whole open fails and rp is released again
    const hold = createServer(); await new Promise<void>((r) => hold.listen(op, "127.0.0.1", () => r()));
    await expect(arms.open({ id: "y", rp, op })).rejects.toThrow(/could not be bound/);
    await new Promise((r) => hold.close(r));
    await expect(fetch(`http://127.0.0.1:${rp}/`)).rejects.toThrow();
    arms.close("nope"); // unknown id: no-op
  });
});
