// The console-api timeout rule against the Lean golden (Fw.Obs.Backoff, op obs.backoff): backoffDecision is a TS
// stand-in checked here, and fwcore itself answers the same cases.
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, describe, expect, it } from "vitest";
import { backoffDecision } from "../src/core/lean.ts";
import { selectCore } from "../src/core/index.ts";

const cases = readFileSync(join(dirname(fileURLToPath(import.meta.url)), "../../../packages/contracts/golden/obs/backoff.jsonl"), "utf8")
  .trim().split("\n").map((l) => JSON.parse(l)) as {
  name: string; request: { params: { loadHigh: number; extra: number }; load: number; baseMs: number; waitedMs: number };
  response: { action: string; waitMs: number };
}[];
const core = selectCore();
afterAll(() => core.close());

describe("obs.backoff golden", () => {
  for (const c of cases) {
    const r = c.request;
    it(`TS rule: ${c.name}`, () => {
      expect(backoffDecision(r.load, r.baseMs, r.waitedMs, r.params.loadHigh, r.params.extra)).toEqual(c.response);
    });
    it(`fwcore: ${c.name}`, async () => {
      expect(await core.ops("obs.backoff", r)).toMatchObject(c.response);
    });
  }
});
