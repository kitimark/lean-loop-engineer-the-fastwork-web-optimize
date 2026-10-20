import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { GateReply, GateRequest, ManifestReply, ManifestRequest, ObjectPathReply, ObjectPathRequest, PlanReply, PlanRequest, ReduceReply, ReduceRequest, StoreError, TrajectoryReply, TrajectoryRequest } from "@fw/contracts";

// Every golden vector is generated from Lean (lean/Fw/Store/Golden.lean); the zod schemas must accept each one.
const dir = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..", "packages", "contracts", "golden", "store");
const load = (stem: string) =>
  readFileSync(join(dir, `${stem}.jsonl`), "utf8").trim().split("\n").map((l) => JSON.parse(l) as { name: string; request: unknown; response: unknown });

const files = [
  ["plan", PlanRequest, PlanReply],
  ["gate", GateRequest, GateReply],
  ["trajectory", TrajectoryRequest, TrajectoryReply],
  ["manifest", ManifestRequest, ManifestReply],
  ["objectPath", ObjectPathRequest, ObjectPathReply],
  ["reduce", ReduceRequest, ReduceReply],
] as const;

describe("store golden vectors parse with the contracts", () => {
  for (const [stem, Req, Rep] of files) {
    const cases = load(stem);
    it(`${stem}: ${cases.length} cases`, () => {
      expect(cases.length).toBeGreaterThan(0);
      for (const c of cases) {
        // A request outside the schema (e.g. no target) must be one fwcore refuses with an error.
        const refused = StoreError.safeParse(c.response).success;
        expect(Req.safeParse(c.request).success || refused, `${c.name} request`).toBe(true);
        const ok = Rep.safeParse(c.response).success || refused;
        expect(ok, `${c.name} response`).toBe(true);
      }
    });
  }
});
