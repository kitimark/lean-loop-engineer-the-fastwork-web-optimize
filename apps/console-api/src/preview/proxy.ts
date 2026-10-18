// Previews through the console's own port: `/preview/<id>/r/…` (task version), `/preview/<id>/o/…` (original snapshot),
// `/preview/<id>/compare` (side by side). The preview servers listen on loopback only; the owner gate (gate.ts, Lean
// `preview_requires_owner`) has already run when a request gets here. Each served request touches the preview (Lean
// `touch_keeps`: the idle clock of `console.previewSweep` restarts). Only I/O: GET/HEAD, hop headers dropped, HTML and CSS
// get their root-absolute paths moved below the prefix (rewrite.ts).
import type { Hono } from "hono";
import type { PreviewManager } from "./manager.ts";
import { rewriteBody } from "./rewrite.ts";

const DROP = new Set(["connection", "keep-alive", "transfer-encoding", "content-length", "content-encoding", "set-cookie", "upgrade", "proxy-authenticate"]);
const ID = /^[a-z0-9][a-z0-9-]{0,100}$/;

export function mountPreviewProxy(app: Hono, pm: PreviewManager) {
  app.all("/preview/:id/*", async (c) => {
    const id = c.req.param("id");
    const e = ID.test(id) ? pm.serving(id) : null;
    if (!e) return c.json({ ok: false, reason: "no such running preview" }, 404);
    if (c.req.method !== "GET" && c.req.method !== "HEAD") return c.json({ ok: false, reason: "read-only" }, 405);
    const base = `/preview/${id}`;
    const rest = c.req.path.slice(base.length); // "/r/x.js", "/o/", "/compare"
    if (rest === "/r" || rest === "/o") return c.redirect(`${base}${rest}/`, 302); // relative links need the slash
    const m = /^\/(r|o)(\/.*)?$/.exec(rest);
    let port: number; let path: string; let prefix: string;
    if (m) { port = m[1] === "r" ? e.rp : e.op; path = m[2] ?? "/"; prefix = `${base}/${m[1]}`; }
    else if (rest === "/compare") { port = e.rp; path = "/__fw/compare"; prefix = base; }
    else return c.redirect(`${base}/r/`, 302);
    pm.touch(id);
    const q = new URL(c.req.url).search;
    let up: Response;
    try {
      up = await fetch(`http://127.0.0.1:${port}${path}${q}`, { method: c.req.method, redirect: "manual", headers: { "accept-encoding": "identity" } });
    } catch { return c.json({ ok: false, reason: "preview server not reachable" }, 502); }
    const headers = new Headers();
    up.headers.forEach((v, k) => { if (!DROP.has(k.toLowerCase())) headers.set(k, v); });
    headers.set("Cache-Control", "no-store");
    const ct = up.headers.get("content-type") ?? "";
    if (/^text\/(html|css)/i.test(ct)) {
      const body = rewriteBody(ct, await up.text(), prefix) ?? "";
      return new Response(c.req.method === "HEAD" ? null : body, { status: up.status, headers });
    }
    return new Response(c.req.method === "HEAD" ? null : up.body, { status: up.status, headers });
  });
}
