// Routes for agents (capability-gated) and for observations. Mounted from app.ts with one line.
import type { Hono } from "hono";
import { AgentRequest } from "@fw/contracts";
import type { Store } from "../store.ts";
import { Drain } from "../spool/drain.ts";
import { CapStore, stamp } from "./cap.ts";

export function mountAgentRoutes(app: Hono, store: Store): { drain: Drain; caps: CapStore } {
  const caps = new CapStore(store.dir);
  caps.ensureSecret();
  const drain = new Drain(store);

  // The only door for `pnpm fw`: no valid, unused capability -> 403, and the reducer is never asked.
  app.post("/api/agent/commands", async (c) => {
    let body: unknown;
    try { body = await c.req.json(); } catch { return c.json({ ok: false, reason: "body is not JSON" }, 400); }
    const req = AgentRequest.safeParse(body);
    if (!req.success) return c.json({ ok: false, reason: "expected {argv: string[], command}" }, 400);
    const s = await caps.consume(req.data.argv);
    if (!s) {
      const miss = caps.lastMiss(); // the hook said why it minted nothing (notFwPrefix, trailingPipe); else the cap is missing, spent or stale
      const why = miss ? `; the capability hook says ${miss.reason}: ${miss.message}` : "";
      return c.json({ ok: false, reason: `no valid, unused capability for this command${why}`, ...(miss ? { cause: miss.reason } : {}) }, 403);
    }
    // one capability covers one `fw` invocation; `fw plan sync` sends its commands as one array (each stamped alike)
    if (Array.isArray(req.data.command)) {
      const replies = [];
      for (const raw of req.data.command) {
        const p = stamp(raw, s);
        if (!p.success) { replies.push({ ok: false, reason: p.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`).join("; ") }); continue; }
        replies.push(await store.submit(p.data));
      }
      const all = replies.every((r) => r.ok);
      return c.json({ ok: all, replies }, all ? 200 : 422);
    }
    const parsed = stamp(req.data.command, s);
    if (!parsed.success) {
      return c.json({ ok: false, reason: parsed.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`).join("; ") }, 400);
    }
    const reply = await store.submit(parsed.data);
    return c.json(reply, reply.ok ? 200 : 422);
  });

  app.post("/api/spool/drain", async (c) => c.json(await drain.run()));
  app.get("/api/obs/summary", async (c) => c.json(await drain.summary()));
  return { drain, caps };
}
