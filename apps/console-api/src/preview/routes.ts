// HTTP glue for the task detail panel and the owner-only preview. The decisions are Lean (`console.preview*`).
// The route reads three facts from the request and passes them as a `Proof`; Lean maps them to an actor and admits
// only `user` (owner cookie AND same-origin Origin AND no console secret). Nothing in the body can claim an actor.
//   secret : the request shows the console secret (the runner's own tools, agents with the secret file)
//   cookie : the HttpOnly SameSite=Strict cookie that the one-time owner link set in the user's browser
//   origin : the Origin header is present and is this console's own origin
// Residual (INFERRED): a process of the same OS user that reads the owner link from the console's stdout or the
// cookie from the browser profile. See research/notes/2026/10-18-task-preview.md.
import type { Hono } from "hono";
import { z } from "zod";
import type { Store } from "../store.ts";
import type { CapStore } from "../cap/cap.ts";
import { SECRET_HEADER } from "../cap/cap.ts";
import { workGraphRow, partsOf } from "./facts.ts";
import type { PreviewManager, Proof } from "./manager.ts";
import { OwnerAuth } from "./owner.ts";

const TaskId = z.string().regex(/^[a-z0-9][a-z0-9-]{0,80}$/);
const StartReq = z.object({ task: TaskId });

const kindOf = (id: string) => (id.startsWith("port-") ? "port" : id.startsWith("fix-") ? "fix" : "other");
const SRC_LABEL: Record<string, string> = {
  handoff: "handoff branch line", ci: "ci/<task>", originCi: "origin/ci/<task>", named: "branch named like the task",
  merge: "merge second parent", handoffCommit: "newest commit touching the handoff",
};

type Hdr = { req: { header(n: string): string | undefined } };

export function mountPreview(app: Hono, store: Store, caps: CapStore, pm: PreviewManager, owner: OwnerAuth) {
  const proofOf = (c: Hdr): Proof => ({
    secret: caps.secretMatches(c.req.header(SECRET_HEADER)),
    cookie: owner.cookieOk(c.req.header("cookie")),
    origin: owner.originOk(c.req.header("origin"), c.req.header("host")),
  });
  const jsonOnly = (c: Hdr) => ((c.req.header("content-type") ?? "").includes("application/json") ? null : "content-type must be application/json");

  /** The one-time owner link: exchanges its token for the owner cookie, then goes to the console. */
  app.get("/owner", (c) => {
    const session = owner.redeem(c.req.query("t"));
    if (session === null) return c.json({ ok: false, reason: "owner link invalid or already used" }, 403);
    c.header("Set-Cookie", OwnerAuth.setCookie(session));
    c.header("Cache-Control", "no-store");
    return c.redirect("/", 303);
  });

  app.get("/api/tasks/:id/detail", async (c) => {
    const id = TaskId.safeParse(c.req.param("id"));
    if (!id.success) return c.json({ ok: false, reason: "bad task id" }, 400);
    const row = workGraphRow(pm.root, id.data);
    const plan = (await store.board()).plan.tasks.find((t) => t.id === id.data) ?? null;
    if (!row && !plan) return c.json({ ok: false, reason: "unknown task" }, 404);
    const facts = pm.facts(id.data);
    const d = await pm.decision(id.data, facts);
    const running = pm.list().previews.find((p) => p.task === id.data) ?? null;
    const lines = facts.handoff?.text.split("\n") ?? [];
    const hf = d.headSrc ? facts.facts.find((f) => f.src === d.headSrc) : undefined;
    return c.json({
      ok: true, task: id.data, kind: kindOf(id.data), title: row?.title ?? plan?.title ?? "",
      state: plan?.state ?? null, owner: plan?.owner ?? row?.owner ?? null, agent: plan?.agent ?? null, evidence: plan?.evidence ?? null,
      deps: row?.deps ?? plan?.deps ?? [], blockers: plan?.blockers ?? [], writes: row?.writes ?? [], parts: partsOf(row?.writes ?? []),
      git: {
        head: d.head, headSource: d.headSrc ? SRC_LABEL[d.headSrc] ?? d.headSrc : facts.children.length > 0 ? "sub-tasks" : "none",
        branch: d.headSrc ? facts.refOf[d.headSrc] ?? null : null, onMain: hf?.onMain ?? false, mainSha: facts.mainSha,
        containedIn: (hf?.cands ?? []).filter((x) => x.contains).map((x) => x.ref),
      },
      handoff: facts.handoff ? { ref: facts.handoff.ref, excerpt: lines.slice(0, 40).join("\n"), lines: lines.length } : null,
      preview: { target: { kind: d.kind, ref: d.ref, sha: d.sha }, running },
      canPreview: proofOf(c).cookie, // this browser holds the owner cookie (Lean decides the rest per request)
    });
  });

  app.get("/api/previews", (c) => c.json({ ok: true, ...pm.list() }));

  app.post("/api/previews", async (c) => {
    const bad = jsonOnly(c); if (bad) return c.json({ ok: false, reason: bad }, 403);
    let body: unknown;
    try { body = await c.req.json(); } catch { return c.json({ ok: false, reason: "body is not JSON" }, 400); }
    const req = StartReq.safeParse(body);
    if (!req.success) return c.json({ ok: false, reason: "expected {task}" }, 400);
    const r = await pm.start(req.data.task, proofOf(c));
    if (!r.ok) return c.json(r, r.reason === "notOwner" ? 403 : 409);
    return c.json({ ok: true, id: r.id, preview: r.entry }, 202);
  });

  app.post("/api/previews/:id/stop", async (c) => {
    const bad = jsonOnly(c); if (bad) return c.json({ ok: false, reason: bad }, 403);
    const r = await pm.stop(c.req.param("id"), proofOf(c));
    return c.json(r, r.ok ? 200 : r.reason === "notOwner" ? 403 : 404);
  });
}
