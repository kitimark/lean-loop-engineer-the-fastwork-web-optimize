import { mkdirSync, mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, describe, expect, it } from "vitest";
import {
  carryCritical, collectAgents, collectCritical, collectSystem, exe, findTranscripts, keepNames, parseCi, parseEtime, parsePs, sessionProcs, parseDocker, parseMemLevel, parseSpool, parseWorktreeCount, pathsFor,
  summarizeLead, summarizeSpool, summarizeTranscript, type Runner, type SystemSnap,
} from "../src/watch-collect.ts";
import { alertKey, appendLog, newAlerts, parseWatchArgs, readLastLog, renderTable, type Health } from "../src/watch.ts";

const T0 = Date.parse("2026-10-17T10:00:00Z");
const ev = (agent: string, h: string, ts: number, extra: object = {}) =>
  JSON.stringify({ agent_id: agent, agent_type: "lean-prover", hook_event_name: h, tool_name: "Bash", tool_use_id: null, duration_ms: 5, is_error: false, verb: "ls", ts, ...extra });
const line = (o: object) => JSON.stringify(o);
const ts = (min: number) => new Date(T0 + min * 60000).toISOString();
const asst = (id: string, min: number, content: object[], usage: object) =>
  line({ type: "assistant", timestamp: ts(min), message: { id, model: "claude-opus-5-5", role: "assistant", content, usage } });
const user = (min: number, content: object[]) => line({ type: "user", timestamp: ts(min), message: { role: "user", content } });

const dirs: string[] = [];
const tmp = () => { const d = mkdtempSync(join(tmpdir(), "fwwatch-")); dirs.push(d); return d; };
afterAll(() => dirs.forEach((d) => rmSync(d, { recursive: true, force: true })));

describe("spool", () => {
  it("counts tools, errors, trailing error streak, stop and resume", () => {
    const evs = parseSpool([
      ev("a", "SubagentStart", T0), ev("a", "PostToolUse", T0 + 1000), ev("a", "PostToolUseFailure", T0 + 2000, { is_error: true }),
      ev("a", "PostToolUseFailure", T0 + 3000, { is_error: true }), "{torn",
    ].join("\n"));
    const s = summarizeSpool(evs);
    expect(s).toMatchObject({ tools: 3, errors: 2, errTail: 2, startedAt: T0, lastAt: T0 + 3000, stoppedAt: null, lastTool: "Bash", lastToolAt: T0 + 3000, idleAt: null });
    expect(summarizeSpool(parseSpool([ev("a", "SubagentStart", 1), ev("a", "SubagentStop", 5)].join("\n"))).stoppedAt).toBe(5);
    expect(summarizeSpool(parseSpool([ev("a", "SubagentStart", 1), ev("a", "SubagentStop", 5), ev("a", "SubagentStart", 9)].join("\n"))).stoppedAt).toBeNull();
    expect(summarizeSpool(parseSpool([ev("a", "SubagentStop", 5), ev("a", "PostToolUse", 9)].join("\n"))).stoppedAt).toBeNull();
  });
  it("last tool and TeammateIdle; a teammate's Stop then Idle is a turn end, not an exit", () => {
    const t = summarizeSpool(parseSpool([
      ev("a", "SubagentStart", 1), ev("a", "PostToolUse", 2, { tool_name: "SendMessage" }), ev("a", "SubagentStop", 3), ev("a", "TeammateIdle", 4),
    ].join("\n")));
    expect(t).toMatchObject({ lastTool: "SendMessage", lastToolAt: 2, idleAt: 4, stoppedAt: null });
    const x = summarizeSpool(parseSpool([ev("a", "TeammateIdle", 2), ev("a", "SubagentStop", 3)].join("\n")));
    expect(x).toMatchObject({ idleAt: 2, stoppedAt: 3 });
  });
  it("the lead: newest tool event and newest Notification, agent events ignored", () => {
    const l = summarizeLead(parseSpool([
      ev("", "PostToolUse", 5, { agent_id: null }), ev("", "Notification", 7, { agent_id: null }), ev("a", "PostToolUse", 9),
    ].join("\n")));
    expect(l).toEqual({ lastToolAt: 5, noteAt: 7 });
    expect(summarizeLead([])).toEqual({ lastToolAt: null, noteAt: null });
  });
});

