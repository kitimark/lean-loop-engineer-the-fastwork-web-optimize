// review-followups: (1) review.previewed cannot pass the public command door, with a mutation check; (2) the preview search names a
// flag by a whole entry (Lean console.reviewPreview, golden packages/contracts/golden/console/reviewPreview.jsonl); (3) previews are
// scoped to the review round (Lean Fw.Console.Review.inRound).
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { z } from "zod";
import { afterEach, describe, expect, it } from "vitest";
import { Command, PublicCommand } from "@fw/contracts";
import { createApp } from "../src/app.ts";
import { stamp } from "../src/cap/cap.ts";
import { selectCore } from "../src/core/index.ts";
import { Store } from "../src/store.ts";
import { ensureReviewSteps } from "../src/review/routes.ts";

const FLAG = "nav:earn-no-transition";
let stores: Store[] = [];
afterEach(() => { stores.forEach((s) => s.close()); stores = []; });

async function rig() {
  const root = mkdtempSync(join(tmpdir(), "fw-review-door-"));
  mkdirSync(join(root, "research/findings"), { recursive: true });
  writeFileSync(join(root, "research/findings/ledger.json"), JSON.stringify({ findings: [
    { id: "nav.earn.noTransition", part: "nav", candidate: "nav:earn-no-transition: transitions off while the nav morphs", status: "look-change",
      visual: "not equal mid-transition", chromium: "win on the open push", webkit: "unknown", flag: FLAG }] }));
  const store = await Store.open(join(root, ".fw-console"), selectCore(), () => 1_700_000_000_000);
  stores.push(store);
  return { store, app: createApp(store, undefined, undefined, undefined, undefined, undefined, undefined, root) };
}
const json = { "content-type": "application/json" };
const previewed = (actor: string) => ({ type: "review.previewed", key: `k-${actor}`, actor, flag: FLAG, device: "phone" });
const post = (app: ReturnType<typeof createApp>, body: unknown) =>
  app.request(`/api/reviews/${encodeURIComponent(FLAG)}/preview`, { method: "POST", body: JSON.stringify(body), headers: json });
const card = async (app: ReturnType<typeof createApp>) => ((await (await app.request("/api/reviews")).json()) as any).items[0].preview;
const count = async (store: Store) => (await store.readEvents()).filter((e) => (e as { type: string }).type === "review.previewed").length;

/** The door check: does a schema admit a review.previewed for each actor? (What the cap door does before it asks the reducer.) */
const admits = (door: z.ZodTypeAny, actor: string) => door.safeParse(previewed(actor)).success;

describe("the public command door refuses review.previewed", () => {
  it("POST /api/commands refuses it for every actor and writes nothing", async () => {
    const { app, store } = await rig();
    for (const actor of ["user", "lead", "script", "agent"]) {
      const r = await app.request("/api/commands", { method: "POST", headers: json, body: JSON.stringify(previewed(actor)) });
      expect(r.status, actor).toBe(400);
    }
    expect(await count(store)).toBe(0);
  });
  it("the cap stamp (the agent door) refuses it whatever actor it stamps", () => {
    for (const actor of ["user", "lead", "script"] as const) {
      expect(stamp(previewed("x"), { actor, signedBy: "t", toolUseId: "u" } as never).success, actor).toBe(false);
    }
  });
  it("only the internal route records it: the preview route with done appends one, the log and reducer accept the type", async () => {
    const { app, store } = await rig();
    await ensureReviewSteps(store);
    expect(Command.safeParse(previewed("user")).success).toBe(true); // the log/reducer union keeps it
    const r = await post(app, { view: "flag", width: 390, done: true });
    expect(r.status).toBe(200);
    expect(await count(store)).toBe(1);
  });
  it("mutation check: a door that admits review.previewed is caught by this test's check", () => {
    // the real door admits none; the mutant (the internal commands moved into the public list) admits it, so `admits` would flag it
    expect(admits(PublicCommand, "user")).toBe(false);
    const internal = Command.options.filter((o) => o.shape.type.value === "review.previewed");
    expect(internal).toHaveLength(1);
    const mutant = z.discriminatedUnion("type", [...PublicCommand.options, ...internal] as never);
    expect(admits(mutant, "user")).toBe(true);
    expect(PublicCommand.options.some((o) => (o.shape.type.value as string) === "review.previewed")).toBe(false);
  });
});

describe("the preview search names a flag by a whole entry (Lean searchHasFlag)", () => {
  const names = async (search: string, flag: string) => {
    const { store } = await rig();
    return (await store.core.ops("console.reviewPreview", { steps: [], events: [], names: { search, flag } })).names;
  };
  it("nav:earn is not named by a search for nav:earn-no-transition, and the reverse", async () => {
    expect(await names("?fw=nav:earn-no-transition", "nav:earn")).toBe(false);
    expect(await names("?fw=nav:earn", "nav:earn-no-transition")).toBe(false);
  });
  it("a whole entry matches, alone or in a comma list or a second fw parameter", async () => {
    expect(await names("?fw=nav:earn-no-transition", "nav:earn-no-transition")).toBe(true);
    expect(await names("?fw=hero:a,nav:earn,nav:earn-no-transition", "nav:earn")).toBe(true);
    expect(await names("?fw=hero:a&fw=nav:earn", "nav:earn")).toBe(true);
    expect(await names("", "nav:earn")).toBe(false);
  });
  it("the route's plan carries the flag exactly in the flag and compare views and none in the faithful view", async () => {
    const { app, store } = await rig();
    await ensureReviewSteps(store);
    for (const [view, search] of [["flag", `?fw=${FLAG}`], ["compare", `?fw=${FLAG}`], ["faithful", ""]] as const) {
      expect(await (await post(app, { view, width: 1280 })).json()).toMatchObject({ ok: true, search });
    }
  });
});

describe("previews are scoped to the review round (Lean Fw.Console.Review.inRound)", () => {
  it("a new round (step posted again after the last was closed without a verdict) does not inherit the old previews", async () => {
    const { app, store } = await rig();
    await ensureReviewSteps(store);
    await post(app, { view: "flag", width: 1280, done: true });
    expect(await card(app)).toMatchObject({ desktop: true, phone: false });
    // close the review step without a decision: the console posts a new one (review-<flag>#1)
    await store.submit({ type: "step.start", key: "start-r1", actor: "user", step: `review-${FLAG}` } as never);
    const closed = await store.submit({ type: "step.done", key: "close-r1", actor: "user", step: `review-${FLAG}` } as never);
    expect(closed, JSON.stringify(closed)).toMatchObject({ ok: true });
    await ensureReviewSteps(store);
    expect(await card(app)).toMatchObject({ open: true, desktop: false, phone: false, missing: ["desktop", "phone"] });
    // a preview in the new round counts, and its key is not the duplicate of round 1's
    await post(app, { view: "flag", width: 1280, done: true });
    expect(await card(app)).toMatchObject({ desktop: true, phone: false });
    const keys = (await store.readEvents()).filter((e) => (e as { type: string }).type === "review.previewed").map((e) => (e as { key: string }).key);
    expect(keys).toEqual([`review-previewed-${FLAG}-desktop`, `review-previewed-${FLAG}-desktop#1`]);
  });
  it("existing events stay readable: a preview recorded in the first round still counts there", async () => {
    const { app, store } = await rig();
    await ensureReviewSteps(store);
    await post(app, { view: "flag", width: 390, done: true });
    const lines = readFileSync(join(store.dir, "events.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l));
    expect(lines.filter((e) => e.type === "review.previewed")).toHaveLength(1);
    expect(await card(app)).toMatchObject({ phone: true, desktop: false });
  });
});
