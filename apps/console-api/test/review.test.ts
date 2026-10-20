import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it } from "vitest";
import { createApp } from "../src/app.ts";
import { selectCore } from "../src/core/index.ts";
import { Store } from "../src/store.ts";
import { readLinks } from "../src/review/routes.ts";

const HERE = dirname(fileURLToPath(import.meta.url));
const GOLDEN = join(HERE, "../../../packages/contracts/golden/console/review.jsonl");
const cases = readFileSync(GOLDEN, "utf8").trim().split("\n").map((l) => JSON.parse(l) as { name: string; request: Record<string, unknown>; response: Record<string, unknown> });
const core = selectCore();
const FLAG = "nav:earn-no-transition";
const LINK = "https://example.test/review/earn";

describe("console.review golden: fwcore gives Lean's answer for every vector", () => {
  it("has the cases the task names", () => {
    const names = cases.map((c) => c.name).join("|");
    for (const w of ["no step yet", "unanswered", "answered keep", "answered reject", "no verdict word", "another flag", "decided look change", "no pending decision", "refused"]) {
      expect(names).toContain(w);
    }
  });
  for (const c of cases) {
    it(c.name, async () => {
      if (c.response.error !== undefined) {
        const got = await core.ops("console.review", c.request).then((r) => r, (e: Error) => ({ error: String(e.message) }));
        expect(JSON.stringify(got)).toContain(String(c.response.error));
        return;
      }
      const { id: _id, ...got } = await core.ops("console.review", c.request) as Record<string, unknown>;
      expect(JSON.parse(JSON.stringify(got))).toEqual(c.response);
    });
  }
  it("an item is open exactly when its state is open, and the badge counts the open ones", () => {
    for (const c of cases) {
      const r = c.response as { items?: { state: string }[]; open: number };
      if (!r.items) continue;
      expect(r.open).toBe(r.items.filter((i) => i.state === "open").length);
    }
  });
});

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
const decide = (app: ReturnType<typeof createApp>, flag: string, body: unknown) =>
  app.request(`/api/reviews/${encodeURIComponent(flag)}`, { method: "POST", body: JSON.stringify(body), headers: { "content-type": "application/json" } });

describe("GET /api/reviews", () => {
  it("one open user item with the ledger words, the material state and the private link from .local/reviews.json", async () => {
    const { app, store } = await rig({ [FLAG]: LINK });
    const r = await (await app.request("/api/reviews")).json() as any;
    expect(r.open).toBe(1);
    expect(r.items).toHaveLength(1);
    const i = r.items[0];
    expect(i).toMatchObject({ flag: FLAG, state: "open", audience: "user", link: LINK, step: `review-${FLAG}` });
    expect(i.changed).toMatchObject({ id: "nav.earn.noTransition", visual: "not equal mid-transition" });
    expect(i.material.chromium).toEqual({ state: "ready", run: "39473950464", artifact: "frames-chromium", expires: "2026-11-19" });
    expect(i.material.webkit).toEqual({ state: "pending", task: "earn-look-review-webkit" });
    const step = (await store.board()).steps.find((s) => s.id === `review-${FLAG}`)!;
    expect(step).toMatchObject({ audience: "user", kind: "choice", options: ["keep", "reject"], status: "waiting" });
  });
  it("a missing .local/reviews.json gives no link; the run id and artifact name stay", async () => {
    const { app } = await rig();
    const i = ((await (await app.request("/api/reviews")).json()) as any).items[0];
    expect(i.link).toBeNull();
    expect(i.material.chromium.run).toBe("39473950464");
    expect(i.material.chromium.artifact).toBe("frames-chromium");
  });
  it("a malformed file or a non-https link gives no link", async () => {
    expect(readLinks((await rig("{not json")).root)).toEqual({});
    expect(readLinks((await rig({ [FLAG]: "javascript:alert(1)" })).root)).toEqual({});
    expect(readLinks((await rig({ [FLAG]: LINK })).root)).toEqual({ [FLAG]: LINK });
  });
  it("posts the step once however often it is read", async () => {
    const { app, dir } = await rig();
    await app.request("/api/reviews"); await app.request("/api/reviews");
    const lines = readFileSync(join(dir, "events.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l));
    expect(lines.filter((e) => e.type === "step.post")).toHaveLength(1);
  });
});

describe("POST /api/reviews/<flag>", () => {
  it("keep closes the item through a step.answer of the user, and it stays closed", async () => {
    const { app, dir, store } = await rig();
    await app.request("/api/reviews");
    const ok = await decide(app, FLAG, { decision: "keep" });
    expect(ok.status).toBe(200);
    const r = await (await app.request("/api/reviews")).json() as any;
    expect(r.open).toBe(0);
    expect(r.items[0].state).toBe("keep");
    const last = readFileSync(join(dir, "events.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l)).pop();
    expect(last).toMatchObject({ type: "step.answer", actor: "user", step: `review-${FLAG}`, answer: "keep" });
    const again = await decide(app, FLAG, { decision: "reject" });
    expect(again.status).toBe(422);
    expect(((await again.json()) as any).reason).toContain("already decided");
    expect(((await (await app.request("/api/reviews")).json()) as any).items[0].state).toBe("keep");
    expect((await store.board()).steps.find((s) => s.id === `review-${FLAG}`)!.answer).toBe("keep");
  });
  it("reject is recorded as reject", async () => {
    const { app } = await rig();
    expect((await decide(app, FLAG, { decision: "reject" })).status).toBe(200);
    expect(((await (await app.request("/api/reviews")).json()) as any).items[0].state).toBe("reject");
  });
  it("Lean refuses a flag without a pending review and a word that is no verdict; a bad body is 400", async () => {
    const { app, dir } = await rig();
    const unknown = await decide(app, "nav:other", { decision: "keep" });
    expect(unknown.status).toBe(422);
    expect(((await unknown.json()) as any).reason).toContain("no pending review");
    const word = await decide(app, FLAG, { decision: "yes" });
    expect(word.status).toBe(422);
    expect(((await word.json()) as any).reason).toContain("keep or reject");
    const bad = await decide(app, "nocolon", { decision: "keep" });
    expect(bad.status).toBe(422);
    expect(((await bad.json()) as any).reason).toContain("bad flag");
    expect((await decide(app, FLAG, { nope: 1 })).status).toBe(400);
    expect((await app.request(`/api/reviews/${encodeURIComponent(FLAG)}`, { method: "POST", body: "x" })).status).toBe(400);
    const log = readFileSync(join(dir, "events.jsonl"), "utf8");
    expect(log).not.toContain("step.answer");
  });
  it("a console origin check applies as for every state-changing route: a foreign Origin is refused", async () => {
    const { app } = await rig();
    const r = await app.request(`/api/reviews/${encodeURIComponent(FLAG)}`, { method: "POST", body: JSON.stringify({ decision: "keep" }), headers: { "content-type": "application/json", origin: "https://evil.example", host: "localhost" } });
    expect(r.status).toBe(403);
  });
});
