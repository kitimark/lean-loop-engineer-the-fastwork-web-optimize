import { appendFileSync, mkdirSync, mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createApp } from "../src/app.ts";
import { selectCore } from "../src/core/index.ts";
import { Drain, alertFor, summarize } from "../src/spool/drain.ts";
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

describe("spool drain", () => {
  it("accepts observations into obs.jsonl, never into events.jsonl", async () => {
    const { dir, app } = await fresh();
    spool(dir, "a1", rec(), rec({ tool_use_id: "t2", duration_ms: 50, is_error: true, hook_event_name: "PostToolUseFailure" }));
    const r = await (await app.request("/api/spool/drain", { method: "POST" })).json();
    expect(r).toMatchObject({ accepted: 2, duplicates: 0, alerts: 0 });
    expect(lines(join(dir, "obs.jsonl"))).toHaveLength(2);
    expect(readFileSync(join(dir, "events.jsonl"), "utf8")).toBe("");
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
    spool(dir, "a1", "not json", { ...rec(), extra: "field" }, rec());
    appendFileSync(join(dir, "spool", "a1.jsonl"), '{"agent_id":"a1","hook_ev'); // no newline yet
    const d = new Drain(store);
    expect(await d.run()).toMatchObject({ accepted: 1, invalid: 2 });
    appendFileSync(join(dir, "spool", "a1.jsonl"), 'ent_name":"SubagentStop","agent_type":null,"tool_name":null,"tool_use_id":null,"duration_ms":null,"is_error":null,"verb":null,"ts":5}\n');
    expect(await d.run()).toMatchObject({ accepted: 1, invalid: 0 });
  });
  it("alerts enter events.jsonl once, as step.post by script", async () => {
    const { dir, store } = await fresh();
    spool(dir, "a1", rec({ hook_event_name: "StopFailure", tool_use_id: null, tool_name: null, ts: 10 }));
    const d = new Drain(store);
    expect(await d.run()).toMatchObject({ accepted: 1, alerts: 1 });
    expect(await new Drain(store).run()).toMatchObject({ accepted: 0, duplicates: 1 }); // via obs seen
    const ev = lines(join(dir, "events.jsonl"));
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
    expect(lines(join(dir, "events.jsonl"))).toHaveLength(1);
  });
  it("only StopFailure and Notification make alerts", () => {
    expect(alertFor(rec() as never, "k")).toBeNull();
    expect(alertFor(rec({ hook_event_name: "Notification" }) as never, "k")?.type).toBe("step.post");
    expect(alertFor(rec({ hook_event_name: "Notification", agent_id: null, agent_type: null }) as never, "k")).toBeNull();
  });
  it("summarize ignores non-tool events", () => {
    expect(summarize([{ ...rec(), hook_event_name: "SubagentStart", key: "k" } as never])).toEqual([]);
  });
});
