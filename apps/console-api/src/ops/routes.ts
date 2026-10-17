// HTTP glue for pure Lean ops that clients (the `fw` CLI) need: the decision is made by fwcore, not here.
import type { Hono } from "hono";
import { z } from "zod";
import type { Store } from "../store.ts";

const PathCheckReq = z.object({ scope: z.array(z.string()), paths: z.array(z.string()) });

const LandScopeReq = z.object({
  writes: z.array(z.string()), names: z.array(z.string()).optional(), allow: z.array(z.string()).optional(), paths: z.array(z.string()),
  task: z.string().optional(), stream: z.string().optional(), // the task kind (port-*, proof-*, measure) adds its registration set
});

export function mountOps(app: Hono, store: Store) {
  /** `ops.pathCheck`: which of `paths` fall outside `scope` (globs, `!` excludes) */
  app.post("/api/ops/path-check", async (c) => {
    let body: unknown;
    try { body = await c.req.json(); } catch { return c.json({ ok: false, reason: "body is not JSON" }, 400); }
    const req = PathCheckReq.safeParse(body);
    if (!req.success) return c.json({ ok: false, reason: "expected {scope: string[], paths: string[]}" }, 400);
    const r = await store.core.ops("ops.pathCheck", req.data);
    return c.json({ ok: r.ok === true, violations: r.violations ?? [] });
  });

  /** `console.landScope` (Fw.Console.Land): may these changed paths land for a task with these write globs? */
  app.post("/api/ops/land-scope", async (c) => {
    let body: unknown;
    try { body = await c.req.json(); } catch { return c.json({ ok: false, reason: "body is not JSON" }, 400); }
    const req = LandScopeReq.safeParse(body);
    if (!req.success) return c.json({ ok: false, reason: "expected {writes, names?, allow?, paths: string[]}" }, 400);
    const r = await store.core.ops("console.landScope", req.data);
    return c.json({ ok: r.ok === true, reason: r.reason ?? null, violations: r.violations ?? [], scope: r.scope ?? [] });
  });
}
