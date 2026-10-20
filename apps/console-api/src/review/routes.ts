// The review queue (user-review-queue): which kept look changes wait for the owner's visual review is Lean `console.review`
// (Fw.Console.Review). This file posts the step Lean says is missing, attaches the ledger's words and the review material, and
// turns an accepted Keep or Reject into a `step.answer` of the user. It decides nothing.
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import type { Hono } from "hono";
import { z } from "zod";
import type { Store } from "../store.ts";
import { readLedger } from "../preview/compose.ts";

/** The review material of a flag: what exists and where it can be fetched. Facts of the run, not decisions. */
export interface Material {
  chromium: { state: "ready" | "pending"; run?: string; artifact?: string; expires?: string; task?: string };
  webkit: { state: "ready" | "pending"; run?: string; artifact?: string; expires?: string; task?: string };
}

/** Review material by flag. Chromium strips: CI run 39473950464, artifact frames-chromium, expires 2026-11-19. WebKit: task earn-look-review-webkit. */
export const MATERIAL: Record<string, Material> = {
  "nav:earn-no-transition": {
    chromium: { state: "ready", run: "39473950464", artifact: "frames-chromium", expires: "2026-11-19" },
    webkit: { state: "pending", task: "earn-look-review-webkit" },
  },
};

const Links = z.record(z.string(), z.string().regex(/^https:\/\/\S+$/));

/** The private review page links of `.local/reviews.json` ({"<flag>": "<url>"}). A missing or unreadable file gives none. */
export function readLinks(root: string): Record<string, string> {
  const f = join(root, ".local/reviews.json");
  if (!existsSync(f)) return {};
  try {
    const r = Links.safeParse(JSON.parse(readFileSync(f, "utf8")));
    return r.success ? r.data : {};
  } catch { return {}; }
}

interface LeanItem {
  flag: string; step: string; date: string; words: string; state: "open" | "keep" | "reject"; post: boolean; title: string; body: string; audience: string;
}
interface LeanReply { items: LeanItem[]; open: number; options: string[]; answer: { ok: boolean; reason?: string; step?: string; word?: string } | null }

async function ask(store: Store, answer?: { flag: string; word: string }): Promise<LeanReply> {
  const steps = (await store.board()).steps.map((s) => ({ id: s.id, answer: s.answer }));
  return (await store.core.ops("console.review", { steps, ...(answer ? { answer } : {}) })) as unknown as LeanReply;
}

/** Post the steps Lean names as missing (single writer: the store); the reducer refuses a second post of one id. */
async function post(store: Store, r: LeanReply): Promise<LeanReply> {
  let posted = false;
  for (const i of r.items) {
    if (!i.post) continue;
    await store.submit({ type: "step.post", key: `review-post-${i.flag}`, actor: "script", step: i.step, card: null, title: i.title,
      kind: "choice", options: r.options, audience: "user", body: i.body });
    posted = true;
  }
  return posted ? ask(store) : r;
}

export function mountReviews(app: Hono, store: Store, root: string) {
  /** `GET /api/reviews`: the Lean items with what changed, the material and the private link (when `.local/reviews.json` has one). */
  app.get("/api/reviews", async (c) => {
    c.header("Cache-Control", "no-store");
    const r = await post(store, await ask(store));
    const ledger = readLedger(root).findings;
    const links = readLinks(root);
    return c.json({
      ok: true, open: r.open, options: r.options,
      items: r.items.map((i) => {
        const row = ledger.find((x) => x.flag === i.flag);
        return {
          flag: i.flag, step: i.step, state: i.state, date: i.date, words: i.words, audience: i.audience,
          changed: row ? { id: row.id ?? null, candidate: row.candidate, visual: row.visual ?? null, chromium: row.chromium ?? null, webkit: row.webkit ?? null } : null,
          material: MATERIAL[i.flag] ?? null,
          link: links[i.flag] ?? null,
        };
      }),
    });
  });

  /** `POST /api/reviews/<flag>` {decision: keep|reject}: Lean accepts or refuses; an accepted answer is the user's `step.answer`. */
  app.post("/api/reviews/:flag", async (c) => {
    let body: unknown;
    try { body = await c.req.json(); } catch { return c.json({ ok: false, reason: "body is not JSON" }, 400); }
    const parsed = z.object({ decision: z.string().max(20) }).safeParse(body);
    if (!parsed.success) return c.json({ ok: false, reason: "expected {decision: keep|reject}" }, 400);
    const flag = c.req.param("flag");
    await post(store, await ask(store));
    let a: LeanReply["answer"];
    try { a = (await ask(store, { flag, word: parsed.data.decision })).answer; } catch (e) {
      return c.json({ ok: false, reason: String((e as Error).message).replace(/^fwcore: /, "") }, 422); // Lean refused the request (a flag that is no key)
    }
    if (!a || !a.ok || !a.step || !a.word) return c.json({ ok: false, reason: a?.reason ?? "refused" }, 422);
    const reply = await store.submit({ type: "step.answer", key: `review-answer-${flag}-${a.word}`, actor: "user", step: a.step, answer: a.word });
    return c.json(reply, reply.ok ? 200 : 422);
  });
}
