import http, { type IncomingMessage } from "node:http";

// Node's Agent honors the server's Keep-Alive hint only with its own `timeout` (node v24.22.0 lib/_http_agent.js:655).
export const IDLE_MS = 30_000;

export const previewAgent = (maxSockets: number) => new http.Agent({ keepAlive: true, maxSockets, timeout: IDLE_MS });

const lastEnd = new WeakMap<object, number>();

export function upstream(agent: http.Agent, port: number, pathq: string, method: string, headers: Record<string, string>): Promise<IncomingMessage> {
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

export function log502(who: string, e: unknown, pathq: string): void {
  const x = e as NodeJS.ErrnoException & { fwReused?: boolean; fwIdle?: number };
  console.error(`preview-502 ${JSON.stringify({ who, code: x.code, syscall: x.syscall, msg: x.message, reused: x.fwReused, idleMs: x.fwIdle, path: pathq })}`);
}
