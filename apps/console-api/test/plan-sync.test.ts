// Plan sync when main moves (claim-order-lean): which commit is synced is Lean's `Fw.Plan.syncFrom` (golden vectors
// below); the reconciler reads the work graph committed at main's head, never a worktree's copy, and a re-sync of an
// unchanged file is all duplicates.
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it } from "vitest";
import { syncFrom, type WorkGraph } from "@fw/contracts";
import { selectCore } from "../src/core/index.ts";
import { Reconciler } from "../src/reconcile/reconciler.ts";
import { Store } from "../src/store.ts";
import { makeRepo } from "./reconcile-fixture.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "../../..");
const vectors = readFileSync(join(root, "packages/contracts/golden/plan/sync.jsonl"), "utf8").trim().split("\n")
  .map((l) => JSON.parse(l) as { name: string; main: string; refs: [string, string][]; last: string | null; from: string | null });

let stores: Store[] = [];
afterEach(() => { stores.forEach((s) => s.close()); stores = []; });

const graph = (titleA = "A"): WorkGraph => ({
  milestones: [{ id: "M", title: "mini" }],
  tasks: [
    { id: "b", title: "B", stream: "s", milestone: "M", deps: ["a"], owner: "o" },
    { id: "a", title: titleA, stream: "s", milestone: "M", deps: [], owner: "o" },
  ],
});
const file = "docs/team/work-graph.json";

describe("plan sync", () => {
  it("syncFrom (TS stand-in) gives Lean's answer on every golden vector", () => {
    expect(vectors.length).toBeGreaterThanOrEqual(7);
    for (const v of vectors) expect(syncFrom(v.main, v.refs, v.last), v.name).toBe(v.from);
  });

  it("the reconciler syncs when main's head changes, skips the same head, and never reads a worktree's file", async () => {
    const fx = makeRepo();
    const store = await Store.open(fx.consoleDir, selectCore(), () => 1_700_000_000_000);
    stores.push(store);
    const rc = new Reconciler(store, fx.root);
    const defines = () => store.readEvents().filter((e) => e.type === "task.define" || e.type === "milestone.define");
    const titleOf = async (id: string) => (await store.board()).plan.tasks.find((t) => t.id === id)?.title;

    // main has no work graph yet: nothing is sent
    await rc.reconcile();
    expect(defines()).toEqual([]);

    // main gains the file: milestone + both tasks, deps first, actor script
    fx.commit(fx.root, file, JSON.stringify(graph()));
    const s1 = await rc.reconcile();
    expect(s1.submitted).toBe(3);
    expect(defines().map((e) => [e.type, e.actor])).toEqual([["milestone.define", "script"], ["task.define", "script"], ["task.define", "script"]]);

    // same head: skipped, nothing sent
    expect(await rc.reconcile()).toMatchObject({ submitted: 0, duplicate: 0, refused: 0 });

    // a worktree branch edits the file: never synced (only main's head is read)
    const wt = fx.worktree("card/x");
    fx.commit(wt, file, JSON.stringify(graph("from a worktree")));
    await rc.reconcile();
    expect(await titleOf("a")).toBe("A");

    // main moves without touching the file: a sync pass, all no-ops (same keys)
    fx.commit(fx.root, "README", "y\n");
    expect(await rc.reconcile()).toMatchObject({ submitted: 0, refused: 0 });
    expect(defines()).toHaveLength(3);

    // main edits one task: exactly that define is new
    fx.commit(fx.root, file, JSON.stringify(graph("A2")));
    expect((await rc.reconcile()).submitted).toBe(1);
    expect(await titleOf("a")).toBe("A2");

    // a fresh reconciler (console restart) re-syncs main's head: every define is a duplicate
    const fresh = await new Reconciler(store, fx.root).reconcile();
    expect(fresh).toMatchObject({ submitted: 0, refused: 0 });
    expect(fresh.duplicate).toBeGreaterThanOrEqual(3);
  });
});
