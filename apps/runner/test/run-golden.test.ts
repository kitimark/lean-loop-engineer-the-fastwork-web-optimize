import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { DownloadReply, DownloadRequest, fwcoreCall, type FwCall } from "../src/run.ts";
import { GateReply, GateRequest, ManifestReply, ManifestRequest, ObjectPathReply, ObjectPathRequest, PlanReply, PlanRequest, ReduceReply, ReduceRequest, StoreError, TrajectoryReply, TrajectoryRequest } from "@fw/contracts";

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
  ["download", DownloadRequest, DownloadReply],
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

const hasCore = (() => { try { fwcoreCall(process.cwd()); return true; } catch { return false; } })();

describe.skipIf(!hasCore)("store golden vectors replay against fwcore", () => {
  const call: FwCall = hasCore ? fwcoreCall(process.cwd()) : () => ({});
  for (const stem of ["plan", "manifest", "download"] as const) {
    it(`${stem}: fwcore gives every golden response`, () => {
      for (const c of load(stem)) {
        const req = c.request as Record<string, unknown>;
        if (StoreError.safeParse(c.response).success) expect(() => call(req), c.name).toThrow();
        else expect(call(req), c.name).toEqual(c.response);
      }
    });
  }
  it("plan: webkit is sent the run count as vms, and the run count separates the keys", () => {
    const plan = load("plan");
    const jobsOf = (name: RegExp) => (plan.find((c) => name.test(c.name))!.response as { jobs: { engine: string; inputs: Record<string, string>; key: [string, string][] }[] }).jobs;
    const three = jobsOf(/^the rewrite in its default configuration/);
    const two = jobsOf(/^2 runs: webkit is sent vms 2/);
    expect(three.find((j) => j.engine === "webkit")!.inputs.vms).toBe("3");
    expect(two.find((j) => j.engine === "webkit")!.inputs.vms).toBe("2");
    for (const e of ["chromium", "webkit"]) expect(two.find((j) => j.engine === e)!.key).not.toEqual(three.find((j) => j.engine === e)!.key);
  });
});
