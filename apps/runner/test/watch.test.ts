import { existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync, rmSync, utimesSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, describe, expect, it } from "vitest";
import {
  carryCritical, collectAgents, collectCritical, collectFeedback, collectSystem, countBuilders, countHeavy, exe, findTranscripts, keepNames, ownProcs, parseStartRows, parseTaskIds, readKeep, parseCi, parseEtime, parsePs, sessionProcs, parseDocker, parseMemLevel, parseSpool, parseWorktreeCount, pathsFor,
  summarizeLead, summarizeSpool, summarizeTranscript, type Runner, type SystemSnap,
} from "../src/watch-collect.ts";
import {
  alertKey, appendLog, check, coreCaller, declareKeep, diffAlerts, keepDecider, newAlerts, parseWatchArgs, readLastLog, renderTable, streamLines,
  type AlertKey, type Health,
} from "../src/watch.ts";

const here = dirname(fileURLToPath(import.meta.url));
const bin = process.env.FW_CORE_BIN ?? join(here, "../../../lean/.lake/build/bin/fwcore");
const have = existsSync(bin);
const core = coreCaller(have ? [bin] : []);

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
    expect(summarizeSpool(parseSpool([ev("a", "SubagentStop", 5), ev("a", "PostToolUse", 9)].join("\n"))).stoppedAt).toBe(5);
  });
  it("carries the session pid of the newest line that has one", () => {
    const s = summarizeSpool(parseSpool([ev("a", "SubagentStart", 1, { session_pid: 11 }), ev("a", "PostToolUse", 5, { session_pid: 12 }), ev("a", "PostToolUse", 9)].join("\n")));
    expect(s.sessionPid).toBe(12);
    expect(summarizeSpool(parseSpool(ev("a", "PostToolUse", 9))).sessionPid).toBeNull();
  });
  it("follows the Lean golden of the resume predicate (Fw.Ops.Obs.stoppedAtOf): only a SubagentStart after the stop resumes", () => {
    const rows = readFileSync(join(here, "../../../packages/contracts/golden/ops/ops.obs.jsonl"), "utf8").trim().split("\n")
      .map((l) => JSON.parse(l) as { name: string; request: { resume?: { hooks: { event: string; ts: number }[] }[] }; response: { resume?: (number | null)[] } })
      .filter((c) => c.request.resume);
    expect(rows.length).toBeGreaterThanOrEqual(9);
    for (const c of rows) {
      const got = c.request.resume!.map((r) => summarizeSpool(parseSpool(r.hooks.map((h) => ev("a", h.event, h.ts)).join("\n"))).stoppedAt);
      expect({ name: c.name, got }).toEqual({ name: c.name, got: c.response.resume });
    }
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
    utimesSync(join(sub("s1"), "agent-live.jsonl"), new Date(now - 60_000), new Date(now - 60_000)); // newest by mtime, not by write order (equal mtimes tie on a fast disk)
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
  it("the run list's read time: now when gh answered, the previous list's time when it failed (a carried list keeps its age)", async () => {
    const ok = await collectSystem(p, { at: 1000, system: prevSys() }, 2000, async () => "[]");
    expect(ok.ciAt).toBe(2000);
    const carried = await collectSystem(p, { at: 1000, system: prevSys() }, 2000, exec("timeout"));
    expect(carried.ciAt).toBe(1000);
    const again = await collectSystem(p, { at: 2000, system: { ...prevSys(), ciAt: 1000 } }, 3000, exec("timeout"));
    expect(again.ciAt).toBe(1000);
  });
  it("a previous check older than 1 h is not carried; a missing program is empty, not stale", async () => {
    const old = await collectSystem(p, { at: 0, system: prevSys() }, 3600_001, exec("timeout"));
    expect(old).toMatchObject({ stale: ["docker", "ci"], ci: [], docker: [] });
    const miss = await collectSystem(p, { at: 1000, system: prevSys() }, 2000, exec("missing"));
    expect(miss).toMatchObject({ stale: [], ci: [], docker: [] });
  });
  it("the process table's pids are the alive pids (Lean deadSession); an unread table gives none, so no agent is judged by it", async () => {
    const ps = "  1     0 05:00 /sbin/launchd\n  77     1 01:00 claude\n";
    const ok = await collectSystem(p, { at: 1000, system: prevSys() }, 2000, async (cmd, args) => (cmd === "ps" && args[1] === "-o" && args[2]?.startsWith("pid=") ? ps : cmd === "gh" || cmd === "docker" ? "" : ""));
    expect(ok.alivePids).toEqual([1, 77]);
    const none = await collectSystem(p, { at: 1000, system: prevSys() }, 2000, async (cmd) => (cmd === "ps" ? null : ""));
    expect(none.alivePids).toBeUndefined();
  });
  it("keep comes from the decision over the lstart rows; a failed decision keeps the previous value, marked stale", async () => {
    const lstart = "  42 Sun Oct 18 09:58:17 2026 node apps/runner/src/fw.ts watch --interval 300 --stream\n";
    const ex: Runner = async (cmd) => (cmd === "env" ? lstart : cmd === "gh" || cmd === "docker" ? { missing: true } : "");
    const seen: unknown[] = [];
    const s = await collectSystem(p, null, 2000, ex, new Map(), async (entries, rows) => { seen.push(entries, rows); return { live: [], keep: [42] }; });
    expect(s.keep).toEqual([42]);
    expect(seen[0]).toEqual([]);
    const failed = await collectSystem(p, { at: 1000, system: { ...prevSys(), keep: [7] } }, 2000, ex, new Map(), async () => { throw new Error("no fwcore"); });
    expect(failed).toMatchObject({ keep: [7], stale: ["keep"] });
    expect((await collectSystem(p, null, 2000, ex)).keep).toEqual([]);
  });
});

