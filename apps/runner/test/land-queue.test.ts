// `fw land --queue` (task land-queue; Lean Fw.Console.LandQueue: enq_idem, enq_appends, res_head, retryAfter_iff, runnerLive_iff,
// Fw.Obs.Next.no_unlanded_while_queued). The TS stand-in is checked against packages/contracts/golden/console/land-queue.jsonl;
// the runner is driven against a real fixture repo with three tiny branches (no CI).
import "./land-timeout.ts";
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createApp } from "../../console-api/src/app.ts";
import { selectCore } from "../../console-api/src/core/index.ts";
import { Reconciler } from "../../console-api/src/reconcile/reconciler.ts";
import { Store } from "../../console-api/src/store.ts";
import { makeRepo } from "../../console-api/test/reconcile-fixture.ts";
import { land, type Http } from "../src/land.ts";
import { enqueue, landAttemptResult, landLogOf, parseLog, pending, queued, queuedBranches, queueFile, readLog, results, retryAfter, runQueue, runnerFile, runnerLive, takeRunner, type Ev } from "../src/land-queue.ts";
import { fwcoreStale, KINDS, reasonOf, refusalReason, refusedLine, type Kind } from "../src/land-verdict.ts";

const golden = join(dirname(new URL(import.meta.url).pathname), "../../../packages/contracts/golden/console/land-queue.jsonl");
type G = { name: string; request: Record<string, unknown> & { op: string }; response: Record<string, unknown> };
const rows: G[] = readFileSync(golden, "utf8").trim().split("\n").map((l) => JSON.parse(l));
const logOf = (q: Record<string, unknown>): Ev[] => (q.log as Record<string, unknown>[]).map((e) => (e.ev === "enq"
  ? { ev: "enq", task: e.task as string, branch: e.branch as string, allow: [] } : { ev: "res", task: e.task as string, kind: e.kind as Kind }));

describe("land queue vs Lean golden", () => {
  for (const g of rows) it(g.name, () => {
    const q = g.request;
    if (q.op === "landQueue.pending") {
      const p = pending(logOf(q));
      expect(g.response).toEqual({ pending: p.map((x) => ({ task: x.task, branch: x.branch })), next: p[0] ? { task: p[0].task, branch: p[0].branch } : null });
    } else if (q.op === "landQueue.queued") expect(g.response).toEqual({ queued: queued(pending(logOf(q)), q.branch as string) });
    else if (q.op === "landQueue.retry") expect(g.response).toEqual({ retry: retryAfter(q.kind as Kind, q.tries as number, q.max as number) });
    else if (q.op === "landQueue.live") expect(g.response).toEqual({ live: runnerLive(q.held as string, q.probe as string | null) });
    else if (q.op === "landQueue.reason") expect(g.response).toEqual({ reason: reasonOf(q.message as string), line: refusedLine(q.message as string) });
    else if (q.op === "landQueue.refusalReason") expect(g.response).toEqual({ reason: refusalReason(q.kind as Kind, (q.reason as string | null) ?? undefined) ?? null });
    else if (q.op === "landQueue.fwcoreStale") expect(g.response).toEqual({ stale: fwcoreStale(q.recorded as string | null, q.same as boolean, q.moved as boolean) });
    else throw new Error(`unknown op ${q.op}`);
  });
  it("covers every kind", () => expect(rows.filter((g) => g.request.op === "landQueue.retry").length).toBeGreaterThanOrEqual(KINDS.length));
});

const tmp = () => { const fx = makeRepo(); return fx.consoleDir; };

