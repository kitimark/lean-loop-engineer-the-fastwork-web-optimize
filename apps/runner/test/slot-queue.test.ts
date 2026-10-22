import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { WHY_TAGS, addWait, noteQueue, parseWaits, queueExtra, queueOf, type WaitMs } from "../src/slot-queue.ts";
import { parseSamples } from "../src/watch-collect.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");

describe("the tag list", () => {
  it("equals the Lean WhyTag.all names (golden adapt.whyTags)", () => {
    const g = readFileSync(join(root, "packages/contracts/golden/sup/adapt.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l) as { request: { op: string }; response: { names: string[] } });
    expect(g.find((c) => c.request.op === "adapt.whyTags")!.response.names).toEqual([...WHY_TAGS]);
  });
});

describe("addWait", () => {
  it("sums the ms per reason in first-seen order", () => {
    let acc: WaitMs[] = [];
    acc = addWait(acc, "simBusy", 2000);
    acc = addWait(acc, "queued", 1000);
    acc = addWait(acc, "simBusy", 3000);
    expect(acc).toEqual([{ why: "simBusy", ms: 5000 }, { why: "queued", ms: 1000 }]);
  });
  it("does not mutate its input and ignores non-positive ms", () => {
    const a: WaitMs[] = [{ why: "gap", ms: 10 }];
    expect(addWait(a, "gap", 5)).toEqual([{ why: "gap", ms: 15 }]);
    expect(a).toEqual([{ why: "gap", ms: 10 }]);
    expect(addWait(a, "pass", 0)).toEqual(a);
    expect(addWait(a, "pass", -3)).toEqual(a);
    expect(addWait(a, "pass", Number.NaN)).toEqual(a);
  });
  it("a legacy sim-lock holder (no lease) is just simBusy time: no owner or tenure is read", () => {
    const acc = [1, 2, 3].reduce((a) => addWait(a, "simBusy", 2000), [] as WaitMs[]);
    expect(acc).toEqual([{ why: "simBusy", ms: 6000 }]);
  });
});

describe("the span field", () => {
  it("is null unless the ticket waited under some reason", () => {
    expect(queueOf("sim", [], 5000)).toBeNull();
    expect(queueOf("sim", [{ why: "simBusy", ms: 5 }], 0)).toBeNull();
    expect(queueOf("sim", [{ why: "simBusy", ms: 1521000 }], 1523000)).toEqual({ kind: "sim", waitMs: 1523000, waits: [{ why: "simBusy", ms: 1521000 }] });
  });
  it("travels to the span extras through the process", () => {
    const q = { kind: "check" as const, waitMs: 4000, waits: [{ why: "simBusy", ms: 3000 }] };
    noteQueue(q);
    expect(queueExtra()).toEqual({ queue: q });
    noteQueue(null);
    expect(queueExtra()).toEqual({});
  });
});

describe("parseSamples reads the queue", () => {
  const line = (o: object) => JSON.stringify({ tool: "fw", step: "slot acquire sim", startMs: 1, durMs: 1523000, exit: 0, host: "local", load: 2, ...o });
  it("maps queue to waitMs and waits", () => {
    const [s] = parseSamples(line({ queue: { kind: "sim", waitMs: 1521000, waits: [{ why: "simBusy", ms: 1480000 }, { why: "memory", ms: 41000 }] } }));
    expect(s).toMatchObject({ waitMs: 1521000, durMs: 1523000, waits: [{ why: "simBusy", ms: 1480000 }, { why: "memory", ms: 41000 }] });
    expect(s).not.toHaveProperty("leaseMs");
  });
  it("drops an unknown reason name, so its ms stay in the judged remainder", () => {
    const [s] = parseSamples(line({ queue: { kind: "sim", waitMs: 9000, waits: [{ why: "bogus", ms: 5000 }, { why: "pass", ms: 4000 }, { why: "gap", ms: "x" }, null, { ms: 3 }] } }));
    expect(s!.waits).toEqual([{ why: "pass", ms: 4000 }]);
    expect(parseWaits("nope")).toEqual([]);
  });
  it("leaves spans without a usable queue unchanged (no backfill)", () => {
    for (const q of [undefined, null, 3, { waitMs: 0, waits: [] }, { waitMs: "x" }]) {
      const [s] = parseSamples(line(q === undefined ? {} : { queue: q }));
      expect(s).not.toHaveProperty("waitMs");
      expect(s).not.toHaveProperty("waits");
    }
  });
  it("an old span with waitMs but no waits gets waits []", () => {
    const [s] = parseSamples(line({ queue: { kind: "sim", waitMs: 100000 } }));
    expect(s).toMatchObject({ waitMs: 100000, waits: [] });
  });
});
