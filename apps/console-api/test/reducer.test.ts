import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { emptyState } from "@fw/contracts";
import { apply, project } from "../src/core/reducer.ts";
import { board, stage } from "../src/core/board.ts";
import { base, cases, ev, ready } from "./cases.ts";
import { goldenCases } from "./golden.ts";

describe("reducer table", () => {
  for (const c of cases()) {
    it(c.name, () => {
      const s = project(c.setup);
      const r = apply(s, c.event);
      if (c.reason === null) {
        expect(r.outcome).toEqual({ accepted: true, duplicate: false });
        expect(r.state.seen).toContain(c.event.key);
      } else {
        expect(r.outcome).toEqual({ accepted: false, reason: c.reason });
        expect(r.state).toBe(s); // refused: state untouched, key not marked seen
      }
    });
  }
});

describe("duplicates and idempotency", () => {
  it("applying the same event twice equals once", () => {
    const e = ev({ type: "card.open", actor: "owner", card: "A", owner: "o", needsDevice: false });
    const once = apply(emptyState(), e);
    const twice = apply(once.state, e);
    expect(twice.state).toEqual(once.state);
    expect(twice.outcome).toEqual({ accepted: true, duplicate: true });
  });
  it("replaying a whole log twice gives the same projection", () => {
    const log = ready();
    expect(project([...log, ...log])).toEqual(project(log));
  });
  it("a refused event can be re-sent with the same key once it becomes valid", () => {
    const [o, a] = base();
    const early = ev({ type: "card.screen", actor: "script", card: "A", sha: "s1", pass: true }, "job:A:result");
    const s1 = apply(project([o!, a!]), early);
    expect(s1.outcome.accepted).toBe(false);
    const b = ev({ type: "card.build", actor: "git", card: "A", sha: "s1", agent: "b" });
    const s2 = apply(apply(project([o!, a!]), b).state, early);
    expect(s2.outcome).toEqual({ accepted: true, duplicate: false });
  });
});

describe("invariants", () => {
  it("a new build resets screen/review evidence", () => {
    const s = project([...ready(), ev({ type: "card.build", actor: "git", card: "A", sha: "s2", agent: "b2" })]);
    expect(stage(s.cards[0]!)).toBe("screen");
  });
  it("a rogue landing is recorded as landed + violation", () => {
    const s = project([...base(), ev({ type: "card.landed", actor: "git", card: "A", sha: "s1" })]);
    expect(s.cards[0]).toMatchObject({ landed: true, violation: true });
  });
  it("request then landed has no violation", () => {
    const s = project([...ready(), ev({ type: "card.land_request", actor: "lead", card: "A", sha: "s1" }),
      ev({ type: "card.landed", actor: "git", card: "A", sha: "s1" })]);
    expect(s.cards[0]).toMatchObject({ landed: true, violation: false });
  });
});

describe("board projection", () => {
  it("derives stage, owner, next, age basis and needs-you with the exact action", () => {
    const s = project([...base(), ev({ type: "step.post", actor: "script", step: "S", card: "A", title: "Plug in", kind: "action", options: null })]);
    const b = board(s, 5000, 9);
    expect(b.cards[0]).toMatchObject({ id: "A", owner: "o", stage: "screen", next: { command: "card.screen" },
      needsYou: { step: "S", action: "Press Start" } });
    expect(b.cards[0]!.lastAt).toBeGreaterThan(0);
    expect(b.needsYou).toHaveLength(1);
  });
  it("stale only without a live run or open step", () => {
    const s = project(base());
    expect(board(s, s.cards[0]!.lastAt + 31 * 60_000, 1).cards[0]!.stale).toBe(true);
    const r = project([...base(), ev({ type: "run.start", actor: "script", run: "R", card: "A", kind: "screen" })]);
    expect(board(r, r.cards[0]!.lastAt + 31 * 60_000, 1).cards[0]!.stale).toBe(false);
  });
});

describe("golden fixtures for fwcore", () => {
  it("console-apply.jsonl is up to date (run `pnpm --filter @fw/console-api gen:golden`)", () => {
    const p = join(dirname(fileURLToPath(import.meta.url)), "../../../packages/contracts/golden/console-apply.jsonl");
    const got = readFileSync(p, "utf8").trim().split("\n").map((l) => JSON.parse(l));
    expect(got).toEqual(JSON.parse(JSON.stringify(goldenCases())));
  });
});
