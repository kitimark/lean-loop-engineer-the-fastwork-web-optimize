// Topics and question threads of the Your steps card (step-threads). A topic's definition is the event `step.topic`; a question is
// the event `review.feedback` on the subject `step:<id>` or `topic:<id>`, the lead's answer `review.feedback.reply`. Which steps
// group under which topic, the order of the groups, the thread of each subject and who may write what are Lean
// (`Fw.Console.Steps`, `console.stepTopics`; the reducer decides). This file hands the log and the board to Lean and submits the
// user's question. It decides nothing.
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

/** The groups and the step and topic threads Lean projects from the log and the board. */
export async function stepTopics(store: Store): Promise<StepTopics> {
  const events = store.readEvents().filter((e) => LOG_TYPES.has(e.type));
  const board = await store.board();
  const steps = board.steps.map((s) => ({ id: s.id, topic: s.topic ?? null, status: s.status, audience: s.audience, lastAt: s.lastAt }));
  return (await store.core.ops("console.stepTopics", { events, steps })) as unknown as StepTopics;
}

/** `cid`: a client-made id for a retry-safe send (letters, digits, dash). */
const Req = z.object({ text: z.string().max(20_000), cid: z.string().regex(/^[A-Za-z0-9-]{8,60}$/).optional() });
const mintId = () => `fb-${Date.now().toString(36)}-${randomBytes(4).toString("hex")}`;

export function mountStepThreads(app: Hono, store: Store) {
  /** `GET /api/steps/topics`: the groups of the open steps for the user and every step and topic thread. Read-only. */
  app.get("/api/steps/topics", async (c) => {
    c.header("Cache-Control", "no-store");
    try { return c.json({ ok: true, ...(await stepTopics(store)) }); }
    catch (e) { return c.json({ ok: false, reason: String((e as Error).message).replace(/^fwcore: /, "") }, 422); }
  });

  /** `POST /api/steps/<step|topic>/<id>/question` {text, cid?}: the user's question on a step or a topic. The actor is `user`; the
   *  reducer accepts or refuses it. A repeated `cid` on the same subject is the same event. */
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