describe("system parsers", () => {
  it("parses memory level, worktrees, docker, ci", () => {
    expect(["1", "2", "4", "", null].map((x) => parseMemLevel(x))).toEqual(["normal", "warn", "critical", "normal", "normal"]);
    expect(parseWorktreeCount("worktree /a\nHEAD x\n\nworktree /b\n")).toBe(2);
    expect(parseDocker("abc\tweb\t2026-10-17 10:00:00 +0700 +07\n")).toEqual([{ id: "abc", name: "web", startedAt: Date.parse("2026-10-17T10:00:00+07:00") }]);
    expect(parseDocker(null)).toEqual([]);
    expect(parseCi('[{"workflowName":"ci","headBranch":"b","status":"completed","conclusion":"failure","createdAt":"2026-10-17T10:00:00Z"}]'))
      .toEqual([{ workflow: "ci", branch: "b", status: "completed", conclusion: "failure", startedAt: T0, endedAt: null, headSha: "" }]);
    expect(parseCi('[{"workflowName":"ci","headBranch":"b","status":"completed","conclusion":"success","createdAt":"2026-10-17T10:00:00Z","updatedAt":"2026-10-17T10:25:00Z"},'
      + '{"workflowName":"ci","headBranch":"c","status":"in_progress","conclusion":"","createdAt":"2026-10-17T10:00:00Z","updatedAt":"2026-10-17T10:05:00Z"}]').map((r) => r.endedAt))
      .toEqual([T0 + 25 * 60000, null]);
    expect(parseCi("nope")).toEqual([]);
  });
});

