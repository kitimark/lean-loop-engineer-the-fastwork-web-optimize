// The arm origins (task preview-proxy-direct). A preview has two arms, the task version and the original snapshot; each is
// served on its OWN port, hence its own origin, so a page's root-absolute requests (`/_app/x.js`, `/selling/x.png`) reach the
// same arm natively: no redirect, no Referer reading, no rewriting of HTML or CSS. The arm's public port is the port Lean
// allocated for it (`Entry.rp`/`op`); the preview server listens on a private loopback port (`brp`/`bop`, Lean
// `Arm.backendOf`). One app answers every arm listener; which arm a request belongs to is read from the LOCAL PORT of its
// socket and decided by Lean `console.previewArm` (`Arm.route`: proved `route_no_leak`, `route_path_free`, `route_identity`),
// never from the path or a header. The gate is the preview port's gate for a preview path (`Arm.armServe`, proved
// `arm_gate_eq_preview_path`): the preview-access cookie of an owner session or a live inspect grant (cookies ignore ports, so
// the cookie the preview port or the grant link set is sent here), the Host must name this arm's port. Nothing is forwarded
// to the preview server but Accept-Encoding and If-None-Match; its Set-Cookie is dropped. GET and HEAD only.
// Only I/O: the verdicts come from fwcore.
import http, { type IncomingMessage } from "node:http";
import { Readable } from "node:stream";
import { Hono } from "hono";
import type { Context } from "hono";
import type { Core } from "../core/index.ts";
import type { PreviewManager } from "./manager.ts";
import { OwnerAuth, LOOPBACK_HOST } from "./owner.ts";
import { isLoopback } from "./lan.ts";
import { remoteOf } from "./gate.ts";
import { Grants } from "./grants.ts";
import type { ReturnStore } from "./return.ts";

const DROP = new Set(["connection", "keep-alive", "transfer-encoding", "set-cookie", "upgrade", "proxy-authenticate"]);
// The preview server (serve-child.ts) closes an idle connection after 65 s + 1 s. Node's client Agent reads that hint
// (`Keep-Alive: timeout=65`) only when it has a `timeout` of its own (_http_agent.js keepSocketAlive: `serverHintTimeout <
// agentTimeout` with agentTimeout 0 never holds), so without `timeout` it keeps an idle socket until the server's FIN arrives
// and can send a request into the connection the server is just closing: ECONNRESET, a 502. A client-side idle limit well
// below the server's closes an idle socket first, so a reused socket is never one the server may be closing.
// The Agent reads a server's `Keep-Alive: timeout=N` hint only when it has a `timeout` of its own (Node v24.22.0
// lib/_http_agent.js:655 `serverHintTimeout < agentTimeout`, agentTimeout 0 without the option); without one it keeps an idle
// socket until the server's FIN arrives and can send a request into a connection the server is closing: ECONNRESET, a 502.
// With `timeout` it closes an idle socket at min(timeout, hint - 1 s) (:641-663), before the server does.
const agent = new http.Agent({ keepAlive: true, maxSockets: 64, timeout: 30_000 });

const lastEnd = new WeakMap<object, number>(); // when a socket last finished a response: the idle time logged with an upstream error
function upstream(port: number, pathq: string, method: string, headers: Record<string, string>): Promise<IncomingMessage> {
  return new Promise((resolve, reject) => {
    let idle: number | undefined, sock: object | undefined;
    const r = http.request({ host: "127.0.0.1", port, path: pathq, method, agent, headers }, (res) => {
      res.on("end", () => { if (sock) lastEnd.set(sock, Date.now()); });
      resolve(res);
    });
    r.on("socket", (s) => { sock = s; const t = lastEnd.get(s); idle = t === undefined ? undefined : Date.now() - t; });
    r.on("error", (e) => reject(Object.assign(e, { fwReused: r.reusedSocket, fwIdle: idle })));
    r.end();
  });
}

/** The local port of the connection a request arrived on (node server only; undefined for in-process requests). */
export const localPortOf = (c: Context): number | undefined =>
  (c.env as { incoming?: { socket?: { localPort?: number } } } | undefined)?.incoming?.socket?.localPort;

