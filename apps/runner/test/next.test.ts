// obs-next-glue: the fact builder replays golden cases 1-7 of packages/contracts/golden/obs/next.jsonl (facts -> raw
// observations -> buildFacts must give the same facts; fwcore on them must give the golden actions), plus one end-to-end
// run against a real child process. No decision is tested here beyond "TS passes fwcore's answer through".
import { spawn } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, describe, expect, it } from "vitest";
import {
  buildFacts, classifyTree, formatNext, handbackAtOf, nextAlerts, parseWorktrees, psCommands, statFile, watchedFileOf, worktreeOf,
  type AgentFacts, type NextReply, type Raw, type RawPs,
} from "../src/next.ts";
import { coreCaller } from "../src/watch.ts";
import { hasWorktree, parsePs as parsePsRows, startFromAge } from "../src/watch-collect.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const fwcore = join(root, "lean/.lake/build/bin/fwcore");
const golden = readFileSync(join(root, "packages/contracts/golden/obs/next.jsonl"), "utf8").trim().split("\n")
  .map((l) => JSON.parse(l) as { name: string; request: { now: number; agents: any[] }; response: NextReply });
// A fact "producer exited" with no watched file cannot be observed (the exit marker is read from the watched file),
// so such Lean-side edge cases (6b) are not replayable through the collector.
const cases17 = golden.filter((g) => /^case \d/.test(g.name)
  && !g.request.agents.some((f) => f.children.some((c: any) => c.producerExited && c.watchedAt == null)));

const dirs: string[] = [];
afterAll(() => dirs.forEach((d) => rmSync(d, { recursive: true, force: true })));

/** drop null/undefined keys recursively: the golden writes absent options as null */
const norm = (v: unknown): unknown =>
  Array.isArray(v) ? v.map(norm)
    : v && typeof v === "object" ? Object.fromEntries(Object.entries(v).filter(([, x]) => x != null).map(([k, x]) => [k, norm(x)]))
    : v;

/** Invert the golden facts into the raw observations a machine with those facts would show. */
function rawOf(now: number, facts: any[]): Raw {
  const ps = new Map<number, RawPs>();
  const files = new Map<string, { mtimeMs: number; lastLine: string }>();
  const alive = new Set<number>();
  const procs: Raw["procs"] = [];
  const addChain = (pid: number, chain: number[], ageMs: number, comm: string) => {
    ps.set(pid, { pid, ppid: chain[0] ?? 1, ageMs, comm });
    chain.forEach((c, i) => { if (!ps.has(c)) ps.set(c, { pid: c, ppid: chain[i + 1] ?? 1, ageMs: 9e9, comm: c === facts[0].session ? "/usr/local/bin/claude" : "/bin/zsh" }); });
  };
  let queued = "";
  const agents: Raw["agents"] = facts.map((f) => {
    if (f.branch?.queued) queued += ` ${f.branch.name}`;
    if (f.worktree?.lockAlive && f.worktree.lockPid != null) alive.add(f.worktree.lockPid);
    for (const c of f.children) {
      const file = c.watchedAt != null ? `/scratch/w${c.pid}.txt` : "";
      const comm = c.kind === "sleepLoop" ? `/bin/zsh -c until grep -q done ${file}; do sleep 5; done`.replace("  ", " ")
        : c.kind === "ciWait" ? `/bin/zsh -c sh waitrun.sh ${c.run} ${c.timeoutMin}`
        : c.kind === "build" ? "/bin/zsh -c lake build" : "/bin/zsh -c sleep 1000";
      addChain(c.pid, c.chain, now - c.startedAt, comm);
      procs.push({ pid: c.pid, name: "zsh", startedAt: c.startedAt, pids: [], agent: f.id });
      if (c.watchedAt != null) files.set(file, { mtimeMs: c.watchedAt, lastLine: c.producerExited ? "[exited with code 0]" : "tick" });
    }
    return {
      id: f.id, name: f.id, task: f.id, state: f.state, ctxTokens: f.ctxTokens, handbackAt: f.handbackAt ?? null,
      worktree: f.worktree || f.branch ? { path: `/wt/agent-${f.id}`, branch: f.branch?.name ?? null, lockPid: f.worktree?.lockPid ?? null } : null,
      ahead: f.branch?.ahead ?? null, landed: f.branch?.landed ?? null,
      mergesClean: f.branch ? f.branch.mergesClean ?? true : null, branchDeps: f.branch?.deps ?? [], handoff: f.handoff ?? false,
    };
  });
  const board = new Map<string, { id: string; done: boolean; agent: string | null }>();
  const ci: Raw["ci"] = [];
  for (const f of facts) {
    if (f.board) board.set(f.id, { id: f.board.id, done: f.board.done, agent: f.board.agent ?? null });
    if (f.ci) ci.push({ ...f.ci, conclusion: f.ci.conclusion ?? null, endedAt: f.ci.endedAt ?? null });
  }
  return { now, session: facts[0].session, agents, procs, ps: [...ps.values()], alive: (p) => alive.has(p), file: (p) => files.get(p) ?? null, queuedText: queued, ci, board };
}

