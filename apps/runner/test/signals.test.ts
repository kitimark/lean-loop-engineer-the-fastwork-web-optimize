// obs-signals: the collector reads synthetic transcripts into Fw.Obs.Signals facts and fwcore classifies them
// (`obs.signals`, golden packages/contracts/golden/obs/signals.jsonl). Fixtures are made up: no real transcript,
// path or id. No decision is tested here beyond "TS reads the facts and passes fwcore's answer through".
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, describe, expect, it } from "vitest";
import {
  buildFacts, childrenOf, commandNeedle, procKindOf, procOfCommand, signalFactsOf, watchOf, type NextReply, type Raw, type RawPs,
} from "../src/next.ts";
import { coreCaller } from "../src/watch.ts";
import {
  collectAgents, leadNotesOf, markerOf, pathsFor, pendingBg, readsStdin, signalsOf, summarizeTranscript, withLeadNotes, type SigFacts,
} from "../src/watch-collect.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const fwcore = join(root, "lean/.lake/build/bin/fwcore");
const dirs: string[] = [];
afterAll(() => dirs.forEach((d) => rmSync(d, { recursive: true, force: true })));

const T0 = Date.parse("2026-01-01T00:00:00Z");
const iso = (s: number) => new Date(T0 + s * 1000).toISOString();
const rec = (o: object) => JSON.stringify(o);
const use = (s: number, id: string, name: string, input: object) =>
  rec({ type: "assistant", timestamp: iso(s), message: { role: "assistant", content: [{ type: "tool_use", id, name, input }] } });
const result = (s: number, id: string, text: string, extra: object = {}) =>
  rec({ type: "user", timestamp: iso(s), message: { role: "user", content: [{ type: "tool_result", tool_use_id: id, content: text }] }, ...extra });
const say = (s: number, text: string) =>
  rec({ type: "assistant", timestamp: iso(s), message: { role: "assistant", stop_reason: "end_turn", content: [{ type: "text", text }] } });

// agent aq: starts, runs `cat > file` in the background (it waits on stdin forever), hands back.
const CAT = "cat > /tmp/fixture-x.txt";
const held = [
  rec({ type: "user", timestamp: iso(0), message: { role: "user", content: "go" } }),
  use(10, "u1", "Bash", { command: CAT, run_in_background: true }),
  result(11, "u1", "Command running in background with ID: bq1. Output is being written to: /tmp/fixture/bq1.output",
    { toolUseResult: { backgroundTaskId: "bq1" } }),
  use(20, "u2", "SubagentHandback", { message: "done" }),
  result(21, "u2", "ok", { toolEndsTurn: true, toolUseResult: { success: true } }),
].join("\n");
// workflow agent wq: its Bash result names the background id only in the text.
const LOOP = "until grep -q done /tmp/fixture/f.out | head -1; do sleep 5; done";
const workflow = [
  rec({ type: "user", timestamp: iso(0), message: { role: "user", content: "go" } }),
  use(5, "w1", "Bash", { command: LOOP }),
  result(6, "w1", "Command running in background with ID: bw2"),
].join("\n");

// the session (pid 100) runs the cat under its shell wrapper; pid 300 runs the same text outside the session
const ps: RawPs[] = [
  { pid: 100, ppid: 1, ageMs: 0, comm: "claude" },
  { pid: 200, ppid: 100, ageMs: 60_000, comm: `/bin/zsh -c source /tmp/fixture/snap.sh && eval '${CAT}'` },
  { pid: 201, ppid: 200, ageMs: 60_000, comm: "cat" },
  { pid: 300, ppid: 1, ageMs: 60_000, comm: `/bin/zsh -c eval '${CAT}'` },
];
const noFile = () => null;
const sigReq = (now: number, agents: SigFacts[]) => ({ op: "obs.signals", now, agents });
const call = (req: object) => coreCaller([fwcore])(req as never) as Promise<{ agents: { agent: string; state: string; ids: string[]; handbackAt: number | null }[] }>;

