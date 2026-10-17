import { afterEach, describe, expect, it } from "vitest";
import { selectCore } from "../src/core/index.ts";
import { Reconciler } from "../src/reconcile/reconciler.ts";
import { branchCard } from "../src/reconcile/naming.ts";
import { Store } from "../src/store.ts";
import { makeRepo } from "./reconcile-fixture.ts";

let stores: Store[] = [];
afterEach(() => { stores.forEach((s) => s.close()); stores = []; });

async function setup() {
  const fx = makeRepo();
  const store = await Store.open(fx.consoleDir, selectCore(), () => 1_700_000_000_000);
  stores.push(store);
  const rec = new Reconciler(store, fx.root);
  const send = (c: object) => store.submit(c as never);
  await send({ type: "card.open", key: "o", actor: "owner", card: "A", owner: "o", needsDevice: false });
  await send({ type: "card.approve", key: "a", actor: "lead", card: "A" });
  return { fx, store, rec, send };
}
const ready = async (send: (c: object) => Promise<unknown>, sha: string) => {
  await send({ type: "card.screen", key: `s${sha}`, actor: "script", card: "A", sha, pass: true });
  await send({ type: "card.review", key: `r${sha}`, actor: "reviewer", card: "A", sha, signedBy: "rev", accept: true });
};

describe("branch naming", () => {
  it("maps card/<id>[/<agent>] only", () => {
    expect(branchCard("card/A")).toEqual({ card: "A", agent: null });
    expect(branchCard("card/A/x1")).toEqual({ card: "A", agent: "x1" });
    expect(branchCard("main")).toBeNull();
    expect(branchCard("worktree-agent-1")).toBeNull();
    expect(branchCard("card/A/b/c")).toBeNull();
  });
});

describe("git reconciler", () => {
  it("emits card.build per new commit, then card.landed when main advances (ready: no violation)", async () => {
    const { fx, store, rec, send } = await setup();
    const wt = fx.worktree("card/A/builder1");
    fx.commit(wt, "a.txt");
    const sha = fx.commit(wt, "b.txt");
    expect(await rec.reconcile()).toMatchObject({ submitted: 2, refused: 0 });
    expect(store.state.cards[0]).toMatchObject({ head: sha, builders: ["builder1", "builder1"] });
    await ready(send, sha);
    await send({ type: "card.land_request", key: "lr", actor: "lead", card: "A", sha });
    fx.git(fx.root, "merge", "--ff-only", "card/A/builder1");
    expect(await rec.reconcile()).toMatchObject({ submitted: 1 });
    expect(store.state.cards[0]).toMatchObject({ landed: true, violation: false });
    expect(store.readEvents().filter((e) => e.type === "card.landed")).toMatchObject([{ actor: "git", sha }]);
  });

  it("a landing without a request is a violation", async () => {
    const { fx, store, rec, send } = await setup();
    const sha = fx.commit(fx.worktree("card/A"), "a.txt");
    await rec.reconcile();
    await ready(send, sha);
    fx.git(fx.root, "merge", "--ff-only", "card/A"); // bypasses fw land
    await rec.reconcile();
    expect(store.state.cards[0]).toMatchObject({ landed: true, violation: true });
  });

  it("a replayed fact is a duplicate, not a second event", async () => {
    const { fx, store, rec } = await setup();
    fx.commit(fx.worktree("card/A"), "a.txt");
    await rec.reconcile();
    expect(await rec.reconcile()).toMatchObject({ submitted: 0, skipped: 1 }); // in-process memo
    const again = new Reconciler(store, fx.root); // fresh process: the reducer dedups by key
    expect(await again.reconcile()).toMatchObject({ submitted: 0, duplicate: 1 });
    expect(store.readEvents().filter((e) => e.type === "card.build")).toHaveLength(1);
  });

  it("a branch whose card is not open yet is retried later; other branches are ignored", async () => {
    const { fx, store, rec, send } = await setup();
    fx.commit(fx.worktree("card/B"), "b.txt");
    fx.commit(fx.worktree("scratch"), "s.txt");
    expect(await rec.reconcile()).toMatchObject({ submitted: 0 });
    await send({ type: "card.open", key: "ob", actor: "owner", card: "B", owner: "o", needsDevice: false });
    expect(await rec.reconcile()).toMatchObject({ submitted: 1 });
    expect(store.state.cards.find((c) => c.id === "B")?.head).not.toBeNull();
  });

  it("a land request on a stale sha is refused by the reducer", async () => {
    const { fx, rec, send } = await setup();
    const wt = fx.worktree("card/A");
    const old = fx.commit(wt, "a.txt");
    fx.commit(wt, "b.txt");
    await rec.reconcile();
    const r = (await send({ type: "card.land_request", key: "lr", actor: "lead", card: "A", sha: old })) as { ok: boolean; reason?: string };
    expect(r).toEqual({ ok: false, reason: "stale sha: not the head commit" });
  });
});
