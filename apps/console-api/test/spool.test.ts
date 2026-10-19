import { appendFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createApp } from "../src/app.ts";
import { selectCore } from "../src/core/index.ts";
import { ObsRecord } from "@fw/contracts";
import { admitLines, Drain, SWEEP_ERRORS, summarize } from "../src/spool/drain.ts";
import { Store } from "../src/store.ts";

let stores: Store[] = [];
afterEach(() => { stores.forEach((s) => s.close()); stores = []; });
const fresh = async () => {
  const dir = mkdtempSync(join(tmpdir(), "fw-spool-"));
  const store = await Store.open(dir, selectCore(), () => 1_700_000_000_000);
  stores.push(store);
  mkdirSync(join(dir, "spool"));
  return { dir, store, app: createApp(store) };
};
const rec = (o: Record<string, unknown> = {}) => ({ agent_id: "a1", agent_type: "builder", hook_event_name: "PostToolUse", tool_name: "Bash",
  tool_use_id: "t1", duration_ms: 100, is_error: false, verb: "pnpm", ts: 1, ...o });
const spool = (dir: string, name: string, ...lines: (object | string)[]) =>
  appendFileSync(join(dir, "spool", `${name}.jsonl`), lines.map((l) => (typeof l === "string" ? l : JSON.stringify(l)) + "\n").join(""));
