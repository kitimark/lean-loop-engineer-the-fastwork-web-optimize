// Event-driven drain and reconciler (task console-idle-cpu): the journal cache, the settled-run skip and the safety tick
// equal Lean `Fw.Console.JournalFold` / `ReconcileSched` on their golden vectors, and the watchers lose no event.
import { appendFileSync, mkdirSync, mkdtempSync, readFileSync, statSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { monitorEventLoopDelay } from "node:perf_hooks";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it } from "vitest";
import { selectCore } from "../src/core/index.ts";
import { Reconciler } from "../src/reconcile/reconciler.ts";
import { Drain } from "../src/spool/drain.ts";
import { DRAIN_SETTLE_MS, startDrainWatch, wakeDoneBound, wakeStartBound } from "../src/spool/drain-watch.ts";
import { commitEnd, JournalCache, nextTick, plan, skipRun } from "../src/spool/journal-cache.ts";
import { parseJournal, scanWorkflows, WfMemo, workflowWatchTargets } from "../src/spool/workflow.ts";
import { Store } from "../src/store.ts";
import { Trigger } from "../src/trigger.ts";
import { Watches } from "../src/watch.ts";
import { makeRepo } from "./reconcile-fixture.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "../../..");
type Case = { kind: string } & Record<string, never>;
const vectors = readFileSync(join(root, "packages/contracts/golden/console/journal-cache.jsonl"), "utf8").trim().split("\n")
  .map((l) => JSON.parse(l) as Record<string, unknown> & { kind: string });
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const until = async (f: () => boolean | Promise<boolean>, ms = 3000) => {
  const t0 = Date.now();
  while (!(await f())) { if (Date.now() - t0 > ms) throw new Error("timeout"); await sleep(10); }
};

let stores: Store[] = [];
let stops: (() => void)[] = [];
afterEach(() => { stops.forEach((s) => s()); stops = []; stores.forEach((s) => s.close()); stores = []; });

describe("journal cache (TS stand-in of Fw.Console.JournalFold)", () => {
  it("has golden vectors of every kind", () => {
    for (const k of ["plan", "commit", "skip", "tick"]) expect(vectors.filter((v) => v.kind === k).length).toBeGreaterThan(3);
  });
  for (const [i, v] of vectors.entries()) {
    it(`matches Lean: case ${i} ${v.kind}`, () => {
      if (v.kind === "plan") expect(plan(v.cached as never, v.stat as never, v.guard as boolean)).toBe(v.act);
      else if (v.kind === "commit") expect(commitEnd(Uint8Array.from(v.bytes as number[]))).toBe(v.end);
      else if (v.kind === "skip") expect(skipRun(v as never)).toBe(v.skip);
      else if (v.kind === "tick") expect(nextTick(v.period as number, v.t as number)).toBe(v.next);
      else throw new Error(`unknown kind ${v.kind}`);
    });
  }

  it("incremental reads equal a full parse at every step, torn lines included", () => {
    const dir = mkdtempSync(join(tmpdir(), "fw-jc-"));
    const f = join(dir, "journal.jsonl");
    const line = (o: object) => JSON.stringify(o) + "\n";
    const chunks = [line({ type: "launched" }), line({ type: "started", agentId: "a1", label: "b:t1" }).slice(0, 20),
      line({ type: "started", agentId: "a1", label: "b:t1" }).slice(20) + line({ type: "started", agentId: "a2", label: "b:t2" }),
      JSON.stringify({ type: "result", agentId: "a1" }), "\n", line({ type: "failed", agentId: "a2" })];
    const c = new JournalCache();
    writeFileSync(f, "");
    let total = 0;
    for (const [i, ch] of chunks.entries()) {
      appendFileSync(f, ch);
      total += ch.length;
      const s = statSync(f);
      const got = c.read("wf_aaaaaaaa-aaa", f, { size: s.size, mtime: Math.floor(s.mtimeMs) + i * 1000 }); // distinct mtimes: a fast test appends within a ms
      expect(got).toEqual(parseJournal("wf_aaaaaaaa-aaa", readFileSync(f, "utf8")));
    }
    expect(c.bytesRead).toBeLessThan(total * 2); // each byte read about once (a torn tail is read again from the offset)
    const s = statSync(f), st = { size: s.size, mtime: Math.floor(s.mtimeMs) + 99_000 };
    const before = c.bytesRead;
    c.read("wf_aaaaaaaa-aaa", f, st); // another mtime, same size: a rewrite, read in full
    expect(c.bytesRead - before).toBe(s.size);
    const again = c.bytesRead;
    c.read("wf_aaaaaaaa-aaa", f, st);
    expect(c.bytesRead).toBe(again); // same stat: nothing read
    writeFileSync(f, line({ type: "launched" })); // shrunk: full read of the new content
    const s2 = statSync(f);
    expect(c.read("wf_aaaaaaaa-aaa", f, { size: s2.size, mtime: Math.floor(s2.mtimeMs) + 200_000 })).toEqual([]);
  });
});