describe("transcript", () => {
  const tr = [
    asst("m1", 0, [{ type: "tool_use", id: "t1", name: "Read" }], { input_tokens: 2, output_tokens: 10, cache_read_input_tokens: 100, cache_creation_input_tokens: 50 }),
    asst("m1", 0, [{ type: "text", text: "SECRET PAYLOAD" }], { input_tokens: 2, output_tokens: 10, cache_read_input_tokens: 100, cache_creation_input_tokens: 50 }),
    user(1, [{ type: "tool_result", tool_use_id: "t1", is_error: true }]),
    asst("m2", 2, [{ type: "tool_use", id: "t2", name: "Bash" }], { input_tokens: 3, output_tokens: 20, cache_read_input_tokens: 200, cache_creation_input_tokens: 5 }),
    line({ type: "api-request-blob", message: { content: [{ type: "tool_use", id: "zz", name: "Blob" }] } }),
  ].join("\n");
  it("takes ctx from the last usage, sums out, finds the in-flight tool", () => {
    const i = summarizeTranscript(tr, { name: "x", description: "d", agentType: "t", spawnDepth: 2, taskKind: "in_process_teammate", toolUseId: "u9" });
    expect(i).toMatchObject({ name: "x", task: "d", type: "t", teammate: true, toolUseId: "u9", model: "claude-opus-5-5", ctxTokens: 208, toolUses: 2, toolErrors: 1, endedTurn: false, lastTool: "Bash", lastToolAt: T0 + 2 * 60000 });
    expect(i.tokens).toEqual({ in: 5, out: 30, cacheRead: 300, cacheWrite: 55 });
    expect(i.inflight).toEqual({ tool: "Bash", verb: null, since: T0 + 2 * 60000 });
    expect(JSON.stringify(i)).not.toContain("SECRET");
  });
  it("collects Agent/Task call ids (a child's meta.toolUseId)", () => {
    const t = asst("m1", 0, [{ type: "tool_use", id: "c1", name: "Agent" }, { type: "tool_use", id: "c2", name: "Task" }, { type: "tool_use", id: "c3", name: "Read" }], {});
    expect(summarizeTranscript(t, null).agentCalls).toEqual(["c1", "c2"]);
    expect(summarizeTranscript(t, null).teammate).toBe(false);
  });
  it("StructuredOutput result means the agent ended", () => {
    const done = tr + "\n" + asst("m3", 3, [{ type: "tool_use", id: "t3", name: "StructuredOutput" }], {}) + "\n" +
      user(3, [{ type: "tool_result", tool_use_id: "t3" }, { type: "tool_result", tool_use_id: "t2" }]);
    expect(summarizeTranscript(done, null).endedTurn).toBe(true);
    expect(summarizeTranscript(done, null).inflight).toBeNull();
  });
});

