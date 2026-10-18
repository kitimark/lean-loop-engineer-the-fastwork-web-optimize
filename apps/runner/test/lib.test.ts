import { readFileSync, readdirSync, existsSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { NO_API_GROUPS, UsageError, gitFullRef, renderBoard, stepCommand, taskCommand } from "../src/lib.ts";

describe("fw step", () => {
  it("post builds a typed command with a derived idempotency key", () => {
    expect(stepCommand(["post", "--id", "s1", "--title", "Plug in", "--card", "A"], { FW_ACTOR: "script" })).toEqual({
      type: "step.post", key: "step.post:s1", actor: "script", step: "s1", card: "A", title: "Plug in", kind: "action", options: null });
  });
  it("answer joins words; done takes the step id", () => {
    expect(stepCommand(["answer", "s1", "yes"], {})).toMatchObject({ type: "step.answer", answer: "yes", actor: "owner" });
    expect(stepCommand(["done", "s1", "--as", "user"], {})).toMatchObject({ type: "step.done", actor: "user", key: "step.done:s1" });
  });
  it("rejects bad usage", () => {
    expect(() => stepCommand(["nope"], {})).toThrow(UsageError);
    expect(() => stepCommand(["post", "--id", "s1"], {})).toThrow(UsageError);
    expect(() => stepCommand(["done"], {})).toThrow(UsageError);
  });
});

describe("fw task (task-state-truth)", () => {
  it("maps arguments to the four outcome marks; default actor lead, content keys", () => {
    expect(taskCommand(["handback", "port-nav", "--tip", "5e277bd"], {})).toEqual({
      type: "task.handback", key: "task.handback:port-nav:port-nav:5e277bd", actor: "lead", task: "port-nav", agent: "port-nav", tip: "5e277bd" });
    expect(taskCommand(["handback", "a", "--agent", "x"], { FW_ACTOR: "script" })).toMatchObject({ actor: "script", agent: "x", tip: null });
    expect(taskCommand(["integrate", "a", "--into", "ci/i-3", "--tip", "b00ef68"], {})).toMatchObject({
      type: "task.integrate", key: "task.integrate:a:ci/i-3:b00ef68", branch: "ci/i-3", tip: "b00ef68" });
    // a name that resolves to main is sent as its full ref, which Lean refuses (Fw.Plan.isMainRef); unresolved: as given
    const refs: Record<string, string> = { HEAD: "refs/heads/main", "ci/i-3": "refs/heads/ci/i-3" };
    expect(taskCommand(["integrate", "a", "--into", "HEAD", "--tip", "t"], {}, 1, (b) => refs[b] ?? null)).toMatchObject({ branch: "refs/heads/main" });
    expect(taskCommand(["integrate", "a", "--into", "ci/i-9", "--tip", "t"], {}, 1, (b) => refs[b] ?? null)).toMatchObject({ branch: "ci/i-9" });
    expect(gitFullRef("--not-a-ref-xyz")).toBeNull();
    expect(taskCommand(["park", "a", "--reason", "folded"], {}, 7)).toEqual({ type: "task.park", key: "task.park:a:7", actor: "lead", task: "a", reason: "folded" });
    expect(taskCommand(["unpark", "a", "--as", "user"], {}, 8)).toEqual({ type: "task.unpark", key: "task.unpark:a:8", actor: "user", task: "a" });
  });
  it("rejects bad usage (the main-branch refusal is fwcore's, not the CLI's)", () => {
    expect(() => taskCommand(["nope", "a"], {})).toThrow(UsageError);
    expect(() => taskCommand(["integrate", "a", "--tip", "t"], {})).toThrow(UsageError);
    expect(() => taskCommand(["park", "a"], {})).toThrow(UsageError);
    expect(() => taskCommand(["unpark"], {})).toThrow(UsageError);
    expect(taskCommand(["integrate", "a", "--into", "main", "--tip", "t"], {})).toMatchObject({ branch: "main" });
  });
});

describe("fw status", () => {
  it("renders derived columns", () => {
    const out = renderBoard({ seq: 3, now: 120_000, steps: [], needsYou: [{ step: "s1", title: "t", action: "Press Start" }],
      cards: [{ id: "A", owner: "o", stage: "screen", next: { who: "script", command: "card.screen" }, lastAt: 0,
        needsYou: { step: "s1", title: "t", action: "Press Start" }, runningRuns: 0, head: "s", landed: false, violation: false, stale: false }] });
    expect(out).toContain("A");
    expect(out).toContain("2m");
    expect(out).toContain("YOU: Press Start (s1)");
  });
});

describe("fw in CI", () => {
  // CI has no console-api: a workflow step `pnpm fw premises` failed on every branch with "console-api is not running"
  it("every `pnpm fw <group>` in .github/** runs without console-api", () => {
    const root = join(import.meta.dirname, "..", "..", "..", ".github");
    const files: string[] = [];
    const walk = (d: string) => { for (const e of readdirSync(d, { withFileTypes: true })) e.isDirectory() ? walk(join(d, e.name)) : /\.ya?ml$/.test(e.name) && files.push(join(d, e.name)); };
    if (existsSync(root)) walk(root);
    const used = files.flatMap((f) => [...readFileSync(f, "utf8").matchAll(/pnpm (?:-s )?fw ([a-z-]+)/g)].map((m) => m[1] ?? ""));
    expect(used.length).toBeGreaterThan(0);
    expect(used.filter((g) => !NO_API_GROUPS.includes(g))).toEqual([]);
  });
});