describe("golden cases through the fact builder", () => {
  it("has the cases", () => { expect(cases17.length).toBeGreaterThanOrEqual(7); });
  for (const g of cases17) {
    it(g.name, async () => {
      const facts = buildFacts(rawOf(g.request.now, g.request.agents));
      expect(norm(facts)).toEqual(norm(g.request.agents));
      if (!existsSync(fwcore)) return; // lake build not run on this machine: the pure part above is still checked
      const reply = (await coreCaller([fwcore])({ op: "obs.next", now: g.request.now, agents: facts })) as NextReply;
      expect(reply.agents).toEqual(g.response.agents);
      expect(formatNext(reply)).toEqual(formatNext(g.response));
    });
  }
});

describe("output", () => {
  it("prints one NEXT line per action, key=value in order, nothing for none", () => {
    expect(formatNext({ agents: [
      { id: "a", actions: [{ action: "killOrphan", pid: 555 }, { action: "nudgeHandoff" }] },
      { id: "b", actions: [] },
      { id: "n", actions: [{ action: "none" }] },
      { id: "c", actions: [{ action: "land", branch: "wt-c", task: "c" }] },
    ] })).toEqual(["NEXT a killOrphan pid=555", "NEXT a nudgeHandoff", "NEXT c land branch=wt-c task=c"]);
  });
  it("alerts: killOrphan -> agent.held, land/routeIntegrator -> agent.unlanded, others none", () => {
    const al = nextAlerts({ agents: [
      { id: "a", actions: [{ action: "killOrphan", pid: 7 }, { action: "waitCi", run: 1 }] },
      { id: "b", actions: [{ action: "land", branch: "x", task: "b" }] },
      { id: "c", actions: [{ action: "routeIntegrator", branch: "y" }, { action: "cleanupWorktree" }] },
    ] });
    expect(al.map((x) => `${x.code} ${x.subject}`)).toEqual(["agent.held a", "agent.unlanded b", "agent.unlanded c"]);
  });
});

describe("observation parsing", () => {
  it("classifies command lines", () => {
    expect(classifyTree("/bin/zsh -c until grep -q done /tmp/x.output; do sleep 5; done")).toMatchObject({ kind: "sleepLoop", watchedFile: "/tmp/x.output" });
    expect(classifyTree("sh -c until false; do sleep 1; done")).toMatchObject({ kind: "sleepLoop", watchedFile: null });
    expect(classifyTree("sh waitrun.sh 42 15")).toMatchObject({ kind: "ciWait", run: 42, timeoutMin: 15 });
    expect(classifyTree("sh waitrun.sh 42")).toMatchObject({ kind: "ciWait", run: 42, timeoutMin: 10 });
    expect(classifyTree("/bin/zsh -c eval x", ["node vitest run"])).toMatchObject({ kind: "build" });
    expect(classifyTree("/bin/zsh -c sleep 99")).toMatchObject({ kind: "other" });
    expect(watchedFileOf("until grep -q 'a b' \"/tmp/log.txt\" 2>/dev/null; do sleep 3; done")).toBe("/tmp/log.txt");
  });
  it("worktrees: lock pid, branch, match by agent id", () => {
    const wts = parseWorktrees("worktree /r\nHEAD a\nbranch refs/heads/main\n\nworktree /r/.claude/worktrees/agent-abc\nHEAD b\nbranch refs/heads/worktree-agent-abc\nlocked claude agent agent-abc (pid 321 start Sat)\n");
    expect(wts[1]).toEqual({ path: "/r/.claude/worktrees/agent-abc", branch: "worktree-agent-abc", lockPid: 321 });
    expect(worktreeOf(wts, "abc", null)?.lockPid).toBe(321);
    expect(worktreeOf(wts, "zzz", null)).toBeNull();
  });
  it("handback time = last SubagentHandback tool call", () => {
    const l = (t: string, name: string) => JSON.stringify({ type: "assistant", timestamp: t, message: { content: [{ type: "tool_use", id: "x", name }] } });
    expect(handbackAtOf([l("2026-10-17T10:00:00Z", "Bash"), l("2026-10-17T10:05:00Z", "SubagentHandback"), "{torn"].join("\n"))).toBe(Date.parse("2026-10-17T10:05:00Z"));
    expect(handbackAtOf(l("2026-10-17T10:00:00Z", "Bash"))).toBeNull();
  });
});