describe("sys.contended counts", () => {
  it("counts lake processes and live heavy-lock holders", () => {
    const rows = parsePs("10 1 00:05 /Users/x/.elan/bin/lake\n11 10 00:05 /bin/zsh\n12 1 00:05 /Users/x/.elan/bin/lake\n13 1 00:05 node");
    expect(countBuilders(rows)).toBe(2);
    const root = mkdtempSync(join(tmpdir(), "fw-heavy-"));
    const starts = [{ pid: 13, start: 1000, args: "node" }, { pid: 14, start: 2000, args: "node" }];
    expect(countHeavy(root, starts)).toBe(0);
    mkdirSync(join(root, ".git", "fw-heavy", "holders"), { recursive: true });
    const put = (pid: number, start: number) => writeFileSync(join(root, ".git", "fw-heavy", "holders", `${pid}.json`), JSON.stringify({ pid, start, kind: "check" }));
    put(13, 1000); // alive, same start: a holder
    put(14, 1999); // pid reused (another start time): stale, as Lean Fw.Sched.Heavy.reused_pid_stale
    put(99, 5);   // no such process
    writeFileSync(join(root, ".git", "fw-heavy", "holders", "bad.json"), "{");
    expect(countHeavy(root, starts)).toBe(1);
    rmSync(root, { recursive: true, force: true });
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
    // the owner carries over when this check found none; a found owner wins
    expect(keepNames([q(1, "gh", 1000), { ...q(2, "gh", 1000), agent: "b" }], [{ ...q(1, "sleep", 1000), agent: "a" }, { ...q(2, "sleep", 1000), agent: "a" }]))
      .toEqual([{ ...q(1, "sleep", 1000), agent: "a" }, { ...q(2, "sleep", 1000), agent: "b" }]);
  });
  it("owner: the root shell's stdout task file names the Bash task; the transcript that started it names the agent", () => {
    const lsof = ["p101", "f1", "n/private/tmp/claude-501/proj/sess/tasks/bj5dpmo2u.output", "p120", "f1", "n/dev/null",
      "p130", "f1", "n/private/tmp/claude-501/proj/sess/tasks/blead0001.output", ""].join("\n");
    const ids = parseTaskIds(lsof);
    expect([...ids]).toEqual([[101, "bj5dpmo2u"], [130, "blead0001"]]);
    expect(parseTaskIds(null).size).toBe(0);
    const q = (pid: number) => ({ pid, name: "sleep", startedAt: 0, pids: [] });
    expect(ownProcs([q(101), q(120), q(130)], ids, new Map([["bj5dpmo2u", "a582f"]])))
      .toEqual([{ ...q(101), agent: "a582f" }, q(120), q(130)]);
    const t = [user(1, [{ type: "tool_result", tool_use_id: "x" }]).replace('"type":"user"', '"type":"user","toolUseResult":{"stdout":"","backgroundTaskId":"bj5dpmo2u"}'),
      line({ type: "user", toolUseResult: "Error: text" }), line({ type: "user", toolUseResult: { stdout: "\"backgroundTaskId\":\"bfake\"" } })].join("\n");
    expect(summarizeTranscript(t, null).bgTasks).toEqual(["bj5dpmo2u"]);
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
    const base = { json: false, intervalS: null, untilAlert: false, stream: false, keep: null, unkeep: null, note: null };
    expect(parseWatchArgs([])).toEqual(base);
    expect(parseWatchArgs(["--until-alert"]).intervalS).toBe(300);
    expect(parseWatchArgs(["--interval", "300", "--stream"])).toEqual({ ...base, intervalS: 300, stream: true });
    expect(parseWatchArgs(["--stream"]).intervalS).toBe(300);
    for (const bad of [["--stream", "--until-alert"], ["--stream", "--json"], ["--keep", "4", "--stream"]]) expect(() => parseWatchArgs(bad)).toThrow();
    expect(parseWatchArgs(["--json", "--interval", "30"])).toEqual({ ...base, json: true, intervalS: 30 });
    expect(() => parseWatchArgs(["--interval", "x"])).toThrow();
    expect(() => parseWatchArgs(["--nope"])).toThrow();
  });
  it("parses --keep/--note/--unkeep alone", () => {
    const base = { json: false, intervalS: null, untilAlert: false, stream: false, keep: null, unkeep: null, note: null };
    expect(parseWatchArgs(["--keep", "42", "--note", "monitor"])).toEqual({ ...base, keep: 42, note: "monitor" });
    expect(parseWatchArgs(["--unkeep", "42"])).toEqual({ ...base, unkeep: 42 });
    for (const bad of [["--keep"], ["--keep", "0"], ["--keep", "1.5"], ["--keep", "4", "--interval", "9"], ["--keep", "4", "--unkeep", "4"],
      ["--note", "x"], ["--unkeep", "4", "--note", "x"], ["--keep", "4", "--json"]])
      expect(() => parseWatchArgs(bad)).toThrow();
  });
  it("parses ps lstart rows (UTC) with their command line", () => {
    expect(parseStartRows("68178 Sun Oct 18 09:58:17 2026     node apps/runner/src/fw.ts watch --interval 300 --stream\n    1 Mon Oct  5 05:57:33 2026 /sbin/launchd\nbad\n 9 Sun Oct 18 09:58:17 2026\n"))
      .toEqual([
        { pid: 68178, start: Date.UTC(2026, 9, 18, 9, 58, 17) / 1000, args: "node apps/runner/src/fw.ts watch --interval 300 --stream" },
        { pid: 1, start: Date.UTC(2026, 9, 5, 5, 57, 33) / 1000, args: "/sbin/launchd" },
        { pid: 9, start: Date.UTC(2026, 9, 18, 9, 58, 17) / 1000, args: "" },
      ]);
  });
  it("streamLines: one OPEN per opened alert, one CLOSE per closed key, each on one line", () => {
    expect(streamLines({ opened: [{ code: "proc.long", subject: "node#7", detail: "31m\n idle" }], closed: [{ code: "ci.slow", subject: "r1" }], next: [] }))
      .toEqual(["OPEN proc.long node#7 31m idle", "CLOSE ci.slow r1"]);
  });
});