describe("collectAgents", () => {
  it("joins spool and transcript by id, newest session wins, drops old ended agents", () => {
    const root = "/x/my.repo";
    const base = tmp();
    const consoleDir = join(base, "fw");
    mkdirSync(join(consoleDir, "spool"), { recursive: true });
    const proj = join(base, "projects", "-x-my-repo");
    const sub = (s: string) => join(proj, s, "subagents");
    mkdirSync(sub("s1"), { recursive: true });
    mkdirSync(join(sub("s2"), "workflows", "wf_1"), { recursive: true });
    const now = Date.now();
    const at = (min: number) => new Date(now + min * 60000).toISOString();
    const tline = (min: number) => line({ type: "assistant", timestamp: at(min), message: { id: "m", model: "claude-sonnet-5-5", content: [{ type: "tool_use", id: "t", name: "Bash" }], usage: { input_tokens: 1, cache_read_input_tokens: 9 } } });
    writeFileSync(join(sub("s1"), "agent-live.jsonl"), tline(-30));
    writeFileSync(join(sub("s1"), "agent-live.meta.json"), JSON.stringify({ name: "old", agentType: "k" }));
    writeFileSync(join(sub("s2"), "agent-live.jsonl"), tline(-3));
    writeFileSync(join(sub("s2"), "agent-live.meta.json"), JSON.stringify({ name: "alive", agentType: "k", spawnDepth: 1 }));
    writeFileSync(join(sub("s2"), "workflows", "wf_1", "agent-wfold.jsonl"), tline(-600));
    writeFileSync(join(consoleDir, "spool", "live.jsonl"), [ev("live", "SubagentStart", now - 3600_000), ev("live", "PostToolUse", now - 120_000)].join("\n"));
    writeFileSync(join(consoleDir, "spool", "gone.jsonl"), [ev("gone", "SubagentStart", now - 9e6), ev("gone", "SubagentStop", now - 8e6)].join("\n"));
    writeFileSync(join(consoleDir, "spool", "main.jsonl"), ev("x", "PostToolUse", now));
    const p = pathsFor(root, { FW_CONSOLE_DIR: consoleDir, FW_PROJECTS_DIR: join(base, "projects") } as never);
    expect(findTranscripts(p).get("live")).toContain("s2");
    const agents = collectAgents(p, now);
    expect(agents.map((a) => a.id)).toEqual(["live", "wfold"]);
    const a = agents[0]!;
    expect(a).toMatchObject({ name: "alive", model: "claude-sonnet-5-5", stoppedAt: null, tools: 1, ctxTokens: 10, kind: "subagent", parent: null, transcriptOnly: false, lastTool: "Bash" });
    expect(a.inflight?.tool).toBe("Bash");
    expect(Math.round((now - a.lastAt) / 60000)).toBe(2);
    expect(agents[1]).toMatchObject({ kind: "workflow", transcriptOnly: true, workflowDone: false });
  });
  it("kind from meta and path, parent from the Agent call id, workflowDone from the run file", () => {
    const base = tmp();
    const consoleDir = join(base, "fw");
    mkdirSync(join(consoleDir, "spool"), { recursive: true });
    const sess = join(base, "projects", "-x-r", "s1");
    const sub = join(sess, "subagents");
    mkdirSync(join(sub, "workflows", "wf_9"), { recursive: true });
    mkdirSync(join(sess, "workflows"), { recursive: true });
    const now = Date.now();
    const at = new Date(now - 60000).toISOString();
    const call = (id: string, name: string) => line({ type: "assistant", timestamp: at, message: { id: "m", content: [{ type: "tool_use", id, name }], usage: {} } });
    writeFileSync(join(sub, "agent-tm.jsonl"), call("u1", "Agent"));
    writeFileSync(join(sub, "agent-tm.meta.json"), JSON.stringify({ name: "mate", taskKind: "in_process_teammate" }));
    writeFileSync(join(sub, "agent-kid.jsonl"), call("k1", "Read"));
    writeFileSync(join(sub, "agent-kid.meta.json"), JSON.stringify({ toolUseId: "u1" }));
    writeFileSync(join(sub, "workflows", "wf_9", "agent-wf.jsonl"), call("w1", "Read"));
    writeFileSync(join(sess, "workflows", "wf_9.json"), JSON.stringify({ status: "completed" }));
    const p = pathsFor("/x/r", { FW_CONSOLE_DIR: consoleDir, FW_PROJECTS_DIR: join(base, "projects") } as never);
    const by = new Map(collectAgents(p, now).map((x) => [x.id, x]));
    expect(by.get("tm")).toMatchObject({ kind: "teammate", parent: null });
    expect(by.get("kid")).toMatchObject({ kind: "subagent", parent: "tm" });
    expect(by.get("wf")).toMatchObject({ kind: "workflow", workflowDone: true, transcriptOnly: true });
  });
});

describe("system carry-forward", () => {
  const p = pathsFor("/x/r", { FW_CONSOLE_DIR: "/nonexistent-fw", FW_PROJECTS_DIR: "/nonexistent-proj" } as never);
  const prevSys = (): SystemSnap => ({
    load1: 1, memPressure: "normal", diskFreeGB: 50, simLock: { holder: null, since: null }, worktrees: 1, consolePids: [], stale: [],
    docker: [{ id: "d1", name: "web", startedAt: 1 }], ci: [{ workflow: "ci", branch: "b", status: "completed", conclusion: "failure", startedAt: 1 }],
  });
  const exec = (fail: "timeout" | "missing"): Runner => async (cmd) =>
    cmd === "gh" || cmd === "docker" ? (fail === "missing" ? { missing: true } : null) : "";
  it("a failed gh/docker call keeps the previous value, marked stale", async () => {
    const s = await collectSystem(p, { at: 1000, system: prevSys() }, 2000, exec("timeout"));
    expect(s.stale.sort()).toEqual(["ci", "docker"]);
    expect(s.ci).toHaveLength(1);
    expect(s.docker).toHaveLength(1);
  });
  it("a previous check older than 1 h is not carried; a missing program is empty, not stale", async () => {
    const old = await collectSystem(p, { at: 0, system: prevSys() }, 3600_001, exec("timeout"));
    expect(old).toMatchObject({ stale: ["docker", "ci"], ci: [], docker: [] });
    const miss = await collectSystem(p, { at: 1000, system: prevSys() }, 2000, exec("missing"));
    expect(miss).toMatchObject({ stale: [], ci: [], docker: [] });
  });
});

