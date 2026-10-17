// Workflow runs as agent events (task workflow-claim): the TS stand-in against the Lean golden, and the drain sweep.
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it } from "vitest";
import { selectCore } from "../src/core/index.ts";
import { Drain } from "../src/spool/drain.ts";
import { scriptRun, wfEvents, workflowDirs } from "../src/spool/workflow.ts";
import { Store } from "../src/store.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "../../..");
type Vec = { name: string; ids: string[]; scripts: string[]; runs: string[]; events: unknown[] };
const vectors = readFileSync(join(root, "packages/contracts/golden/plan/workflow.jsonl"), "utf8").trim().split("\n")
  .map((l) => JSON.parse(l) as Vec);

let stores: Store[] = [];
afterEach(() => { stores.forEach((s) => s.close()); stores = []; });

describe("workflow golden (Lean Fw.Plan.wfEvents)", () => {
  it("has vectors", () => expect(vectors.length).toBeGreaterThan(4));
  for (const v of vectors) it(v.name, () => expect(wfEvents(v.ids, v.scripts, v.runs)).toEqual(v.events));
  it("scriptRun keeps hyphens in the name", () =>
    expect(scriptRun("wave-next-builders-wf_eaf1cd1e-ed1.js")).toEqual({ name: "wave-next-builders", run: "wf_eaf1cd1e-ed1" }));
  it("workflowDirs: FW_WORKFLOWS_DIR wins; a missing project dir gives none", () => {
    expect(workflowDirs("/x", { FW_WORKFLOWS_DIR: "/a:/b" })).toEqual(["/a", "/b"]);
    expect(workflowDirs("/x/y", {}, "/nonexistent-home")).toEqual([]);
  });
});

describe("drain sweeps workflow runs", () => {
  it("a run named like a task binds it, and its end unbinds it (the incident)", async () => {
    const dir = mkdtempSync(join(tmpdir(), "fw-wf-"));
    const store = await Store.open(dir, selectCore(), () => 1_700_000_000_000);
    stores.push(store);
    const wf = join(dir, "sess", "workflows");
    mkdirSync(join(wf, "scripts"), { recursive: true });
    const r = await store.submit({ type: "task.define", key: "d:mistake-retro", actor: "lead", task: "mistake-retro", title: "T", stream: "s",
      milestone: null, deps: [], owner: "o", writes: [], devices: [], needs: [], evidence: null } as never);
    expect(r.ok).toBe(true);
    const agentOf = async () => (await store.board()).plan.tasks.find((t) => t.id === "mistake-retro")?.agent ?? null;
    const drain = new Drain(store, () => [wf]);
    await drain.run();
    expect(await agentOf()).toBeNull();
    writeFileSync(join(wf, "scripts", "mistake-retro-wf_b3d4e643-ace.js"), "");
    writeFileSync(join(wf, "scripts", "other-wf_05e58d40-de0.js"), "");
    await drain.run();
    expect(await agentOf()).toBe("mistake-retro");
    await drain.run(); // a repeated sweep adds nothing
    expect(await agentOf()).toBe("mistake-retro");
    writeFileSync(join(wf, "wf_b3d4e643-ace.json"), "{}");
    await drain.run();
    expect(await agentOf()).toBeNull();
  });
});