describe.skipIf(!have)("fwcore ops.watchDiff / ops.watchKeep", () => {
  const golden = (op: string) => readFileSync(join(here, `../../../packages/contracts/golden/ops/${op}.jsonl`), "utf8").trim().split("\n")
    .map((l) => JSON.parse(l) as { name: string; request: Record<string, unknown>; response: Record<string, unknown> });
  it.each([...golden("ops.watchDiff"), ...golden("ops.watchKeep")].filter((c) => !("error" in c.response)).map((c) => [c.name, c] as const))("golden: %s", async (_n, c) => {
    const { id: _id, ...reply } = await core(c.request);
    expect(reply).toEqual(c.response);
  });
  it("--keep writes keep.json with the process start; --unkeep removes; gone or reused pids drop out", async () => {
    const dir = mkdtempSync(join(tmpdir(), "fw-keep-"));
    try {
      const paths = pathsFor("/x/r", { FW_CONSOLE_DIR: dir } as never);
      const decide = keepDecider(core);
      const rows = [{ pid: 7, start: 1000, args: "/usr/bin/caffeinate -i" }, { pid: 8, start: 2000, args: "Python x.py" }];
      const o = (x: object) => ({ json: false, intervalS: null, untilAlert: false, stream: false, keep: null, unkeep: null, note: null, ...x });
      expect(await declareKeep(paths, o({ keep: 7, note: "awake" }), rows, decide)).toContain("pid 7 (caffeinate) declared");
      await declareKeep(paths, o({ keep: 8 }), rows, decide);
      expect(readKeep(paths)).toEqual([{ pid: 7, start: 1000, note: "awake" }, { pid: 8, start: 2000, note: null }]);
      await expect(declareKeep(paths, o({ keep: 9 }), rows, decide)).rejects.toThrow(/no running process 9/);
      await declareKeep(paths, o({ unkeep: 7 }), rows, decide);
      expect(readKeep(paths).map((e) => e.pid)).toEqual([8]);
      // pid 8 now names a process started 1 s later (reused pid): not the declared one, at any load
      expect(await decide(readKeep(paths), [{ pid: 8, start: 2001, args: "x" }])).toEqual({ live: [], keep: [] });
      expect(await decide(readKeep(paths), [{ pid: 8, start: 2000, args: "x" }])).toEqual({ live: [0], keep: [8] });
      await declareKeep(paths, o({ keep: 7 }), [rows[0]!], decide);
      expect(readKeep(paths)).toEqual([{ pid: 7, start: 1000, note: null }]);
      writeFileSync(join(dir, "keep.json"), JSON.stringify([{ pid: 5, startedAt: 9000, note: null }]));
      expect(readKeep(paths)).toEqual([]);
    } finally { rmSync(dir, { recursive: true, force: true }); }
  });
  it("the lead Monitor command line is kept without a declaration", async () => {
    const decide = keepDecider(core);
    expect(await decide([], [{ pid: 9, start: 1, args: "node apps/runner/src/fw.ts watch --interval 300 --stream" }, { pid: 10, start: 1, args: "node apps/runner/src/fw.ts watch --until-alert" }]))
      .toEqual({ live: [], keep: [9] });
  });
  it("new alerts are those not in the previous check; the first check is a baseline", async () => {
    const h = (codes: [string, string][]): Health => ({ agents: [], system: { alerts: [] }, counts: {}, alerts: codes.map(([code, subject]) => ({ code, subject, detail: "" })) });
    expect(await newAlerts(core, null, h([["a", "1"]]))).toEqual([]);
    expect((await newAlerts(core, [{ code: "a", subject: "1" }], h([["a", "1"], ["b", "2"]]))).map(alertKey)).toEqual(["b|2"]);
  });
  it("a stream over a trace prints each key open once until it closes", async () => {
    const trace: [string, string][][] = [[["x", "1"]], [["x", "1"], ["y", "2"]], [["y", "2"]], [], [["x", "1"]]];
    let open: AlertKey[] = [];
    const lines: string[] = [];
    for (const t of trace) {
      const d = await diffAlerts(core, open, t.map(([code, subject]) => ({ code, subject, detail: "d" })));
      lines.push(...streamLines(d));
      open = d.next;
    }
    expect(lines).toEqual(["OPEN x 1 d", "OPEN y 2 d", "CLOSE x 1", "CLOSE y 2", "OPEN x 1 d"]);
  });
  it("the last logged check is read back as the baseline", async () => {
    const base = tmp();
    const p = pathsFor("/x/r", { FW_CONSOLE_DIR: join(base, "fw"), FW_PROJECTS_DIR: base } as never);
    expect(readLastLog(p)).toBeNull();
    const h = (code: string): Health => ({ agents: [], system: { alerts: [] }, counts: {}, alerts: [{ code, subject: "s", detail: "" }] });
    const snap = (now: number) => ({ now, params: {}, agents: [], lead: { lastToolAt: null, noteAt: null }, system: { pad: "x".repeat(70000) } }) as never;
    appendLog(p, snap(1), h("one"));
    appendLog(p, snap(2), h("two"));
    const last = readLastLog(p)!;
    expect(last.at).toBe(2);
    expect(await newAlerts(core, last.output.alerts.map((a) => ({ code: a.code, subject: a.subject })), h("two"))).toEqual([]);
  });
});