describe("queue file", () => {
  it("enqueue is idempotent per task and keeps order; a torn line is skipped", () => {
    const dir = tmp();
    expect(enqueue(dir, { task: "a", branch: "wa", allow: [] }).added).toBe(true);
    expect(enqueue(dir, { task: "b", branch: "wb", allow: ["x/**"] }).added).toBe(true);
    expect(enqueue(dir, { task: "a", branch: "other", allow: [] }).added).toBe(false);
    appendFileSync(queueFile(dir), "{torn\n");
    expect(pending(readLog(dir)).map((x) => [x.task, x.branch, x.allow])).toEqual([["a", "wa", []], ["b", "wb", ["x/**"]]]);
    expect(queuedBranches(dir)).toEqual(["wa", "wb"]);
    expect(parseLog("not json\n{\"ev\":\"zzz\"}\n")).toEqual([]);
  });
  it("land.queueAppendAtomic: 20 concurrent enqueuers leave 20 whole lines", async () => {
    const dir = tmp();
    mkdirSync(dir, { recursive: true });
    await Promise.all(Array.from({ length: 20 }, (_, i) => Promise.resolve().then(() => appendFileSync(queueFile(dir), JSON.stringify({ ev: "enq", task: `t${i}`, branch: `w${i}`, allow: [] }) + "\n"))));
    expect(pending(readLog(dir))).toHaveLength(20);
    expect(readFileSync(queueFile(dir), "utf8").trim().split("\n")).toHaveLength(20);
  });
  it("results keeps the last kind per task", () => {
    expect(results([{ ev: "res", task: "a", kind: "reads" }, { ev: "res", task: "a", kind: "done" }, { ev: "res", task: "b", kind: "scope" }])).toEqual([{ task: "a", kind: "done" }, { task: "b", kind: "scope" }]);
  });
});

describe("runner lock", () => {
  it("a second runner finds a live one (pid + start time) and does not run; a reused pid or a dead holder is taken over", () => {
    const dir = tmp();
    const a = takeRunner(dir, () => "T0");
    expect(a).not.toBeNull();
    expect(takeRunner(dir, () => "T0")).toBeNull(); // same pid, same start time: live
    a!.release();
    expect(existsSync(runnerFile(dir))).toBe(false);
    writeFileSync(runnerFile(dir), JSON.stringify({ pid: 999999, start: "OLD" }));
    const b = takeRunner(dir, () => "NEW"); // the pid is now another incarnation
    expect(b).not.toBeNull();
    b!.release();
    writeFileSync(runnerFile(dir), JSON.stringify({ pid: 999999, start: "OLD" }));
    const c = takeRunner(dir, (pid) => (pid === 999999 ? null : "T1")); // no such process
    expect(c).not.toBeNull();
    c!.release();
  });
});

