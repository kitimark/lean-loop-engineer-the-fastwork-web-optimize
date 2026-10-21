import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createApp } from "../src/app.ts";
import { selectCore } from "../src/core/index.ts";
import { Store } from "../src/store.ts";
import { ensureReviewSteps } from "../src/review/routes.ts";

const FLAG = "nav:earn-no-transition";
let stores: Store[] = [];
afterEach(() => { stores.forEach((s) => s.close()); stores = []; });

/** A temp root with the findings ledger row of the flag and, when given, `.local/reviews.json`. */
async function rig(links?: unknown) {
  const root = mkdtempSync(join(tmpdir(), "fw-review-"));
  mkdirSync(join(root, "research/findings"), { recursive: true });
  writeFileSync(join(root, "research/findings/ledger.json"), JSON.stringify({ findings: [
    { id: "nav.earn.noTransition", part: "nav", candidate: "nav:earn-no-transition: transitions off while the nav morphs", status: "look-change",
      visual: "not equal mid-transition", chromium: "win on the open push", webkit: "unknown", flag: FLAG }] }));
  if (links !== undefined) { mkdirSync(join(root, ".local"), { recursive: true }); writeFileSync(join(root, ".local/reviews.json"), typeof links === "string" ? links : JSON.stringify(links)); }
  const dir = join(root, ".fw-console");
  const store = await Store.open(dir, selectCore(), () => 1_700_000_000_000);
  stores.push(store);
  return { root, dir, store, app: createApp(store, undefined, undefined, undefined, undefined, undefined, undefined, root) };
}
const post = (app: ReturnType<typeof createApp>, flag: string, body: unknown) =>
  app.request(`/api/reviews/${encodeURIComponent(flag)}/preview`, { method: "POST", body: JSON.stringify(body), headers: { "content-type": "application/json" } });
const events = (dir: string) => readFileSync(join(dir, "events.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l));
const info = async (app: ReturnType<typeof createApp>) => ((await (await app.request("/api/reviews")).json()) as any).items[0].preview;

describe("review preview routes (Lean console.reviewPreview)", () => {
  it("GET /api/reviews: nothing previewed, both devices missing, with the ask lines", async () => {
    const { app, store } = await rig();
    await ensureReviewSteps(store);
    const p = await info(app);
    expect(p).toMatchObject({ open: true, desktop: false, phone: false, missing: ["desktop", "phone"] });
    expect(p.asks.join(" ")).toContain("LAN address");
  });
  it("the plan of each view: the flag arm carries exactly ?fw=<flag>, the faithful arm none, compare the flag; nothing is recorded", async () => {
    const { app, dir, store } = await rig();
    await ensureReviewSteps(store);
    const n = events(dir).length;
    const f = await (await post(app, FLAG, { view: "flag", width: 1280 })).json() as any;
    expect(f).toMatchObject({ ok: true, search: `?fw=${FLAG}`, arm: "r", slot: "open-main", device: "desktop", recorded: false });
    expect(await (await post(app, FLAG, { view: "faithful", width: 1280 })).json()).toMatchObject({ search: "", arm: "r" });
    expect(await (await post(app, FLAG, { view: "compare", width: 1280 })).json()).toMatchObject({ search: `?fw=${FLAG}`, arm: "compare" });
    expect(events(dir)).toHaveLength(n);
  });
  it("the device comes from the width: 600 is the phone, 601 the desktop", async () => {
    const { app, store } = await rig();
    await ensureReviewSteps(store);
    expect(((await (await post(app, FLAG, { view: "flag", width: 600 })).json()) as any).device).toBe("phone");
    expect(((await (await post(app, FLAG, { view: "flag", width: 601 })).json()) as any).device).toBe("desktop");
  });
  it("done records the user's review.previewed once per device; the card then shows it and asks only for the missing device", async () => {
    const { app, dir, store } = await rig();
    await ensureReviewSteps(store);
    const r = await (await post(app, FLAG, { view: "flag", width: 1280, done: true })).json() as any;
    expect(r).toMatchObject({ ok: true, recorded: true, preview: { desktop: true, phone: false, missing: ["phone"] } });
    await post(app, FLAG, { view: "compare", width: 1000, done: true }); // the same device again: the idempotent key
    expect(events(dir).filter((e) => e.type === "review.previewed")).toEqual([
      expect.objectContaining({ actor: "user", flag: FLAG, device: "desktop", key: `review-previewed-${FLAG}-desktop` })]);
    const p = await info(app);
    expect(p.asks.join(" ")).toContain("phone");
    await post(app, FLAG, { view: "flag", width: 390, done: true });
    expect(await info(app)).toMatchObject({ desktop: true, phone: true, missing: [], asks: [] });
  });
  it("Keep and Reject are not gated by a preview", async () => {
    const { app, store } = await rig();
    await ensureReviewSteps(store);
    const r = await app.request(`/api/reviews/${encodeURIComponent(FLAG)}`, { method: "POST", body: JSON.stringify({ decision: "keep" }), headers: { "content-type": "application/json" } });
    expect(r.status).toBe(200);
  });
  it("a decided review gets no preview; an unknown flag, view or body is refused", async () => {
    const { app, store } = await rig();
    await ensureReviewSteps(store);
    expect((await post(app, "nav:other", { view: "flag", width: 390 })).status).toBe(422);
    expect((await post(app, FLAG, { view: "original", width: 390 })).status).toBe(422);
    expect((await post(app, "nocolon", { view: "flag", width: 390 })).status).toBe(422);
    expect((await post(app, FLAG, { view: "flag" })).status).toBe(400);
    await app.request(`/api/reviews/${encodeURIComponent(FLAG)}`, { method: "POST", body: JSON.stringify({ decision: "reject" }), headers: { "content-type": "application/json" } });
    const late = await post(app, FLAG, { view: "flag", width: 390, done: true });
    expect(late.status).toBe(422);
    expect(((await late.json()) as any).reason).toContain("no open look-change review");
    expect(events(store.dir).filter((e) => e.type === "review.previewed")).toHaveLength(0);
  });
});
