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
  it("lists the 4 chromium strips ready, with tag data, note and diff; webkit material is pending so none", async () => {
    const { app } = await rig(stub().download);
    const i = ((await (await app.request("/api/reviews")).json()) as any).items[0];
    expect(i.strips).toHaveLength(4);
    expect(i.strips.every((s: any) => s.state === "ready" && s.engine === "chromium")).toBe(true);
    const close390 = i.strips.find((s: any) => s.width === 390 && s.push === "close");
    expect(close390).toMatchObject({ file: "chromium-390-close.png", run: "39473950464", artifact: "frames-chromium", diff: "about 0.4 s earlier" });
    expect(close390.note).toContain("Join waitlist");
  });
  it("on the expiry day the strips are expired and name the dispatch that re-makes them", async () => {
    const { app } = await rig(stub().download, "2026-11-19");
    const i = ((await (await app.request("/api/reviews")).json()) as any).items[0];
    expect(i.strips.every((s: any) => s.state === "expired" && s.redo === `[ci:trajectory-probe] [frames:${FLAG}]`)).toBe(true);
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
    for (const f of ["..%2F..%2Fevents.jsonl", "..", "%2e%2e%2fx.png", "strips%2Fchromium-390-open.png", "other.png", "chromium-390-open.PNG", "playwright-webkit-390-open.png"]) {
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

describe("console.review strips in Lean (material ready for both engines)", () => {
  const looks = (webkit: string) => [{ date: "2026-10-21", decision: "kept", flag: FLAG, review: "pending",
    material: { chromium: { state: "ready" }, webkit: { state: webkit } } }];
  it("returns the 8 strips, the webkit ones with an empty note, and serves a webkit file from its own artifact", async () => {
    const r = await selectCore().ops("console.review", { looks: looks("ready"), steps: [], today: "2026-10-21", serve: { flag: FLAG, file: "playwright-webkit-1280-close.png" } }) as any;
    const st = r.items[0].strips;
    expect(st).toHaveLength(8);
    expect(st.filter((s: any) => s.engine === "webkit").map((s: any) => s.artifact).sort()).toEqual(["frames-apple-1280", "frames-apple-1280", "frames-apple-390", "frames-apple-390"]);
    expect(st.find((s: any) => s.engine === "webkit").note).toBe("");
    expect(r.serve).toEqual({ ok: true, run: "39530106935", artifact: "frames-apple-1280", path: "strips/playwright-webkit-1280-close.png" });
  });
  it("webkit pending gives only the chromium strips and refuses a webkit file", async () => {
    const r = await selectCore().ops("console.review", { looks: looks("pending"), steps: [], today: "2026-10-21", serve: { flag: FLAG, file: "playwright-webkit-1280-close.png" } }) as any;
    expect(r.items[0].strips).toHaveLength(4);
    expect(r.serve.ok).toBe(false);
  });
});