describe("runQueue", () => {
  const entry = (dir: string, t: string) => enqueue(dir, { task: t, branch: `w-${t}`, allow: [] });
  it("lands first in first out, records one result per task and leaves nothing pending", async () => {
    const dir = tmp();
    ["a", "b", "c"].forEach((t) => entry(dir, t));
    const order: string[] = [];
    const r = await runQueue({ consoleDir: dir, retryMs: 1, attempt: async (e) => { order.push(e.task); return "done"; } });
    expect(order).toEqual(["a", "b", "c"]);
    expect(r.results.map((x) => x.kind)).toEqual(["done", "done", "done"]);
    expect(pending(readLog(dir))).toEqual([]);
    expect(existsSync(runnerFile(dir))).toBe(false);
  });
  it("retries only busy and dirty (bounded); a refusal for good is final, whatever its prose says", async () => {
    const dir = tmp();
    ["a", "b", "c"].forEach((t) => entry(dir, t));
    const calls: Record<string, number> = {};
    const r = await runQueue({ consoleDir: dir, retryMs: 1, maxTries: 3, attempt: async (e) => {
      calls[e.task] = (calls[e.task] ?? 0) + 1;
      if (e.task === "a") return calls.a! < 3 ? (calls.a === 1 ? "busy" : "dirty") : "done";
      if (e.task === "b") return "checks"; // its output may say "busy" (a Lean warning naming dispatch_busy): the kind decides
      return "busy"; // never frees up: stops at maxTries
    } });
    expect(calls).toEqual({ a: 3, b: 1, c: 3 });
    expect(r.results.map((x) => [x.task, x.kind, x.tries])).toEqual([["a", "done", 3], ["b", "checks", 1], ["c", "busy", 3]]);
  });
  it("an attempt that throws is `unknown`, final; the queue goes on", async () => {
    const dir = tmp();
    ["a", "b"].forEach((t) => entry(dir, t));
    const r = await runQueue({ consoleDir: dir, retryMs: 1, attempt: async (e) => { if (e.task === "a") throw new Error("boom"); return "done"; } });
    expect(r.results.map((x) => x.kind)).toEqual(["unknown", "done"]);
  });
  it("a throwing attempt prints its message before the verdict and records it in the queue and land logs", async () => {
    const dir = tmp();
    entry(dir, "a");
    mkdirSync(join(dir, "land-logs"), { recursive: true });
    writeFileSync(join(dir, "land-logs", "a-abc1234.log"), "check output\n");
    const err: string[] = [];
    const r = await runQueue({ consoleDir: dir, retryMs: 1, err: (l) => err.push(l), attempt: async () => { throw new Error("unknown op console.landDigest"); } });
    expect(err).toEqual(["REFUSED: unknown op console.landDigest"]);
    expect(r.results[0]).toMatchObject({ kind: "unknown", reason: "unknown op console.landDigest" });
    const res = readFileSync(queueFile(dir), "utf8").trim().split("\n").map((l) => JSON.parse(l)).find((e) => e.ev === "res");
    expect(res.reason).toBe("unknown op console.landDigest");
    expect(readFileSync(join(dir, "land-logs", "a-abc1234.log"), "utf8")).toContain("REFUSED: unknown op console.landDigest");
  });
  it("a refusal without a message still carries a reason; one the attempt explained is not printed twice", async () => {
    const dir = tmp();
    ["a", "b"].forEach((t) => entry(dir, t));
    const err: string[] = [];
    const r = await runQueue({ consoleDir: dir, err: (l) => err.push(l), attempt: async (e) => (e.task === "a" ? "unknown" : { kind: "scope", reason: "out of scope" }) });
    expect(err).toEqual(["REFUSED: no message"]);
    expect(r.results.map((x) => x.reason)).toEqual(["no message", "out of scope"]);
  });
  it("an empty reason from the attempt becomes 'no message' in the line, the result and the log", async () => {
    const dir = tmp();
    entry(dir, "a");
    const err: string[] = [];
    const r = await runQueue({ consoleDir: dir, err: (l) => err.push(l), attempt: async () => ({ kind: "unknown", reason: "" }) });
    expect(err).toEqual(["REFUSED: no message"]);
    expect(r.results[0]!.reason).toBe("no message");
    expect(readFileSync(queueFile(dir), "utf8")).toContain('"reason":"no message"');
  });
  it("landLogOf matches the exact task name: task a never takes the log of task a-b", () => {
    const dir = tmp();
    mkdirSync(join(dir, "land-logs"), { recursive: true });
    writeFileSync(join(dir, "land-logs", "a-b-abc1234.log"), "x\n");
    expect(landLogOf(dir, "a")).toBe(join(dir, "land-logs", "a-queue.log"));
    expect(landLogOf(dir, "a-b")).toBe(join(dir, "land-logs", "a-b-abc1234.log"));
    writeFileSync(join(dir, "land-logs", "a-def5678.log"), "x\n");
    expect(landLogOf(dir, "a")).toBe(join(dir, "land-logs", "a-def5678.log"));
  });
  it("does not run while a live runner holds the lock; the entry stays pending", async () => {
    const dir = tmp();
    entry(dir, "a");
    const held = takeRunner(dir, () => "T0")!;
    const r = await runQueue({ consoleDir: dir, startTime: () => "T0", attempt: async () => "done" });
    expect(r.ran).toBe(false);
    expect(pending(readLog(dir)).map((x) => x.task)).toEqual(["a"]);
    held.release();
  });
  it("an entry queued while the runner works is landed too (no lost wakeup)", async () => {
    const dir = tmp();
    entry(dir, "a");
    const order: string[] = [];
    const r = await runQueue({ consoleDir: dir, retryMs: 1, attempt: async (e) => { order.push(e.task); if (e.task === "a") entry(dir, "late"); return "done"; } });
    expect(order).toEqual(["a", "late"]);
    expect(r.results).toHaveLength(2);
  });
});

