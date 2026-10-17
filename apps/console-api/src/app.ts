import { existsSync, readFileSync } from "node:fs";
import { extname, join, normalize } from "node:path";
import { Hono } from "hono";
import { streamSSE } from "hono/streaming";
import { Command } from "@fw/contracts";
import type { Store } from "./store.ts";

const MIME: Record<string, string> = {
  ".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".svg": "image/svg+xml", ".json": "application/json",
};

export function createApp(store: Store, webDist?: string) {
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
    const reply = await store.submit(parsed.data);
    return c.json(reply, reply.ok ? 200 : 422);
  });

  app.get("/api/board", async (c) => c.json(await store.board()));
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
  return app;
}