const lines = (f: string) => readFileSync(f, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
/** events.jsonl without the agent life facts (agent.spawn/stop/label; every event of an id is a heartbeat since round 3) */
const notLife = <E extends { type: string }>(es: E[]) => es.filter((e) => !e.type.startsWith("agent."));

describe("spool drain", () => {
  it("accepts observations into obs.jsonl; events.jsonl gets only the id's heartbeat", async () => {
    const { dir, app } = await fresh();
    spool(dir, "a1", rec(), rec({ tool_use_id: "t2", duration_ms: 50, is_error: true, hook_event_name: "PostToolUseFailure" }));
    const r = await (await app.request("/api/spool/drain", { method: "POST" })).json();
    expect(r).toMatchObject({ accepted: 2, duplicates: 0, alerts: 0 });
    expect(lines(join(dir, "obs.jsonl"))).toHaveLength(2);
    // both records fall in one 10-minute bucket of id a1: one heartbeat (Lean `Fw.Ops.Obs.seenKey`)
    expect(lines(join(dir, "events.jsonl")).map((e) => [e.type, e.agent, e.actor])).toEqual([["agent.spawn", "a1", "hook"]]);
    expect(await (await app.request("/api/obs/summary")).json()).toEqual([{ agent_type: "builder", tool_name: "Bash", calls: 2, errors: 1, total_ms: 150 }]);
  });
  it("idempotent: a re-sent record and a re-run drain add nothing; restart rebuilds seen from obs.jsonl", async () => {
    const { dir, store } = await fresh();
    spool(dir, "a1", rec());
    const d = new Drain(store);
    expect((await d.run()).accepted).toBe(1);
    spool(dir, "a1", rec({ ts: 99 })); // same agent/event/tool_use_id, other ts: same key
    expect(await d.run()).toMatchObject({ accepted: 0, duplicates: 1 });
    expect((await new Drain(store).run()).accepted).toBe(0);
    expect(lines(join(dir, "obs.jsonl"))).toHaveLength(1);
  });
  it("key is agent|event|tool_use_id, decoded by Lean ops.hook; hook-only events use ts", async () => {
    const { dir, store } = await fresh();
    spool(dir, "a1", rec(), rec({ tool_use_id: null, hook_event_name: "SubagentStart", ts: 7 }), rec({ tool_use_id: null, hook_event_name: "SubagentStart", ts: 8 }));
    await new Drain(store).run();
    expect(lines(join(dir, "obs.jsonl")).map((l) => l.key)).toEqual(["a1|PostToolUse|t1", "a1|SubagentStart|7", "a1|SubagentStart|8"]);
  });
  it("invalid and torn lines: invalid is counted and skipped, a torn tail waits", async () => {
    const { dir, store } = await fresh();
    spool(dir, "a1", "not json", { ...rec(), ts: -1 }, rec());
    appendFileSync(join(dir, "spool", "a1.jsonl"), '{"agent_id":"a1","hook_ev'); // no newline yet
    const d = new Drain(store);
    expect(await d.run()).toMatchObject({ accepted: 1, invalid: 2 });
    expect(lines(join(dir, "spool-rejects.jsonl")).map((l) => l.why)).toEqual([["json"], ["ts:invalid"]]);
    appendFileSync(join(dir, "spool", "a1.jsonl"), 'ent_name":"SubagentStop","agent_type":null,"tool_name":null,"tool_use_id":null,"duration_ms":null,"is_error":null,"verb":null,"ts":5}\n');
    expect(await d.run()).toMatchObject({ accepted: 1, invalid: 0 });
  });
  it("alerts enter events.jsonl once, as step.post by script", async () => {
    const { dir, store } = await fresh();
    spool(dir, "a1", rec({ hook_event_name: "StopFailure", tool_use_id: null, tool_name: null, ts: 10 }));
    const d = new Drain(store);
    expect(await d.run()).toMatchObject({ accepted: 1, alerts: 1 });
    expect(await new Drain(store).run()).toMatchObject({ accepted: 0, duplicates: 1 }); // via obs seen
    const ev = notLife(lines(join(dir, "events.jsonl")));
    expect(ev).toHaveLength(1);
    expect(ev[0]).toMatchObject({ type: "step.post", actor: "script", card: null });
    expect((await store.board()).steps).toHaveLength(1);
  });
  it("a refused alert is not marked seen and is retried on the next drain", async () => {
    const { dir, store } = await fresh();
    spool(dir, "a1", rec({ hook_event_name: "Notification", tool_use_id: null, tool_name: null, ts: 11 }), rec({ tool_use_id: "t9" }));
    const real = store.submit.bind(store);
    store.submit = async () => ({ ok: false, reason: "refused for test" });
    const d = new Drain(store);
    expect(await d.run()).toMatchObject({ retry: 1, alerts: 0 });
    expect(lines(join(dir, "obs.jsonl") ).length).toBe(1); // only the later observation; the alert key is not seen
    store.submit = real;
    expect(await d.run()).toMatchObject({ alerts: 1, accepted: 1, duplicates: 1 });
    expect(notLife(lines(join(dir, "events.jsonl")))).toHaveLength(1);
  });
  it("an agent's permission prompt names agent, kind and tool; its next tool result cancels it", async () => {
    const { dir, store } = await fresh();
    spool(dir, "a1", rec({ hook_event_name: "Notification", tool_use_id: null, tool_name: "Bash", notification_type: "permission_prompt", message_len: 40, ts: 10 }));
    const d = new Drain(store);
    expect(await d.run()).toMatchObject({ accepted: 1, alerts: 1 });
    let steps = (await store.board()).steps;
    expect(steps).toHaveLength(1);
    expect(steps[0]).toMatchObject({ id: "alert-a1-10", status: "waiting" });
    expect(steps[0]!.title).toContain("builder");
    expect(steps[0]!.title).toContain("permission to use Bash");
    spool(dir, "a1", rec({ tool_use_id: "t5", ts: 20 }));
    await d.run();
    steps = (await store.board()).steps;
    expect(steps[0]!.status).toBe("cancelled");
    expect(notLife(lines(join(dir, "events.jsonl"))).map((e) => [e.type, e.actor])).toEqual([["step.post", "script"], ["step.cancel", "script"]]);
    // idempotent: a fresh drain over the same spool adds nothing
    expect(await new Drain(store).run()).toMatchObject({ accepted: 0, alerts: 0 });
    expect(notLife(lines(join(dir, "events.jsonl")))).toHaveLength(2);
  });
  it("a second prompt of the same agent while one is open posts nothing; another agent's tool result keeps it open", async () => {
    const { dir, store } = await fresh();
    spool(dir, "a1", rec({ hook_event_name: "Notification", tool_use_id: null, notification_type: "agent_needs_input", ts: 10 }),
      rec({ hook_event_name: "Notification", tool_use_id: null, notification_type: "agent_needs_input", ts: 11 }));
    spool(dir, "a2", rec({ agent_id: "a2", tool_use_id: "t7", ts: 30 }));
    expect(await new Drain(store).run()).toMatchObject({ accepted: 3, alerts: 1 });
    expect((await store.board()).steps.map((s) => [s.id, s.status])).toEqual([["alert-a1-10", "waiting"]]);
  });
  it("the lead's own Notification (no agent_id, nothing else in flight) is no alert", async () => {
    const { dir, store } = await fresh();
    spool(dir, "main", rec({ agent_id: null, agent_type: null, hook_event_name: "Notification", tool_use_id: null, notification_type: "permission_prompt", ts: 5 }));
    expect(await new Drain(store).run()).toMatchObject({ accepted: 1, alerts: 0 });
    expect((await store.board()).steps).toHaveLength(0);
  });
  it("a Notification without agent_id is attributed to the single agent with a tool in flight", async () => {
    const { dir, store } = await fresh();
    spool(dir, "a1", rec({ hook_event_name: "PreToolUse", tool_use_id: "t1", ts: 1 }));
    spool(dir, "main", rec({ agent_id: null, agent_type: null, hook_event_name: "PreToolUse", tool_name: "Agent", tool_use_id: "tm", ts: 2 }),
      rec({ agent_id: null, agent_type: null, hook_event_name: "Notification", tool_use_id: null, tool_name: "Bash", notification_type: "permission_prompt", ts: 5 }));
    expect(await new Drain(store).run()).toMatchObject({ alerts: 1 });
    expect((await store.board()).steps.map((s) => s.id)).toEqual(["alert-a1-5"]);
  });
  it("StopFailure posts an alert naming the agent", async () => {
    const { dir, store } = await fresh();
    spool(dir, "a1", rec({ hook_event_name: "StopFailure", tool_use_id: null, tool_name: null, ts: 4 }));
    await new Drain(store).run();
    expect((await store.board()).steps[0]!.title).toContain("builder stopped on an API failure");
  });
  // task task-state-truth regression: a real SubagentStop line (2026-10-18 spool) with background_tasks. The strict zod
  // schema refused 6376 of these, so no agent.stop reached the plan.
  const realStop = '{"agent_id":"a0e52ab0600cc97da","agent_type":"","hook_event_name":"SubagentStop","tool_name":null,"tool_use_id":null,"duration_ms":null,"is_error":null,"verb":null,"ts":1792269356759,"background_tasks":20}';
  const health = (dir: string, agents: { id: string; name: string }[]) => appendFileSync(join(dir, "health.jsonl"), JSON.stringify({ at: 1,
    input: { now: 1, agents, system: { diskFreeGB: 1 } },
    output: { agents: [], system: { alerts: [] }, counts: { active: 0, idle: 0, parked: 0, stalled: 0, done: 0 }, alerts: [] } }) + "\n");
  const define = (store: Store, task: string) => store.submit({ type: "task.define", key: `d:${task}`, actor: "lead", task, title: task, stream: "lean",
    milestone: null, deps: [], owner: "lean-prover", writes: [], devices: [], evidence: null });
  it("a real SubagentStop with background_tasks is accepted and stops its named agent at the record time", async () => {
    const { dir, store } = await fresh();
    await define(store, "fix-nav");
    health(dir, [{ id: "a0e52ab0600cc97da", name: "fix-nav" }]);
    spool(dir, "a0", rec({ agent_id: "a0e52ab0600cc97da", hook_event_name: "PostToolUse", tool_use_id: "t9", ts: 1792269000000 }));
    const d = new Drain(store);
    expect(await d.run()).toMatchObject({ accepted: 1, invalid: 0 });
    expect((await store.board()).plan.tasks[0]).toMatchObject({ id: "fix-nav", state: "running", agent: "fix-nav", since: 1792269000000 });
    spool(dir, "a0", realStop);
    expect(await d.run()).toMatchObject({ accepted: 1, invalid: 0, stops: 1, unknown: 0 });
    expect(lines(join(dir, "obs.jsonl"))[1]).toMatchObject({ key: "a0e52ab0600cc97da|SubagentStop|1792269356759", background_tasks: 20 });
    expect((await store.board()).plan.tasks[0]).toMatchObject({ state: "parked", agent: null });
  });
  it("a stop without a name in the health index still stops the id, counted as unnamed", async () => {
    const { dir, store } = await fresh();
    spool(dir, "a0", realStop);
    expect(await new Drain(store).run()).toMatchObject({ accepted: 1, stops: 1, unnamed: 1 });
    expect(lines(join(dir, "events.jsonl")).map((e) => [e.type, e.agent])).toEqual([["agent.stop", "a0e52ab0600cc97da"]]);
  });
  it("liveness by id: an unnamed id is bound by its label, a stop ends it, a later tool call does not, a later start revives it", async () => {
    const { dir, store } = await fresh();
    await define(store, "fix-nav");
    spool(dir, "a1", rec({ agent_id: "id7", hook_event_name: "SubagentStart", tool_use_id: null, tool_name: null, ts: 1_700_000_000_000 - 60_000 }));
    const d = new Drain(store);
    await d.run();
    expect((await store.board()).plan.tasks[0]).toMatchObject({ state: "ready" }); // no label yet: id7 binds nothing
    health(dir, [{ id: "id7", name: "fix-nav" }]);
    expect(await d.run()).toMatchObject({ labels: 1 });
    expect((await store.board()).plan.tasks[0]).toMatchObject({ state: "running", agent: "fix-nav" });
    spool(dir, "a1", rec({ agent_id: "id7", hook_event_name: "SubagentStop", tool_use_id: null, tool_name: null, ts: 1_700_000_000_000 - 50_000 }));
    expect(await d.run()).toMatchObject({ stops: 1, unnamed: 0 });
    expect((await store.board()).plan.tasks[0]).toMatchObject({ state: "parked", agent: null });
    spool(dir, "a1", rec({ agent_id: "id7", tool_use_id: "t8", ts: 1_700_000_000_000 - 40_000 }));
    await d.run();
    expect((await store.board()).plan.tasks[0]).toMatchObject({ state: "parked", agent: null }); // Fw.Ops.Obs.no_revive_after_stop
    spool(dir, "a1", rec({ agent_id: "id7", hook_event_name: "SubagentStart", tool_use_id: null, tool_name: null, ts: 1_700_000_000_000 - 30_000 }));
    await d.run();
    expect((await store.board()).plan.tasks[0]).toMatchObject({ state: "running", agent: "fix-nav" }); // Fw.Ops.Obs.start_revives
  });
  it("a resumed agent heartbeats again: stop, start, then a tool call 15 min later is a sighting (Fw.Ops.Obs.heartbeat_after_resume)", async () => {
    const { dir, store } = await fresh();
    const T = 1_700_000_000_000;
    spool(dir, "a1", rec({ agent_id: "id9", hook_event_name: "SubagentStart", tool_use_id: null, tool_name: null, ts: T }));
    spool(dir, "a1", rec({ agent_id: "id9", hook_event_name: "SubagentStop", tool_use_id: null, tool_name: null, ts: T + 60_000 }));
    spool(dir, "a1", rec({ agent_id: "id9", tool_use_id: "t1", ts: T + 120_000 }));
    const d = new Drain(store);
    await d.run();
    const seen = () => lines(join(dir, "events.jsonl")).filter((e) => e.type === "agent.spawn" && String(e.key).startsWith("seen:id9|"));
    expect(seen()).toHaveLength(0); // stopped: a tool call is not a sighting
    spool(dir, "a1", rec({ agent_id: "id9", hook_event_name: "SubagentStart", tool_use_id: null, tool_name: null, ts: T + 180_000 }));
    spool(dir, "a1", rec({ agent_id: "id9", tool_use_id: "t2", ts: T + 180_000 + 15 * 60_000 }));
    await d.run();
    expect(seen().map((e) => e.key)).toEqual([`seen:id9|0|${Math.floor((T + 180_000 + 15 * 60_000) / 600_000)}`]);
  });
  it("a fwcore throw in lifeOf: the line is not marked seen, it is retried, counted, and the spool alert names it", async () => {
    const { dir, store } = await fresh();
    spool(dir, "a1", rec());
    const real = store.core.ops.bind(store.core);
    store.core.ops = async (op: string, f: Record<string, unknown> = {}) => { if ("life" in f) throw new Error("boom"); return real(op, f); };
    const d = new Drain(store);
    expect(await d.run()).toMatchObject({ accepted: 0, retry: 1, issues: 1, alerts: 1, sweepErrors: 1 });
    expect((await store.board()).steps[0]!.title).toContain("sweep:lifeOf x1");
    expect(JSON.parse(readFileSync(join(dir, SWEEP_ERRORS), "utf8"))).toEqual({ pid: process.pid, count: 1, ops: { lifeOf: 1 } });
    expect(existsSync(join(dir, "obs.jsonl")) ? lines(join(dir, "obs.jsonl")) : []).toHaveLength(0);
    store.core.ops = real;
    expect(await d.run()).toMatchObject({ accepted: 1, retry: 0, sweepErrors: 0 });
  });
  // round 4, lead decision 3: no swallowed fwcore throw. Each sweep's throw is counted per op in sweep-errors.json (the
  // watch raises svc.sweepError from it) and the drain still finishes.
  const throwing = (store: Store, when: (op: string, f: Record<string, unknown>) => boolean) => {
    const real = store.core.ops.bind(store.core);
    store.core.ops = async (op: string, f: Record<string, unknown> = {}) => { if (when(op, f)) throw new Error("boom"); return real(op, f); };
    return () => { store.core.ops = real; };
  };
  const swept = (dir: string) => JSON.parse(readFileSync(join(dir, SWEEP_ERRORS), "utf8")) as { pid: number; count: number; ops: Record<string, number> };
  // round 5, lead decision 4: the whole drain body (board, submits, posts) runs in one try
  it("a rejecting core: every throw of the drain body is counted (svc.sweepError), run() never rejects; the next drain reads the lines again", async () => {
    const { dir, store } = await fresh();
    spool(dir, "a1", rec());
    health(dir, [{ id: "a1", name: "fix-nav" }]);
    const realBoard = store.board.bind(store);
    store.board = async () => { throw new Error("core down"); };
    const restore = throwing(store, () => true);
    const d = new Drain(store);
    const r = await d.run();
    expect(r.sweepErrors).toBeGreaterThanOrEqual(1);
    expect(d.sweepErrors()).toMatchObject({ drain: 1 });
    expect(swept(dir).ops).toMatchObject({ drain: 1 });
    expect(await d.run()).toMatchObject({ accepted: 0 });
    expect(d.sweepErrors()).toMatchObject({ drain: 2 });
    restore();
    store.board = realBoard;
    expect(await d.run()).toMatchObject({ accepted: 1, sweepErrors: 0 });
  });
  it("a fwcore throw in admission, the alert plan, the label sweep or the workflow sweep is counted per op", async () => {
    const { dir, store } = await fresh();
    spool(dir, "a1", rec());
    health(dir, [{ id: "a1", name: "fix-nav" }]);
    const restore = throwing(store, (op, f) => op === "console.alert" || "raw" in f || "labels" in f);
    const d = new Drain(store, () => { throw new Error("no dirs"); });
    expect(await d.run()).toMatchObject({ accepted: 0, sweepErrors: 3 });
    expect(swept(dir).ops).toEqual({ workflow: 1, label: 1, admit: 1 });
    restore();
    const again = throwing(store, (op) => op === "console.alert");
    expect(await d.run()).toMatchObject({ accepted: 0, retry: 1, labels: 1 });
    expect(swept(dir).ops).toEqual({ workflow: 2, label: 1, admit: 1, alertPlan: 1 });
    again();
    expect(await d.run()).toMatchObject({ accepted: 1, retry: 0 });
  });
  it("an unknown field is accepted, counted and raised once as a spool alert", async () => {
    const { dir, store } = await fresh();
    spool(dir, "a1", { ...rec(), extra: "field" }, { ...rec({ tool_use_id: "t2" }), extra: 1 });
    const d = new Drain(store);
    expect(await d.run()).toMatchObject({ accepted: 2, invalid: 0, unknown: 2, alerts: 1 });
    expect(lines(join(dir, "obs.jsonl")).every((l) => !("extra" in l))).toBe(true);
    const steps = (await store.board()).steps;
    expect(steps.map((s) => s.id)).toEqual(["alert-spool-1700000000000"]);
    expect(steps[0]!.title).toContain("extra:unknown x2");
    spool(dir, "a1", { ...rec({ tool_use_id: "t3" }), extra: 2 });
    expect(await d.run()).toMatchObject({ accepted: 1, unknown: 1, alerts: 0 }); // one open: no second alert
  });
  it("quiet (round 5): an agent not seen for quietMs shows quiet with its last-seen time; no stop is sent", async () => {
    const { dir, store } = await fresh();
    await define(store, "fix-nav");
    health(dir, [{ id: "a1", name: "fix-nav" }]);
    const at = 1_700_000_000_000 - 2 * 3600_000 - 1;
    spool(dir, "a1", rec({ ts: at }));
    expect(await new Drain(store).run()).toMatchObject({ accepted: 1, sweepErrors: 0 });
    expect((await store.board()).plan.tasks[0]).toMatchObject({ state: "quiet", agent: null, since: at, outcome: null });
    expect(store.readEvents().filter((e) => e.type === "agent.stop")).toEqual([]);
  });
  it("golden: zod ObsRecord accepts every record Lean keeps, and refuses what Lean rejects", async () => {
    const { store } = await fresh();
    const spawn = '{"agent_id":"affbc82ef59f14f9a","agent_type":"lean-prover","hook_event_name":"SpawnGuard","tool_name":"Agent","tool_use_id":"toolu_x","duration_ms":null,"is_error":null,"verb":"allow","ts":1792275587015,"agent_name":null,"role":"checker","want_kind":"subagent","got_kind":"subagent","has_name":false,"isolation":false,"depth":1,"seen_by":"pre-tool-use"}';
    const note = JSON.stringify({ ...rec({ hook_event_name: "Notification", tool_use_id: null }), notification_type: "permission_prompt", message_len: 12 });
    // soft fields (not decision fields) never reject: an ill-typed one is kept as null with a note
    const soft = [JSON.stringify(rec({ verb: "v".repeat(41) })), JSON.stringify(rec({ duration_ms: 1.5 })), JSON.stringify(rec({ is_error: "no" }))];
    const ok = [realStop, spawn, note, JSON.stringify(rec()), JSON.stringify({ ...rec(), future: [1] }), JSON.stringify(rec({ verb: "v".repeat(40) })), ...soft];
    const bad = ["[]", "1", JSON.stringify(rec({ hook_event_name: "" })), JSON.stringify({ ...rec(), ts: undefined }), JSON.stringify(rec({ agent_id: "" })),
      JSON.stringify(rec({ agent_name: "" })), JSON.stringify(rec({ agent_id: "i".repeat(121) })), JSON.stringify(rec({ ts: 1.5 }))];
    const vs = await admitLines(store.core, [...ok, ...bad]);
    expect(vs.map((v) => v.ok)).toEqual([...ok.map(() => true), ...bad.map(() => false)]);
    for (const v of vs) if (v.ok) expect(ObsRecord.safeParse(v.rec).success).toBe(true);
    for (const b of bad.slice(2)) expect(ObsRecord.safeParse(JSON.parse(b)).success).toBe(false);
    expect(vs.slice(ok.length).map((v) => (v.ok ? "" : v.why))).toEqual(["json", "json", "hook_event_name:invalid", "ts:missing",
      "agent_id:invalid", "agent_name:invalid", "agent_id:invalid", "ts:invalid"]);
    expect(vs.slice(ok.length - soft.length, ok.length).map((v) => (v.ok ? v.notes : []))).toEqual([["verb:invalid"], ["duration_ms:invalid"], ["is_error:invalid"]]);
  });
  it("summarize ignores non-tool events", async () => {
    const { store } = await fresh();
    expect(await summarize(store.core, [{ ...rec(), hook_event_name: "SubagentStart", key: "k" } as never])).toEqual([]);
  });
});
