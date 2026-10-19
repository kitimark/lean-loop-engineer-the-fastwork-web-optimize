// Previews on the preview port: `/preview/<id>/r/…` (task version), `/preview/<id>/o/…` (original snapshot),
// `/preview/<id>/compare` (side by side). The preview servers listen on loopback only; the preview gate (preview-app.ts, Lean
// `preview_requires_cookie`) has already run when a request gets here. Each served request touches the preview (Lean
// `touch_keeps`: the idle clock of `console.previewSweep` restarts). Only I/O: GET/HEAD, hop headers dropped, HTML and CSS
// get their root-absolute paths moved below the prefix (rewrite.ts). Other files pass through as the preview server sent them
// (its cache headers, ETag and encoding; the client's Accept-Encoding and If-None-Match are forwarded). A rewritten body is
// kept per (preview, arm, path, query) with the upstream ETag it came from, gets its own strong ETag, and is compressed once.
import http, { type IncomingMessage } from "node:http";
import { Readable } from "node:stream";
import type { Context, Hono } from "hono";
import type { PreviewManager } from "./manager.ts";
import { rewriteBody } from "./rewrite.ts";
import { etagMatches, pickEncoding, Variants } from "./cache-policy.ts";

const DROP = new Set(["connection", "keep-alive", "transfer-encoding", "set-cookie", "upgrade", "proxy-authenticate"]);
const ID = /^[a-z0-9][a-z0-9-]{0,100}$/;
const agent = new http.Agent({ keepAlive: true, maxSockets: 64 });

function upstream(port: number, pathq: string, method: string, headers: Record<string, string>): Promise<IncomingMessage> {
  return new Promise((resolve, reject) => {
    const r = http.request({ host: "127.0.0.1", port, path: pathq, method, agent, headers }, resolve);
    r.on("error", reject);
    r.end();
  });
}
const readAll = async (m: IncomingMessage): Promise<Buffer> => { const cs: Buffer[] = []; for await (const c of m) cs.push(c as Buffer); return Buffer.concat(cs); };
const one = (v: string | string[] | undefined): string | undefined => (Array.isArray(v) ? v[0] : v);

/** HTML and CSS are rewritten: a path with a trailing slash, an `.html`/`.css` name, or no extension (`/compare`). */
export const rewriteLane = (path: string): boolean => path.endsWith("/") || /\.(html|css)$/i.test(path) || !/\.[^/]+$/.test(path);

type Rewritten = { upstreamEtag?: string; variants: Variants; ct: string; cc: string | undefined };
const MAX_REWRITTEN = 300;
const rewritten = new Map<string, Rewritten>();

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
    const method = c.req.method;
    const clientEnc = c.req.header("accept-encoding");
    const clientEtag = c.req.header("if-none-match");
    try {
      if (rewriteLane(path)) {
        const key = `${id}|${prefix}|${path}${q}`;
        const hit = rewritten.get(key);
        const up = await upstream(port, `${path}${q}`, "GET", { "accept-encoding": "identity", ...(hit?.upstreamEtag ? { "if-none-match": hit.upstreamEtag } : {}) });
        let entry: Rewritten;
        if (up.statusCode === 304 && hit) { up.resume(); entry = hit; }
        else {
          const buf = await readAll(up);
          const ct = one(up.headers["content-type"]) ?? "";
          const text = up.statusCode === 200 && /^text\/(html|css)/i.test(ct) ? rewriteBody(ct, buf.toString("utf8"), prefix) : null;
          if (text === null) {
            const headers = new Headers();
            for (const [k, v] of Object.entries(up.headers)) if (!DROP.has(k) && v !== undefined && k !== "content-length") headers.set(k, Array.isArray(v) ? v.join(", ") : v);
            return new Response(method === "HEAD" ? null : new Uint8Array(buf), { status: up.statusCode ?? 502, headers });
          }
          const upstreamEtag = one(up.headers.etag);
          entry = { upstreamEtag, variants: new Variants(Buffer.from(text, "utf8")), ct, cc: one(up.headers["cache-control"]) };
          if (upstreamEtag) {
            rewritten.set(key, entry);
            if (rewritten.size > MAX_REWRITTEN) rewritten.delete(rewritten.keys().next().value!);
          }
        }
        const enc = pickEncoding(clientEnc);
        const v = entry.variants.get(enc);
        const headers = new Headers({ "content-type": entry.ct, vary: "accept-encoding", "cache-control": entry.cc ?? "no-cache" });
        if (entry.upstreamEtag) {
          headers.set("etag", v.etag);
          if (etagMatches(clientEtag, v.etag)) return new Response(null, { status: 304, headers });
        }
        if (enc !== "identity") headers.set("content-encoding", enc);
        headers.set("content-length", String(v.body.length));
        return new Response(method === "HEAD" ? null : new Uint8Array(v.body), { status: 200, headers });
      }
      const fwd: Record<string, string> = {};
      if (clientEnc) fwd["accept-encoding"] = clientEnc;
      if (clientEtag) fwd["if-none-match"] = clientEtag;
      const up = await upstream(port, `${path}${q}`, method, fwd);
      const headers = new Headers();
      for (const [k, v] of Object.entries(up.headers)) if (!DROP.has(k) && v !== undefined) headers.set(k, Array.isArray(v) ? v.join(", ") : v);
      const status = up.statusCode ?? 502;
      if (method === "HEAD" || status === 304) { up.resume(); return new Response(null, { status, headers }); }
      return new Response(Readable.toWeb(up) as unknown as ReadableStream, { status, headers });
    } catch { return c.json({ ok: false, reason: "preview server not reachable" }, 502); }
  };
  // the gate (gate.ts) judged the same effective path, so a Referer-routed request needs the owner session like any preview request
  app.use("*", async (c, next) => {
    if (c.req.method !== "GET" && c.req.method !== "HEAD") return next();
    const via = viaReferer(c.req.path, c.req.header("referer"), c.req.header("host"));
    return via && pm.serving(/^\/preview\/([^/]+)/.exec(via)![1]!) ? handle(c, via) : next();
  });
  app.all("/preview/:id/*", (c) => handle(c, c.req.path));
}