describe("three fixture branches through the real land", () => {
  let stores: Store[] = [];
  afterEach(() => { stores.forEach((s) => s.close()); stores = []; });
  Object.assign(process.env, { GIT_AUTHOR_NAME: "t", GIT_AUTHOR_EMAIL: "t@example.invalid", GIT_COMMITTER_NAME: "t", GIT_COMMITTER_EMAIL: "t@example.invalid" });
  it("lands t1, t2, t3 in queue order; reports the queue overhead per land", async () => {
    const fx = makeRepo();
    const store = await Store.open(fx.consoleDir, selectCore(), () => 1_700_000_000_000);
    stores.push(store);
    const app = createApp(store, undefined, new Reconciler(store, fx.root));
    const http: Http = {
      get: async (p) => { const r = await app.request(p); return { status: r.status, body: await r.json() }; },
      post: async (p, b) => {
        const r = await app.request(p, { method: "POST", body: JSON.stringify(b), headers: { "content-type": "application/json" } });
        return { status: r.status, body: await r.json() };
      },
    };
    const ids = ["t1", "t2", "t3"];
    for (const t of ids) await store.submit({ type: "task.define", key: `d-${t}`, actor: "lead", task: t, title: t, stream: "s", milestone: null, deps: [], owner: "builder", writes: ["src/**"], devices: [], evidence: null } as never);
    mkdirSync(join(fx.root, "docs/team"), { recursive: true });
    writeFileSync(join(fx.root, "docs/team/work-graph.json"), JSON.stringify({ tasks: ids.map((t) => ({ id: t, owner: "builder", stream: "s", writes: ["src/**"], evidence: null })) }, null, 1) + "\n");
    fx.git(fx.root, "add", "--", "docs/team/work-graph.json");
    fx.git(fx.root, "commit", "-q", "-m", "work graph");
    for (const t of ids) fx.commit(fx.worktree(`worktree-agent-${t}`), `src/${t}.ts`);
    const consoleDir = join(fx.root, ".fw-console");
    for (const t of ids) enqueue(consoleDir, { task: t, branch: `worktree-agent-${t}`, allow: [] });
    let landMs = 0;
    const t0 = Date.now();
    const r = await runQueue({ consoleDir, retryMs: 1, attempt: async (e) => {
      const s = Date.now();
      const res = await land(e.branch, { http, cwd: fx.root, checks: [["true"]], ci: false, task: e.task, retryMs: 1, lockWaitMs: 0 });
      landMs += Date.now() - s;
      return res.kind ?? "unknown";
    } });
    const total = Date.now() - t0;
    expect(r.results.map((x) => [x.task, x.kind])).toEqual([["t1", "done"], ["t2", "done"], ["t3", "done"]]);
    // the files arrive on main in queue order (oldest first)
    const added = fx.git(fx.root, "log", "--first-parent", "--diff-filter=A", "--name-only", "--format=", "main", "--", "src").split("\n").filter(Boolean).reverse();
    expect(added.filter((f) => /^src\/t\d\.ts$/.test(f))).toEqual(["src/t1.ts", "src/t2.ts", "src/t3.ts"]);
    expect(pending(readLog(consoleDir))).toEqual([]);
    process.stderr.write(`land-queue overhead: total ${total} ms, in land ${landMs} ms, overhead ${total - landMs} ms for 3 lands (${((total - landMs) / 3).toFixed(1)} ms per land)\n`);
  });
});

describe("landAttemptResult", () => {
  it("a refused land gives its kind and the reason of its last REFUSED line", () =>
    expect(landAttemptResult({ ok: false, kind: "scope", lines: ["REFUSED: first", "x", "REFUSED: out of scope"] })).toEqual({ kind: "scope", reason: "out of scope" }));
  it("a refused land without a REFUSED line gives just its kind (unknown when it has none)", () => {
    expect(landAttemptResult({ ok: false, kind: "checks", lines: ["check output"] })).toBe("checks");
    expect(landAttemptResult({ ok: false, lines: [] })).toBe("unknown");
  });
  it("an ok land gives done, or its own kind", () => {
    expect(landAttemptResult({ ok: true, lines: ["REFUSED: stale note"] })).toBe("done");
    expect(landAttemptResult({ ok: true, kind: "empty", lines: [] })).toBe("empty");
  });
});
