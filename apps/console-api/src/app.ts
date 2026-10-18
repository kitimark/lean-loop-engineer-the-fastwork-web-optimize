import { existsSync, readFileSync } from "node:fs";
import { extname, join, normalize } from "node:path";
import { Hono } from "hono";
import { streamSSE } from "hono/streaming";
import { Command } from "@fw/contracts";
import type { Store } from "./store.ts";
import { mountReconcile } from "./reconcile/routes.ts";
import type { Reconciler } from "./reconcile/reconciler.ts";
import { mountAgentRoutes } from "./cap/routes.ts";
import { SECRET_HEADER, openDoor } from "./cap/cap.ts";
import { mountOps } from "./ops/routes.ts";
import { readLatestHealth } from "./health.ts";
import { mountPreview } from "./preview/routes.ts";
import type { PreviewManager } from "./preview/manager.ts";
import { OwnerAuth } from "./preview/owner.ts";
import { mountOwnerGate } from "./preview/gate.ts";
import { LoginGuard } from "./preview/login.ts";

/** Owner login and LAN mode (console-lan-owner): the login guard and whether LAN requests are possible at all. */
export interface GateOptions { login: LoginGuard; lan: boolean }

const MIME: Record<string, string> = {
  ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".svg": "image/svg+xml", ".json": "application/json",
};

/** Which code this process runs: the commit of its checkout when it started (its base) and the start time (ms,
 *  informational). `fw watch` asks whether the range base..main touches the process's input files (fwcore `svc.stale`);
 *  api.json also holds the build commit of the fwcore child (`coreCommit`, or `coreUnknown`). */
export interface ServiceInfo { commit: string | null; startedAt: number }

export function createApp(store: Store, webDist?: string, reconciler?: Reconciler, previews?: PreviewManager, owner: OwnerAuth = new OwnerAuth(), service?: ServiceInfo, gate?: GateOptions) {
  const app = new Hono();
  // a failed core call (fwcore crash, bad reply) fails the request; the core restarts itself
  app.onError((e, c) => c.json({ ok: false, reason: `decision core failed: ${e.message}` }, 500));
  // No page of another origin (a task preview) may frame the console: clickjacking would ride the owner's own token.
  app.use("*", async (c, next) => {
    c.header("X-Frame-Options", "DENY");
    c.header("Content-Security-Policy", "frame-ancestors 'none'");
    await next();
  });
  // The owner gate runs first on every request (Lean `console.ownerGate`); with previews it is always on, because previews are
  // served only to an owner session. Without LAN mode every request is loopback and only `/preview/*` is gated.
  if (previews || gate) {
    const g = gate ?? { login: new LoginGuard(store.core, null), lan: false };
    mountOwnerGate(app, { core: store.core, owner, login: g.login, lan: g.lan });
  }

  // Every state-changing route (all non-GET; the login excepted, it judges its own Origin) passes the one Lean gate
  // `console.ownerAction` kind `command`: an `Origin` header, when there is one, must be a console origin (Lean
  // `preview_origin_refused`, `computed_trusted_refuses_preview`). Command-line tools send none and meet the actor door
  // below. Owner routes then also need the bearer token (`owner_requires_bearer`).
  app.use("*", async (c, next) => {
    const m = c.req.method;
    if (m === "GET" || m === "HEAD" || c.req.path === "/owner/login") return next();
    if (!(await owner.actionOk(store.core, "command", false, c.req.header("origin"), c.req.header("host")))) {
      return c.json({ ok: false, reason: "refused: the Origin of this request is not the console" }, 403);
    }
    return next();
  });

  // Typed commands only. 400 = not a valid command; 422 = the reducer refused it, with the reason.
  app.post("/api/commands", async (c) => {
    let body: unknown;
    try { body = await c.req.json(); } catch { return c.json({ ok: false, reason: "body is not JSON" }, 400); }
    const parsed = Command.safeParse(body);
    if (!parsed.success) {
      return c.json({ ok: false, reason: parsed.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`).join("; ") }, 400);
    }
    // The door has no capability: an agent actor (lead/owner/reviewer) in the body is the self-declared kind the
    // capability door exists to prevent. Lean `Fw.Ops.Identity.openDoor`: it passes only with the console secret.
    if (!openDoor(parsed.data.actor, caps.secretMatches(c.req.header(SECRET_HEADER)))) {
      return c.json({ ok: false, reason: `actor ${parsed.data.actor} needs a capability: use \`pnpm fw\` (this door takes user, script, git, hook)` }, 403);
    }
    const reply = await store.submit(parsed.data);
    return c.json(reply, reply.ok ? 200 : 422);
  });

  mountOps(app, store);
  if (reconciler) mountReconcile(app, store, reconciler);
  const { drain, caps } = mountAgentRoutes(app, store); // capability-gated agent door + spool drain
  if (previews) mountPreview(app, store, caps, previews, owner); // task detail panel + owner-only preview (task-preview)
  app.get("/api/board", async (c) => c.json(await store.board()));
  app.get("/api/plan", async (c) => c.json((await store.board()).plan)); // the work graph, derived by fwcore
  // latest `fw watch` check (fwcore obs.health output) with the running code's `service` ({commit, startedAt}), or null
  // before any check; GET /api/service is the same `service` object without needing a check
  app.get("/api/health", (c) => {
    c.header("x-fw-console-pid", String(process.pid)); // lets `owner-link` prove which process it signals
    const h = readLatestHealth(store.dir);
    return c.json(h && service ? { ...h, service } : h);
  });
  app.get("/api/service", (c) => c.json(service ?? null));
  app.get("/api/events", (c) => {
    const since = Number(c.req.query("since") ?? 0);
    return c.json(store.readEvents().filter((e) => e.seq > since));
  });

  app.get("/api/stream", (c) =>
    streamSSE(c, async (stream) => {
      let closed = false;
      let wake: (() => void) | null = null;
      const push = () => wake?.();
      const off = store.subscribe(push);
      stream.onAbort(() => { closed = true; off(); push(); });
      const send = async () => stream.writeSSE({ event: "board", data: JSON.stringify(await store.board()) });
      await send();
      while (!closed) {
        await new Promise<void>((res) => { wake = res; setTimeout(res, 15000); });
        if (closed) break;
        await send(); // also serves as heartbeat
      }
    }));

  if (webDist && existsSync(webDist)) {
    app.get("*", (c) => {
      const p = normalize(c.req.path).replace(/^(\.\.[/\\])+/, "");
      let file = join(webDist, p);
      if (!existsSync(file) || extname(file) === "") file = join(webDist, "index.html");
      return c.body(readFileSync(file), 200, { "content-type": MIME[extname(file)] ?? "application/octet-stream" });
    });
  }
  return Object.assign(app, { drain });
}
