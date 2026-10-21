// Feedback threads on the review cards (review-feedback). The user's comments and the lead's replies are the events
// `review.feedback` and `review.feedback.reply`; the thread of a flag, its open count, who may write which event, which `to` a
// reply may name and the text cap are Lean (`Fw.Console.ReviewFeedback`; the reducer decides, `console.reviewFeedback` projects
// the log). This file reads the log's feedback events, hands them to Lean, and submits the user's comment. It decides nothing.
import { randomBytes } from "node:crypto";
import type { Hono } from "hono";
import { z } from "zod";
import type { Store } from "../store.ts";

/** One comment as Lean returns it. */
export interface Comment { id: string; text: string; at: number; status: "open" | "answered"; reply: { text: string; at: number } | null }
export interface Thread { flag: string; open: number; comments: Comment[] }

/** The feedback events of the log, in log order (the log is the only record). */
async function feedbackEvents(store: Store): Promise<unknown[]> {
  return (await store.readEvents()).filter((e) => e.type === "review.feedback" || e.type === "review.feedback.reply");
}

/** The threads Lean projects from the log; with `flag`, just that flag's thread (empty when it has no comment). */
export async function threads(store: Store, flag?: string): Promise<Thread[]> {
  const r = await store.core.ops("console.reviewFeedback", { events: await feedbackEvents(store), ...(flag ? { flag } : {}) });
  return (r as unknown as { threads: Thread[] }).threads;
}

/** Per flag: its thread, for `GET /api/reviews`. */
export async function feedbackInfo(store: Store): Promise<Record<string, Thread>> {
  return Object.fromEntries((await threads(store)).map((t) => [t.flag, t]));
}

/** `cid`: a client-made id for a retry-safe send (letters, digits, dash; no crypto needed, so a plain-http LAN page can make one). */
const Req = z.object({ text: z.string().max(20_000), cid: z.string().regex(/^[A-Za-z0-9-]{8,60}$/).optional() });
const mintId = () => `fb-${Date.now().toString(36)}-${randomBytes(4).toString("hex")}`;

export function mountReviewFeedback(app: Hono, store: Store) {
  /** `GET /api/reviews/feedback`: every thread. Read-only. */
  app.get("/api/reviews/feedback", async (c) => {
    c.header("Cache-Control", "no-store");
    return c.json({ ok: true, threads: await threads(store) });
  });

  /** `GET /api/reviews/<flag>/feedback`: one flag's thread. */
  app.get("/api/reviews/:flag/feedback", async (c) => {
    c.header("Cache-Control", "no-store");
    try { return c.json({ ok: true, thread: (await threads(store, c.req.param("flag")))[0] }); }
    catch (e) { return c.json({ ok: false, reason: String((e as Error).message).replace(/^fwcore: /, "") }, 422); }
  });

  /** `POST /api/reviews/<flag>/feedback` {text, cid?}: the user's comment. The actor is `user` (the owner session behind the gate); the
   *  reducer accepts or refuses it. A repeated `cid` on the same flag is the same event (a duplicate, not a second comment); the key holds the flag, so the same `cid` on another flag is a new event that the reducer refuses (ids are unique). */
  app.post("/api/reviews/:flag/feedback", async (c) => {
    c.header("Cache-Control", "no-store");
    let body: unknown;
    try { body = await c.req.json(); } catch { return c.json({ ok: false, reason: "body is not JSON" }, 400); }
    const req = Req.safeParse(body);
    if (!req.success) return c.json({ ok: false, reason: "expected {text}" }, 400);
    const flag = c.req.param("flag");
    const id = req.data.cid ? `fb-${req.data.cid}` : mintId();
    const reply = await store.submit({ type: "review.feedback", key: `review-feedback-${flag}-${id}`, actor: "user", flag, id, text: req.data.text } as never);
    if (!reply.ok) return c.json(reply, 422);
    return c.json({ ...reply, id, thread: (await threads(store, flag))[0] });
  });
}
