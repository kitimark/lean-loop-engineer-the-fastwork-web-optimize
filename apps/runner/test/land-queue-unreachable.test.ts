// Task land-queue-unreachable (Lean Fw.Console.LandQueue: health_bounded, healthReached_within, healthReached_never, healthReached_late,
// attemptNext_unreachable_not_unknown, attemptNext_returns, attemptNext_never, attemptNext_exhausted, healthWaitAfter_iff).
// The TS twin is checked against the golden ops landQueue.health / healthSchedule / attempt / healthAfter; the queue is driven against
// a fake console (a real HTTP server on a loopback port) that goes away and comes back.
import "./land-timeout.ts";
import { readFileSync } from "node:fs";
import { createServer, type Server } from "node:http";
import { dirname, join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { makeRepo } from "../../console-api/test/reconcile-fixture.ts";
import { httpFor } from "../src/land.ts";
import { CONSOLE_UNREACHABLE_REASON, ConsoleUnreachable, HEALTH_BOUND_MS, HEALTH_POLLS, attemptNext, enqueue, healthDelay, healthReached, healthWaitAfter, pending, pollTime, readLog, runQueue, waitHealth } from "../src/land-queue.ts";
import type { Kind } from "../src/land-verdict.ts";

const PROBE_CAP = 2000, REQS = 3; // a health probe's own cap; requests per client test
const golden = join(dirname(new URL(import.meta.url).pathname), "../../../packages/contracts/golden/console/land-queue.jsonl");
type G = { name: string; request: Record<string, unknown> & { op: string }; response: Record<string, unknown> };
const rows: G[] = readFileSync(golden, "utf8").trim().split("\n").map((l) => JSON.parse(l) as G);

describe("unreachable console vs Lean golden", () => {
  for (const g of rows.filter((r) => /^landQueue\.(health|healthSchedule|attempt|healthAfter)$/.test(r.request.op))) it(g.name, () => {
    const q = g.request;
    if (q.op === "landQueue.health") expect(g.response).toEqual({ reached: healthReached(q.back as number | null) });
    else if (q.op === "landQueue.healthSchedule") {
      const idx = Array.from({ length: HEALTH_POLLS }, (_, i) => i);
      expect(g.response).toEqual({ polls: HEALTH_POLLS, delays: idx.map(healthDelay), times: idx.map(pollTime), boundMs: HEALTH_BOUND_MS });
    } else if (q.op === "landQueue.attempt") {
      const n = attemptNext(q.kind === null ? "unreachable" : { landed: q.kind as Kind }, q.tries as number, q.max as number, q.back as number | null);
      expect(g.response).toEqual({ next: n === "retry" ? "retry" : "final", kind: n === "retry" ? null : n.final, reason: n !== "retry" && n.reason !== undefined ? n.reason : null });
    } else expect(g.response).toEqual({ wait: healthWaitAfter(q.kind as Kind, q.paths as string[]) });
  });
  it("covers each branch of the decision", () => {
    const names = rows.filter((r) => r.request.op === "landQueue.attempt").map((r) => r.name).join("|");
    for (const w of ["back in 5 s", "back at the bound", "back after the bound", "never back", "attempts used"]) expect(names).toContain(w);
  });
});

/** A fake console: GET /api/health and GET /api/plan answer 200 while it listens; down means the port refuses connections. */
function fakeConsole() {
  let srv: Server | null = null;
  let port = 0;
  const up = async () => {
    srv = createServer((req, res) => { res.setHeader("content-type", "application/json"); res.end(req.url === "/api/health" ? '{"ok":true}' : '{"tasks":[]}'); });
    await new Promise<void>((ok) => srv!.listen(port, "127.0.0.1", () => ok()));
    port = (srv.address() as { port: number }).port;
  };
  const down = async () => { const s = srv; srv = null; if (s) await new Promise<void>((ok) => { s.close(() => ok()); s.closeAllConnections(); }); };
  return { up, down, base: () => `http://127.0.0.1:${port}`, isUp: () => srv !== null };
}

describe("a console that goes away and comes back", () => {
  let fc: ReturnType<typeof fakeConsole>;
  afterEach(async () => { await fc.down(); });
  const setup = async (downMs: number | null) => {
    fc = fakeConsole();
    await fc.up();
    const base = fc.base();
    await fc.down(); // same port, refused from now on
    const http = httpFor(base);
    let clock = 0; // virtual time since the first failure
    const sleeps: number[] = [];
    const sleep = async (ms: number) => { sleeps.push(ms); clock += ms; if (downMs !== null && clock >= downMs && !fc.isUp()) await fc.up(); };
    const health = async () => { try { return (await fetch(`${base}/api/health`, { signal: AbortSignal.timeout(PROBE_CAP) })).ok; } catch { return false; } };
    const attempt = async () => { await http.get("/api/plan"); return "done" as Kind; };
    return { http, sleep, sleeps, health, attempt, clock: () => clock };
  };

  it("httpFor turns a refused connection into ConsoleUnreachable (not a generic error)", async () => {
    const s = await setup(null);
    await expect(s.http.get("/api/plan")).rejects.toBeInstanceOf(ConsoleUnreachable);
  });

  for (const downMs of [0, 1000, 12_000, HEALTH_BOUND_MS]) it(`down ${downMs} ms then up: the entry lands (done, never unknown)`, async () => {
    const dir = makeRepo().consoleDir;
    enqueue(dir, { task: "a", branch: "wa", allow: [] });
    enqueue(dir, { task: "b", branch: "wb", allow: [] });
    const s = await setup(downMs);
    const r = await runQueue({ consoleDir: dir, retryMs: 1, attempt: s.attempt, health: s.health, sleep: s.sleep });
    expect(r.results.map((x) => [x.task, x.kind])).toEqual([["a", "done"], ["b", "done"]]);
    expect(r.results[0]!.tries).toBe(2); // the failed first attempt, then the land
    expect(s.clock()).toBeLessThanOrEqual(HEALTH_BOUND_MS);
    expect(pending(readLog(dir))).toEqual([]);
  });

  it("never up: the named refusal console-unreachable (kind busy, not unknown) after a bounded wait; the rest stays pending", async () => {
    const dir = makeRepo().consoleDir;
    enqueue(dir, { task: "a", branch: "wa", allow: [] });
    enqueue(dir, { task: "b", branch: "wb", allow: [] });
    const s = await setup(null);
    const errs: string[] = [];
    const r = await runQueue({ consoleDir: dir, retryMs: 1, attempt: s.attempt, health: s.health, sleep: s.sleep, err: (l) => errs.push(l), maxTries: 5 });
    const a = r.results.find((x) => x.task === "a")!;
    expect(a.kind).toBe("busy");
    expect(a.kind).not.toBe("unknown");
    expect(a.reason).toBe(CONSOLE_UNREACHABLE_REASON);
    expect(a.reason!.startsWith("console-unreachable")).toBe(true);
    expect(errs).toContain(`REFUSED: ${CONSOLE_UNREACHABLE_REASON}`);
    expect(s.clock()).toBe(HEALTH_BOUND_MS); // one full wait, then the queue stops
    expect(s.sleeps).toHaveLength(HEALTH_POLLS - 1);
    expect(r.results).toHaveLength(1);
    expect(pending(readLog(dir)).map((x) => x.task)).toEqual(["b"]);
  });

  it("back only after the bound: still the named refusal", async () => {
    const dir = makeRepo().consoleDir;
    enqueue(dir, { task: "a", branch: "wa", allow: [] });
    const s = await setup(HEALTH_BOUND_MS + 1);
    const r = await runQueue({ consoleDir: dir, retryMs: 1, attempt: s.attempt, health: s.health, sleep: s.sleep, maxTries: 1 });
    expect(r.results[0]).toMatchObject({ task: "a", kind: "busy", reason: CONSOLE_UNREACHABLE_REASON });
  });

  it("a console that is down at every attempt exhausts maxTries into the named refusal", async () => {
    const dir = makeRepo().consoleDir;
    enqueue(dir, { task: "a", branch: "wa", allow: [] });
    let n = 0;
    const r = await runQueue({ consoleDir: dir, retryMs: 1, maxTries: 3, health: async () => true, sleep: async () => undefined,
      attempt: async () => { n++; throw new ConsoleUnreachable("http://127.0.0.1:1", new Error("refused")); } });
    expect(n).toBe(3);
    expect(r.results[0]).toMatchObject({ kind: "busy", tries: 3, reason: CONSOLE_UNREACHABLE_REASON });
  });

  it("without a health probe a thrown error is still unknown (unchanged)", async () => {
    const dir = makeRepo().consoleDir;
    enqueue(dir, { task: "a", branch: "wa", allow: [] });
    const r = await runQueue({ consoleDir: dir, retryMs: 1, attempt: async () => { throw new ConsoleUnreachable("u", new Error("x")); } });
    expect(r.results[0]!.kind).toBe("unknown");
  });

  it("waitHealth polls on the Lean schedule", async () => {
    const sleeps: number[] = [];
    expect(await waitHealth(async () => false, async (ms) => { sleeps.push(ms); })).toBe(false);
    expect(sleeps).toEqual(Array.from({ length: HEALTH_POLLS - 1 }, (_, i) => healthDelay(i)));
    expect(sleeps.reduce((a, b) => a + b, 0)).toBe(HEALTH_BOUND_MS);
  });
});

describe("after the queue's own fwcore rebuild", () => {
  const two = (dir: string) => { enqueue(dir, { task: "a", branch: "wa", allow: [] }); enqueue(dir, { task: "b", branch: "wb", allow: [] }); };
  const opts = (dir: string, order: string[], health: () => Promise<boolean>) => {
    let n = 0;
    return { consoleDir: dir, retryMs: 1, sleep: async () => undefined, health,
      attempt: async () => { n++; order.push(`land-${n}`); return "done" as Kind; },
      head: () => `h${n}`, diff: () => ["lean/Fw/X.lean"], rebuild: async () => { order.push("rebuild"); return true; } };
  };
  it("waits for the console's health before the next entry (a restart window of 3 probes)", async () => {
    const dir = makeRepo().consoleDir;
    two(dir);
    const order: string[] = [];
    let probes = 0;
    const r = await runQueue(opts(dir, order, async () => { probes++; order.push("probe"); return probes > 3; }));
    expect(order).toEqual(["land-1", "rebuild", "probe", "probe", "probe", "probe", "land-2", "rebuild", "probe"]);
    expect(r.results.map((x) => x.kind)).toEqual(["done", "done"]);
  });
  it("a console that does not return gives the next entry the named refusal and stops the queue", async () => {
    const dir = makeRepo().consoleDir;
    two(dir);
    enqueue(dir, { task: "c", branch: "wc", allow: [] });
    const errs: string[] = [];
    const r = await runQueue({ ...opts(dir, [], async () => false), err: (l) => errs.push(l) });
    expect(r.results.map((x) => [x.task, x.kind, x.reason])).toEqual([["a", "done", undefined], ["b", "busy", CONSOLE_UNREACHABLE_REASON]]);
    expect(errs).toEqual([`REFUSED: ${CONSOLE_UNREACHABLE_REASON}`]);
    expect(pending(readLog(dir)).map((x) => x.task)).toEqual(["c"]);
  });
  it("no health wait after a land that changed no core source", async () => {
    const dir = makeRepo().consoleDir;
    two(dir);
    let probes = 0;
    await runQueue({ ...opts(dir, [], async () => { probes++; return false; }), diff: () => ["docs/x.md"] });
    expect(probes).toBe(0);
  });
});

/** A fake console that counts sockets and keeps the `connection` header of every request. */
async function countingConsole(keepAliveTimeoutMs: number) {
  const seen: string[] = [];
  let sockets = 0;
  const srv = createServer((req, res) => { seen.push(String(req.headers.connection)); res.setHeader("content-type", "application/json"); res.end('{"ok":true}'); });
  srv.keepAliveTimeout = keepAliveTimeoutMs;
  srv.on("connection", () => { sockets++; });
  await new Promise<void>((ok) => srv.listen(0, "127.0.0.1", () => ok()));
  return { base: `http://127.0.0.1:${(srv.address() as { port: number }).port}`, seen, sockets: () => sockets, close: async () => { srv.closeAllConnections(); await new Promise<void>((ok) => srv.close(() => ok())); } };
}

// Mechanism (INFERRED for the six 2026-10-20 failures, reproduced as a race): the land process sat 7-14 s in synchronous calls after its last
// console request, past the console's 5 s keepAliveTimeout; the next fetch reused the pooled socket the console had closed -> ECONNRESET
// "fetch failed". The reuse is deterministic (first test); the reset on it is a race (the opt-in test below, ~3 % per try in isolation).
describe("the land's HTTP client never reuses a socket", () => {
  it("plain fetch reuses keep-alive sockets (the precondition of the reset)", async () => {
    const c = await countingConsole(5000);
    try {
      for (let i = 0; i < REQS; i++) await (await fetch(`${c.base}/api/plan`)).json();
      expect(c.sockets()).toBeLessThan(REQS); // pooled: fewer sockets than requests
    } finally { await c.close(); }
  });
  it("httpFor sends connection: close and dials one socket per request, also across a blocked event loop", async () => {
    const c = await countingConsole(300);
    try {
      const http = httpFor(c.base);
      for (let i = 0; i < REQS; i++) {
        expect((await http.get("/api/plan")).status).toBe(200);
        Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 450); // block the loop past the server's keepAliveTimeout, as the land's sync calls do
      }
      expect(c.sockets()).toBe(REQS);
      expect(c.seen).toEqual(Array(REQS).fill("close"));
    } finally { await c.close(); }
  });
});
