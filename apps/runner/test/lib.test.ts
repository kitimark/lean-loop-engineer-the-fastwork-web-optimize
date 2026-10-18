import { readFileSync, readdirSync, existsSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { NO_API_GROUPS, UsageError, renderBoard, stepCommand } from "../src/lib.ts";

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
