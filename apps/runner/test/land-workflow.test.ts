import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { runTier, spawnRunner } from "../src/checks.ts";
import { candidateChecks, checksWithReads, selectChecks, WORKFLOW_LINT } from "../src/land.ts";
import { EXIT, WORKFLOW_LINT_ID, WORKFLOW_LINT_READS, workflowVerdict, type Finding } from "../src/land-checks-workflow.ts";
import { fwcoreCall } from "../src/run.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const script = join(root, "scripts/check-workflows.sh");
type Row =
  | { kind: "select"; name: string; request: { changed: string[]; reads: string[] }; response: { select: string[] } }
  | { kind: "verdict"; name: string; request: { installed: boolean; findings: Finding[] }; response: { verdict: string; exit: number } };
const rows: Row[] = readFileSync(join(root, "packages/contracts/golden/ci/workflow-lint.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l));

describe("workflow-lint follows the Lean golden (Fw.Ci.WorkflowLint)", () => {
  it("has selecting, idle, refusing, failing, warning and passing cases", () => {
    const v = new Set(rows.flatMap((r) => (r.kind === "verdict" ? [r.response.verdict] : [])));
    expect([...v].sort()).toEqual(["fail", "pass", "refused", "warn"]);
    expect(rows.some((r) => r.kind === "select" && r.response.select.length > 0)).toBe(true);
    expect(rows.some((r) => r.kind === "select" && r.response.select.length === 0)).toBe(true);
  });
  for (const r of rows) {
    if (r.kind === "select") {
      it(r.name, () => {
        expect(r.request.reads).toEqual(WORKFLOW_LINT_READS);
        expect(selectChecks([{ id: WORKFLOW_LINT_ID, reads: r.request.reads }], r.request.changed)).toEqual(r.response.select);
      });
    } else {
      it(r.name, () => {
        const v = workflowVerdict(r.request.installed, r.request.findings);
        expect(v).toBe(r.response.verdict);
        expect(EXIT[v]).toBe(r.response.exit);
      });
    }
  }
});

describe("fw land selects workflow-lint", () => {
  it("is a candidate check with the declared argv", () => {
    expect(candidateChecks(root).find((c) => c.id === WORKFLOW_LINT_ID)).toEqual(WORKFLOW_LINT);
    expect(WORKFLOW_LINT.argv).toEqual(["sh", "scripts/check-workflows.sh"]);
  });
  it("a changed workflow file selects it, a doc change does not", () => {
    expect(checksWithReads(root, [".github/workflows/trajectory-probe.yml"]).map((c) => c.id)).toContain(WORKFLOW_LINT_ID);
    expect(checksWithReads(root, ["docs/team/tools/land.md"]).map((c) => c.id)).not.toContain(WORKFLOW_LINT_ID);
  });
});

const wf = (env: string) => `on: push\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo hi\n        env:\n${env}`;
const tmp = () => mkdtempSync(join(tmpdir(), "wflint-"));
const put = (name: string, text: string) => { const d = tmp(); const f = join(d, name); writeFileSync(f, text); return f; };
const noActionlintPath = () => {
  const bin = join(tmp(), "bin");
  mkdirSync(bin);
  for (const t of ["node", "dirname"]) symlinkSync(spawnSync("sh", ["-c", `command -v ${t}`], { encoding: "utf8" }).stdout.trim(), join(bin, t));
  return bin;
};
const run = (args: string[], env: NodeJS.ProcessEnv = process.env) => spawnSync("/bin/sh", [script, ...args], { cwd: root, encoding: "utf8", env });

describe("scripts/check-workflows.sh", () => {
  it("a clean workflow passes", () => {
    const r = run([put("ok.yml", wf("          A: 1\n"))]);
    expect(r.status).toBe(0);
    expect(r.stdout).toContain("workflow-lint: pass");
  });
  it("a duplicated env key fails with actionlint's reason (inc-workflow-dup-key)", () => {
    const r = run([put("dup.yml", wf("          SEARCH: a\n          SEARCH: b\n"))]);
    expect(r.status).toBe(1);
    expect(r.stdout).toContain("[syntax-check]");
    expect(r.stdout).toContain("SEARCH");
    expect(r.stdout).toContain("duplicated");
  });
  it("an unknown expression property fails", () => {
    const r = run([put("expr.yml", wf("          A: ${{ github.nope }}\n"))]);
    expect(r.status).toBe(1);
    expect(r.stdout).toContain("[expression]");
  });
  it("a shellcheck finding alone is a warning", () => {
    const r = run([put("sc.yml", `on: push\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo $HOME_X\n`)]);
    expect(r.status).toBe(0);
    expect(r.stdout).toContain("warning [shellcheck]");
    expect(r.stdout).toContain("workflow-lint: warn");
  });
  it("a missing actionlint refuses with a named reason and never passes", () => {
    const r = run([put("ok.yml", wf("          A: 1\n"))], { ...process.env, PATH: noActionlintPath() });
    expect(r.status).toBe(3);
    expect(r.stdout).toContain("REFUSED workflow-lint: actionlint is not installed");
  });
  it("the repo's workflow files pass today", () => {
    const r = run([]);
    expect(r.stdout).toContain("workflow-lint:");
    expect(r.status).toBe(0);
  });
});

describe("the land refuses", () => {
  const check = (f: string, env?: NodeJS.ProcessEnv) => ({ ...WORKFLOW_LINT, argv: ["env", ...(env?.PATH ? [`PATH=${env.PATH}`] : []), "/bin/sh", script, f] });
  const land = async (c: ReturnType<typeof check>) => {
    const log: string[] = [];
    const code = await runTier([c], root, fwcoreCall(root), spawnRunner, (s) => log.push(s));
    return { code, text: log.join("\n") };
  };
  it("a duplicated env key refuses the land", async () => {
    const r = await land(check(put("dup.yml", wf("          SEARCH: a\n          SEARCH: b\n"))));
    expect(r.code).toBe(1);
    expect(r.text).toContain("VERDICT fail workflow-lint");
  });
  it("a missing actionlint refuses the land", async () => {
    const r = await land(check(put("ok.yml", wf("          A: 1\n")), { PATH: noActionlintPath() }));
    expect(r.code).toBe(1);
    expect(r.text).toContain("REFUSED workflow-lint: actionlint is not installed");
  });
  it("a clean workflow passes the land", async () => {
    const r = await land(check(put("ok.yml", wf("          A: 1\n"))));
    expect(r.code).toBe(0);
  });
});