describe("transcript signals", () => {
  it("launch, turn bounds and handback from a transcript", () => {
    const s = signalsOf("aq", held);
    expect(s.facts.launched).toEqual([{ id: "bq1", time: T0 + 11_000 }]);
    expect(s.facts.bounds).toEqual([{ time: T0, start: true }, { time: T0 + 21_000, start: false }]);
    expect(s.facts.handbacks).toEqual([T0 + 21_000]);
    expect(s.commands.get("bq1")).toBe(CAT);
    expect(s.outputs.get("bq1")).toBe("/tmp/fixture/bq1.output");
    expect(s.openCall).toBe(false);
  });
  it("a workflow agent's background id from the result text, matched to its command by tool_use_id", () => {
    const s = signalsOf("wq", workflow);
    expect(s.facts.launched.map((l) => l.id)).toEqual(["bw2"]);
    expect(procKindOf(s.commands.get("bw2")!)).toBe("sleepLoop");
    expect(summarizeTranscript(workflow, null).bgTasks).toEqual(["bw2"]);
  });
  it("end markers, stdin readers, command needles", () => {
    expect(markerOf("[killed]")).toEqual({ how: "killed" });
    expect(markerOf("[exited with code -1]")).toEqual({ how: "exited", code: -1 });
    expect(markerOf("exited with code 0")).toBeNull();
    expect([CAT, "read x", "tee /tmp/a", "cat"].map(readsStdin)).toEqual([true, true, true, true]);
    expect(["cat /tmp/a", "echo a | cat", "cat < /tmp/a", "cat > /tmp/a << 'EOF'"].map(readsStdin)).toEqual([false, false, false, false]);
    expect(procKindOf(CAT)).toBe("stdin");
    expect(procKindOf(`/bin/zsh -c eval '${LOOP}'`)).toBe("sleepLoop");
    expect(procKindOf("tail -f /tmp/fixture/f | while read l; do echo $l; sleep 1; done")).toBe("other");
    expect(commandNeedle("\n  sed -n 'p' x")).toBe("sed -n");
    expect(commandNeedle("ls 'a'")).toBeNull();
  });
  it("the live process of a pending id: the topmost match under the session", () => {
    expect(procOfCommand(ps, 100, CAT)).toBe(200);
    expect(procOfCommand(ps, 0, CAT)).toBe(200);
    expect(procOfCommand(ps, 100, "sleep 3600 && true")).toBeNull();
    const f = signalFactsOf(signalsOf("aq", held), [], noFile, ps, 100, null);
    expect(f.procs).toEqual([{ id: "bq1", pid: 200, kind: "stdin" }]);
    expect(f.ends).toEqual([]);
  });
  it("an output marker ends the id (no proc then); the lead's notes add ends and notices; meta.finished is recorded", () => {
    const killed = signalFactsOf(signalsOf("aq", held), [], () => ({ mtimeMs: T0 + 50_000, lastLine: "[killed]" }), ps, 100, T0 + 22_000);
    expect(killed.ends).toEqual([{ id: "bq1", time: T0 + 50_000, how: "killed" }]);
    expect(killed.procs).toEqual([]);
    expect(killed.metaFinished).toEqual([T0 + 22_000]);
    const note = (id: string, summary: string) => rec({ type: "queue-operation", operation: "enqueue", timestamp: iso(40),
      content: `<task-notification><task-id>${id}</task-id><status>completed</status><summary>${summary}</summary></task-notification>` });
    const notes = leadNotesOf([note("aq", "Agent stopped, waiting on its own background work"), note("bq1", "done"), note("aq", "Agent finished")].join("\n"));
    const f = withLeadNotes(signalsOf("aq", held).facts, notes);
    expect(f.ends).toEqual([{ id: "bq1", time: T0 + 40_000, how: "notified" }]);
    expect(f.notices).toEqual([{ time: T0 + 40_000, finished: false }, { time: T0 + 40_000, finished: true }]);
  });
  it("a stale meta.finished is ignored: records after the meta was written, or an open tool call", () => {
    const meta = { finished: true };
    expect(summarizeTranscript(held, meta, T0 + 21_000).finished).toBe(true);
    expect(summarizeTranscript(held, meta, T0 + 5_000).finished).toBe(false);
    expect(summarizeTranscript(held + "\n" + use(30, "u3", "Read", {}), meta, T0 + 60_000).finished).toBe(false);
  });
  it("fwcore: held after the handback, hung past the 30-min cap, done once the marker ends the id", async () => {
    if (!existsSync(fwcore)) return; // lake build not run on this machine: the pure part above is still checked
    const live = signalFactsOf(signalsOf("aq", held), [], noFile, ps, 100, T0 + 22_000);
    const hb = T0 + 21_000;
    expect((await call(sigReq(hb + 60_000, [live]))).agents).toEqual([{ agent: "aq", state: "handedBackHeld", ids: ["bq1"], handbackAt: hb }]);
    expect((await call(sigReq(hb + 31 * 60_000, [live]))).agents).toEqual([{ agent: "aq", state: "hung", ids: ["bq1"], handbackAt: hb }]);
    const done = signalFactsOf(signalsOf("aq", held), [], () => ({ mtimeMs: T0 + 50_000, lastLine: "[exited with code 0]" }), ps, 100, T0 + 22_000);
    expect((await call(sigReq(hb + 31 * 60_000, [done]))).agents[0]!.state).toBe("handedBackDone");
  });
});

