// Test rig for the arm origins: two real listeners (the task arm and the original arm of preview `p1`) answered by the real
// arm app (arm-app.ts, Lean `console.previewArm` through fwcore), in front of two preview-server handlers.
import { createServer, request, type IncomingHttpHeaders, type Server } from "node:http";
import { serve } from "@hono/node-server";
import { selectCore } from "../src/core/index.ts";
import { OwnerAuth } from "../src/preview/owner.ts";
import { createArmApp } from "../src/preview/arm-app.ts";
import { Grants } from "../src/preview/grants.ts";
import type { PreviewManager } from "../src/preview/manager.ts";

export type Raw = { status: number; headers: IncomingHttpHeaders; bytes: Buffer };

/** `handlers`: the preview-server request handlers of the two arms (e.g. `handler({ root })`). */
export async function armRig(handlers: { r: Server; o: Server }, opts: { lan?: boolean } = {}) {
  // The private port of an arm is its public port + 1000 (Lean `Arm.backendOf`), so the arm listeners come first and the
  // preview-server handlers bind at those ports; a taken port retries the pair.
  const listenAt = (s: Server, port: number) => new Promise<void>((res, rej) => {
    s.once("error", rej); s.listen(port, "127.0.0.1", () => { s.off("error", rej); res(); });
  });
  const core = selectCore();
  const owner = new OwnerAuth();
  const grants = new Grants(core, () => undefined);
  const ports = { rp: 0, op: 0 };
  const touched: string[] = [];
  let serving = true;
  const pm = {
    serving: (id: string) => (id === "p1" && serving ? { id, rp: ports.rp, op: ports.op, brp, bop, phase: "serving" } : null),
    touch: (id: string) => { touched.push(id); },
    liveTable: () => [{ id: "p1", task: "t", rp: ports.rp, op: ports.op, started: 0 }],
  } as unknown as PreviewManager;
  const app = createArmApp(core, owner, pm, { lan: opts.lan ?? false, grants });
  const listenArm = (port: number): Promise<{ srv: ReturnType<typeof serve>; port: number }> => new Promise((res, rej) => {
    const srv = serve({ fetch: app.fetch as never, port, hostname: "127.0.0.1" }, () => res({ srv, port }));
    srv.once("error", rej);
  });
  const shut = (s: { close(cb?: () => void): unknown }) => new Promise((r) => { s.close(() => r(null)); (s as Server).closeAllConnections?.(); });
  let a!: Awaited<ReturnType<typeof listenArm>>, b!: typeof a;
  for (let tries = 0; ; tries++) {
    const base = 20_000 + Math.floor(Math.random() * 20_000) * 1; // arm ports in 20000..39999, backends 1000 above
    const opened: Array<{ close(cb?: () => void): unknown }> = [];
    try {
      a = await listenArm(base); opened.push(a.srv as never);
      b = await listenArm(base + 1); opened.push(b.srv as never);
      await listenAt(handlers.r, base + 1000); opened.push(handlers.r);
      await listenAt(handlers.o, base + 1001);
      break;
    } catch (e) {
      for (const s of opened) await shut(s);
      if (tries > 50) throw e;
    }
  }
  ports.rp = a.port; ports.op = b.port;
  const brp = a.port + 1000, bop = b.port + 1000;
  const token = owner.open();
  const cookie = owner.previewCookieFor(token).map((c) => c.split(";")[0]!)[0]!;
  const raw = (port: number, path: string, headers: Record<string, string> = {}, method = "GET") => new Promise<Raw>((resolve, reject) => {
    const req = request({ host: "127.0.0.1", port, path, headers, method }, (res) => {
      const cs: Buffer[] = [];
      res.on("data", (c) => cs.push(c));
      res.on("end", () => resolve({ status: res.statusCode!, headers: res.headers, bytes: Buffer.concat(cs) }));
    });
    req.on("error", reject);
    req.end();
  });
  return {
    rp: a.port, op: b.port, brp, bop, owner, grants, cookie, touched, app, raw,
    stopServing() { serving = false; },
    async close() {
      for (const s of [a.srv, b.srv, handlers.r, handlers.o]) await new Promise((r) => { (s as Server).close(() => r(null)); (s as Server).closeAllConnections?.(); });
    },
  };
}

export const noHandler = () => createServer((_req, res) => { res.statusCode = 404; res.end("none"); });
