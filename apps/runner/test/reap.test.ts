import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { classify, isMcp, parseLsof, parsePs, reapCli, reapLines, ReapUsage, type Facts } from "../src/reap.ts";
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
    expect(classify("/x/bin/node /r/apps/site/main.ts")).toBe("other");
    expect(classify("/x/lake build")).toBe("other");
  });
  it("finds the mcp processes", () => {
    expect(isMcp("/x/uv tool uvx --from lean-lsp-mcp==0.31.0 lean-lsp-mcp --lean-project-path lean")).toBe(true);
    expect(isMcp("/x/python /c/bin/lean-lsp-mcp --lean-project-path lean")).toBe(true);
    expect(isMcp("grep lean-lsp-mcpx")).toBe(false);
  });
  it("parses ps and lsof", () => {
    const ps = parsePs("  12   1  12 Tue Oct 20 02:59:44 2026 /bin/node a b\nnot a row\n");
    expect(ps).toHaveLength(1);
    expect(ps[0]).toMatchObject({ pid: 12, ppid: 1, pgid: 12, args: "/bin/node a b" });
    expect([...parseLsof("p12\nfcwd\ni77\nn/x\np13\nfcwd\nn/y\n")]).toEqual([[12, 77]]);
  });
});

describe("fw reap --list and the land report", () => {
  const facts: Facts = { rows: [{ pid: 500, ppid: 400, pgid: 500, start: 9, cwd: 11, kind: "lspServe" }], live: [1], mcps: [400] };
  const call = fwcoreCall(root);
  it("prints Lean's list and signals nothing", () => {
    const out: string[] = [];
    expect(reapCli(["--list"], root, call, (s) => out.push(s), () => facts)).toBe(0);
    expect(out).toEqual(["500 group lspServe: lake serve of lean-lsp-mcp, cwd in no live checkout"]);
    expect(() => reapCli(["--stop"], root, call)).toThrow(ReapUsage);
  });
  it("the land report names the same rows, and nothing when none", () => {
    expect(reapLines(root, call, () => facts)[1]).toContain("500 group lspServe");
    expect(reapLines(root, call, () => ({ ...facts, live: [11] }))).toEqual([]);
    expect(reapLines(root, call, () => null)).toEqual([]);
  });
});
