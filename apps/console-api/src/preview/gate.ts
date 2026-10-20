// The owner gate and the login routes of the CONSOLE port (console-lan-owner). Every request is classified and judged by
// Lean (`console.ownerGate` = `Fw.Console.Preview.Owner.allow`, proved `lan_requires_owner`, `console_never_serves_preview`,
// `loopback_unchanged`); this file reads the facts (remote address, Authorization header, Host header, path) and turns the
// verdict into a response. In LAN mode a request from a non-loopback (or unknown) address reaches `/owner/login` and the
// static shell (no data) and nothing else until it carries the owner bearer token; no cookie counts. The console port never serves a preview: those live on their own port (preview-app.ts), which is
// another origin. Login, logout and every owner action also need `Origin` = a console origin (Lean `console.ownerAction`,
// proved `owner_requires_bearer`, `owner_action_requires_console_origin`, `computed_trusted_refuses_preview`).
import type { Context, Hono } from "hono";
import { bodyLimit } from "hono/body-limit";
import type { Core } from "../core/index.ts";
import { OwnerAuth } from "./owner.ts";
import { LoginGuard, loginPage } from "./login.ts";
import { NONCE, type ReturnStore } from "./return.ts";
import { isLoopback } from "./lan.ts";

export type OwnerDeps = { core: Core; owner: OwnerAuth; login: LoginGuard; lan: boolean; returns?: ReturnStore };

/** The login body is a passphrase: nothing legitimate is larger (bytes). */
export const LOGIN_BODY_MAX = 1024;

/** The socket's remote address (node server only; undefined for in-process requests). */
export const remoteOf = (c: Context): string | undefined =>
  (c.env as { incoming?: { socket?: { remoteAddress?: string } } } | undefined)?.incoming?.socket?.remoteAddress;

export function mountOwnerGate(app: Hono, d: OwnerDeps) {
  const wantsHtml = (c: Context) => (c.req.method === "GET" || c.req.method === "HEAD") && (c.req.header("accept") ?? "").includes("text/html");

  app.use("*", async (c, next) => {
    const remote = remoteOf(c);
    const lan = d.lan && !isLoopback(remote); // outside LAN mode the console listens on loopback only
    const hostOk = d.owner.hostOk(c.req.header("host"));
    const r = await d.core.ops("console.ownerGate", { lan, session: d.owner.bearerOk(c.req.header("authorization")), hostOk, path: c.req.path });
    if (r.allow === true) return next();
    c.header("Cache-Control", "no-store");
    if (lan && !hostOk) return c.json({ ok: false, reason: "unknown host" }, 421);
    if (r.class === "preview") return c.json({ ok: false, reason: "previews are served on the preview port, not here" }, 404);
    if (wantsHtml(c)) return c.redirect("/owner/login", 303);
    return c.json({ ok: false, reason: "owner login required" }, 401);
  });

  app.get("/owner/login", (c) => {
    c.header("Cache-Control", "no-store");
    const r = c.req.query("r");
    return c.html(loginPage({ enabled: d.login.enabled, ...(r && NONCE.test(r) ? { ret: r } : {}) }), d.login.enabled ? 200 : 503);
  });

  // the body is capped before it is read (a chunked body too)
  app.post("/owner/login", bodyLimit({ maxSize: LOGIN_BODY_MAX, onError: (c) => c.json({ ok: false, reason: "request too large" }, 413) }), async (c) => {
    c.header("Cache-Control", "no-store");
    const reply = (status: 401 | 403 | 415 | 429 | 503 | 400, message: string, retryAt?: number | null) => {
      if (retryAt) c.header("Retry-After", String(Math.max(1, Math.ceil((retryAt - Date.now()) / 1000))));
      return c.json({ ok: false, reason: message }, status);
    };
    if (!(c.req.header("content-type") ?? "").includes("application/json")) return reply(415, "the login is a JSON request (use the login page)");
    // a page of another origin (a preview) cannot post here, and a refused origin costs the owner no try
    if (!(await d.owner.actionOk(d.core, "login", false, c.req.header("origin"), c.req.header("host")))) return reply(403, "refused: cross-origin login");
    // a body that does not parse says nothing about its content: the passphrase must not reach any message
    let presented = "";
    let ret: unknown;
    try {
      const text = await c.req.text();
      const body = JSON.parse(text) as { passphrase?: unknown; r?: unknown };
      presented = String(body.passphrase ?? "");
      ret = body.r;
    } catch { return reply(400, "unreadable request"); }
    const o = await d.login.attempt(remoteOf(c) ?? "unknown", presented);
    presented = "";
    switch (o.verdict) {
      case "ok": {
        const token = d.owner.open();
        for (const ck of d.owner.previewCookieFor(token)) c.header("Set-Cookie", ck, { append: true }); // preview viewing only
        const next = d.returns ? await d.returns.landing(ret, c.req.header("host")) : "/";
        return c.json({ ok: true, token, next });
      }
      case "locked": return reply(429, "too many tries; wait before trying again", o.retryAt);
      case "disabled": return reply(503, "owner login is disabled on this console");
      default: return reply(401, "wrong passphrase", o.retryAt);
    }
  });

  app.post("/owner/logout", async (c) => {
    c.header("Cache-Control", "no-store");
    const auth = c.req.header("authorization");
    if (!(await d.owner.actionOk(d.core, "owner", d.owner.bearerOk(auth), c.req.header("origin"), c.req.header("host"))))
      return c.json({ ok: false, reason: "refused: not the owner, or not from the console origin" }, 403);
    d.owner.close(auth);
    for (const ck of OwnerAuth.clearCookies()) c.header("Set-Cookie", ck, { append: true });
    return c.json({ ok: true });
  });

  /** what this browser holds (the web app asks it: show the login link or the owner controls) and where the previews are */
  app.get("/api/owner", (c) => c.json({ ok: true, session: d.owner.bearerOk(c.req.header("authorization")), loginEnabled: d.login.enabled, previewPort: d.owner.previewPort }));
}
