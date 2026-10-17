// Work graph through the real fwcore: golden replay, the batch door, agent.spawn/stop from the spool (both orders),
// old logs, task.done from a landing, and the plan sync the reconciler runs when main moves.
import { appendFileSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it } from "vitest";
import { LiveBoard } from "@fw/contracts";
import { createApp } from "../src/app.ts";
import { capMac, sha256 } from "../src/cap/cap.ts";
import { selectCore } from "../src/core/index.ts";
import { Reconciler } from "../src/reconcile/reconciler.ts";
import { Drain } from "../src/spool/drain.ts";
import { Store } from "../src/store.ts";
import { syncCommands, type WorkGraph } from "../../runner/src/plan.ts";
import { makeRepo } from "./reconcile-fixture.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "../../..");
const graphFile = join(root, "docs/team/work-graph.json");
const golden = readFileSync(join(root, "packages/contracts/golden/plan/work-graph.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l)) as
  { requests: { op: string; event?: object; now?: number; seq?: number }[]; replies: { board?: unknown }[] }[];

let stores: Store[] = [];
afterEach(() => { stores.forEach((s) => s.close()); stores = []; });
const open = async (dir = mkdtempSync(join(tmpdir(), "fw-plan-"))) => {
  const store = await Store.open(dir, selectCore(), () => 1_700_000_000_000);
  stores.push(store);
  return { dir, store };
};
const planOf = async (store: Store) => (await store.board()).plan;
const mini = (): WorkGraph => ({
  milestones: [{ id: "M", title: "mini" }],
  tasks: [
    { id: "b", title: "B", stream: "s", milestone: "M", deps: ["a"], owner: "o" },
    { id: "a", title: "A", stream: "s", milestone: "M", deps: [], owner: "o", writes: ["x/**"] },
    { id: "c", title: "C", stream: "s", milestone: "M", deps: [], owner: "o", writes: ["x/y"] },
  ],
});

describe("the real work graph through fwcore", () => {
  it("Lean's golden events give Lean's golden board (stateful console.query)", async () => {
    const { store } = await open();
    const g = golden[0]!;
    for (const r of g.requests) if (r.op === "console.apply") expect((await store.core.apply(r.event as never)).outcome.accepted).toBe(true);
    const q = g.requests.find((r) => r.op === "console.query")!;
    expect(await store.core.board(q.now!, q.seq!)).toEqual(g.replies.find((r) => r.board)!.board);
  });

  it("docs/team/work-graph.json via fw plan sync's commands: every task lands, states obey the Lean iff rules", async () => {
    const { store } = await open();
    const file = JSON.parse(readFileSync(graphFile, "utf8")) as WorkGraph;
    const cmds = syncCommands(file);
    for (const c of cmds) expect(await store.submit(c), JSON.stringify(c)).toMatchObject({ ok: true });
    const p = await planOf(store);
    expect(p.tasks.map((t) => t.id).sort()).toEqual(file.tasks.map((t) => t.id).sort());
    const st = new Map(p.tasks.map((t) => [t.id, t]));
    for (const t of p.tasks) {
      const undone = t.deps.filter((d) => st.get(d)!.state !== "done");
      expect(t.blockers.sort(), t.id).toEqual(undone.sort());
      if (t.state === "ready") expect(undone).toEqual([]);
      if (t.state === "blocked") expect(undone.length).toBeGreaterThan(0);
      expect(t.state === "done", t.id).toBe(t.evidence !== null);
    }
    for (const t of p.tasks) expect(t.lane, t.id).toBe(t.needs.includes("device") ? "device" : "agent"); // Lean lane_device_iff
    const byId = new Map(file.tasks.map((t) => [t.id, t]));
    for (const t of p.tasks) expect(t.needs, t.id).toEqual(byId.get(t.id)!.needs ?? []); // sync stores needs (missing = [])
    const ready = new Set(p.tasks.filter((t) => t.state === "ready" && t.lane === "agent").map((t) => t.id));
    expect(p.parallelSafe.flat().sort()).toEqual([...ready].sort()); // groups partition the agent-ready tasks    p.criticalPath.slice(1).forEach((id, i) => expect(st.get(id)!.deps).toContain(p.criticalPath[i]));
    for (const m of p.milestones) expect(m.total).toBe(file.tasks.filter((t) => t.milestone === m.id && !t.cut).length); // msView_kept
    for (const t of p.tasks) expect(t.state === "cut", t.id).toBe(!!byId.get(t.id)!.cut && t.evidence === null); // tstate_cut_iff
    for (const id of p.criticalPath) expect(byId.get(id)!.cut ?? false, id).toBe(false); // view_criticalPath_not_cut
    expect(p.tasks.filter((t) => t.state === "cut").length).toBeGreaterThan(0);
    // second sync: every key is already applied
    for (const c of cmds) expect(await store.submit(c)).toMatchObject({ ok: true, duplicate: true });
  });
});

describe("agent door", () => {
  it("one capability carries a whole sync (array); refusals are reported per command", async () => {
    const { dir, store } = await open();
    const app = createApp(store);
    const secret = readFileSync(join(dir, "secret"), "utf8").trim();
    const argv = ["plan", "sync", "g.json"], hash = sha256(argv.join(" ")), now = Date.now();
    appendFileSync(join(dir, "caps.jsonl"), JSON.stringify({ agent_id: null, agent_type: "main", tool_use_id: "t1", cmd_hash: hash, mac: capMac(secret, null, "main", "t1", hash), ts: now }) + "\n");
    const cmds = [...syncCommands(mini()), { ...syncCommands(mini())[1]!, key: "bad", task: "z", deps: ["nope"] }];
    const r = await app.request("/api/agent/commands", { method: "POST", body: JSON.stringify({ argv, command: cmds }), headers: { "content-type": "application/json" } });
    const body = (await r.json()) as { ok: boolean; reason?: string; replies: { ok: boolean; reason?: string }[] };
    expect(body.reason ?? "", String(r.status)).toBe("");
    expect(body.ok).toBe(false);
    expect(body.replies.map((x) => x.ok)).toEqual([true, true, true, true, false]); // unknown dep refused by the reducer
    expect((await planOf(store)).tasks.map((t) => [t.id, t.state])).toEqual([["a", "ready"], ["b", "blocked"], ["c", "ready"]]);
    expect(await (await app.request("/api/plan")).json()).toEqual(await planOf(store));
  });
});

describe("automation", () => {
  const spawnRec = (name: string, id: string) => JSON.stringify({ agent_id: null, agent_type: null, hook_event_name: "SpawnGuard",
    tool_name: "Agent", tool_use_id: id, duration_ms: null, is_error: null, verb: "allow", agent_name: name, ts: 5 }) + "\n";
  const stopRec = (agentId: string) => JSON.stringify({ agent_id: agentId, agent_type: "lean-prover", hook_event_name: "SubagentStop",
    tool_name: null, tool_use_id: null, duration_ms: null, is_error: null, verb: null, ts: 9 }) + "\n";
  const health = (dir: string, agents: [string, string][]) => appendFileSync(join(dir, "health.jsonl"), JSON.stringify({
    at: 1, input: { now: 1, agents: agents.map(([id, name]) => ({ id, name })), system: { diskFreeGB: 100 } },
    output: { agents: agents.map(([id]) => ({ id, state: "active", alerts: [] })), system: { alerts: [] },
      counts: { active: agents.length, idle: 0, parked: 0, stalled: 0, gone: 0, done: 0 }, alerts: [] },
  }) + "\n");
  const rows = async (store: Store) => (await planOf(store)).tasks.map((t) => [t.id, t.state, t.agent]);

  // the obs-next-lean trace (claim-order-lean): the agent spawned before plan sync defined its task
  for (const order of ["define, then spawn", "spawn, then define"] as const) {
    it(`a spawned agent named like a task works on it, whatever the order (${order}); other names do nothing`, async () => {
      const { dir, store } = await open();
      mkdirSync(join(dir, "spool"));
      const define = async () => { for (const c of syncCommands(mini())) await store.submit(c); };
      const spawn = async () => {
        appendFileSync(join(dir, "spool", "s.jsonl"), spawnRec("a", "u1") + spawnRec("scout-7", "u2"));
        expect(await new Drain(store).run()).toMatchObject({ accepted: 2, invalid: 0 });
      };
      if (order === "define, then spawn") { await define(); await spawn(); } else { await spawn(); await define(); }
      expect(await rows(store)).toEqual([["a", "running", "a"], ["b", "blocked", null], ["c", "ready", null]]);
      // the hook sends the fact unconditionally; nothing is claimed by name matching in TS
      expect(store.readEvents().filter((e) => e.type === "agent.spawn")).toMatchObject([{ actor: "hook", agent: "a" }, { actor: "hook", agent: "scout-7" }]);
      expect(store.readEvents().filter((e) => e.type === "task.claim")).toEqual([]);
    });
  }

  it("a stopped agent releases its undone task (the stop's name comes from the health line); a stop before the define too", async () => {
    const { dir, store } = await open();
    mkdirSync(join(dir, "spool"));
    health(dir, [["id-a", "a"], ["id-c", "c"]]);
    appendFileSync(join(dir, "spool", "s.jsonl"), spawnRec("a", "u1") + spawnRec("c", "u2") + stopRec("id-c") + stopRec("id-unknown"));
    await new Drain(store).run();
    for (const c of syncCommands(mini())) await store.submit(c);
    expect(await rows(store)).toEqual([["a", "running", "a"], ["b", "blocked", null], ["c", "ready", null]]);
    expect(store.readEvents().filter((e) => e.type === "agent.stop")).toMatchObject([{ actor: "hook", agent: "c", key: "stop:id-c" }]);
    appendFileSync(join(dir, "spool", "s.jsonl"), stopRec("id-a"));
    await new Drain(store).run();
    expect(await rows(store)).toEqual([["a", "ready", null], ["b", "blocked", null], ["c", "ready", null]]);
  });

  it("an old log (legacy `live` on task.define, task.claim, no agent.spawn) replays to the board it gave before", async () => {
    const dir = mkdtempSync(join(tmpdir(), "fw-plan-"));
    const lines: object[] = [];
    let seq = 0;
    const log = (c: object) => lines.push({ ...c, seq: ++seq, ts: 1_700_000_000_000 });
    for (const c of syncCommands(mini())) log({ ...c, ...(c.type === "task.define" && c.task !== "a" ? { live: ["c", "zz"] } : {}) });
    log({ type: "task.claim", key: "claim:a", actor: "hook", task: "a", agent: "a" });
    writeFileSync(join(dir, "events.jsonl"), lines.map((l) => JSON.stringify(l)).join("\n") + "\n");
    const { store } = await open(dir);
    // before claim-order-lean: c was claimed by the live fact, a by the claim, b stays blocked (its dep a is undone)
    expect(await rows(store)).toEqual([["a", "running", "a"], ["b", "blocked", null], ["c", "running", "c"]]);
    // a client's legacy `live` is dropped now: the console binds from agent.spawn only
    const d = syncCommands({ milestones: [], tasks: [{ id: "n", title: "N", stream: "s", deps: [], owner: "o" }] })[0]!;
    await store.submit({ ...d, live: ["n"] } as never);
    expect(store.readEvents().at(-1)).not.toHaveProperty("live");
    expect((await planOf(store)).tasks.find((t) => t.id === "n")).toMatchObject({ state: "ready", agent: null });
  });

  it("a card named like a task, once landed, finishes it with the landed sha as evidence", async () => {
    const fx = makeRepo();
    const { store } = await open(fx.consoleDir);
    for (const c of syncCommands(mini())) await store.submit(c);
    const send = (c: object) => store.submit(c as never);
    await send({ type: "card.open", key: "o", actor: "owner", card: "a", owner: "o", needsDevice: false });
    await send({ type: "card.approve", key: "ap", actor: "lead", card: "a" });
    const sha = fx.commit(fx.worktree("card/a"), "a.txt");
    const rc = new Reconciler(store, fx.root);
    await rc.reconcile();
    await send({ type: "card.screen", key: "s", actor: "script", card: "a", sha, pass: true });
    await send({ type: "card.review", key: "r", actor: "reviewer", card: "a", sha, signedBy: "rev", accept: true });
    await send({ type: "card.land_request", key: "lr", actor: "lead", card: "a", sha });
    fx.git(fx.root, "merge", "--ff-only", "card/a");
    await rc.reconcile();
    const p = await planOf(store);
    expect(p.tasks.find((t) => t.id === "a")).toMatchObject({ state: "done", evidence: sha });
    expect(p.tasks.find((t) => t.id === "b")!.state).toBe("ready"); // unblocked by the landing
    expect(store.readEvents().filter((e) => e.type === "task.done")).toMatchObject([{ actor: "git", task: "a", evidence: sha }]);
  });
});