describe("end to end with a real child process", () => {
  const started: number[] = [];
  afterAll(() => { for (const pid of started) { try { process.kill(-pid, "SIGKILL"); } catch { /* gone */ } } }); // only groups this test started

  async function observe(script: string, state: string) {
    const child = spawn("sh", ["-c", script], { detached: true, stdio: "ignore" });
    child.unref();
    started.push(child.pid!);
    const deadline = Date.now() + Math.max(60_000, (Number(process.env.FW_EXEC_TIMEOUT_MS) || 5000) * 2);
    for (;;) { // under load ps can exceed its timeout and return []: poll, bounded
      const now = Date.now();
      const ps = await psCommands();
      const raw: Raw = {
        now, session: process.pid, ps, alive: () => true, file: statFile, queuedText: "", ci: [], board: new Map(),
        procs: [{ pid: child.pid!, name: "sh", startedAt: now, pids: [], agent: "e2e" }],
        agents: [{ id: "e2e", name: "e2e", task: "e2e", state, ctxTokens: 0, handbackAt: null, worktree: null, ahead: null, landed: null, mergesClean: null, branchDeps: [], handoff: false }],
      };
      const facts = buildFacts(raw);
      if (facts[0]!.children.length > 0 || Date.now() > deadline) return { facts, now, pid: child.pid! };
      await new Promise((r) => setTimeout(r, 50));
    }
  }

  it("a real `until false; do sleep 1; done` is a sleepLoop owned by the session", async () => {
    const { facts, pid } = await observe("until false; do sleep 1; done", "idle");
    const c = facts[0]!.children;
    expect(c).toHaveLength(1);
    expect(c[0]).toMatchObject({ pid, kind: "sleepLoop", watchedAt: null, producerExited: false });
    expect(c[0]!.chain[0]).toBe(process.pid);
    if (existsSync(fwcore)) { // young loop, no watched file: no kill
      const r = (await coreCaller([fwcore])({ op: "obs.next", now: Date.now(), agents: facts })) as NextReply;
      expect(formatNext(r).filter((l) => l.includes("killOrphan"))).toEqual([]);
    }
  });

  it("a loop on a finished task's output file: producerExited, and fwcore proposes the kill of this pid", async () => {
    const d = mkdtempSync(join(tmpdir(), "fwnext-")); dirs.push(d);
    mkdirSync(join(d, "tasks"));
    const f = join(d, "tasks", "t1.output");
    writeFileSync(f, "building\n[exited with code 0]\n");
    const { facts, pid } = await observe(`until grep -q NEVERAPPEARS ${f}; do sleep 1; done`, "idle");
    expect(facts[0]!.children[0]).toMatchObject({ pid, kind: "sleepLoop", producerExited: true });
    expect(facts[0]!.children[0]!.watchedAt).toBeGreaterThan(0);
    if (existsSync(fwcore)) {
      const r = (await coreCaller([fwcore])({ op: "obs.next", now: Date.now(), agents: facts })) as NextReply;
      expect(formatNext(r)).toContain(`NEXT e2e killOrphan pid=${pid}`);
      expect(nextAlerts(r).map((a) => a.code)).toContain("agent.held");
    }
  });
});