describe("settled runs", () => {
  const def = async (store: Store, t: string) =>
    expect((await store.submit({ type: "task.define", key: `d:${t}`, actor: "lead", task: t, title: "T", stream: "s", milestone: null, deps: [],
      owner: "o", writes: [], devices: [], needs: [], evidence: null } as never)).ok).toBe(true);

  it("an ended, fully accepted run is not read again; a later append, a new task or a new run still count", async () => {
    const dir = mkdtempSync(join(tmpdir(), "fw-wf-"));
    const store = await Store.open(dir, selectCore(), () => 1_700_000_000_000);
    stores.push(store);
    const wf = join(dir, "sess", "workflows");
    const runDir = (r: string) => join(dir, "sess", "subagents", "workflows", r);
    mkdirSync(join(wf, "scripts"), { recursive: true });
    const r1 = "wf_b37180a7-494", r2 = "wf_c37180a7-495";
    for (const r of [r1, r2]) mkdirSync(runDir(r), { recursive: true });
    const line = (o: object) => JSON.stringify(o) + "\n";
    await def(store, "fix-nav");
    writeFileSync(join(wf, "scripts", `fix-nav-${r1}.js`), "");
    writeFileSync(join(runDir(r1), "journal.jsonl"), line({ type: "started", agentId: "a1", label: "b:fix-nav" }));
    writeFileSync(join(wf, "scripts", `other-${r2}.js`), "");
    writeFileSync(join(runDir(r2), "journal.jsonl"), line({ type: "started", agentId: "a2", label: "b:later-task" }));
    writeFileSync(join(wf, `${r1}.json`), "{}");
    writeFileSync(join(wf, `${r2}.json`), "{}");
    const drain = new Drain(store, () => [wf]);
    await drain.run();
    expect((await store.board()).plan.tasks.find((t) => t.id === "fix-nav")?.agent).toBeNull(); // ended
    const read0 = drain.wfMemo.journals.bytesRead;
    expect(read0).toBeGreaterThan(0);
    await drain.run();
    expect(drain.wfMemo.journals.bytesRead).toBe(read0); // both runs settled: nothing read
    const seq = store.seq;
    await drain.run();
    expect(store.seq).toBe(seq);
    // a task defined later whose name labels an agent of a settled run: the ids changed, so the run is looked at again
    await def(store, "later-task");
    await drain.run();
    const lt = (await store.board()).plan.tasks.find((t) => t.id === "later-task");
    expect(store.seq).toBeGreaterThan(seq + 1);
    expect(lt?.agent).toBeNull(); // spawned and stopped (its run ended)
    // events a full scan without a memo would send are the events the memo sent, never fewer
    const full = scanWorkflows(wf, (await store.board()).plan.tasks.map((t) => t.id));
    const memo = new WfMemo();
    expect(scanWorkflows(wf, (await store.board()).plan.tasks.map((t) => t.id), memo)).toEqual(full);
  });

  it("an ended run that appends again is read again", async () => {
    const dir = mkdtempSync(join(tmpdir(), "fw-wf-"));
    const store = await Store.open(dir, selectCore(), () => 1_700_000_000_000);
    stores.push(store);
    const wf = join(dir, "sess", "workflows");
    const r = "wf_d37180a7-496", rd = join(dir, "sess", "subagents", "workflows", r);
    mkdirSync(join(wf, "scripts"), { recursive: true });
    mkdirSync(rd, { recursive: true });
    await def(store, "fix-nav");
    const j = join(rd, "journal.jsonl");
    writeFileSync(j, JSON.stringify({ type: "started", agentId: "a1", label: "b:x" }) + "\n");
    writeFileSync(join(wf, `${r}.json`), "{}");
    const drain = new Drain(store, () => [wf]);
    await drain.run();
    const read0 = drain.wfMemo.journals.bytesRead;
    appendFileSync(j, JSON.stringify({ type: "started", agentId: "a3", label: "b:fix-nav" }) + "\n");
    utimesSync(j, Date.now() / 1000 + 5, Date.now() / 1000 + 5);
    await drain.run();
    expect(drain.wfMemo.journals.bytesRead).toBeGreaterThan(read0);
    expect(drain.wfMemo.journals.bytesRead - read0).toBeLessThan(200); // only the appended line
    expect((await store.board()).plan.tasks.find((t) => t.id === "fix-nav")).toBeTruthy();
  });

  it("watch targets: FW_WORKFLOWS_DIR names the session dirs; the project dir is watched for new sessions", () => {
    const t = workflowWatchTargets("/x", { FW_WORKFLOWS_DIR: "/a/sess/workflows" });
    expect(t.map((x) => x.path)).toEqual(["/a/sess", "/a/sess/subagents", "/a/sess/workflows", "/a/sess/subagents/workflows"]);
    const rec = t.find((x) => x.path === "/a/sess/workflows")!;
    expect([rec.accept("journal.jsonl"), rec.accept("agent-a1.jsonl"), rec.accept("agent-a1.meta.json"), rec.accept("wf_1.json")]).toEqual([true, false, true, true]);
    const none = workflowWatchTargets("/x y", {}, "/nonexistent-home");
    expect(none.map((x) => x.recursive)).toEqual([false]);
  });
});

