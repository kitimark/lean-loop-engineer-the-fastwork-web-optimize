// Preview of a look-change review (review-preview-devices). Which arm and search a Preview button opens, which device the viewport
// width means, whether the review may be previewed at all, and which devices are still unchecked are Lean `console.reviewPreview`
// (Fw.Console.ReviewPreview). This file hands Lean the board steps and the accepted `review.previewed` events, and submits the one
// event Lean plans. It decides nothing. The page opens the build itself through `POST /api/builds/open` (the task-preview machinery).
import type { Hono } from "hono";
import { z } from "zod";
import type { Store } from "../store.ts";

/** What the card shows about previews, as Lean returns it. */
export interface PreviewInfo { open: boolean; desktop: boolean; phone: boolean; missing: string[]; asks: string[] }

interface Plan { ok: boolean; reason?: string; view?: string; search?: string; arm?: "r" | "compare"; slot?: string; device?: string; key?: string;
  event?: { type: string; flag: string; device: string }; carries?: boolean }
interface Reply { items: (PreviewInfo & { flag: string })[]; plan: Plan | null }

/** The accepted preview events of the log in the shape Lean reads ({flag, device, key}). Lean places each event in a review round by
 *  the round tag of its key (Fw.Console.ReviewPreview.roundOfKey), never by log position. The log is the only record. */
async function seen(store: Store): Promise<{ events: { flag: string; device: string; key?: string }[] }> {
  const events: { flag: string; device: string; key?: string }[] = [];
  for (const e of await store.readEvents()) {
    const x = e as unknown as { type?: string; flag?: unknown; device?: unknown; key?: unknown };
    if (x.type === "review.previewed" && typeof x.flag === "string" && typeof x.device === "string")
      events.push({ flag: x.flag, device: x.device, ...(typeof x.key === "string" ? { key: x.key } : {}) });
  }
  return { events };
}

async function ask(store: Store, click?: { flag: string; view: string; width: number }): Promise<Reply> {
  const steps = (await store.board()).steps.map((s) => ({ id: s.id, answer: s.answer, open: s.status === "waiting" || s.status === "started" }));
  return (await store.core.ops("console.reviewPreview", { steps, ...(await seen(store)),...(click ? { ask: click } : {}) })) as unknown as Reply;
}

/** Per flag: the previewed devices and the ask lines, for `GET /api/reviews`. */
export async function previewInfo(store: Store): Promise<Record<string, PreviewInfo>> {
  const r = await ask(store);
  return Object.fromEntries(r.items.map(({ flag, ...i }) => [flag, i]));
}

const Req = z.object({ view: z.string().max(20), width: z.number().int().min(0).max(100_000), done: z.boolean().optional() });

/** `POST /api/reviews/<flag>/preview` {view: flag|faithful|compare, width, done?}. Without `done` it answers the arm and search to open
 *  (nothing is recorded). With `done` (the page opened) it records the user's `review.previewed` for the device the width means. */
export function mountReviewPreview(app: Hono, store: Store, previewPort: () => number | null) {
  app.post("/api/reviews/:flag/preview", async (c) => {
    c.header("Cache-Control", "no-store");
    let body: unknown;
    try { body = await c.req.json(); } catch { return c.json({ ok: false, reason: "body is not JSON" }, 400); }
    const req = Req.safeParse(body);
    if (!req.success) return c.json({ ok: false, reason: "expected {view: flag|faithful|compare, width}" }, 400);
    let r: Reply;
    try { r = await ask(store, { flag: c.req.param("flag"), view: req.data.view, width: req.data.width }); }
    catch (e) { return c.json({ ok: false, reason: String((e as Error).message).replace(/^fwcore: /, "") }, 422); }
    const p = r.plan;
    if (!p || !p.ok || !p.event || !p.key) return c.json({ ok: false, reason: p?.reason ?? "refused" }, 422);
    // Lean checks that the search names the flag by a whole entry (flag and compare views) or by none (faithful view).
    if (p.carries !== true) return c.json({ ok: false, reason: "the search does not carry the flag exactly" }, 500);
    if (req.data.done) {
      const e = p.event;
      const reply = await store.submit({ type: "review.previewed", key: p.key, actor: "user", flag: e.flag, device: e.device } as never);
      if (!reply.ok) return c.json(reply, 422);
    }
    const fresh = (await ask(store)).items.find((i) => i.flag === c.req.param("flag"));
    return c.json({ ok: true, view: p.view, search: p.search, arm: p.arm, slot: p.slot, device: p.device, previewPort: previewPort(),
      recorded: req.data.done === true, ...(fresh ? { preview: { desktop: fresh.desktop, phone: fresh.phone, missing: fresh.missing, asks: fresh.asks } } : {}) });
  });
}
