// Reconcile coalescing: the TS scheduler equals Lean `Fw.Console.ReconcileSched` on its golden vectors, and the
// Reconciler never runs two passes at once nor queues more than one.
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it } from "vitest";
import { selectCore } from "../src/core/index.ts";
import { fin, init, req, ticket } from "../src/reconcile/coalesce.ts";
import { onMainSet } from "../src/reconcile/git.ts";
import { Reconciler } from "../src/reconcile/reconciler.ts";
import { Store } from "../src/store.ts";
import { makeRepo } from "./reconcile-fixture.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "../../..");
type Step = { state: { started: number; finished: number; pending: number }; ticket: number | null };
const vectors = readFileSync(join(root, "packages/contracts/golden/console/reconcile-sched.jsonl"), "utf8").trim().split("\n")
  .map((l) => JSON.parse(l) as { name: string; events: string[]; steps: Step[] });

let stores: Store[] = [];
afterEach(() => { stores.forEach((s) => s.close()); stores = []; });

describe("scheduler (TS stand-in of Fw.Console.ReconcileSched)", () => {
  it("has golden vectors", () => expect(vectors.length).toBeGreaterThan(5));
  for (const v of vectors) {
    it(`matches Lean: ${v.name}`, () => {
      let s = init;
      v.events.forEach((e, i) => {
        const t = e === "req" ? ticket(s) : null;
        s = e === "req" ? req(s) : fin(s);
        expect(v.steps[i]).toEqual({ state: s, ticket: t });
      });
    });
  }
});

describe("Reconciler coalescing", () => {
  it("runs at most one pass at a time and at most one more after it, however many requests arrive", async () => {
    const fx = makeRepo();
    const store = await Store.open(fx.consoleDir, selectCore(), () => 1_700_000_000_000);
    stores.push(store);
    const rec = new Reconciler(store, fx.root);
    let running = 0, maxRunning = 0, passes = 0;
    let gate!: () => void;
    let held = new Promise<void>((r) => { gate = r; });
    (rec as unknown as { pass: () => Promise<unknown> }).pass = async () => {
      passes++; running++; maxRunning = Math.max(maxRunning, running);
      await held;
      running--;
      return { submitted: 0, duplicate: 0, refused: 0, skipped: passes };
    };
    const first = rec.reconcile();
    const rest = [rec.reconcile(), rec.reconcile(), rec.reconcile(), rec.reconcile()];
    expect(passes).toBe(1);
    const open = gate; held = new Promise<void>((r) => { gate = r; });
    open();
    const a = await first;
    expect(a.skipped).toBe(1);
    await new Promise((r) => setImmediate(r));
    expect(passes).toBe(2); // the four waiting requests share one pass that started after them
    gate();
    const bs = await Promise.all(rest);
    expect(bs.every((b) => b.skipped === 2)).toBe(true);
    expect(maxRunning).toBe(1);
    expect(passes).toBe(2);
    const again = await rec.reconcile(); // idle again: a new request starts a pass at once
    expect(again.skipped).toBe(3);
  });
});

describe("onMainSet", () => {
  it("answers like git merge-base --is-ancestor for full shas, prefixes and unknown ids", () => {
    const fx = makeRepo();
    const head = fx.git(fx.root, "rev-parse", "HEAD");
    const wt = fx.worktree("card/X");
    const off = fx.commit(wt, "x.txt");
    const on = onMainSet(fx.root, "main");
    expect(on(head)).toBe(true);
    expect(on(head.slice(0, 9))).toBe(true);
    expect(on(off)).toBe(false);
    expect(on("deadbeefdeadbeef")).toBe(false);
    expect(onMainSet(fx.root, "nope")(head)).toBe(false);
  });
});
