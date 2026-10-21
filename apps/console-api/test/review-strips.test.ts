// review-strips-console: the strips of a look-change review. Which strips exist, their state and the allowlist are Lean
// (`Fw.Console.ReviewStrips`, through `console.review`); these tests check the route glue with a stubbed downloader.
import { existsSync, mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createApp } from "../src/app.ts";
import { selectCore } from "../src/core/index.ts";
import { Store } from "../src/store.ts";
import { OwnerAuth } from "../src/preview/owner.ts";
import { LoginGuard } from "../src/preview/login.ts";
import type { Downloader } from "../src/review/routes.ts";

const FLAG = "nav:earn-no-transition";
const url = (f: string) => `/api/reviews/${encodeURIComponent(FLAG)}/strips/${f}`;
const PNG = Buffer.from("89504e470d0a1a0a", "hex");
let stores: Store[] = [];
afterEach(() => { stores.forEach((s) => s.close()); stores = []; });

async function rig(download: Downloader, today = "2026-10-21") {
  const root = mkdtempSync(join(tmpdir(), "fw-strips-"));
  mkdirSync(join(root, "research/findings"), { recursive: true });
  const dir = join(root, ".fw-console");
  const store = await Store.open(dir, selectCore(), () => 1_700_000_000_000);
  stores.push(store);
  return { dir, store, app: createApp(store, undefined, undefined, undefined, undefined, undefined, undefined, root, { download, today: () => today }) };
}
/** A downloader that writes the chromium strip into the directory it is given, and counts its calls. */
function stub() {
  const calls: string[] = [];
  const download: Downloader = async (run, artifact, dir) => {
    calls.push(`${run}/${artifact}`);
    await new Promise((r) => setTimeout(r, 20));
    mkdirSync(join(dir, "strips"), { recursive: true });
    writeFileSync(join(dir, "strips/chromium-390-open.png"), PNG);
  };
  return { calls, download };
}

describe("GET /api/reviews strips", () => {
  it("lists the 8 strips: 4 chromium ready with the gen.mjs notes, 4 webkit with an empty note; run and expiry are the material's", async () => {
    const { app } = await rig(stub().download);
    const i = ((await (await app.request("/api/reviews")).json()) as any).items[0];
    expect(i.strips).toHaveLength(8);
    expect(i.strips.every((s: any) => s.state === "ready")).toBe(true);
    const ch = i.strips.filter((s: any) => s.engine === "chromium"), wk = i.strips.filter((s: any) => s.engine === "webkit");
    expect([ch.length, wk.length]).toEqual([4, 4]);
    expect(ch.every((s: any) => s.run === i.material.chromium.run && s.expires === i.material.chromium.expires && s.note !== "")).toBe(true);
    expect(wk.every((s: any) => s.run === i.material.webkit.run && s.expires === i.material.webkit.expires && s.note === "")).toBe(true);
    const close390 = ch.find((s: any) => s.width === 390 && s.push === "close");
    expect(close390).toMatchObject({ file: "chromium-390-close.png", run: "39473950464", artifact: "frames-chromium", diff: "about 0.4 s earlier" });
    expect(close390.note).toContain("Join waitlist");
    expect(wk.find((s: any) => s.width === 1280 && s.push === "close")).toMatchObject({ file: "playwright-webkit-1280-close.png", run: "39530106935", artifact: "frames-apple-1280", expires: "2026-11-20" });
  });
  it("on 2026-11-19 chromium is expired (with the redo line) and webkit still ready", async () => {
    const { app } = await rig(stub().download, "2026-11-19");
    const i = ((await (await app.request("/api/reviews")).json()) as any).items[0];
    const ch = i.strips.filter((s: any) => s.engine === "chromium"), wk = i.strips.filter((s: any) => s.engine === "webkit");
    expect(ch.every((s: any) => s.state === "expired" && s.redo === `[ci:trajectory-probe] [frames:${FLAG}]`)).toBe(true);
    expect(wk.every((s: any) => s.state === "ready")).toBe(true);
  });
  it("on 2026-11-20 all 8 strips are expired", async () => {
    const { app } = await rig(stub().download, "2026-11-20");
    const i = ((await (await app.request("/api/reviews")).json()) as any).items[0];
    expect(i.strips).toHaveLength(8);
    expect(i.strips.every((s: any) => s.state === "expired")).toBe(true);
  });
});

