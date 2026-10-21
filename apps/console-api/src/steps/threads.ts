import { randomBytes } from "node:crypto";
import type { Hono } from "hono";
import { z } from "zod";
import type { Store } from "../store.ts";
import type { Thread } from "../review/feedback.ts";

export interface StepGroup {
  topic: string | null; title: string; summary: string; updatedAt: number | null;
  steps: string[]; openQuestions: number; activity: number; thread: Thread | null;
}
export interface StepTopics { groups: StepGroup[]; threads: Thread[] }

const LOG_TYPES = new Set(["step.topic", "review.feedback", "review.feedback.reply"]);

export async function stepTopics(store: Store): Promise<StepTopics> {
  const events = store.readEvents().filter((e) => LOG_TYPES.has(e.type));
  const board = await store.board();
  const steps = board.steps.map((s) => ({ id: s.id, topic: s.topic ?? null, status: s.status, audience: s.audience, lastAt: s.lastAt }));
  return (await store.core.ops("console.stepTopics", { events, steps })) as unknown as StepTopics;
}

const Req = z.object({ text: z.string().max(20_000), cid: z.string().regex(/^[A-Za-z0-9-]{8,60}$/).optional() });
const mintId = () => `fb-${Date.now().toString(36)}-${randomBytes(4).toString("hex")}`;

export function mountStepThreads(app: Hono, store: Store) {
  app.get("/api/steps/topics", async (c) => {
    c.header("Cache-Control", "no-store");
    try { return c.json({ ok: true, ...(await stepTopics(store)) }); }
    catch (e) { return c.json({ ok: false, reason: String((e as Error).message).replace(/^fwcore: /, "") }, 422); }
  });

  app.post("/api/steps/:kind/:id/question", async (c) => {
    c.header("Cache-Control", "no-store");
    const kind = c.req.param("kind");
    if (kind !== "step" && kind !== "topic") return c.json({ ok: false, reason: "the subject is step or topic" }, 400);
    let body: unknown;
    try { body = await c.req.json(); } catch { return c.json({ ok: false, reason: "body is not JSON" }, 400); }
    const req = Req.safeParse(body);
    if (!req.success) return c.json({ ok: false, reason: "expected {text}" }, 400);
    const flag = `${kind}:${c.req.param("id")}`;
    const id = req.data.cid ? `fb-${req.data.cid}` : mintId();
    const reply = await store.submit({ type: "review.feedback", key: `step-question-${flag}-${id}`, actor: "user", flag, id, text: req.data.text } as never);
    if (!reply.ok) return c.json(reply, 422);
    const { groups, threads } = await stepTopics(store);
    return c.json({ ...reply, groups, threads, id });
  });
}