describe("signals in obs.next", () => {
  const live = signalFactsOf(signalsOf("aq", held), [], noFile, ps, 100, null);
  const raw = (signals: SigFacts | null): Raw => ({
    now: T0 + 21_000 + 31 * 60_000, session: 100,
    agents: [{ id: "aq", name: "fixture-task", task: null, state: "idle", ctxTokens: 0, handbackAt: null, worktree: null, ahead: null,
      landed: null, mergesClean: null, branchDeps: [], handoff: true, signals }],
    procs: [{ pid: 200, name: "zsh", startedAt: T0 + 10_000, pids: [201], agent: "aq" }], ps,
    alive: () => true, file: noFile, queuedText: "", ci: [], board: new Map(),
  });
  it("a process the signals match to a stdin reader is a stdinWait child; a watched file names its producer", () => {
    expect(childrenOf(raw(live), "aq").map((c) => c.kind)).toEqual(["stdinWait"]);
    expect(childrenOf(raw(null), "aq").map((c) => c.kind)).toEqual(["other"]);
    expect(watchOf("/tmp/fixture/tasks/bq1.output", new Set())).toEqual({ kind: "task", id: "bq1" });
    expect(watchOf("/tmp/fixture/tasks/aq.output", new Set(["aq"]))).toEqual({ kind: "agent", id: "aq" });
    expect(watchOf("/tmp/fixture/subagents/agent-aq.jsonl", new Set())).toEqual({ kind: "agent", id: "aq" });
    expect(watchOf("/tmp/fixture/f.out", new Set())).toBeNull();
  });
  it("fwcore: the hung stdin child of a handed-back agent holds it (no kill without a Reap-held entry); without signals nothing", async () => {
    if (!existsSync(fwcore)) return;
    const ask = (r: Raw) => coreCaller([fwcore])({ op: "obs.next", now: r.now, agents: buildFacts(r) } as never) as Promise<NextReply>;
    const a = (await ask(raw(live))).agents![0]!;
    expect(a.actions).toEqual([{ action: "investigate", reason: "heldByChild" }]);
    expect(a.signal).toEqual({ state: "hung", ids: ["bq1"] });
    expect(a.keep).toBe(true);
    expect((await ask(raw(null))).agents![0]!.actions).toEqual([{ action: "none" }]);
  });
});

describe("retention without meta.finished", () => {
  it("an ended transcript-only agent stays while it holds a background id, and leaves 1 h after it ended otherwise", () => {
    const base = mkdtempSync(join(tmpdir(), "fwsig-"));
    dirs.push(base);
    const sub = join(base, "projects", "-x-r", "s1", "subagents");
    mkdirSync(sub, { recursive: true });
    const now = T0 + 3 * 3600_000; // the agents ended 3 h ago
    const ended = (t: string) => t + "\n" + say(22, "handed back");
    writeFileSync(join(sub, "agent-held.jsonl"), ended(held));
    writeFileSync(join(sub, "agent-plain.jsonl"), ended(held.replace(/"backgroundTaskId":"bq1"/, '"x":1').replace(/background with ID: bq1/, "")));
    for (const id of ["held", "plain"]) writeFileSync(join(sub, `agent-${id}.meta.json`), JSON.stringify({ finished: true }));
    const p = pathsFor("/x/r", { FW_CONSOLE_DIR: join(base, "fw"), FW_PROJECTS_DIR: join(base, "projects") } as never);
    expect(collectAgents(p, now).map((a) => a.id)).toEqual(["held"]);
    expect(pendingBg(signalsOf("held", readFileSync(join(sub, "agent-held.jsonl"), "utf8")).facts, now, 24 * 3600_000)).toEqual(["bq1"]);
  });
});
