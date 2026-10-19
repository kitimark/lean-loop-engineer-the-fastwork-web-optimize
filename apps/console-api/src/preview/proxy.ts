// The preview port's shell (task preview-proxy-direct): `/preview/<id>/compare` (the side-by-side page, which frames the two
// arm origins) and the entry paths `/preview/<id>`, `/r`, `/o` (with or without the slash), which answer 302 to the arm's own
// origin (`http://<this host>:<arm port>/`, a page-level hop for a link, never for a subresource). The arms themselves are not
// served here: each has its own port (arm-app.ts), so no root-absolute request ever reaches this app, nothing is redirected
// on the way to a module and no HTML, CSS or script is rewritten. The preview gate (preview-app.ts, Lean
// `preview_requires_cookie`) has already run when a request gets here. Each served request touches the preview (Lean
// `touch_keeps`). The compare page is fetched from the preview server's private port as it sent it (GET/HEAD only).
import http, { type IncomingMessage } from "node:http";
import { Readable } from "node:stream";
import type { Context, Hono } from "hono";
import type { PreviewManager } from "./manager.ts";

const DROP = new Set(["connection", "keep-alive", "transfer-encoding", "set-cookie", "upgrade", "proxy-authenticate"]);
const ID = /^[a-z0-9][a-z0-9-]{0,100}$/;
const agent = new http.Agent({ keepAlive: true, maxSockets: 8 });

function upstream(port: number, pathq: string, method: string, headers: Record<string, string>): Promise<IncomingMessage> {
  return new Promise((resolve, reject) => {
    const r = http.request({ host: "127.0.0.1", port, path: pathq, method, agent, headers }, resolve);
    r.on("error", reject);
    r.end();
  });
}

/** `http://<host of this request, without its port>:<port>/` (the arm's origin; `host` was judged by the gate). */
export const armOrigin = (host: string | undefined, port: number): string | null => {
  const m = host ? /^(\[[0-9a-f:]+\]|[a-z0-9.-]+)(?::\d{1,5})?$/i.exec(host) : null;
  return m ? `http://${m[1]}:${port}/` : null;
};

export function mountPreviewProxy(app: Hono, pm: PreviewManager) {
  const handle = async (c: Context) => {
    const full = c.req.path;
    const id = /^\/preview\/([^/]+)/.exec(full)![1]!;
    const e = ID.test(id) ? pm.serving(id) : null;
    if (!e) return c.json({ ok: false, reason: "no such running preview" }, 404);
    if (c.req.method !== "GET" && c.req.method !== "HEAD") return c.json({ ok: false, reason: "read-only" }, 405);
    const rest = full.slice(`/preview/${id}`.length); // "", "/", "/r", "/r/", "/o", "/o/", "/compare"
    const search = new URL(c.req.url).search;
    const arm = /^\/?(r|o)?\/?$/.exec(rest);
    if (arm) {
      const to = armOrigin(c.req.header("host"), arm[1] === "o" ? e.op : e.rp);
      return to ? c.redirect(`${to}${search}`, 302) : c.json({ ok: false, reason: "bad host" }, 400);
    }
    if (rest !== "/compare") return c.json({ ok: false, reason: "arms have their own ports; see /preview/<id>/compare" }, 404);
    pm.touch(id);
    try {
      const clientEnc = c.req.header("accept-encoding");
      const up = await upstream(e.brp, `/__fw/compare${search}`, c.req.method, clientEnc ? { "accept-encoding": clientEnc } : {});
      const headers = new Headers();
      for (const [k, v] of Object.entries(up.headers)) if (!DROP.has(k) && v !== undefined) headers.set(k, Array.isArray(v) ? v.join(", ") : v);
      const status = up.statusCode ?? 502;
      if (c.req.method === "HEAD" || status === 304) { up.resume(); return new Response(null, { status, headers }); }
      return new Response(Readable.toWeb(up) as unknown as ReadableStream, { status, headers });
    } catch { return c.json({ ok: false, reason: "preview server not reachable" }, 502); }
  };
  app.all("/preview/:id", handle);
  app.all("/preview/:id/*", handle);
}