/** The Host header names this arm: a loopback name on the arm's port, or the LAN address on it (LAN mode). */
export const armHostOk = (host: string | undefined, port: number, lanAddr: string | null): boolean =>
  !!host && ((LOOPBACK_HOST.test(host) && host.endsWith(`:${port}`)) || (lanAddr !== null && host === `${lanAddr}:${port}`));

export function createArmApp(core: Core, owner: OwnerAuth, pm: PreviewManager, opts: { lan: boolean; lanAddr?: string | null; grants?: Grants; returns?: ReturnStore }) {
  const app = new Hono();
  app.onError((e, c) => c.json({ ok: false, reason: `decision core failed: ${e.message}` }, 500));
  const grants = opts.grants ?? new Grants(core, () => undefined);
  const wantsHtml = (c: Context) => (c.req.method === "GET" || c.req.method === "HEAD") && (c.req.header("accept") ?? "").includes("text/html");

  app.all("*", async (c) => {
    const port = localPortOf(c);
    if (port === undefined) return c.json({ ok: false, reason: "not an arm listener" }, 404);
    const lan = opts.lan && !isLoopback(remoteOf(c));
    const hostOk = armHostOk(c.req.header("host"), port, opts.lanAddr ?? null);
    const g = grants.lookup(c.req.header("cookie"));
    const u = new URL(c.req.url);
    const pathq = u.pathname + u.search;
    const r = await core.ops("console.previewArm", {
      lan, session: owner.previewOk(c.req.header("cookie")), hostOk, grant: g.known, grantStarted: g.started, now: grants.now(),
      port, path: pathq, live: pm.liveTable(),
    });
    c.header("Cache-Control", "no-store");
    if (r.allow !== true) {
      if (lan && !hostOk) return c.json({ ok: false, reason: "unknown host" }, 421);
      const msg = "preview access needed: open this link from the console task page, after logging in there";
      if (hostOk && c.req.method === "GET" && wantsHtml(c) && opts.returns) {
        const to = await opts.returns.redirectFor({ method: c.req.method, html: true, host: c.req.header("host"), port, pathq });
        if (to) return c.redirect(to, 303);
      }
      if (wantsHtml(c)) return c.html(`<!doctype html><meta charset="utf-8"><title>fw preview</title><p>${msg}.</p>`, 401);
      return c.json({ ok: false, reason: msg }, 401);
    }
    if (r.by === "grant" && g.id) grants.used(g.id, u.pathname);
    if (r.act !== "proxy") return c.json({ ok: false, reason: "no preview on this port" }, 404);
    const id = String(r.preview);
    if (!pm.serving(id)) return c.json({ ok: false, reason: "no such running preview" }, 404);
    if (c.req.method !== "GET" && c.req.method !== "HEAD") return c.json({ ok: false, reason: "read-only" }, 405);
    pm.touch(id);
    const fwd: Record<string, string> = {};
    const enc = c.req.header("accept-encoding"); if (enc) fwd["accept-encoding"] = enc;
    const etag = c.req.header("if-none-match"); if (etag) fwd["if-none-match"] = etag;
    try {
      const up = await upstream(Number(r.backend), String(r.path), c.req.method, fwd);
      const headers = new Headers();
      for (const [k, v] of Object.entries(up.headers)) if (!DROP.has(k) && v !== undefined) headers.set(k, Array.isArray(v) ? v.join(", ") : v);
      const status = up.statusCode ?? 502;
      if (c.req.method === "HEAD" || status === 304) { up.resume(); return new Response(null, { status, headers }); }
      return new Response(Readable.toWeb(up) as unknown as ReadableStream, { status, headers });
    } catch (e) {
      const x = e as NodeJS.ErrnoException & { fwReused?: boolean; fwIdle?: number };
      console.error(`preview-502 ${JSON.stringify({ code: x.code, syscall: x.syscall, msg: x.message, reused: x.fwReused, idleMs: x.fwIdle, path: pathq })}`);
      return c.json({ ok: false, reason: "preview server not reachable" }, 502);
    }
  });
  return app;
}
