// HTTP glue: POST /api/reconcile (run a pass now), GET /api/land/:card (readiness read from the board,
// where `stage` is computed by Lean; `ready` is just stage == land_ready).
import type { Hono } from "hono";
import type { Store } from "../store.ts";
import type { Reconciler } from "./reconciler.ts";

export function mountReconcile(app: Hono, store: Store, rec: Reconciler) {
  app.post("/api/reconcile", async (c) => c.json(await rec.reconcile()));
  app.get("/api/land/:card", async (c) => {
    await rec.reconcile();
    const b = await store.board();
    const card = b.cards.find((x) => x.id === c.req.param("card"));
    if (!card) return c.json({ ok: false, reason: "no such card" }, 404);
    return c.json({ ok: true, card: card.id, stage: card.stage, head: card.head, landed: card.landed,
      violation: card.violation, stale: card.stale, ready: card.stage === "land_ready", next: card.next });
  });
}
