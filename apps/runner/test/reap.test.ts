import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { classify, COULD_NOT_LIST, insideLive, isMcp, parseLsof, parsePs, wtIdOf, reapCli, reapLines, ReapUsage, recordedConsoles, type Facts } from "../src/reap.ts";
import { fwcoreCall } from "../src/run.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const cases = readFileSync(join(root, "packages", "contracts", "golden", "ops", "lspreap.jsonl"), "utf8").trim().split("\n")
  .map((l) => JSON.parse(l) as { name: string; request: Record<string, unknown>; response: unknown });

describe("ops.lspReap golden vectors replay through fwcore", () => {
  const call = fwcoreCall(root);
  for (const c of cases) it(c.name, () => { expect(call(c.request)).toEqual(c.response); });
});

describe("gathering glue", () => {
  it("classifies argv", () => {
    expect(classify("/opt/lake serve --")).toBe("lspServe");
    expect(classify("/x/bin/node /r/apps/console-api/src/main.ts")).toBe("console");
    expect(classify("/x/bin/node /r/apps/site/main.ts")).toBe("tool"); // a tool: selected only through a removed worktree or a dead ancestor
    expect(classify("/x/bin/lean --server")).toBe("tool");
    expect(classify("/x/pnpm test")).toBe("other");
    expect(classify("/h/ms-playwright/chromium-1/Chromium --headless")).toBe("tool");
    expect(classify("/x/lake build")).toBe("tool");
  });
  it("finds the mcp processes", () => {
    expect(isMcp("/x/uv tool uvx --from lean-lsp-mcp==0.31.0 lean-lsp-mcp --lean-project-path lean")).toBe(true);
    expect(isMcp("/x/python /c/bin/lean-lsp-mcp --lean-project-path lean")).toBe(true);
    expect(isMcp("grep lean-lsp-mcpx")).toBe(false);
  });
  it("parses a stat column, drops zombies and finds worktree ids", () => {
    const ps = parsePs("  12   1  12 Ss   Tue Oct 20 02:59:44 2026 /bin/node a\n  13   1  13 Z    Tue Oct 20 02:59:44 2026 (node)\n  14   1  14 S+   Tue Oct 20 02:59:44 2026 x\n");
    expect(ps.map((p) => p.pid)).toEqual([12, 14]);
    expect(wtIdOf("/m/.claude/worktrees/a1/lean/x", "/m")).toBe("a1");
    expect(wtIdOf("/m/.claude/worktrees/", "/m")).toBeNull();
    expect(wtIdOf("/m/lean", "/m")).toBeNull();
  });
  it("parses ps and lsof", () => {
    const ps = parsePs("  12   1  12 Tue Oct 20 02:59:44 2026 /bin/node a b\nnot a row\n");
    expect(ps).toHaveLength(1);
    expect(ps[0]).toMatchObject({ pid: 12, ppid: 1, pgid: 12, args: "/bin/node a b" });
    expect([...parseLsof("p12\nfcwd\ni77\nn/x\np13\nfcwd\nn/y\n")]).toEqual([[12, { ino: 77, path: "/x" }]]);
  });
});

describe("fw reap --list and the land report", () => {
  const facts: Facts = { rows: [{ pid: 500, ppid: 400, pgid: 500, start: 9, cwd: 11, kind: "lspServe" }], live: [1], mcps: [{ pid: 400, cwd: 1 }], keep: [] };
  const call = fwcoreCall(root);
  it("prints Lean's list and signals nothing", () => {
    const out: string[] = [];
    expect(reapCli(["--list"], root, call, (s) => out.push(s), () => facts)).toBe(0);
    expect(out).toEqual(["500 group lspServe: lake serve of lean-lsp-mcp, cwd in no live checkout"]);
    expect(() => reapCli(["--bogus"], root, call)).toThrow(ReapUsage);
  });
  it("the land report names the same rows, and nothing when none", () => {
    expect(reapLines(root, call, () => facts)[1]).toContain("500 group lspServe");
    expect(reapLines(root, call, () => ({ ...facts, live: [11] }))).toEqual([]);
    expect(reapLines(root, call, () => null)).toEqual([COULD_NOT_LIST]);
    expect(reapLines(root, call, () => { throw new Error("x"); })).toEqual([COULD_NOT_LIST]);
  });
  it("a recorded console with a dead cwd and parent 1 is not listed", () => {
    const f: Facts = { rows: [{ pid: 600, ppid: 1, pgid: 600, start: 100, cwd: 12, kind: "console" }], live: [1], mcps: [], keep: [{ pid: 600, at: 101 }] };
    expect(reapLines(root, call, () => f)).toEqual([]);
    expect(reapLines(root, call, () => ({ ...f, keep: [] }))[1]).toContain("600 group console");
  });
  it("another repo's lean-lsp-mcp does not make its lake serve a leftover", () => {
    const f: Facts = { rows: [{ pid: 500, ppid: 400, pgid: 500, start: 9, cwd: 11, kind: "lspServe" }], live: [1], mcps: [{ pid: 400, cwd: 77 }], keep: [] };
    expect(reapLines(root, call, () => f)).toEqual([]);
  });
});

describe("live checkout identity and the recorded console", () => {
  const d = mkdtempSync(join(tmpdir(), "reap-"));
  it("a nested directory inside a checkout is live only when stat gives lsof's inode", async () => {
    const { statSync } = await import("node:fs");
    mkdirSync(join(d, "wt", "a", "b"), { recursive: true });
    const ino = statSync(join(d, "wt", "a", "b")).ino;
    expect(insideLive({ ino, path: join(d, "wt", "a", "b") }, [join(d, "wt")])).toBe(true);
    expect(insideLive({ ino: ino + 1, path: join(d, "wt", "a", "b") }, [join(d, "wt")])).toBe(false);
    expect(insideLive({ ino, path: join(d, "wt-other") }, [join(d, "wt")])).toBe(false);
    expect(insideLive({ ino, path: join(d, "gone") }, [join(d, "wt")])).toBe(false);
  });
  it("reads pid and start second from api.json, none when absent", () => {
    mkdirSync(join(d, "c"), { recursive: true });
    writeFileSync(join(d, "c", "api.json"), JSON.stringify({ port: 1, pid: 600, startedAt: 101_500 }));
    expect(recordedConsoles(root, { FW_CONSOLE_DIR: join(d, "c") })).toContainEqual({ pid: 600, at: 101 });
    expect(recordedConsoles(root, { FW_CONSOLE_DIR: join(d, "none") }).every((k) => k.pid !== 600)).toBe(true);
    rmSync(d, { recursive: true, force: true });
  });
});