describe("false-positive facts (inc-next-false-positives) and retention", () => {
  const base = (): Raw => ({
    now: 1e9, session: 1, procs: [], ps: [], alive: () => false, file: () => null, queuedText: "", ci: [],
    board: new Map([
      ["v", { id: "v", done: false, agent: null, deps: ["port", "other"] }],
      ["port", { id: "port", done: false, agent: null }],
      ["other", { id: "other", done: true, agent: null }],
    ]),
    agents: [{
      id: "a1", name: "v", task: "v", state: "done", ctxTokens: 0, handbackAt: 5, ahead: 3, landed: false,
      worktree: { path: "/wt/agent-a1", branch: "wt-v", lockPid: null }, mergesClean: false, branchDeps: ["wt-port"], handoff: true,
    }],
  });
  it("branch facts: merge result, contained unlanded branches, then board deps not done", () => {
    const f = buildFacts(base())[0]!;
    expect(f.branch).toMatchObject({ mergesClean: false, deps: ["wt-port", "port"] });
    expect(f.handoff).toBe(true);
  });
  it("an unchecked merge counts as clean", () => {
    const r = base(); r.agents[0]!.mergesClean = null; r.agents[0]!.branchDeps = [];
    expect(buildFacts(r)[0]!.branch).toMatchObject({ mergesClean: true });
  });
  it("hasWorktree: an ended agent with a worktree directory is not pre-filtered", () => {
    const d = mkdtempSync(join(tmpdir(), "fw-keep-")); dirs.push(d);
    mkdirSync(join(d, ".claude/worktrees/agent-zz"), { recursive: true });
    const p = { root: d, consoleDir: join(d, ".fw-console"), home: d, projectsDir: join(d, "p") };
    expect(hasWorktree(p, "zz")).toBe(true);
    expect(hasWorktree(p, "yy")).toBe(false);
  });
});

export type { AgentFacts };

// proc-startedat-negative: CircleCI (ubuntu-2404) failed with "field startedAt: expected a non-negative integer". The
// start is now - age; the age came from `ps etime`, which on that image can exceed the clock, so the start was negative.
describe("an etime longer than the clock (the CircleCI shape)", () => {
  const now = 1_760_000_000_000;
  const psText = "    1     0 03:41:48 /usr/local/bin/claude\n    5     1 25000-03:04:05 sh -c until grep -q X /t/o; do sleep 1; done\n";
  it("startFromAge: a longer-than-clock age is unknown (-1), a normal age is the start", () => {
    expect(startFromAge(now, 90_000)).toBe(now - 90_000);
    expect(startFromAge(now, now)).toBe(0);
    expect(startFromAge(now, now + 1)).toBe(-1);
    expect(startFromAge(now, 1_728_000_000_000 * 40)).toBe(-1);
  });
  it("the child fact carries the unknown start and fwcore accepts it without proposing a kill for age", async () => {
    const ps = parsePsRows(psText);
    expect(ps.find((r) => r.pid === 5)!.ageMs).toBeGreaterThan(now); // the text parses to an age beyond the epoch
    const raw: Raw = {
      now, session: 1, ps, alive: () => true, file: () => null, queuedText: "", ci: [], board: new Map(),
      procs: [{ pid: 5, name: "sh", startedAt: -1, pids: [], agent: "e2e" }],
      agents: [{ id: "e2e", name: "e2e", task: "e2e", state: "idle", ctxTokens: 0, handbackAt: null, worktree: null, ahead: null, landed: null, mergesClean: null, branchDeps: [], handoff: false }],
    };
    const facts = buildFacts(raw);
    expect(facts[0]!.children[0]!.startedAt).toBe(-1);
    if (existsSync(fwcore)) {
      const r = (await coreCaller([fwcore])({ op: "obs.next", now, agents: facts })) as NextReply;
      expect(formatNext(r).filter((l) => l.includes("killOrphan"))).toEqual([]);
      const h = await coreCaller([fwcore])({ op: "obs.health", now, system: { diskFreeGB: 50, procs: [{ pid: 5, name: "sh", startedAt: -1 }] } });
      expect(JSON.stringify(h)).not.toContain("proc.long");
    }
  });
});