describe("Watches", () => {
  it("a missing path is not counted as opened (Node 24.21.0 Linux accepts a recursive watch of it and never fires); it opens once it exists", async () => {
    const d = mkdtempSync(join(tmpdir(), "fw-wm-"));
    const missing = join(d, "a", "b");
    let events = 0;
    const w = new Watches(() => [{ path: missing, recursive: true, accept: () => true }], () => { events++; });
    stops.push(() => w.close());
    expect(w.sync()).toBe(0);
    expect(w.size).toBe(0);
    mkdirSync(join(missing, "c"), { recursive: true });
    expect(w.sync()).toBe(1);
    expect(w.sync()).toBe(0); // already open
    await sleep(100);
    writeFileSync(join(missing, "c", "j.jsonl"), "{}\n");
    await until(() => events > 0, 2000);
  });
});

describe("Trigger", () => {
  it("coalesces pokes into one pass and runs a pass after a request that arrives during one", async () => {
    let passes = 0, release!: () => void;
    let gate = new Promise<void>((r) => { release = r; });
    const t = new Trigger({ run: async () => { passes++; await gate; }, safetyMs: 60_000, settleMs: 20 });
    for (let i = 0; i < 10; i++) t.poke();
    await sleep(60);
    expect(passes).toBe(1);
    t.poke(); await sleep(60); t.poke(); await sleep(60); // two requests while the pass runs: one pending
    expect(passes).toBe(1);
    const open = release; gate = new Promise<void>((r) => { release = r; });
    open();
    await until(() => passes === 2);
    release();
    await sleep(30);
    expect(passes).toBe(2);
    t.stop();
  });

  it("the safety tick runs a pass with no event", async () => {
    let passes = 0;
    const t = new Trigger({ run: async () => { passes++; }, safetyMs: 50, settleMs: 10 });
    t.start();
    await until(() => passes >= 3);
    t.stop();
  });
});

