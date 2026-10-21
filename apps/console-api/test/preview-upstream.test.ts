// Task preview-502-flake: the Agent that talks to the preview server closes an idle socket before the server does. Node's Agent
// reads the server's `Keep-Alive: timeout=N` hint only when it has a `timeout` option (v24.22.0 lib/_http_agent.js:655).
import http from "node:http";
import type { AddressInfo } from "node:net";
import { afterEach, describe, expect, it } from "vitest";
import { IDLE_MS, previewAgent, upstream } from "../src/preview/upstream.ts";

const closers: Array<() => void> = [];
afterEach(() => { for (const c of closers.splice(0)) c(); });

async function server(keepAliveTimeout: number): Promise<number> {
  const srv = http.createServer((_q, r) => { r.writeHead(200, { "content-length": "2" }); r.end("ok"); });
  srv.keepAliveTimeout = keepAliveTimeout;
  await new Promise<void>((ok) => srv.listen(0, "127.0.0.1", ok));
  closers.push(() => { srv.closeAllConnections(); srv.close(); });
  return (srv.address() as AddressInfo).port;
}

/** The idle timeout (ms) the Agent put on the socket it keeps after one response; undefined when no socket is kept. */
async function keptSocketTimeout(agent: http.Agent, port: number): Promise<number | undefined> {
  const res = await upstream(agent, port, "/", "GET", {});
  res.resume();
  await new Promise((ok) => res.on("end", ok));
  await new Promise((ok) => setImmediate(ok));
  const socks = Object.values(agent.freeSockets).flat() as Array<{ timeout?: number }>;
  closers.push(() => agent.destroy());
  return socks[0]?.timeout;
}

describe("preview upstream agent", () => {
  it("honours a server's keep-alive hint: the idle limit is the hint minus the agent's 1 s buffer", async () => {
    expect(await keptSocketTimeout(previewAgent(4), await server(3000))).toBe(2000);
  });
  it("without the hint the idle limit is its own", async () => {
    expect(await keptSocketTimeout(previewAgent(4), await server(65_000))).toBe(IDLE_MS);
  });
  it("a bare keep-alive Agent ignores the hint (the cause of the 502: an idle socket is kept without limit)", async () => {
    const t = await keptSocketTimeout(new http.Agent({ keepAlive: true }), await server(3000));
    expect(t === undefined || t === 0).toBe(true);
  });
});
