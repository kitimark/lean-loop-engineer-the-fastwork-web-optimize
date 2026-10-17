import { describe, expect, it } from "vitest";
import { UsageError, renderBoard, stepCommand } from "../src/lib.ts";

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
