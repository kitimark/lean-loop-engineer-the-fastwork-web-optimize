import "./land-timeout.ts";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createApp } from "../../console-api/src/app.ts";
import { selectCore } from "../../console-api/src/core/index.ts";
import { Reconciler } from "../../console-api/src/reconcile/reconciler.ts";
import { Store } from "../../console-api/src/store.ts";
import { makeRepo } from "../../console-api/test/reconcile-fixture.ts";
import { cardCommand } from "../src/card.ts";
import { land, worktreeOf, type Http } from "../src/land.ts";

let stores: Store[] = [];
afterEach(() => { stores.forEach((s) => s.close()); stores = []; });

async function setup() {
  const fx = makeRepo();
  const store = await Store.open(fx.consoleDir, selectCore(), () => 1_700_000_000_000);
  stores.push(store);
  const app = createApp(store, undefined, new Reconciler(store, fx.root));
  const http: Http = {
    get: async (p) => { const r = await app.request(p); return { status: r.status, body: await r.json() }; },
    post: async (p, b) => {
      const r = await app.request(p, { method: "POST", body: JSON.stringify(b), headers: { "content-type": "application/json", "x-fw-secret": readFileSync(join(fx.consoleDir, "secret"), "utf8").trim() } });
      return { status: r.status, body: await r.json() };
    },
  };
  const cmd = (c: object) => store.submit(c as never);
  await cmd({ type: "card.open", key: "o", actor: "owner", card: "A", owner: "o", needsDevice: false });
  await cmd({ type: "card.approve", key: "a", actor: "lead", card: "A" });
  const evidence = async (sha: string) => {
    await cmd({ type: "card.screen", key: `s${sha}`, actor: "script", card: "A", sha, pass: true });
    await cmd({ type: "card.review", key: `r${sha}`, actor: "reviewer", card: "A", sha, signedBy: "rev", accept: true });
  };
  // these tests have no hook, hence no capability: the land request goes through the web/user door
  const submit = (c: object) => http.post("/api/commands", c);
  const opts = { http, cwd: fx.root, checks: [["true"]], submit, ci: false as const, allow: ["**"] };
  return { fx, store, http, cmd, evidence, opts };
}

describe("fw land", () => {
  it("lands a ready card: ff-only on main, the reconciler records card.landed, no violation", async () => {
    const { fx, store, http, evidence, opts } = await setup();
    const wt = fx.worktree("card/A");
    const sha = fx.commit(wt, "a.txt");
    await http.post("/api/reconcile", {});
    await evidence(sha);
    const r = await land("card/A", opts);
    expect(r.lines.join("\n")).toContain("recorded");
    expect(r.ok).toBe(true);
    expect(fx.git(fx.root, "rev-parse", "main")).toBe(sha);
    expect((await store.board()).cards[0]).toMatchObject({ landed: true, violation: false });
    expect(store.readEvents().find((e) => e.type === "card.land_request")).toMatchObject({ sha });
    expect(store.readEvents().map((e) => `${e.type}:${e.actor}`)).toEqual(
      ["card.open:owner", "card.approve:lead", "card.build:git", "card.screen:script", "card.review:reviewer", "card.land_request:lead", "card.landed:git"]);
  });

  it("refuses a card that is not ready and leaves main alone", async () => {
    const { fx, opts } = await setup();
    fx.commit(fx.worktree("card/A"), "a.txt");
    const before = fx.git(fx.root, "rev-parse", "main");
    const r = await land("card/A", opts);
    expect(r.ok).toBe(false);
    expect(r.lines.join("\n")).toMatch(/stage screen/);
    expect(fx.git(fx.root, "rev-parse", "main")).toBe(before);
  });

  it("a commit after the evidence makes the old evidence stale: refused", async () => {
    const { fx, http, evidence, opts } = await setup();
    const wt = fx.worktree("card/A");
    const old = fx.commit(wt, "a.txt");
    await http.post("/api/reconcile", {});
    await evidence(old);
    fx.commit(wt, "b.txt");
    const r = await land("card/A", opts);
    expect(r.ok).toBe(false);
    expect(r.lines.join("\n")).toMatch(/stage screen/);
  });

  it("a failing fast check refuses before any request or merge", async () => {
    const { fx, store, http, evidence, opts } = await setup();
    const sha = fx.commit(fx.worktree("card/A"), "a.txt");
    await http.post("/api/reconcile", {});
    await evidence(sha);
    const r = await land("card/A", { ...opts, checks: [["false"]] });
    expect(r.ok).toBe(false);
    expect(store.readEvents().some((e) => e.type === "card.land_request")).toBe(false);
    expect(fx.git(fx.root, "rev-parse", "main")).not.toBe(sha);
  });

  it("a path check violation refuses", async () => {
    const { fx, http, evidence, opts } = await setup();
    const sha = fx.commit(fx.worktree("card/A"), ".fw-console/events.jsonl");
    await http.post("/api/reconcile", {});
    await evidence(sha);
    const r = await land("card/A", opts);
    expect(r.ok).toBe(false);
    expect(r.lines.join("\n")).toMatch(/outside the scope/);
    expect(fx.git(fx.root, "rev-parse", "main")).not.toBe(sha);
  });

  it("never rebases: a card branch behind main is refused for a fast-forward and left untouched", async () => {
    const { fx, http, evidence, opts } = await setup();
    const wt = fx.worktree("card/A");
    const sha = fx.commit(wt, "a.txt");
    await http.post("/api/reconcile", {});
    await evidence(sha);
    fx.commit(fx.root, "other.txt");
    const r = await land("card/A", opts);
    expect(r.ok).toBe(false);
    expect(r.lines.join("\n")).toMatch(/behind main/);
    expect(fx.git(fx.root, "rev-parse", "card/A")).toBe(sha);
    expect(worktreeOf(fx.root, "card/A")).toBe(wt);
  });

  it("a card landing without writes or --allow is refused with the changed files", async () => {
    const { fx, http, evidence, opts } = await setup();
    const sha = fx.commit(fx.worktree("card/A"), "a.txt");
    await http.post("/api/reconcile", {});
    await evidence(sha);
    const r = await land("card/A", { ...opts, allow: undefined });
    expect(r.ok).toBe(false);
    expect(r.lines.join("\n")).toMatch(/no writes[\s\S]*a\.txt/);
  });

  it("refuses a branch that is not a card branch", async () => {
    const { opts } = await setup();
    expect((await land("main", opts)).ok).toBe(false);
  });
});

describe("fw card", () => {
  it("builds typed commands with default actors and derived keys", () => {
    expect(cardCommand(["open", "A", "--owner", "o"], {})).toEqual({ type: "card.open", key: "card.open:A", actor: "owner", card: "A", owner: "o", needsDevice: false });
    expect(cardCommand(["screen", "A", "abc", "--pass", "true"], {})).toMatchObject({ type: "card.screen", actor: "script", sha: "abc", pass: true });
    expect(cardCommand(["review", "A", "abc", "--by", "r", "--accept", "yes"], {})).toMatchObject({ type: "card.review", actor: "reviewer", signedBy: "r" });
    expect(() => cardCommand(["screen", "A", "abc"], {})).toThrow();
    expect(() => cardCommand(["bogus"], {})).toThrow();
  });
});
