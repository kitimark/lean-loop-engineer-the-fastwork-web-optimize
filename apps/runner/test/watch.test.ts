import { mkdirSync, mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, describe, expect, it } from "vitest";
import {
  collectAgents, findTranscripts, parseCi, parseDocker, parseMemLevel, parseSpool, parseWorktreeCount, pathsFor,
  summarizeSpool, summarizeTranscript,
} from "../src/watch-collect.ts";
import { alertKey, newAlerts, parseWatchArgs, renderTable, type Health } from "../src/watch.ts";

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
    expect(s).toMatchObject({ tools: 3, errors: 2, errTail: 2, startedAt: T0, lastAt: T0 + 3000, stoppedAt: null, waiting: false });
    expect(summarizeSpool(parseSpool([ev("a", "SubagentStart", 1), ev("a", "SubagentStop", 5)].join("\n"))).stoppedAt).toBe(5);
    expect(summarizeSpool(parseSpool([ev("a", "SubagentStart", 1), ev("a", "SubagentStop", 5), ev("a", "SubagentStart", 9)].join("\n"))).stoppedAt).toBeNull();
  });
  it("waiting only while the notification is the latest tool-level event", () => {
    const w = summarizeSpool(parseSpool([ev("a", "PostToolUse", 1), ev("a", "Notification", 2)].join("\n")));
    expect(w.waiting).toBe(true);
    const r = summarizeSpool(parseSpool([ev("a", "Notification", 2), ev("a", "PostToolUse", 3)].join("\n")));
    expect(r.waiting).toBe(false);
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
    const i = summarizeTranscript(tr, { name: "x", description: "d", agentType: "t", spawnDepth: 2 });
    expect(i).toMatchObject({ name: "x", task: "d", type: "t", depth: 2, model: "claude-opus-5-5", ctxTokens: 208, toolUses: 2, toolErrors: 1, endedTurn: false });
    expect(i.tokens).toEqual({ in: 5, out: 30, cacheRead: 300, cacheWrite: 55 });
    expect(i.inflight).toEqual({ tool: "Bash", verb: null, since: T0 + 2 * 60000 });
    expect(JSON.stringify(i)).not.toContain("SECRET");
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
    expect(a).toMatchObject({ name: "alive", model: "claude-sonnet-5-5", stoppedAt: null, tools: 1, ctxTokens: 10 });
    expect(a.inflight?.tool).toBe("Bash");
    expect(Math.round((now - a.lastAt) / 60000)).toBe(2);
  });
});

describe("system parsers", () => {
  it("parses memory level, worktrees, docker, ci", () => {
    expect(["1", "2", "4", "", null].map((x) => parseMemLevel(x))).toEqual(["normal", "warn", "critical", "normal", "normal"]);
    expect(parseWorktreeCount("worktree /a\nHEAD x\n\nworktree /b\n")).toBe(2);
    expect(parseDocker("abc\tweb\t2026-10-17 10:00:00 +0700 +07\n")).toEqual([{ id: "abc", name: "web", startedAt: Date.parse("2026-10-17T10:00:00+07:00") }]);
    expect(parseDocker(null)).toEqual([]);
    expect(parseCi('[{"workflowName":"ci","headBranch":"b","status":"completed","conclusion":"failure","createdAt":"2026-10-17T10:00:00Z"}]'))
      .toEqual([{ workflow: "ci", branch: "b", status: "completed", conclusion: "failure", startedAt: T0 }]);
    expect(parseCi("nope")).toEqual([]);
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
  it("renders at most 40 lines and never the agent ids of done agents", () => {
    const agents = Array.from({ length: 60 }, (_, i) => ({
      id: `id${i}`, name: `agent-${i}`, task: null, type: "t", model: "claude-opus-5-5", depth: 1, startedAt: T0, lastAt: T0 - i * 60000, stoppedAt: i % 7 === 0 ? T0 : null,
      tools: i, errors: 0, errTail: 0, inflight: null, waitingPermission: false, ctxTokens: 1000 * i, tokens: { in: 0, out: 0, cacheRead: 0, cacheWrite: 0 },
    }));
    const snap = { now: T0, params: {}, agents, system: { load1: 1, memPressure: "normal" as const, diskFreeGB: 50, simLock: { holder: null, since: null }, docker: [], worktrees: 3, consolePids: [], ci: [] } };
    const h: Health = {
      agents: agents.map((a) => ({ id: a.id, state: a.stoppedAt ? "done" : "active", alerts: [] })),
      system: { alerts: [] }, counts: { active: 50, idle: 0, waiting: 0, stalled: 0, done: 10 },
      alerts: Array.from({ length: 30 }, (_, i) => ({ code: "agent.ctxHigh", subject: `id${i}`, detail: "d" })),
    };
    const out = renderTable(snap, h);
    expect(out.split("\n").length).toBeLessThanOrEqual(40);
    expect(out).toContain("+");
    expect(out).toContain("agent-1 ");
  });
});
