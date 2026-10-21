import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { classify, type Facts, type Io, idleTotal, isSerena, loadBases, parseCpuTime, parseLocks, reapCli, render, select, stopSelected } from "../src/reap.ts";
import { fwcoreCall } from "../src/run.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const cases = readFileSync(join(root, "packages", "contracts", "golden", "ops", "reap-idle.jsonl"), "utf8").trim().split("\n")
  .map((l) => JSON.parse(l) as { name: string; request: Record<string, unknown>; response: unknown });

describe("reap-idle.jsonl golden vectors replay through fwcore", () => {
  const call = fwcoreCall(root);
  it("has the cases of branch D and of the baselines", () => {
    const ops = new Set(cases.map((c) => c.request.op));
    for (const op of ["ops.lspReap", "ops.reapPlan", "ops.reapIdle"]) expect(ops.has(op)).toBe(true);
  });
  for (const c of cases) it(c.name, () => { expect(call(c.request)).toEqual(c.response); });
});

describe("branch D facts", () => {
  it("parses ps time values of macOS and Linux into centiseconds", () => {
    expect(parseCpuTime("0:07.99")).toBe(799);
    expect(parseCpuTime("125:03.12")).toBe(750312);
    expect(parseCpuTime("01:02:03")).toBe(372300);
    expect(parseCpuTime("2-01:00:00")).toBe((2 * 86400 + 3600) * 100);
    expect(parseCpuTime("0:01.5")).toBe(150);
    expect(parseCpuTime("x")).toBeNull();
  });
  it("reads worktree locks with the holder pid their reason names", () => {
    const p = ["worktree /r", "HEAD a", "branch refs/heads/main", "",
      "worktree /r/.claude/worktrees/wf_a", "HEAD b", "locked claude agent wf_a (pid 92347 start Mon Oct 19 04:10:25 2026)", "",
      "worktree /r/.claude/worktrees/wf_b", "HEAD c", "",
      "worktree /r/.claude/worktrees/wf_c", "HEAD d", "locked", "",
      "worktree /elsewhere", "locked by hand", ""].join("\n");
    const idOf = (path: string) => /\/\.claude\/worktrees\/([^/]+)$/.exec(path)?.[1] ?? null;
    expect(parseLocks(p, idOf)).toEqual([{ id: "wf_a", holder: 92347 }, { id: "wf_c", holder: null }]);
  });
  it("classifies serena processes before any tool name", () => {
    expect(classify("/opt/homebrew/bin/uv tool uvx --from serena-agent==2.0.0 serena start-mcp-server --project lean")).toBe("serena");
    expect(classify("/x/Python /h/.cache/uv/archive-v0/a/bin/serena start-mcp-server")).toBe("serena");
    expect(classify("node /h/.serena/language_servers/static/ts-lsp/node_modules/.bin/typescript-language-server --stdio")).toBe("serena");
    expect(isSerena("/x/bin/lean --server")).toBe(false);
    expect(isSerena("/x/serena-notes/lean --server")).toBe(false);
    expect(classify("/x/bin/lean --worker file:///r/A.lean")).toBe("tool");
  });
  it("reads stored baselines and drops malformed ones; a missing file gives none", () => {
    const d = mkdtempSync(join(tmpdir(), "reap-idle-"));
    const f = join(d, "reap-idle.json");
    expect(loadBases(f)).toEqual([]);
    writeFileSync(f, JSON.stringify({ bases: [{ pid: 5, start: 1, since: 2, cpu: 3 }, { pid: 6, start: 1, since: "x", cpu: 3 }] }));
    expect(loadBases(f)).toEqual([{ pid: 5, start: 1, since: 2, cpu: 3 }]);
    writeFileSync(f, "{");
    expect(loadBases(f)).toEqual([]);
    rmSync(d, { recursive: true, force: true });
  });
});

const mcpStack = (cpu502: number): Facts => ({
  rows: [
    { pid: 400, ppid: 1, pgid: 400, start: 9, cwd: 1, kind: "other", cpu: 50 },
    { pid: 500, ppid: 400, pgid: 500, start: 9, cwd: 30, kind: "lspServe", wt: "w", inRepo: true, cpu: 10 },
    { pid: 501, ppid: 500, pgid: 500, start: 9, cwd: 30, kind: "tool", wt: "w", inRepo: true, cpu: 600 },
    { pid: 502, ppid: 501, pgid: 502, start: 9, cwd: 30, kind: "tool", wt: "w", inRepo: true, cpu: cpu502 },
  ],
  live: [1, 30], mcps: [{ pid: 400, cwd: 1, wt: null }], keep: [], liveIds: ["w"],
  now: 5000, bases: [{ pid: 500, start: 9, since: 1000, cpu: 10 }, { pid: 501, start: 9, since: 1000, cpu: 600 }, { pid: 502, start: 9, since: 1000, cpu: 700 }],
});

describe("fw reap --list with an idle lean-lsp-mcp stack", () => {
  const call = fwcoreCall(root);
  const io: Io = { signal: () => { throw new Error("no signal in a test"); }, sleep: () => {}, table: () => null, rss: (pids) => new Map(pids.map((p) => [p, 102_400])) };
  it("lists every process of the stack with its reason and MB, and a total", () => {
    const out: string[] = [];
    expect(reapCli(["--list"], root, call, (s) => out.push(s), () => mcpStack(900), io)).toBe(0);
    expect(out).toEqual([
      "500 group mcpIdle: lean-lsp-mcp server stack idle (CPU quiet) in a worktree with no live agent (100.0 MB)",
      "501 pid mcpIdle: lean-lsp-mcp server stack idle (CPU quiet) in a worktree with no live agent (100.0 MB)",
      "502 group mcpIdle: lean-lsp-mcp server stack idle (CPU quiet) in a worktree with no live agent (100.0 MB)",
      "mcpIdle: 3 process(es), 300.0 MB RSS",
    ]);
  });
  it("a busy worker, a live lock or a lean-lsp-mcp started in the worktree keeps the stack", () => {
    expect(select(mcpStack(1001), call)).toEqual([]);
    expect(select({ ...mcpStack(900), locks: [{ id: "w", holder: 400 }] }, call)).toEqual([]);
    expect(select({ ...mcpStack(900), mcps: [{ pid: 400, cwd: 1, wt: "w" }] }, call)).toEqual([]);
    expect(select({ ...mcpStack(900), rows: mcpStack(900).rows.map((r) => (r.pid === 400 ? { ...r, kind: "serena" } : r)) }, call)).toEqual([]);
  });
  it("other kinds print without MB and no total line", () => {
    const s = [{ pid: 7, start: 1, kind: "removed", group: true, reason: "r" }];
    expect(render(s, new Map([[7, 2048]]))).toEqual(["7 group removed: r"]);
    expect(idleTotal(s, new Map())).toEqual([]);
  });
  it("stores Lean's baselines in the idle file; a stop with nothing selected sends no signal", () => {
    const d = mkdtempSync(join(tmpdir(), "reap-idle-"));
    const f = join(d, "reap-idle.json");
    select({ ...mcpStack(1001), idleFile: f }, call);
    expect(loadBases(f)).toEqual([
      { pid: 500, start: 9, since: 1000, cpu: 10 }, { pid: 501, start: 9, since: 1000, cpu: 600 }, { pid: 502, start: 9, since: 5000, cpu: 1001 },
    ]);
    const quiet: Io = { ...io, table: () => null };
    expect(stopSelected(root, call, quiet, () => ({ ...mcpStack(1001), idleFile: f }))).not.toBeNull();
    rmSync(d, { recursive: true, force: true });
  });
});
