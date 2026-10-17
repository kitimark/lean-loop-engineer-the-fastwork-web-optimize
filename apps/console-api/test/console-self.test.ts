// Lean-owned rules of console-api itself, checked against the Lean-generated goldens
// (packages/contracts/golden, written by lean/scripts/OpsGolden.lean):
//  - ops/ops.obs.jsonl: the obs key and the tool-call summary (`Fw.Ops.Obs`), as drain.ts calls them;
//  - plan/plan.trailers.jsonl: `Task:` trailers -> task.done facts (`Fw.Plan.Trailer`), as git.ts calls it;
//  - console/console.landReadiness.jsonl: what a card needs before it may land (`Fw.Console.Land`);
//  - console/console.actor.jsonl: the actor and event type of console-api's own events (`Fw.Console.Self`).
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, describe, expect, it } from "vitest";
import { selectCore } from "../src/core/index.ts";
import { alertPlan } from "../src/spool/drain.ts";

type Case = { name: string; request: { op: string } & Record<string, unknown>; response: Record<string, unknown> };
const golden = (f: string): Case[] => readFileSync(join(dirname(fileURLToPath(import.meta.url)), "../../../packages/contracts/golden", f), "utf8")
  .trim().split("\n").map((l) => JSON.parse(l) as Case);
const core = selectCore();
afterAll(() => core.close());

/** The reply of fwcore to a golden request, errors as `{error}` like the golden file. */
const reply = async (req: Case["request"]): Promise<unknown> => {
  const { op, ...fields } = req;
  try { const { id: _id, ...r } = await core.ops(op, fields); return r; } catch (e) { return { error: (e as Error).message.replace(/^fwcore: /, "") }; }
};

for (const f of ["ops/ops.obs.jsonl", "plan/plan.trailers.jsonl", "console/console.landReadiness.jsonl", "console/console.actor.jsonl", "console/console.alert.jsonl"]) {
  describe(`${f} golden conformance (fwcore)`, () => {
    const cases = golden(f);
    it("has cases", () => expect(cases.length).toBeGreaterThanOrEqual(3));
    for (const c of cases) it(c.name, async () => expect(await reply(c.request)).toEqual(c.response));
  });
}

describe("console-api's own events match Lean console.actor", () => {
  const all = golden("console/console.actor.jsonl").find((c) => c.name === "all sources")!.response.sources as
    { source: string; actor: string; type: string; allowed: boolean }[];
  const bySource = Object.fromEntries(all.map((s) => [s.source, s]));
  it("every source is allowed by the MAY table", () => {
    expect(all.map((s) => s.source)).toEqual(["alert", "claim", "build", "landed", "taskDone"]);
    for (const s of all) expect(s.allowed).toBe(true);
  });
  it("alertPlan posts and cancels as the alert source", async () => {
    const rec = { agent_id: "a1", agent_type: "builder", hook_event_name: "Notification", tool_name: null, tool_use_id: null,
      duration_ms: null, is_error: null, verb: null, ts: 1 };
    const a = (await alertPlan(core, rec, [], [])).post;
    expect(a && { actor: a.actor, type: a.type }).toEqual({ actor: bySource.alert!.actor, type: bySource.alert!.type });
    const c = (await alertPlan(core, { ...rec, hook_event_name: "PostToolUse", ts: 2 }, [], ["alert-a1-1"])).close;
    expect(c.map((x) => [x.actor, x.type])).toEqual([["script", "step.cancel"]]);
  });
  it("claims, builds, landings and trailers write as hook and git (literals in drain.ts and reconciler.ts)", () => {
    expect([bySource.claim, bySource.build, bySource.landed, bySource.taskDone].map((s) => [s!.actor, s!.type])).toEqual(
      [["hook", "task.claim"], ["git", "card.build"], ["git", "card.landed"], ["git", "task.done"]]);
  });
});
