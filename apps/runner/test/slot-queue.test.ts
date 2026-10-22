// timing-queue-wait: the acquire span records the holder the ticket waited behind; parseSamples hands it to Lean as waitMs/leaseMs.
// The verdict (queued / slow / alert) is Lean's (golden/obs/timing.jsonl, replayed in timing-alert.test.ts).
import { describe, expect, it } from "vitest";
import type { Entry } from "../src/slot-core.ts";
import { behindOf, blockers, mergeBehind, noteQueue, queueExtra, queueOf } from "../src/slot-queue.ts";
import { parseSamples } from "../src/watch-collect.ts";

const e = (owner: string, kind: Entry["kind"], leaseS: number, till = leaseS): Entry => ({ owner, token: owner, kind, since: 0, till, foot: 0, leaseS });
const live = [e("a", "check", 600), e("m", "measure", 1800), e("s", "sim", 900)];

describe("blocker selection", () => {
  it("a measure pass or gap is held by the measure lease", () => {
    for (const why of ["pass", "gap", "unknown", "measureBusy"] as const) expect(blockers(why, live).map((h) => h.owner)).toEqual(["m"]);
  });
  it("a Simulator ticket waits behind the sim lease", () => expect(blockers("simBusy", live).map((h) => h.owner)).toEqual(["s"]));
  it("anything else is behind the live holder with the longest lease", () => {
    expect(behindOf("full", live)).toEqual({ kind: "measure", owner: "m", leaseS: 1800 });
    expect(behindOf("queued", [])).toBeNull();
    expect(behindOf("memLow", live)).toBeNull();
    expect(behindOf("pass", [e("a", "check", 600)])).toBeNull();
  });
  it("records the renewed tenure (till - since), not the per-renewal lease", () => {
    const renewed = e("r", "sim", 60, 600);
    expect(behindOf("simBusy", [renewed])).toEqual({ kind: "sim", owner: "r", leaseS: 600 });
    expect(behindOf("full", [e("a", "check", 600), renewed, e("legacy", "sim", 0, 300)])?.owner).toBe("a");
    expect(behindOf("simBusy", [e("legacy", "sim", 0, 300)])?.leaseS).toBe(300);
  });
  it("keeps the longer lease across polls", () => {
    const a = { kind: "check" as const, owner: "a", leaseS: 600 }, b = { kind: "measure" as const, owner: "m", leaseS: 1800 };
    expect(mergeBehind(a, b)).toEqual(b);
    expect(mergeBehind(b, a)).toEqual(b);
    expect(mergeBehind(null, a)).toEqual(a);
    expect(mergeBehind(a, null)).toEqual(a);
  });
});

describe("the span field", () => {
  it("is null unless a holder blocked and the ticket waited", () => {
    const b = { kind: "measure" as const, owner: "m", leaseS: 1800 };
    expect(queueOf(null, 5000)).toBeNull();
    expect(queueOf(b, 0)).toBeNull();
    expect(queueOf(b, 1521000)).toEqual({ kind: "measure", owner: "m", waitMs: 1521000, leaseMs: 1800000 });
  });
  it("travels to the span extras through the process", () => {
    noteQueue({ kind: "check", owner: "a", waitMs: 4000, leaseMs: 600000 });
    expect(queueExtra()).toEqual({ queue: { kind: "check", owner: "a", waitMs: 4000, leaseMs: 600000 } });
    noteQueue(null);
    expect(queueExtra()).toEqual({});
  });
});

describe("parseSamples reads the queue", () => {
  const line = (o: object) => JSON.stringify({ tool: "fw", step: "slot wait check", startMs: 1, durMs: 1523000, exit: 0, host: "local", load: 2, ...o });
  it("maps queue to waitMs and leaseMs", () => {
    const [s] = parseSamples(line({ queue: { kind: "measure", owner: "m", waitMs: 1521000, leaseMs: 1800000 } }));
    expect(s).toMatchObject({ waitMs: 1521000, leaseMs: 1800000, durMs: 1523000 });
  });
  it("leaves spans without a usable queue unchanged (no backfill)", () => {
    for (const q of [undefined, null, 3, { waitMs: 0, leaseMs: 5 }, { waitMs: "x", leaseMs: 5 }, { waitMs: 5 }]) {
      const [s] = parseSamples(line(q === undefined ? {} : { queue: q }));
      expect(s).not.toHaveProperty("waitMs");
      expect(s).not.toHaveProperty("leaseMs");
    }
  });
});