describe("drain on file events", () => {
  const spool = (dir: string, n: string, o: object) => appendFileSync(join(dir, "spool", `${n}.jsonl`), JSON.stringify(o) + "\n");
  const rec = (o: Record<string, unknown> = {}) => ({ agent_id: "a1", agent_type: "builder", hook_event_name: "PostToolUse", tool_name: "Bash",
    tool_use_id: "t1", duration_ms: 100, is_error: false, verb: "pnpm", ts: 1, ...o });
  const fresh = async () => {
    const dir = mkdtempSync(join(tmpdir(), "fw-dw-"));
    const store = await Store.open(dir, selectCore(), () => 1_700_000_000_000);
    stores.push(store);
    mkdirSync(join(dir, "spool"));
    return { dir, store };
  };

  it("a spool append is drained at once, far sooner than the safety tick", async () => {
    const { dir, store } = await fresh();
    const d = new Drain(store, () => []);
    const w = startDrainWatch(dir, () => d.run(), () => undefined, 60_000, () => []);
    stops.push(w.stop);
    await until(() => w.trigger.passes >= 1);
    await sleep(100);
    const n0 = w.trigger.passes;
    spool(dir, "a1", rec());
    await until(() => store.seq >= 1, 2000);
    await until(() => w.trigger.passes > n0);
    const idle = w.trigger.passes;
    await sleep(300);
    expect(w.trigger.passes).toBe(idle); // no timer drives it
  });

  it("a dropped event (no watcher) is drained by the safety tick", async () => {
    const { dir, store } = await fresh();
    const d = new Drain(store, () => []);
    const w = startDrainWatch(dir, () => d.run(), () => undefined, 200, () => []);
    stops.push(w.stop);
    await until(() => w.trigger.passes >= 1);
    w.watches.close(); // every event from here on is "dropped"
    spool(dir, "a1", rec({ tool_use_id: "t9" }));
    await until(() => store.seq >= 1, 3000);
  });

  // Wake bound (Lean `ReconcileSched.poke_wake_le`, `tick_wake_le`; assumptions and deadlines in golden `wake-params.jsonl`): the
  // pass that answers an append or a new session dir is the first one that starts after it, and it starts by the event time plus
  // `wakeStartBound(period, PASS_MAX_MS)`, the period being the settle window (a file event) or the safety tick (an event the
  // kernel dropped). The deadline adds `WAKE_MARGIN_MS` for timer rounding and event-loop lag. There is no other allowance: a pass
  // over `PASS_MAX_MS` (the assumption of the bound) and a loop stall over `WAKE_MARGIN_MS` fail the test at once, each with the
  // trail (pokes, passes with their start, length and pokes, loop lag, the wait that failed, Node version) that names the cause.
  const param = (name: string): number => {
    const row = paramRows.find((r) => r.name === name);
    if (!row) throw new Error(`wake-params.jsonl has no row ${name}`);
    return row.value;
  };
  const paramRows = readFileSync(join(root, "packages/contracts/golden/console/wake-params.jsonl"), "utf8").trim().split("\n")
    .map((l) => JSON.parse(l) as { name: string; value: number; kind: string });
  const wakeRows = readFileSync(join(root, "packages/contracts/golden/console/wake-bound.jsonl"), "utf8").trim().split("\n")
    .map((l) => JSON.parse(l) as { settle: number; pass: number; start: number; done: number });
  const POLL_MS = 5;

  it("the TS wake bounds and test parameters equal the Lean golden rows", () => {
    expect(wakeRows.length).toBeGreaterThan(3);
    for (const r of wakeRows) {
      expect(wakeStartBound(r.settle, r.pass)).toBe(r.start);
      expect(wakeDoneBound(r.settle, r.pass)).toBe(r.done);
    }
    expect(param("settle_ms")).toBe(DRAIN_SETTLE_MS);
    expect(param("event_deadline_ms")).toBe(wakeStartBound(DRAIN_SETTLE_MS, param("pass_max_ms")) + param("wake_margin_ms"));
    expect(param("rescue_deadline_ms")).toBe(wakeStartBound(param("rescue_tick_ms"), param("pass_max_ms")) + param("wake_margin_ms"));
  });

  type Pass = { start: number; end: number | null; pokes: number };

  /** One run of the scenario: a journal line is appended (event path: after a new session dir) and the first pass that starts after
   *  it must start by `deadline` and, once done, have put the line's agent on its task. `watcher: false` leaves the workflow dirs
   *  unwatched, so only the tick can answer. Resolves with the trail text; rejects with it when a bound fails. */
  async function wakeScenario(o: { tick: number; watcher: boolean; newDir: boolean; deadline: number }): Promise<string> {
    const { dir, store } = await fresh();
    const maxPass = param("pass_max_ms"), margin = param("wake_margin_ms");
    const wf = join(dir, "sess", "workflows");
    const run = "wf_e37180a7-497";
    const rd = join(dir, "sess", "subagents", "workflows", run);
    mkdirSync(join(wf, "scripts"), { recursive: true });
    if (!o.newDir) mkdirSync(rd, { recursive: true });
    const submitted = await store.submit({ type: "task.define", key: "d:fix-nav", actor: "lead", task: "fix-nav", title: "T", stream: "s",
      milestone: null, deps: [], owner: "o", writes: [], devices: [], needs: [], evidence: null } as never);
    expect(submitted.ok).toBe(true);
    const agentOf = async () => (await store.board()).plan.tasks.find((t) => t.id === "fix-nav")?.agent ?? null;
    const lag = monitorEventLoopDelay({ resolution: 10 });
    lag.enable();
    stops.push(() => lag.disable());
    const passes: Pass[] = [];
    const ref: { w?: ReturnType<typeof startDrainWatch> } = {};
    const d = new Drain(store, () => [wf]);
    const w = startDrainWatch(dir, async () => {
      const p: Pass = { start: performance.now(), end: null, pokes: ref.w?.trigger.pokes ?? 0 };
      passes.push(p);
      try { return await d.run(); } finally { p.end = performance.now(); }
    }, () => undefined, o.tick, () => o.watcher ? workflowWatchTargets(dir, { FW_WORKFLOWS_DIR: wf }) : []);
    ref.w = w;
    stops.push(w.stop);
    const t0 = performance.now();
    const ms = (x: number) => (x - t0).toFixed(0);
    const trail = (what: string, cause: string): string => [
      `${what}: ${cause}`,
      `node ${process.version}; tick ${o.tick}, deadline ${o.deadline}, PASS_MAX_MS ${maxPass}, margin ${margin}, watches ${w.watches.size}, pokes ${w.trigger.pokes}, passes ${w.trigger.passes}`,
      `loop lag ms: max ${(lag.max / 1e6).toFixed(0)}, mean ${(lag.mean / 1e6).toFixed(0)}, p99 ${(lag.percentile(99) / 1e6).toFixed(0)}`,
      ...passes.map((p, i) => `  pass ${i}: start ${ms(p.start)}, length ${p.end === null ? "running" : (p.end - p.start).toFixed(0)}, pokes at start ${p.pokes}`),
    ].join("\n");
    const waitPassEnd = async (i: number, what: string) => {
      for (;;) {
        const p = passes[i]!;
        if (p.end !== null) return;
        if (performance.now() - p.start > maxPass) throw new Error(trail(what, `pass ${i} still running after PASS_MAX_MS (long pass)`));
        await sleep(POLL_MS);
      }
    };
    /** Wait for the first pass numbered `from` or later; return its index. */
    const answer = async (what: string, from: number, writeAt: number, pokesAtWrite: number, mustPoke: boolean): Promise<number> => {
      lag.reset();
      while (passes.length <= from) {
        const running = passes[from - 1];
        if (running && running.end === null && performance.now() - running.start > maxPass)
          throw new Error(trail(what, `pass ${from - 1} runs over PASS_MAX_MS (long pass)`));
        if (performance.now() - writeAt > o.deadline) {
          const slow = passes.some((p) => p.end !== null && p.end - p.start > maxPass);
          throw new Error(trail(what, `no pass started within ${o.deadline} ms of the write (${slow ? "long pass" : lag.max / 1e6 > margin ? "starved loop"
            : w.trigger.pokes === pokesAtWrite ? "lost event: no poke" : "poke without a pass"})`));
        }
        await sleep(POLL_MS);
      }
      const p = passes[from]!;
      const late = p.start - writeAt;
      if (late > o.deadline) throw new Error(trail(what, `pass ${from} started ${late.toFixed(0)} ms after the write, over the deadline ${o.deadline}`));
      if (mustPoke && p.pokes <= pokesAtWrite) throw new Error(trail(what, `pass ${from} started with no poke after the write (pokes ${p.pokes}, were ${pokesAtWrite})`));
      if (lag.max / 1e6 > margin) throw new Error(trail(what, `event loop stalled ${(lag.max / 1e6).toFixed(0)} ms, over the margin ${margin} (starved loop)`));
      return from;
    };
    await until(() => passes.length >= 1 && passes[0]!.end !== null);
    await sleep(100);
    if (o.newDir) {
      if (o.watcher) expect(w.watches.size).toBeGreaterThanOrEqual(3);
      const from = passes.length, writeAt = performance.now(), pokes = w.trigger.pokes;
      mkdirSync(rd, { recursive: true }); // subagents/ did not exist at start: found through the session dir watch
      const i = await answer("new session dir", from, writeAt, pokes, o.watcher);
      await waitPassEnd(i, "new session dir");
      await sleep(100);
    }
    const from = passes.length, pokes = w.trigger.pokes;
    const writeAt = performance.now(); // taken at the write itself: only a pass that starts later answers it
    writeFileSync(join(rd, "journal.jsonl"), JSON.stringify({ type: "started", agentId: "a1", label: "fix:fix-nav" }) + "\n");
    const i = await answer("journal append", from, writeAt, pokes, o.watcher);
    await waitPassEnd(i, "journal append");
    const got = await agentOf();
    if (got === null) throw new Error(trail("journal append", `pass ${i} ended but its output lacks the appended journal line (task fix-nav has no agent)`));
    return trail("journal append", `woke ${passes[i]!.start - writeAt > 0 ? (passes[i]!.start - writeAt).toFixed(0) : 0} ms after the write`);
  }

  it("event path: an append and a new session dir wake the drain by the proved event bound, the watcher poking before the pass", { repeats: 9 }, async () => {
    // a 60 s tick cannot answer within the deadline, so only the file events can
    const out = await wakeScenario({ tick: 60_000, watcher: true, newDir: true, deadline: param("event_deadline_ms") });
    expect(out).toContain("woke");
  });

  it("event path: the same scenario fails when the watcher is disabled", async () => {
    await expect(wakeScenario({ tick: 60_000, watcher: false, newDir: true, deadline: param("event_deadline_ms") }))
      .rejects.toThrow(/new session dir: no pass started within 2550 ms of the write \(lost event: no poke\)/);
  });

  it("tick rescue: with every event dropped the safety tick wakes the drain by the proved tick bound", { repeats: 9 }, async () => {
    const out = await wakeScenario({ tick: param("rescue_tick_ms"), watcher: false, newDir: false, deadline: param("rescue_deadline_ms") });
    expect(out).toContain("woke");
  });
});

