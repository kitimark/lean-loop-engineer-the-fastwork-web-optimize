import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createApp } from "../src/app.ts";
import { tsCore } from "../src/core/index.ts";
import { Store } from "../src/store.ts";

let stores: Store[] = [];
afterEach(() => { stores.forEach((s) => s.close()); stores = []; });
const fresh = async (dir = mkdtempSync(join(tmpdir(), "fw-console-"))) => {
  const store = await Store.open(dir, tsCore(), () => 1_700_000_000_000);
  stores.push(store);
  return { dir, store, app: createApp(store) };
};
const post = (app: ReturnType<typeof createApp>, body: unknown) =>
  app.request("/api/commands", { method: "POST", body: JSON.stringify(body), headers: { "content-type": "application/json" } });
const open = { type: "card.open", key: "k1", actor: "owner", card: "A", owner: "o", needsDevice: false };

describe("console-api", () => {
  it("appends accepted commands, answers duplicates without a second line", async () => {
    const { dir, app } = await fresh();
    expect(await (await post(app, open)).json()).toEqual({ ok: true, seq: 1, duplicate: false });
    expect(await (await post(app, open)).json()).toEqual({ ok: true, seq: null, duplicate: true });
    const lines = readFileSync(join(dir, "events.jsonl"), "utf8").trim().split("\n");
    expect(lines).toHaveLength(1);
    expect(JSON.parse(lines[0]!)).toMatchObject({ seq: 1, ts: 1_700_000_000_000, type: "card.open" });
  });
  it("refuses with 422 and a reason; logs it outside events.jsonl", async () => {
    const { dir, app } = await fresh();
    const r = await post(app, { type: "card.approve", key: "k2", actor: "owner", card: "A" });
    expect(r.status).toBe(422);
    expect(await r.json()).toEqual({ ok: false, reason: "actor owner may not cause card.approve" });
    expect(readFileSync(join(dir, "events.jsonl"), "utf8")).toBe("");
    expect(readFileSync(join(dir, "refused.jsonl"), "utf8")).toContain("may not cause");
  });
  it("400 for a command that is not in the catalogue (no way to set a status)", async () => {
    const { app } = await fresh();
    expect((await post(app, { type: "card.set_status", key: "k", actor: "owner", card: "A", status: "done" })).status).toBe(400);
  });
  it("restart replays the log into the same projection", async () => {
    const { dir, store, app } = await fresh();
    await post(app, open);
    const before = store.state;
    store.close(); stores = [];
    const again = await Store.open(dir, tsCore());
    stores.push(again);
    expect(again.state).toEqual(before);
    expect(again.seq).toBe(1);
  });
  it("board endpoint reflects events", async () => {
    const { app } = await fresh();
    await post(app, open);
    const b = (await (await app.request("/api/board")).json()) as { cards: unknown[] };
    expect(b.cards[0]).toMatchObject({ id: "A", stage: "question" });
  });
});