describe("system parsers", () => {
  it("parses memory level, worktrees, docker, ci", () => {
    expect(["1", "2", "4", "", null].map((x) => parseMemLevel(x))).toEqual(["normal", "warn", "critical", "normal", "normal"]);
    expect(parseWorktreeCount("worktree /a\nHEAD x\n\nworktree /b\n")).toBe(2);
    expect(parseDocker("abc\tweb\t2026-10-17 10:00:00 +0700 +07\n")).toEqual([{ id: "abc", name: "web", startedAt: Date.parse("2026-10-17T10:00:00+07:00") }]);
    expect(parseDocker(null)).toEqual([]);
    expect(parseCi('[{"workflowName":"ci","headBranch":"b","status":"completed","conclusion":"failure","createdAt":"2026-10-17T10:00:00Z"}]'))
      .toEqual([{ workflow: "ci", branch: "b", status: "completed", conclusion: "failure", startedAt: T0, endedAt: null }]);
    expect(parseCi('[{"workflowName":"ci","headBranch":"b","status":"completed","conclusion":"success","createdAt":"2026-10-17T10:00:00Z","updatedAt":"2026-10-17T10:25:00Z"},'
      + '{"workflowName":"ci","headBranch":"c","status":"in_progress","conclusion":"","createdAt":"2026-10-17T10:00:00Z","updatedAt":"2026-10-17T10:05:00Z"}]').map((r) => r.endedAt))
      .toEqual([T0 + 25 * 60000, null]);
    expect(parseCi("nope")).toEqual([]);
  });
});

describe("session processes", () => {
  it("parses ps etime and rows", () => {
    expect(["00:07", "12:34", "01:00:00", "2-03:04:05", "x", "1:2:3:4"].map(parseEtime))
      .toEqual([7000, 754000, 3600_000, ((2 * 24 + 3) * 60 + 4) * 60_000 + 5000, null, null]);
    expect(parsePs("  10     1    03:41:48 claude\n 11 10 00:30 /bin/zsh\nbad line\n 12 11 00:20 npm exec x@latest\n"))
      .toEqual([{ pid: 10, ppid: 1, ageMs: (3 * 3600 + 41 * 60 + 48) * 1000, comm: "claude" },
        { pid: 11, ppid: 10, ageMs: 30000, comm: "/bin/zsh" }, { pid: 12, ppid: 11, ageMs: 20000, comm: "npm exec x@latest" }]);
    expect(["/bin/zsh", "/Applications/A B.app/Contents/MacOS/A B", "npm exec x@latest", "node"].map(exe))
      .toEqual(["zsh", "A B", "npm", "node"]);
  });
  it("takes the Bash shells of this process's claude ancestor, names them by their first program", () => {
    const rows = parsePs([
      "100 1 01:00:00 claude", "101 100 30:00 /bin/zsh", "102 101 29:00 /bin/zsh", "103 102 29:00 /opt/x/bin/node",
      "104 103 28:00 sleep", "110 100 01:00:00 npm exec some-mcp", "120 100 05:00 /bin/zsh", "121 120 05:00 node",
      "200 1 01:00:00 claude", "201 200 50:00 /bin/zsh",
    ].join("\n"));
    const now = 10_000_000;
    expect(sessionProcs(rows, 121, now)).toEqual([
      { pid: 101, name: "node", startedAt: now - 30 * 60000, pids: [102, 103, 104] },
      { pid: 120, name: "node", startedAt: now - 5 * 60000, pids: [121] },
    ]);
    expect(sessionProcs(rows, 999, now)).toEqual([]);
    expect(sessionProcs(parsePs("5 1 00:01 /bin/zsh\n6 5 00:01 node"), 6, now)).toEqual([]);
  });
  it("a tree keeps its first name while its root pid and start time stay", () => {
    const q = (pid: number, name: string, startedAt: number) => ({ pid, name, startedAt, pids: [] });
    expect(keepNames([q(1, "gh", 1000), q(2, "gh", 1000), q(3, "gh", 1000)], [q(1, "sleep", 2500), q(2, "sleep", 9000)]))
      .toEqual([q(1, "sleep", 1000), q(2, "gh", 1000), q(3, "gh", 1000)]);
  });
});

