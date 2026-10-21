// The request from an app of the preview port or of an arm to the preview server's private port (task preview-502-flake).
// One Agent per caller, built here so that none forgets its idle limit.
import http, { type IncomingMessage } from "node:http";

/** Idle limit of a pooled socket, ms. Node's client Agent reads a server's `Keep-Alive: timeout=N` hint only when it has a
 *  `timeout` of its own (Node v24.22.0 lib/_http_agent.js:655 `serverHintTimeout < agentTimeout`, with agentTimeout 0 without
 *  the option that never holds); without one it keeps an idle socket until the server's FIN arrives, and a request sent into
 *  a connection the server is just closing fails with ECONNRESET (a 502 here). With `timeout` the Agent closes an idle
 *  socket at min(timeout, hint - 1 s) (:641-663), before the server does. The preview server's own limit is 65 s + 1 s. */
export const IDLE_MS = 30_000;

export const previewAgent = (maxSockets: number) => new http.Agent({ keepAlive: true, maxSockets, timeout: IDLE_MS });

const lastEnd = new WeakMap<object, number>(); // when a socket last finished a response: the idle time logged with an error

/** GET/HEAD `pathq` on 127.0.0.1:`port` through `agent`; an error carries `fwReused` (a pooled socket) and `fwIdle` (ms it was idle). */
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

/** The line logged when a preview server cannot be reached (stderr). */
export function log502(who: string, e: unknown, pathq: string): void {
  const x = e as NodeJS.ErrnoException & { fwReused?: boolean; fwIdle?: number };
  console.error(`preview-502 ${JSON.stringify({ who, code: x.code, syscall: x.syscall, msg: x.message, reused: x.fwReused, idleMs: x.fwIdle, path: pathq })}`);
}
