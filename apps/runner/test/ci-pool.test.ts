import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { poolMain, poolRequest, rowLine } from "../src/ci-pool.ts";
import { UsageError } from "../src/lib.ts";
import { fwcoreCall } from "../src/run.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const call = fwcoreCall(root);
type Line = { op: string; name: string; request: Record<string, unknown>; response: Record<string, unknown> };
const lines = readFileSync(join(root, "packages/contracts/golden/ci/pool-fallback.jsonl"), "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l) as Line);

describe("the Lean golden, replayed through fwcore", () => {
  it("has rows for both ops", () => {
    expect(new Set(lines.map((l) => l.op))).toEqual(new Set(["ci.poolRoute", "ci.poolConsts"]));
  });
  for (const l of lines) {
    it(`${l.op}: ${l.name}`, () => {
      let got: Record<string, unknown>;
      try { got = call({ op: l.op, ...l.request }); } catch (e) { got = { error: (e as Error).message.replace(/^fwcore [\w.]+: /, "") }; }
      expect(got).toEqual(l.response);
    });
  }
});

describe("fw ci pool", () => {
  const dir = mkdtempSync(join(tmpdir(), "ci-pool-"));
  const golden = lines.find((l) => l.name === "a free slot: GitHub")!;
  it("builds the route request from inline and @file JSON", () => {
    writeFileSync(join(dir, "reqs.json"), JSON.stringify(golden.request.reqs));
    const req = poolRequest(["route", "--state", JSON.stringify(golden.request.state), "--reqs", "@reqs.json"], dir);
    expect(req).toEqual({ op: "ci.poolRoute", ...golden.request });
  });
  it("builds the consts request", () => {
    expect(poolRequest(["consts", "--cfg", "enterprise"], dir)).toEqual({ op: "ci.poolConsts", cfg: "enterprise" });
  });
  it("refuses a route without state or reqs, an unknown verb and bad JSON", () => {
    expect(() => poolRequest(["route", "--state", "{}"], dir)).toThrow(UsageError);
    expect(() => poolRequest(["nope"], dir)).toThrow(UsageError);
    expect(() => poolRequest(["route", "--state", "{", "--reqs", "[]"], dir)).toThrow(UsageError);
  });
  it("prints one line per request and a summary", () => {
    const out: string[] = [];
    const code = poolMain(["route", "--state", JSON.stringify(golden.request.state), "--reqs", JSON.stringify(golden.request.reqs)], dir, () => golden.response, (l) => out.push(l));
    expect(code).toBe(0);
    expect(out).toEqual([
      "wktr rep 0 attempt 0: run github/macos macos-26 wktrIosSim timeout 16 min, 0 credits",
      "sent 1, waiting 0, done 0; macFree true, expWaitS 0",
    ]);
  });
  it("prints a terminal row with its outcome", () => {
    expect(rowLine({ lane: "wktr", rep: 0, attempt: 0, decision: "done", outcome: "stale" })).toBe("wktr rep 0 attempt 0: done stale");
  });
});
