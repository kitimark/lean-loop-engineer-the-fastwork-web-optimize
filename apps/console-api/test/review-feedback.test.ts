import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
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

async function rig() {
  const root = mkdtempSync(join(tmpdir(), "fw-fb-"));
  mkdirSync(join(root, "research/findings"), { recursive: true });
  writeFileSync(join(root, "research/findings/ledger.json"), JSON.stringify({ findings: [
    { id: "nav.earn.noTransition", part: "nav", candidate: "nav:earn-no-transition: transitions off", status: "look-change", visual: "x", chromium: "win", webkit: "unknown", flag: FLAG }] }));
  const store = await Store.open(join(root, ".fw-console"), selectCore(), () => 1_700_000_000_000);
  stores.push(store);
  await ensureReviewSteps(store);
  return { store, app: createApp(store, undefined, undefined, undefined, undefined, undefined, undefined, root) };
}
type App = Awaited<ReturnType<typeof rig>>["app"];
const send = (app: App, text: string, cid?: string, flag = FLAG) =>
  app.request(`/api/reviews/${encodeURIComponent(flag)}/feedback`, { method: "POST", body: JSON.stringify({ text, ...(cid ? { cid } : {}) }), headers: { "content-type": "application/json" } });
const thread = async (app: App, flag = FLAG) => ((await (await app.request(`/api/reviews/${encodeURIComponent(flag)}/feedback`)).json()) as any).thread;
const reply = (store: Store, to: string, text = "done", actor: "lead" | "user" = "lead") =>
  store.submit({ type: "review.feedback.reply", key: `r-${to}-${actor}`, actor, flag: FLAG, to, text } as never);

describe("review feedback (Lean Fw.Console.ReviewFeedback)", () => {
  it("a comment is an open comment of the flag, shown on its review card", async () => {
    const { app } = await rig();
    const r = await (await send(app, "look at the font", "abcd1234")).json() as any;
    expect(r).toMatchObject({ ok: true, id: "fb-abcd1234", thread: { flag: FLAG, open: 1 } });
    expect(r.thread.comments[0]).toMatchObject({ id: "fb-abcd1234", text: "look at the font", status: "open", reply: null });
    const items = ((await (await app.request("/api/reviews")).json()) as any).items;
    expect(items[0].feedback).toMatchObject({ flag: FLAG, open: 1 });
  });
  it("a repeated cid is one comment, not two", async () => {
    const { app } = await rig();
    await send(app, "same", "abcd1234");
    const again = await (await send(app, "same", "abcd1234")).json() as any;
    expect(again.ok).toBe(true);
    expect((await thread(app)).comments).toHaveLength(1);
  });
  it("the lead's reply closes exactly the comment it names", async () => {
    const { app, store } = await rig();
    await send(app, "one", "aaaaaaaa"); await send(app, "two", "bbbbbbbb");
    expect(await reply(store, "fb-aaaaaaaa")).toMatchObject({ ok: true });
    const t = await thread(app);
    expect(t.open).toBe(1);
    expect(t.comments.map((c: any) => [c.id, c.status])).toEqual([["fb-aaaaaaaa", "answered"], ["fb-bbbbbbbb", "open"]]);
    expect(t.comments[0].reply).toMatchObject({ text: "done" });
  });
  it("an unknown or already-answered `to` is refused", async () => {
    const { app, store } = await rig();
    await send(app, "one", "aaaaaaaa");
    expect(await reply(store, "fb-nope")).toMatchObject({ ok: false, reason: "no such feedback" });
    await reply(store, "fb-aaaaaaaa");
    expect(await store.submit({ type: "review.feedback.reply", key: "again", actor: "lead", flag: FLAG, to: "fb-aaaaaaaa", text: "twice" } as never))
      .toMatchObject({ ok: false, reason: "feedback already answered" });
  });
  it("feedback is never accepted from the lead, and a reply never from the user", async () => {
    const { app, store } = await rig();
    expect(await store.submit({ type: "review.feedback", key: "k1", actor: "lead", flag: FLAG, id: "fb-1", text: "x" } as never))
      .toMatchObject({ ok: false, reason: "actor lead may not cause review.feedback" });
    await send(app, "one", "aaaaaaaa");
    expect(await reply(store, "fb-aaaaaaaa", "mine", "user")).toMatchObject({ ok: false, reason: "actor user may not cause review.feedback.reply" });
    expect((await thread(app)).open).toBe(1);
  });
  it("a text over the cap or a blank one is refused (422) and nothing is recorded", async () => {
    const { app } = await rig();
    const long = await send(app, "a".repeat(2001), "cccccccc");
    expect(long.status).toBe(422);
    expect(await long.json()).toMatchObject({ ok: false });
    expect((await send(app, "   ", "dddddddd")).status).toBe(422);
    expect((await thread(app)).comments).toHaveLength(0);
  });
  it("a flag that is not a key part:variant is refused", async () => {
    const { app } = await rig();
    const r = await send(app, "x", "eeeeeeee", "nocolon");
    expect(r.status).toBe(422);
    expect(await r.json()).toMatchObject({ ok: false, reason: "flag must be a key part:variant" });
  });
  it("without a cid the server mints an id, and two sends are two comments", async () => {
    const { app } = await rig();
    await send(app, "one"); await send(app, "two");
    expect((await thread(app)).comments).toHaveLength(2);
  });
});