describe("GET /api/reviews/<flag>/strips/<file>", () => {
  it("serves an allowlisted file; a second request is a cache hit with no second download", async () => {
    const s = stub();
    const { app, dir } = await rig(s.download);
    const a = await app.request(url("chromium-390-open.png"));
    expect(a.status).toBe(200);
    expect(a.headers.get("content-type")).toBe("image/png");
    expect(Buffer.from(await a.arrayBuffer())).toEqual(PNG);
    const b = await app.request(url("chromium-390-open.png"));
    expect(b.status).toBe(200);
    expect(s.calls).toEqual(["39473950464/frames-chromium"]);
    expect(existsSync(join(dir, "review-cache/39473950464/frames-chromium/strips/chromium-390-open.png"))).toBe(true);
  });
  it("at most one download in flight per artifact", async () => {
    const s = stub();
    const { app } = await rig(s.download);
    const rs = await Promise.all([1, 2, 3].map(() => app.request(url("chromium-390-open.png"))));
    expect(rs.map((r) => r.status)).toEqual([200, 200, 200]);
    expect(s.calls).toHaveLength(1);
  });
  it("refuses every name that is no row file, with no download", async () => {
    const s = stub();
    const { app } = await rig(s.download);
    for (const f of ["..%2F..%2Fevents.jsonl", "..", "%2e%2e%2fx.png", "strips%2Fchromium-390-open.png", "other.png", "chromium-390-open.PNG", "playwright-webkit-390-open-screencast.png"]) {
      expect((await app.request(url(f))).status).toBe(404);
    }
    expect((await app.request(`/api/reviews/nav:other/strips/chromium-390-open.png`)).status).toBe(404);
    expect((await app.request(`/api/reviews/nocolon/strips/chromium-390-open.png`)).status).toBe(404);
    expect(s.calls).toHaveLength(0);
  });
  it("an expired strip is not served and nothing is downloaded", async () => {
    const s = stub();
    const { app } = await rig(s.download, "2026-11-19");
    expect((await app.request(url("chromium-390-open.png"))).status).toBe(404);
    const w = await rig(s.download, "2026-11-20");
    expect((await w.app.request(url("playwright-webkit-390-open.png"))).status).toBe(404);
    expect(s.calls).toHaveLength(0);
  });
  it("a refused download (403) gives 502, leaves no cache and is not retried", async () => {
    const calls: string[] = [];
    const { app, dir } = await rig(async (r, a) => { calls.push(`${r}/${a}`); throw new Error("HTTP 403: rate limit"); });
    expect((await app.request(url("chromium-390-open.png"))).status).toBe(502);
    expect((await app.request(url("chromium-390-close.png"))).status).toBe(502);
    expect(calls).toHaveLength(1);
    expect(existsSync(join(dir, "review-cache/39473950464/frames-chromium"))).toBe(false);
  });
  it("an artifact without the file gives 404", async () => {
    const { app } = await rig(async (_r, _a, dir) => { mkdirSync(join(dir, "strips"), { recursive: true }); });
    expect((await app.request(url("chromium-390-close.png"))).status).toBe(404);
  });
  it("is behind the owner gate: a LAN request without a token is refused", async () => {
    const s = stub();
    const store = (await rig(s.download)).store;
    const owner = new OwnerAuth(); owner.setPorts(4000, 4001); owner.setLanHosts(["198.51.100.9:4000"]);
    const app = createApp(store, undefined, undefined, undefined, owner, undefined, { login: new LoginGuard(store.core, "fake-pass-for-tests-only"), lan: true }, undefined, { download: s.download, today: () => "2026-10-21" });
    const r = await app.request(url("chromium-390-open.png"), { headers: { host: "198.51.100.9:4000" } }, { incoming: { socket: { remoteAddress: "198.51.100.50" } } });
    expect(r.status).toBe(401);
    expect(s.calls).toHaveLength(0);
    const ok = await app.request(url("chromium-390-open.png"), { headers: { host: "198.51.100.9:4000", authorization: `Bearer ${owner.open()}` } }, { incoming: { socket: { remoteAddress: "198.51.100.50" } } });
    expect(ok.status).toBe(200);
  });
});

describe("console.review strips in Lean (run and expiry only from the material)", () => {
  const mat = (webkit: object) => ({ chromium: { state: "ready", run: "1", artifact: "frames-chromium", expires: "2026-12-01" }, webkit });
  const looks = (m: object) => [{ date: "2026-10-21", decision: "kept", flag: FLAG, review: "pending", material: m }];
  const ask = (m: object | null, file = "playwright-webkit-1280-close.png") =>
    selectCore().ops("console.review", { ...(m ? { looks: looks(m) } : {}), steps: [], today: "2026-10-21", serve: { flag: FLAG, file } }) as any;
  it("the default material serves a webkit file from its own artifact, run 39530106935", async () => {
    const r = await ask(null);
    expect(r.items[0].strips.filter((s: any) => s.engine === "webkit").map((s: any) => s.artifact).sort()).toEqual(["frames-apple-1280", "frames-apple-1280", "frames-apple-390", "frames-apple-390"]);
    expect(r.serve).toEqual({ ok: true, run: "39530106935", artifact: "frames-apple-1280", path: "strips/playwright-webkit-1280-close.png" });
  });
  it("a new run in the material changes the strips' run and expiry (rows hold none)", async () => {
    const r = await ask(mat({ state: "ready", run: "777", artifact: "frames-apple-390, frames-apple-1280", expires: "2026-12-09" }));
    const wk = r.items[0].strips.filter((s: any) => s.engine === "webkit");
    expect(wk.every((s: any) => s.run === "777" && s.expires === "2026-12-09")).toBe(true);
    expect(r.serve).toMatchObject({ ok: true, run: "777" });
  });
  it("a row whose artifact the material does not name is missing and not served", async () => {
    const r = await ask(mat({ state: "ready", run: "5", artifact: "frames-apple-390", expires: "2026-12-09" }));
    const w = r.items[0].strips.filter((s: any) => s.engine === "webkit");
    expect(w.filter((s: any) => s.state === "missing").map((s: any) => s.file)).toEqual(["playwright-webkit-1280-close.png", "playwright-webkit-1280-open.png"]);
    expect(w.filter((s: any) => s.state === "missing").every((s: any) => s.run === undefined)).toBe(true);
    expect(r.serve.ok).toBe(false);
  });
  it("webkit pending gives only the chromium strips and refuses a webkit file", async () => {
    const r = await ask(mat({ state: "pending", task: "x" }));
    expect(r.items[0].strips).toHaveLength(4);
    expect(r.serve.ok).toBe(false);
  });
});
