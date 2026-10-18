// Previews through the console's own port: `/preview/<id>/r/…` (task version), `/preview/<id>/o/…` (original snapshot),
// `/preview/<id>/compare` (side by side). The preview servers listen on loopback only; the owner gate (gate.ts, Lean
// `preview_requires_owner`) has already run when a request gets here. Each served request touches the preview (Lean
// `touch_keeps`: the idle clock of `console.previewSweep` restarts). Only I/O: GET/HEAD, hop headers dropped, HTML and CSS
// get their root-absolute paths moved below the prefix (rewrite.ts).
import type { Context, Hono } from "hono";
import type { PreviewManager } from "./manager.ts";
import { rewriteBody } from "./rewrite.ts";

const DROP = new Set(["connection", "keep-alive", "transfer-encoding", "content-length", "content-encoding", "set-cookie", "upgrade", "proxy-authenticate"]);
const ID = /^[a-z0-9][a-z0-9-]{0,100}$/;

/** A request for a root-absolute path that the preview's own JavaScript built (`"/selling/x.png"`, `"/_app/..."`): bundles hold
 *  such strings and the rewriter does not touch scripts. Its Referer is the preview page; the request is then read as the same
 *  path below that preview. Returns the preview-relative target, or null for a request that is the console's own. */
export function viaReferer(path: string, referer: string | undefined, host: string | undefined): string | null {
  if (!referer || !host || /^\/(preview|api|owner)(\/|$)/.test(path)) return null;
  const m = /^https?:\/\/([^/]+)\/preview\/([a-z0-9][a-z0-9-]{0,100})\/(r|o)(?:\/|$)/.exec(referer);
  if (!m || m[1] !== host) return null;
  return `/preview/${m[2]}/${m[3]}${path}`;
}

export function mountPreviewProxy(app: Hono, pm: PreviewManager) {
  const handle = async (c: Context, full: string) => {
    const id = /^\/preview\/([^/]+)/.exec(full)![1]!;
    const e = ID.test(id) ? pm.serving(id) : null;
    if (!e) return c.json({ ok: false, reason: "no such running preview" }, 404);
    if (c.req.method !== "GET" && c.req.method !== "HEAD") return c.json({ ok: false, reason: "read-only" }, 405);
    const base = `/preview/${id}`;
    const rest = full.slice(base.length); // "/r/x.js", "/o/", "/compare"
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
  };
  // the gate (gate.ts) judged the same effective path, so a Referer-routed request needs the owner session like any preview request
  app.use("*", async (c, next) => {
    if (c.req.method !== "GET" && c.req.method !== "HEAD") return next();
    const via = viaReferer(c.req.path, c.req.header("referer"), c.req.header("host"));
    return via && pm.serving(/^\/preview\/([^/]+)/.exec(via)![1]!) ? handle(c, via) : next();
  });
  app.all("/preview/:id/*", (c) => handle(c, c.req.path));
}