describe("render", () => {
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

describe("review.feedback alert (Lean Fw.Obs.FeedbackAlert, wired in Fw.Obs.Health)", () => {
  const FLAG = "nav:earn-no-transition";
  const post = (id: string, text: string, ts: number, flag = FLAG) => line({ seq: ts, ts, type: "review.feedback", key: `k-${id}`, actor: "user", flag, id, text });
  const reply = (to: string, text: string, ts: number, flag = FLAG) => line({ seq: ts, ts, type: "review.feedback.reply", key: `r-${to}`, actor: "lead", flag, to, text });
  const dirWith = (lines: string[]) => { const d = tmp(); writeFileSync(join(d, "events.jsonl"), lines.join("\n") + "\n"); return pathsFor("/x/r", { FW_CONSOLE_DIR: d } as never); };
  const snap = (feedback: unknown[]) => ({
    now: 1_000_000, params: {}, agents: [], lead: { lastToolAt: null, noteAt: null },
    system: { load1: 0, memPressure: "normal", diskFreeGB: 100, simLock: { holder: null, since: null }, docker: [], worktrees: 1, consolePids: [], ci: [], stale: [], feedback },
  }) as never;

  it("collectFeedback reads only the two feedback event types, in log order, in the wire shape", () => {
    const p = dirWith([line({ seq: 1, ts: 1, type: "step.start", step: "x" }), post("fb-1", "one", 100), "{torn", reply("fb-1", "done", 110),
      line({ seq: 5, ts: 5, type: "review.feedback", flag: 3, id: "x", text: "bad flag" })]);
    expect(collectFeedback(p)).toEqual([
      { kind: "post", flag: FLAG, ref: "fb-1", text: "one", ts: 100 }, { kind: "reply", flag: FLAG, ref: "fb-1", text: "done", ts: 110 }]);
    expect(collectFeedback(pathsFor("/x/r", { FW_CONSOLE_DIR: "/nonexistent-fw" } as never))).toEqual([]);
  });
  it("collectSystem carries the feedback events of the log", async () => {
    const p = dirWith([post("fb-1", "one", 100)]);
    const s = await collectSystem(p, null, 2000, async () => "");
    expect(s.feedback).toEqual([{ kind: "post", flag: FLAG, ref: "fb-1", text: "one", ts: 100 }]);
  });
  it.skipIf(!have)("a posted comment opens the alert in fwcore's report and the lead's reply closes it", async () => {
    const open = collectFeedback(dirWith([post("fb-1", "look at the font", 100)]));
    const h1 = await check(snap(open), core);
    expect(h1.alerts.filter((a) => a.code === "review.feedback")).toEqual([
      { code: "review.feedback", subject: FLAG, detail: "1 open; newest: look at the font", critical: false }]);
    const closed = collectFeedback(dirWith([post("fb-1", "look at the font", 100), reply("fb-1", "done", 110)]));
    const h2 = await check(snap(closed), core);
    expect(h2.alerts.filter((a) => a.code === "review.feedback")).toEqual([]);
    // a second open comment on another flag is its own alert
    const two = collectFeedback(dirWith([post("fb-1", "a", 100), post("fb-2", "b", 101, "hero:cta-pulse"), reply("fb-1", "ok", 102)]));
    expect((await check(snap(two), core)).alerts.filter((a) => a.code === "review.feedback").map((a) => a.subject)).toEqual(["hero:cta-pulse"]);
  });
});
