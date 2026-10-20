// HTTP glue for the task detail panel and the owner-only preview. The decisions are Lean (`console.preview*`).
// The route reads three facts from the request and passes them as a `Proof`; Lean maps them to an actor and admits
// only `user` (owner bearer token AND console Origin AND no console secret). Nothing in the body can claim an actor.
//   secret : the request shows the console secret (the runner's own tools, agents with the secret file)
//   cookie : (field name kept) the request carries a live owner bearer token; no cookie is an owner proof
//   origin : the Origin header is present and is this console's own origin
// Residual (INFERRED): a process of the same OS user that reads the owner link from the console's stdout or the
// owner token from the browser profile's localStorage. See research/notes/2026/10-18-task-preview.md.
import type { Hono } from "hono";
import { z } from "zod";
import type { Store } from "../store.ts";
import type { CapStore } from "../cap/cap.ts";
import { SECRET_HEADER } from "../cap/cap.ts";
import { workGraphRow, partsOf } from "./facts.ts";
import type { BuildAt, PreviewManager, Proof } from "./manager.ts";
import { OwnerAuth } from "./owner.ts";
import { buildRows, rowAt, readRegistry } from "./builds.ts";
import type { Grants } from "./grants.ts";
import { isLoopback } from "./lan.ts";
import { remoteOf } from "./gate.ts";
import { gitIn } from "./facts.ts";
import { mountCompose } from "./compose.ts";

const TaskId = z.string().regex(/^[a-z0-9][a-z0-9-]{0,80}$/);
const StartReq = z.object({ task: TaskId });
const StartBuild = z.object({ build: z.string().min(1).max(200) });
const Arm = z.enum(["r", "compare"]);
/** `{row}` opens a Builds row; `{search}` opens a pasted search in the main build. Neither names a commit, a path or a command. */
const OpenReq = z.union([z.object({ row: z.string().min(1).max(200), arm: Arm.optional() }), z.object({ search: z.string().max(4000), arm: Arm.optional() })]);

const kindOf = (id: string) => (id.startsWith("port-") ? "port" : id.startsWith("fix-") ? "fix" : "other");
const SRC_LABEL: Record<string, string> = {
  handoff: "handoff branch line", ci: "ci/<task>", originCi: "origin/ci/<task>", named: "branch named like the task",
  merge: "merge second parent", handoffCommit: "newest commit touching the handoff",
};

type Hdr = { req: { header(n: string): string | undefined } };

