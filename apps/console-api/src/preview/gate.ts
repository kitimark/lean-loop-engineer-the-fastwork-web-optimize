// The owner gate and the login routes (console-lan-owner). Every request is classified and judged by Lean
// (`console.ownerGate` = `Fw.Console.Preview.Owner.allow`, proved `lan_requires_owner`, `preview_requires_owner`,
// `loopback_unchanged`); this file reads the facts (remote address, cookie, Host header, path) and turns the verdict into a
// response. In LAN mode a request from a non-loopback (or unknown) address reaches `/owner/login` and nothing else until it
// carries an owner session. Previews are served only to a session, from loopback too.
import type { Context, Hono } from "hono";
import type { Core } from "../core/index.ts";
import { OwnerAuth } from "./owner.ts";
import { LoginGuard, loginPage } from "./login.ts";
import { isLoopback } from "./lan.ts";
import { viaReferer } from "./proxy.ts";

export type OwnerDeps = { core: Core; owner: OwnerAuth; login: LoginGuard; lan: boolean };

/** The socket's remote address (node server only; undefined for in-process requests). */
export const remoteOf = (c: Context): string | undefined =>
  (c.env as { incoming?: { socket?: { remoteAddress?: string } } } | undefined)?.incoming?.socket?.remoteAddress;

export function mountOwnerGate(app: Hono, d: OwnerDeps) {
  const wantsHtml = (c: Context) => (c.req.method === "GET" || c.req.method === "HEAD") && (c.req.header("accept") ?? "").includes("text/html");

  app.use("*", async (c, next) => {
    const remote = remoteOf(c);
    const lan = d.lan && !isLoopback(remote); // outside LAN mode the console listens on loopback only
    const hostOk = d.owner.hostOk(c.req.header("host"));
    const r = await d.core.ops("console.ownerGate", { lan, session: d.owner.cookieOk(c.req.header("cookie")), hostOk, path: viaReferer(c.req.path, c.req.header("referer"), c.req.header("host")) ?? c.req.path });
    if (r.allow === true) return next();
    c.header("Cache-Control", "no-store");
    if (lan && !hostOk) return c.json({ ok: false, reason: "unknown host" }, 421);
    if (wantsHtml(c)) return c.redirect("/owner/login", 303);
    return c.json({ ok: false, reason: "owner login required" }, 401);
  });

  app.get("/owner/login", (c) => {
    c.header("Cache-Control", "no-store");
    if (d.owner.cookieOk(c.req.header("cookie"))) return c.redirect("/", 303);
    return c.html(loginPage({ enabled: d.login.enabled }), d.login.enabled ? 200 : 503);
  });

  app.post("/owner/login", async (c) => {
    c.header("Cache-Control", "no-store");
    const json = (c.req.header("content-type") ?? "").includes("application/json");
    const reply = (status: 401 | 429 | 503 | 400 | 413, message: string, retryAt?: number | null) => {
      if (retryAt) c.header("Retry-After", String(Math.max(1, Math.ceil((retryAt - Date.now()) / 1000))));
      return json ? c.json({ ok: false, reason: message }, status) : c.html(loginPage({ enabled: d.login.enabled, message }), status);
    };
    // a body that does not parse says nothing about its content: the passphrase must not reach any message
    let presented = "";
    try {
      const text = await c.req.text();
      if (text.length > 4096) return reply(413, "request too large");
      presented = json ? String((JSON.parse(text) as { passphrase?: unknown }).passphrase ?? "") : (new URLSearchParams(text).get("passphrase") ?? "");
    } catch { return reply(400, "unreadable request"); }
    const o = await d.login.attempt(remoteOf(c) ?? "unknown", presented);
    presented = "";
    switch (o.verdict) {
      case "ok":
        c.header("Set-Cookie", OwnerAuth.setCookie(d.owner.open()));
        return json ? c.json({ ok: true }) : c.redirect("/", 303);
      case "locked": return reply(429, "too many tries; wait before trying again", o.retryAt);
      case "disabled": return reply(503, "owner login is disabled on this console");
      default: return reply(401, "wrong passphrase", o.retryAt);
    }
  });

  app.post("/owner/logout", (c) => {
    d.owner.close(c.req.header("cookie"));
    c.header("Set-Cookie", OwnerAuth.clearCookie());
    c.header("Cache-Control", "no-store");
    return c.redirect("/owner/login", 303);
  });

  /** what this browser holds (the web app asks it: show the login link or the owner controls) */
  app.get("/api/owner", (c) => c.json({ ok: true, session: d.owner.cookieOk(c.req.header("cookie")), loginEnabled: d.login.enabled }));
}
