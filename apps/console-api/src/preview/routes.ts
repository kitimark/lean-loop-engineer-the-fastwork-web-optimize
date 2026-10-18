// HTTP glue for the task detail panel and the owner-only preview. The decisions are Lean (`console.preview*`); the actor
// is stamped here, never read from the body: a caller that shows the console secret (the runner's own tools, agents
// with the secret file) is stamped `lead`, which Lean refuses. The browser (no secret) is `user`.
// Not proof against an agent that sends no secret and no Origin (same user id, same loopback): INFERRED limit, see
// research/notes/2026/10-18-task-preview.md.
import type { Hono } from "hono";
import { z } from "zod";
import type { Store } from "../store.ts";
import type { CapStore } from "../cap/cap.ts";
import { SECRET_HEADER } from "../cap/cap.ts";
import { workGraphRow, partsOf } from "./facts.ts";
import type { PreviewManager } from "./manager.ts";

const TaskId = z.string().regex(/^[a-z0-9][a-z0-9-]{0,80}$/);
const StartReq = z.object({ task: TaskId });
const LOOPBACK = /^https?:\/\/(127\.0\.0\.1|localhost|\[::1\])(:\d+)?$/;

const kindOf = (id: string) => (id.startsWith("port-") ? "port" : id.startsWith("fix-") ? "fix" : "other");

export function mountPreview(app: Hono, store: Store, caps: CapStore, pm: PreviewManager) {
  /** a browser page on another origin must not be able to drive the console (the console binds loopback only) */
  const guard = (c: { req: { header(n: string): string | undefined } }) => {
    const origin = c.req.header("origin");
    if (origin && !LOOPBACK.test(origin)) return "origin not allowed";
    if (!(c.req.header("content-type") ?? "").includes("application/json")) return "content-type must be application/json";
    return null;
  };
  const actorOf = (c: { req: { header(n: string): string | undefined } }) => (caps.secretMatches(c.req.header(SECRET_HEADER)) ? "lead" : "user");

  app.get("/api/tasks/:id/detail", async (c) => {
    const id = TaskId.safeParse(c.req.param("id"));
    if (!id.success) return c.json({ ok: false, reason: "bad task id" }, 400);
    const row = workGraphRow(pm.root, id.data);
    const plan = (await store.board()).plan.tasks.find((t) => t.id === id.data) ?? null;
    if (!row && !plan) return c.json({ ok: false, reason: "unknown task" }, 404);
    const facts = pm.facts(id.data);
    const target = await pm.target(id.data, facts);
    const running = pm.list().previews.find((p) => p.task === id.data) ?? null;
    const lines = facts.handoff?.text.split("\n") ?? [];
    return c.json({
      ok: true, task: id.data, kind: kindOf(id.data), title: row?.title ?? plan?.title ?? "",
      state: plan?.state ?? null, owner: plan?.owner ?? row?.owner ?? null, agent: plan?.agent ?? null, evidence: plan?.evidence ?? null,
      deps: row?.deps ?? plan?.deps ?? [], blockers: plan?.blockers ?? [], writes: row?.writes ?? [], parts: partsOf(row?.writes ?? []),
      git: { head: facts.head, headSource: facts.headSource, branch: facts.branch, onMain: facts.onMain, mainSha: facts.mainSha, containedIn: facts.containedIn },
      handoff: facts.handoff ? { ref: facts.handoff.ref, excerpt: lines.slice(0, 40).join("\n"), lines: lines.length } : null,
      preview: { target, running },
    });
  });

  app.get("/api/previews", (c) => c.json({ ok: true, ...pm.list() }));

  app.post("/api/previews", async (c) => {
    const bad = guard(c); if (bad) return c.json({ ok: false, reason: bad }, 403);
    let body: unknown;
    try { body = await c.req.json(); } catch { return c.json({ ok: false, reason: "body is not JSON" }, 400); }
    const req = StartReq.safeParse(body);
    if (!req.success) return c.json({ ok: false, reason: "expected {task}" }, 400);
    const r = await pm.start(req.data.task, actorOf(c));
    if (!r.ok) return c.json(r, r.reason === "notOwner" ? 403 : 409);
    return c.json({ ok: true, id: r.id, preview: r.entry }, 202);
  });

  app.post("/api/previews/:id/stop", async (c) => {
    const bad = guard(c); if (bad) return c.json({ ok: false, reason: bad }, 403);
    const r = await pm.stop(c.req.param("id"), actorOf(c));
    return c.json(r, r.ok ? 200 : r.reason === "notOwner" ? 403 : 404);
  });
}