export function mountPreview(app: Hono, store: Store, caps: CapStore, pm: PreviewManager, owner: OwnerAuth, inspect?: { grants: Grants; lan: boolean }) {
  const proofOf = async (c: Hdr): Promise<Proof> => ({
    secret: caps.secretMatches(c.req.header(SECRET_HEADER)),
    cookie: owner.bearerOk(c.req.header("authorization")),
    origin: await owner.actionOk(store.core, "owner", true, c.req.header("origin"), c.req.header("host")), // Origin = a console origin, trusted list from Lean
  });
  const jsonOnly = (c: Hdr) => ((c.req.header("content-type") ?? "").includes("application/json") ? null : "content-type must be application/json");

  /** The one-time owner link: exchanges its token for an owner token, handed to the console web in the URL fragment (never
   *  sent to a server; the web moves it into localStorage and clears it), plus the preview-access cookie. */
  app.get("/owner", (c) => {
    const session = owner.redeem(c.req.query("t"));
    if (session === null) return c.json({ ok: false, reason: "owner link invalid or already used" }, 403);
    for (const ck of owner.previewCookieFor(session)) c.header("Set-Cookie", ck, { append: true });
    c.header("Cache-Control", "no-store");
    c.header("Referrer-Policy", "no-referrer");
    return c.redirect(`/#owner=${session}`, 303);
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
      canPreview: owner.bearerOk(c.req.header("authorization")), previewPort: owner.previewPort, // this browser sent a live owner token (Lean decides the rest per request)
    });
  });

  mountCompose(app, store.core, pm.root); // the Compose tab: variants, classes, explanations and the decision (Lean `console.compose`)

  app.get("/api/previews", (c) => c.json({ ok: true, ...pm.list(), previewPort: owner.previewPort }));

  /** The Builds tab: landed port/fix tasks and the flag and preset rows, all decided by Lean `console.builds`. Read-only. */
  app.get("/api/builds", async (c) => {
    const b = await buildRows(pm.root, store.core);
    return c.json({ ok: true, ...b, canPreview: owner.bearerOk(c.req.header("authorization")), previewPort: owner.previewPort, ...pm.list() });
  });

  /** Open a Builds row, or a pasted search in main's build (Lean `console.buildsOpen`, `console.buildsSearch`). The client sends a row id or
   *  a search string, never a commit or a path. A search is checked first (charset, then the site's rules) and is only ever a client-side
   *  query on a preview path. Start and stop keep the owner gate of `pm.start`/`pm.stop`; a serving preview is only linked, as in
   *  `GET /api/previews`. Replies: `open` (path and url to use now) or `pending` (a build of this commit runs: poll `GET /api/previews`
   *  for the id, then ask again). Asking again never starts a second build in the same slot (two slots at one commit can race; follow-up). */
  app.post("/api/builds/open", async (c) => {
    c.header("Cache-Control", "no-store");
    const bad = jsonOnly(c); if (bad) return c.json({ ok: false, reason: bad }, 403);
    let body: unknown;
    try { body = await c.req.json(); } catch { return c.json({ ok: false, reason: "body is not JSON" }, 400); }
    const req = OpenReq.safeParse(body);
    if (!req.success) return c.json({ ok: false, reason: "expected {row} or {search}" }, 400);
    const arm = req.data.arm ?? "r";
    const reg = readRegistry(pm.root);
    if ("search" in req.data) {
      const v = await store.core.ops("console.buildsSearch", { registry: reg, search: req.data.search });
      if (v.ok !== true) return c.json({ ok: false, reason: "search refused", reasons: v.reasons }, 422);
    }
    const port = owner.previewPort;
    if (port === null) return c.json({ ok: false, reason: "the preview port is not listening yet" }, 503);
    const previews = pm.list().previews.map((p) => ({ id: p.id, slot: p.task, sha: p.target.sha, serving: p.phase === "serving" }));
    const lanAddr = owner.lanPreviewAddr;
    const lan = { lan: lanAddr !== null, ...(lanAddr ? { lanAddr } : {}), port };
    let at: BuildAt;
    let o: Record<string, unknown>;
    if ("row" in req.data) {
      const row = rowAt(await buildRows(pm.root, store.core), req.data.row);
      if (!row) return c.json({ ok: false, reason: "unknown build row" }, 404);
      at = row;
      o = await store.core.ops("console.buildsOpen", { mode: "row", arm, slot: row.slot, sha: row.target.sha, search: row.search, previews, ...lan });
    } else {
      const main = (gitIn(pm.root)(["rev-parse", "main"]) ?? "").trim();
      if (!main) return c.json({ ok: false, reason: "no main commit" }, 409);
      o = await store.core.ops("console.buildsOpen", { mode: "search", arm, main, search: req.data.search, registry: reg, previews, ...lan });
      at = { slot: String(o.slot), target: { kind: "main", ref: "main", sha: main }, search: "" };
    }
    if (o.ok !== true) return c.json({ ok: false, reason: "search refused", reasons: o.reasons }, 422);
    const canonical = String(o.canonical);
    if (o.act === "reuse") return c.json({ ok: true, state: "open", preview: o.preview, path: o.path, url: o.url, canonical });
    if (o.act === "wait") return c.json({ ok: true, state: "pending", preview: o.preview, canonical }, 202);
    const proof = await proofOf(c);
    if (o.act === "rebuild") {
      const s = await pm.stop(String(o.preview), proof);
      if (!s.ok) return c.json({ ok: false, reason: s.reason }, s.reason === "notOwner" ? 403 : 409);
    }
    const r = await pm.start(at.slot, proof, at);
    if (!r.ok) return c.json(r, r.reason === "notOwner" ? 403 : 409);
    return c.json({ ok: true, state: "pending", preview: r.id, canonical }, 202);
  });

  /** An inspect grant for the lead and agents (preview-inspect): `{id?}` -> a one-time link on the preview port. Lean
   *  `console.previewGrant` allows it only for a loopback request; the link opens preview paths only, for at most an hour. */
  if (inspect) app.post("/api/preview/grant", async (c) => {
    c.header("Cache-Control", "no-store");
    const bad = jsonOnly(c); if (bad) return c.json({ ok: false, reason: bad }, 403);
    // a page of another origin (a preview) may not ask: the Origin, when present, must be a console origin
    if (!(await owner.actionOk(store.core, "command", false, c.req.header("origin"), c.req.header("host")))) return c.json({ ok: false, reason: "refused: not from the console origin" }, 403);
    const body = await c.req.json().catch(() => ({})) as { id?: unknown; arm?: unknown };
    let id: string | null = null;
    if (body.id !== undefined && body.id !== null) {
      if (typeof body.id !== "string" || !/^[a-z0-9][a-z0-9-]{0,100}$/.test(body.id)) return c.json({ ok: false, reason: "bad preview id" }, 400);
      if (!pm.serving(body.id)) return c.json({ ok: false, reason: "no such running preview" }, 404);
      id = body.id;
    }
    const port = owner.previewPort;
    if (port === null) return c.json({ ok: false, reason: "the preview port is not listening yet" }, 503);
    const arm = body.arm === "o" ? "o" : "r";
    const lan = inspect.lan && !isLoopback(remoteOf(c));
    const g = await inspect.grants.issue(lan, id ? `/preview/${id}/${arm}/` : null);
    if (!g.ok) return c.json({ ok: false, reason: "grants are issued to loopback requests only" }, 403);
    return c.json({ ok: true, url: `http://127.0.0.1:${port}/__grant?t=${g.token}`, expiresInSec: Math.floor(g.ttlMs / 1000) });
  });

  app.post("/api/previews", async (c) => {
    const bad = jsonOnly(c); if (bad) return c.json({ ok: false, reason: bad }, 403);
    let body: unknown;
    try { body = await c.req.json(); } catch { return c.json({ ok: false, reason: "body is not JSON" }, 400); }
    const req = StartReq.or(StartBuild).safeParse(body);
    if (!req.success) return c.json({ ok: false, reason: "expected {task} or {build}" }, 400);
    let r;
    if ("build" in req.data) {
      const at = rowAt(await buildRows(pm.root, store.core), req.data.build);
      if (!at) return c.json({ ok: false, reason: "unknown build row" }, 404);
      r = await pm.start(at.slot, await proofOf(c), at);
    } else r = await pm.start(req.data.task, await proofOf(c));
    if (!r.ok) return c.json(r, r.reason === "notOwner" ? 403 : 409);
    return c.json({ ok: true, id: r.id, preview: r.entry }, 202);
  });

  app.post("/api/previews/:id/stop", async (c) => {
    const bad = jsonOnly(c); if (bad) return c.json({ ok: false, reason: bad }, 403);
    const r = await pm.stop(c.req.param("id"), await proofOf(c));
    return c.json(r, r.ok ? 200 : r.reason === "notOwner" ? 403 : 404);
  });
}
