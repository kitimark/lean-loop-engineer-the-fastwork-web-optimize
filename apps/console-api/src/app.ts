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

const MIME: Record<string, string> = {
  ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".svg": "image/svg+xml", ".json": "application/json",
};

/** Which code this process runs: the commit of its checkout when it started (its base) and the start time (ms,
 *  informational). `fw watch` asks whether the range base..main touches the process's input files (fwcore `svc.stale`);
 *  api.json also holds the build commit of the fwcore child (`coreCommit`, or `coreUnknown`). */
export interface ServiceInfo { commit: string | null; startedAt: number }

export function createApp(store: Store, webDist?: string, reconciler?: Reconciler, service?: ServiceInfo) {
  const app = new Hono();
  // a failed core call (fwcore crash, bad reply) fails the request; the core restarts itself
  app.onError((e, c) => c.json({ ok: false, reason: `decision core failed: ${e.message}` }, 500));

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
  app.get("/api/board", async (c) => c.json(await store.board()));
  app.get("/api/plan", async (c) => c.json((await store.board()).plan)); // the work graph, derived by fwcore
  // latest `fw watch` check (fwcore obs.health output) with the running code's `service` ({commit, startedAt}), or null
  // before any check; GET /api/service is the same `service` object without needing a check
  app.get("/api/health", (c) => {
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
