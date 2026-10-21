import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createApp } from "../src/app.ts";
import { selectCore } from "../src/core/index.ts";
import { Store } from "../src/store.ts";

let stores: Store[] = [];
afterEach(() => { stores.forEach((s) => s.close()); stores = []; });

let clock = 1_700_000_000_000;
async function rig() {
  const root = mkdtempSync(join(tmpdir(), "fw-st-"));
  const store = await Store.open(join(root, ".fw-console"), selectCore(), () => (clock += 1000));
  stores.push(store);
  return { store, app: createApp(store) };
}
type App = Awaited<ReturnType<typeof rig>>["app"];
const post = (store: Store, step: string, topic: string | null, audience: "user" | "lead" = "user") =>
  store.submit({ type: "step.post", key: `p-${step}`, actor: "lead", step, card: null, title: `Step ${step}`, kind: "action", options: null, audience, topic } as never);
const define = (store: Store, topic: string, title: string, summary: string, actor = "lead") =>
  store.submit({ type: "step.topic", key: `t-${topic}-${summary}`, actor, topic, title, summary } as never);
const ask = (app: App, kind: string, id: string, text: string, cid?: string) =>
  app.request(`/api/steps/${kind}/${id}/question`, { method: "POST", body: JSON.stringify({ text, ...(cid ? { cid } : {}) }), headers: { "content-type": "application/json" } });
const reply = (store: Store, flag: string, to: string, text = "answer", actor = "lead") =>
  store.submit({ type: "review.feedback.reply", key: `r-${flag}-${to}`, actor, flag, to, text } as never);
const topics = async (app: App) => (await (await app.request("/api/steps/topics")).json()) as any;

describe("topics and question threads of the Your steps card (Lean Fw.Console.Steps)", () => {
  it("open steps group under their topic with the lead's title and summary; steps without a defined topic fall in the rest", async () => {
    const { store, app } = await rig();
    await define(store, "smooth", "Smoothness", "Hero exit first.");
    await post(store, "a", "smooth"); await post(store, "b", null); await post(store, "c", "undefined-topic");
    const r = await topics(app);
    expect(r.ok).toBe(true);
    const by = Object.fromEntries(r.groups.map((g: any) => [g.topic, g]));
    expect(by.smooth).toMatchObject({ title: "Smoothness", summary: "Hero exit first.", steps: ["a"] });
    expect(by.smooth.updatedAt).toBeTypeOf("number");
    expect(by[null as never]).toMatchObject({ steps: ["b", "c"] });
  });
  it("a later definition replaces the summary; a step for the lead or a closed step is not grouped", async () => {
    const { store, app } = await rig();
    await define(store, "smooth", "Smoothness", "old");
    await define(store, "smooth", "Smoothness", "new");
    await post(store, "a", "smooth"); await post(store, "b", "smooth", "lead"); await post(store, "c", "smooth");
    await store.submit({ type: "step.cancel", key: "cx", actor: "user", step: "c" } as never);
    const g = (await topics(app)).groups.find((x: any) => x.topic === "smooth");
    expect(g).toMatchObject({ summary: "new", steps: ["a"] });
  });
  it("only the lead or a script defines a topic; an empty title or text is refused", async () => {
    const { store } = await rig();
    expect(await define(store, "t", "T", "s", "user")).toMatchObject({ ok: false, reason: "actor user may not cause step.topic" });
    expect(await define(store, "t", " ", "s")).toMatchObject({ ok: false, reason: "title is empty" });
    expect(await define(store, "t", "T", " ")).toMatchObject({ ok: false, reason: "text is empty" });
    expect(await define(store, "t", "T", "s", "script")).toMatchObject({ ok: true });
  });
  it("a question on a step opens a thread; the lead's reply closes exactly that question", async () => {
    const { store, app } = await rig();
    await post(store, "a", null);
    const q1 = await (await ask(app, "step", "a", "why this?", "aaaaaaaa")).json() as any;
    expect(q1).toMatchObject({ ok: true, id: "fb-aaaaaaaa" });
    await ask(app, "step", "a", "and that?", "bbbbbbbb");
    expect(await reply(store, "step:a", "fb-aaaaaaaa")).toMatchObject({ ok: true });
    const t = (await topics(app)).threads.find((x: any) => x.flag === "step:a");
    expect(t.open).toBe(1);
    expect(t.comments.map((c: any) => [c.id, c.status])).toEqual([["fb-aaaaaaaa", "answered"], ["fb-bbbbbbbb", "open"]]);
  });
  it("a question on a topic counts as open in its group and is not a review feedback alert subject", async () => {
    const { store, app } = await rig();
    await define(store, "smooth", "Smoothness", "s"); await post(store, "a", "smooth");
    await ask(app, "topic", "smooth", "what is left?", "cccccccc");
    const g = (await topics(app)).groups.find((x: any) => x.topic === "smooth");
    expect(g).toMatchObject({ openQuestions: 1, thread: { flag: "topic:smooth", open: 1 } });
  });
  it("a repeated cid is one question; a blank or over-long text is refused with 422", async () => {
    const { app } = await rig();
    await ask(app, "step", "a", "same", "aaaaaaaa");
    expect((await ask(app, "step", "a", "same", "aaaaaaaa")).status).toBe(200);
    expect((await topics(app)).threads.find((x: any) => x.flag === "step:a").comments).toHaveLength(1);
    expect((await ask(app, "step", "a", "  ", "dddddddd")).status).toBe(422);
    expect((await ask(app, "step", "a", "a".repeat(2001), "eeeeeeee")).status).toBe(422);
  });
  it("the subject must be step or topic; the lead may not ask and the user may not reply", async () => {
    const { store, app } = await rig();
    expect((await ask(app, "card", "a", "x", "ffffffff")).status).toBe(400);
    expect(await store.submit({ type: "review.feedback", key: "k", actor: "lead", flag: "step:a", id: "fb-1", text: "x" } as never))
      .toMatchObject({ ok: false, reason: "actor lead may not cause review.feedback" });
    await ask(app, "step", "a", "q", "aaaaaaaa");
    expect(await reply(store, "step:a", "fb-aaaaaaaa", "mine", "user")).toMatchObject({ ok: false });
  });
});
