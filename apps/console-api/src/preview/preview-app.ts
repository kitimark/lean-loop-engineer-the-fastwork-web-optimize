// The preview port (console-lan-owner, round 2). Task previews are code an agent wrote, so they must not run on the console's
// origin: this app is served on its OWN port (console port + 1 by default), hence another origin (Lean
// `preview_origin_ne_console`). It accepts only the preview-access cookie (`fw_preview`, issued to an owner session, grants
// viewing only: Lean `cookie_never_owner`), judged by Lean `console.ownerGate` with `port: "preview"`
// (`allowPreview`, `preview_requires_cookie`). It forwards no console cookie to a preview server (proxy.ts sends none, and
// drops `Set-Cookie` from the answer). It serves nothing but `/preview/<id>/compare` and the entry redirects to the arms'
// own origins (proxy.ts, arm-app.ts: each arm has its own port). Owner actions live on the console
// origin only and refuse an `Origin` of this port.
import { Hono } from "hono";
import type { Context } from "hono";
import type { Core } from "../core/index.ts";
import type { PreviewManager } from "./manager.ts";
import { OwnerAuth } from "./owner.ts";
import { isLoopback } from "./lan.ts";
import { remoteOf } from "./gate.ts";
import { mountPreviewProxy } from "./proxy.ts";
import { Grants } from "./grants.ts";
import type { ReturnStore } from "./return.ts";
import { localPortOf } from "./arm-app.ts";

export function createPreviewApp(core: Core, owner: OwnerAuth, pm: PreviewManager, opts: { lan: boolean; grants?: Grants; returns?: ReturnStore }) {
  const app = new Hono();
  app.onError((e, c) => c.json({ ok: false, reason: `decision core failed: ${e.message}` }, 500));
  const wantsHtml = (c: Context) => (c.req.method === "GET" || c.req.method === "HEAD") && (c.req.header("accept") ?? "").includes("text/html");

  const grants = opts.grants ?? new Grants(core, () => undefined);

  // An inspect grant link (preview-inspect): `/__grant?t=<token>` sets the grant cookie. Lean `console.previewGrant` judges it
  // (loopback only, known, unused, ten minutes); the cookie opens preview paths only (`console.ownerGate`, `allowGrant`).
  app.get("/__grant", async (c) => {
    c.header("Cache-Control", "no-store"); c.header("Referrer-Policy", "no-referrer");
    const lan = opts.lan && !isLoopback(remoteOf(c));
    if (lan && !owner.previewHostOk(c.req.header("host"))) return c.json({ ok: false, reason: "unknown host" }, 421);
    const r = await grants.redeem(lan, c.req.query("t"));
    if (!r.ok) return c.json({ ok: false, reason: `grant refused: ${r.verdict}` }, 403);
    c.header("Set-Cookie", Grants.setCookie(r.cookie, r.maxAgeSec));
    if (r.next) return c.redirect(r.next, 302);
    return c.html(`<!doctype html><meta charset="utf-8"><title>fw preview</title><p>preview access granted for ${Math.floor(r.maxAgeSec / 60)} minutes.</p>`);
  });

  app.use("*", async (c, next) => {
    const lan = opts.lan && !isLoopback(remoteOf(c)); // outside LAN mode this port listens on loopback only
    const hostOk = owner.previewHostOk(c.req.header("host"));
    const g = grants.lookup(c.req.header("cookie"));
    const r = await core.ops("console.ownerGate", {
      lan, session: owner.previewOk(c.req.header("cookie")), hostOk, path: c.req.path, port: "preview",
      grant: g.known, grantStarted: g.started, now: grants.now(),
    });
    if (r.allow === true) { c.header("Cache-Control", "no-store"); if (r.by === "grant" && g.id) grants.used(g.id, c.req.path); return next(); }
    c.header("Cache-Control", "no-store");
    if (lan && !hostOk) return c.json({ ok: false, reason: "unknown host" }, 421);
    const msg = "preview access needed: open this link from the console task page, after logging in there";
    if (hostOk && wantsHtml(c) && opts.returns) {
      const u = new URL(c.req.url);
      const to = await opts.returns.redirectFor({ html: true, host: c.req.header("host"), port: localPortOf(c), pathq: u.pathname + u.search });
      if (to) return c.redirect(to, 303);
    }
    if (wantsHtml(c)) return c.html(`<!doctype html><meta charset="utf-8"><title>fw preview</title><p>${msg}.</p>`, 401);
    return c.json({ ok: false, reason: msg }, 401);
  });

  mountPreviewProxy(app, pm);
  app.all("*", (c) => c.json({ ok: false, reason: "nothing here; previews are at /preview/<id>/" }, 404));
  return app;
}