describe("critical path", () => {
  const base = tmp();
  const p = pathsFor("/x/r", { FW_CONSOLE_DIR: join(base, "fwc"), FW_PROJECTS_DIR: base } as never);
  it("reads criticalPath from /api/plan; no console-api is none; a failed call is null", async () => {
    expect(await collectCritical(p, {}, async () => { throw new Error("unused"); })).toEqual([]);
    expect(await collectCritical(p, { FW_API: "http://h" }, async (u) => (u === "http://h/api/plan" ? { criticalPath: ["a", 3, "b"] } : {})))
      .toEqual(["a", "b"]);
    expect(await collectCritical(p, { FW_API: "http://h" }, async () => { throw new Error("down"); })).toBeNull();
    expect(await collectCritical(p, { FW_API: "http://h" }, async () => ({}))).toBeNull();
  });
  it("a failed call carries the previous check's path for 1 h, marked stale", () => {
    const sys = {} as SystemSnap;
    expect(carryCritical(["x"], null, 0)).toEqual({ critical: ["x"], stale: false });
    expect(carryCritical(null, { at: 0, system: sys, critical: ["a"] }, 3600_000)).toEqual({ critical: ["a"], stale: true });
    expect(carryCritical(null, { at: 0, system: sys, critical: ["a"] }, 3600_001)).toEqual({ critical: [], stale: true });
    expect(carryCritical(null, null, 0)).toEqual({ critical: [], stale: true });
  });
});

describe("cli", () => {
  it("parses flags", () => {
    expect(parseWatchArgs([])).toEqual({ json: false, intervalS: null, untilAlert: false });
    expect(parseWatchArgs(["--until-alert"]).intervalS).toBe(300);
    expect(parseWatchArgs(["--json", "--interval", "30"])).toEqual({ json: true, intervalS: 30, untilAlert: false });
    expect(() => parseWatchArgs(["--interval", "x"])).toThrow();
    expect(() => parseWatchArgs(["--nope"])).toThrow();
  });
  it("new alerts are those not in the previous check; the first check is a baseline", () => {
    const h = (codes: [string, string][]): Health => ({ agents: [], system: { alerts: [] }, counts: {}, alerts: codes.map(([code, subject]) => ({ code, subject, detail: "" })) });
    expect(newAlerts(null, h([["a", "1"]]))).toEqual([]);
    const prev = new Set([alertKey({ code: "a", subject: "1", detail: "" })]);
    expect(newAlerts(prev, h([["a", "1"], ["b", "2"]])).map(alertKey)).toEqual(["b|2"]);
  });
  it("the last logged check is read back as the baseline", () => {
    const base = tmp();
    const p = pathsFor("/x/r", { FW_CONSOLE_DIR: join(base, "fw"), FW_PROJECTS_DIR: base } as never);
    expect(readLastLog(p)).toBeNull();
    const h = (code: string): Health => ({ agents: [], system: { alerts: [] }, counts: {}, alerts: [{ code, subject: "s", detail: "" }] });
    const snap = (now: number) => ({ now, params: {}, agents: [], lead: { lastToolAt: null, noteAt: null }, system: { pad: "x".repeat(70000) } }) as never;
    appendLog(p, snap(1), h("one"));
    appendLog(p, snap(2), h("two"));
    const last = readLastLog(p)!;
    expect(last.at).toBe(2);
    expect(newAlerts(new Set(last.output.alerts.map(alertKey)), h("two"))).toEqual([]);
  });
  it("renders at most 40 lines and never the agent ids of done agents", () => {
    const agents = Array.from({ length: 60 }, (_, i) => ({
      id: `id${i}`, name: `agent-${i}`, task: null, type: "t", model: "claude-opus-5-5", kind: "subagent" as const, parent: null,
      startedAt: T0, lastAt: T0 - i * 60000, stoppedAt: i % 7 === 0 ? T0 : null, tools: i, errors: 0, errTail: 0, inflight: null,
      lastTool: null, lastToolAt: null, idleAt: null, workflowDone: false, transcriptOnly: false,
      ctxTokens: 1000 * i, tokens: { in: 0, out: 0, cacheRead: 0, cacheWrite: 0 },
    }));
    const snap = { now: T0, params: {}, agents, lead: { lastToolAt: null, noteAt: null }, system: { load1: 1, memPressure: "normal" as const, diskFreeGB: 50, simLock: { holder: null, since: null }, docker: [], worktrees: 3, consolePids: [], ci: [], stale: ["ci"] } };
    const h: Health = {
      agents: agents.map((a) => ({ id: a.id, state: a.stoppedAt ? "done" : "active", alerts: [] })),
      system: { alerts: [] }, counts: { active: 50, idle: 0, parked: 0, stalled: 0, done: 10 },
      alerts: Array.from({ length: 30 }, (_, i) => ({ code: "agent.ctxHigh", subject: `id${i}`, detail: "d" })),
    };
    const out = renderTable(snap, h);
    expect(out.split("\n").length).toBeLessThanOrEqual(40);
    expect(out).toContain("+");
    expect(out).toContain("agent-1 ");
    expect(out).toContain("parked 0");
    expect(out).toContain("(0 failed) stale");
    expect(out).toContain("gone 0 done 10");
  });
});