describe("reconciler on ref events", () => {
  it("a branch created under refs/heads and a store event each start a pass; idle starts none; the tick covers a dropped event", async () => {
    const fx = makeRepo();
    const store = await Store.open(fx.consoleDir, selectCore(), () => 1_700_000_000_000);
    stores.push(store);
    const r = new Reconciler(store, fx.root);
    let passes = 0;
    (r as unknown as { pass: () => Promise<unknown> }).pass = async () => { passes++; return { submitted: 0, duplicate: 0, refused: 0, skipped: 0 }; };
    r.startWatching(3000, 30);
    stops.push(() => r.stop());
    await until(() => passes >= 1);
    await sleep(400);
    const p0 = passes;
    await sleep(500);
    expect(passes).toBe(p0); // idle, inside the safety period: no pass
    fx.worktree("card/X"); // a new ref
    await until(() => passes > p0);
    const p1 = passes;
    await sleep(150);
    await store.submit({ type: "task.define", key: "d:zz", actor: "lead", task: "zz", title: "T", stream: "s", milestone: null, deps: [], owner: "o", writes: [], devices: [], needs: [], evidence: null } as never);
    await until(() => passes > p1);
    // dropped events: the watchers are closed, the tick still runs a pass
    (r as unknown as { watches: { close(): void } }).watches.close();
    const p2 = passes;
    await until(() => passes > p2, 4500);
  });
});
