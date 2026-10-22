import "./land-timeout.ts";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it } from "vitest";
import { createApp } from "../../console-api/src/app.ts";
import { selectCore } from "../../console-api/src/core/index.ts";
import { Reconciler } from "../../console-api/src/reconcile/reconciler.ts";
import { Store } from "../../console-api/src/store.ts";
import { makeRepo } from "../../console-api/test/reconcile-fixture.ts";
import { inScope, land, SEED_READS, seedDue, seedLag, unpushedLag, type Http } from "../src/land.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "../../..");
const golden = readFileSync(join(root, "packages/contracts/golden/console/land-speed.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l));

describe("seedDue / seedLag equal the Lean golden", () => {
  it("landSpeed.seedDue: lags 0, 5, 6", () => {
    const rows = golden.filter((c) => c.request.op === "landSpeed.seedDue");
    expect(rows.map((c) => [c.request.lag, c.response.due])).toEqual([[0, false], [5, false], [6, true]]);
    for (const c of rows) expect(seedDue(c.request.lag)).toBe(c.response.due);
  });

  it("landSpeed.seedLag: lag, due and the counted paths", () => {
    const rows = golden.filter((c) => c.request.op === "landSpeed.seedLag");
    expect(rows.length).toBe(4);
    for (const c of rows) {
      const changed = c.request.changed as string[];
      expect({ lag: seedLag(changed), due: seedDue(seedLag(changed)), counted: changed.filter((p) => inScope(SEED_READS, p)) }, c.name).toEqual(c.response);
    }
  });

  it("SEED_READS are the paths the setup-lean cache key hashes", () => {
    const action = readFileSync(join(root, ".github/actions/setup-lean/action.yml"), "utf8");
    const keys = action.split("\n").filter((l) => /^\s*key: lake-/.test(l));
    expect(keys.length).toBeGreaterThan(0);
    for (const k of keys) {
      const globs = [...k.matchAll(/hashFiles\(([^)]*)\)/g)].flatMap((m) => [...m[1]!.matchAll(/'([^']+)'/g)].map((g) => g[1]!));
      expect([...globs].sort()).toEqual([...SEED_READS].sort());
    }
  });
});

let stores: Store[] = [];
afterEach(() => { stores.forEach((s) => s.close()); stores = []; });
Object.assign(process.env, { GIT_AUTHOR_NAME: "t", GIT_AUTHOR_EMAIL: "t@example.invalid", GIT_COMMITTER_NAME: "t", GIT_COMMITTER_EMAIL: "t@example.invalid" });

const BR = "worktree-agent-t1";

async function setup() {
  const fx = makeRepo();
  const store = await Store.open(fx.consoleDir, selectCore(), () => 1_700_000_000_000);
  stores.push(store);
  const app = createApp(store, undefined, new Reconciler(store, fx.root));
  const http: Http = {
    get: async (p) => { const r = await app.request(p); return { status: r.status, body: await r.json() }; },
    post: async (p, b) => {
      const r = await app.request(p, { method: "POST", body: JSON.stringify(b), headers: { "content-type": "application/json" } });
      return { status: r.status, body: await r.json() };
    },
  };
  const writes = ["lean/**", "docs/**"];
  await store.submit({ type: "task.define", key: "d", actor: "lead", task: "t1", title: "t", stream: "s", milestone: null, deps: [], owner: "builder", writes, devices: [], evidence: null } as never);
  mkdirSync(join(fx.root, "docs/team"), { recursive: true });
  writeFileSync(join(fx.root, "docs/team/work-graph.json"), JSON.stringify({ tasks: [{ id: "t1", owner: "builder", writes }] }));
  const wt = fx.worktree(BR);
  const opts = { http, cwd: fx.root, checks: [["true"]], ci: false as const, task: "t1" };
  return { fx, wt, opts };
}

const leanFiles = (n: number) => Array.from({ length: n }, (_, i) => `lean/Fw/M${i}.lean`);

describe("fw land prints PUSH-DUE <n> after a land when due", () => {
  it("six Lake-key paths ahead of origin/main: PUSH-DUE 6 is the last line", async () => {
    const { fx, wt, opts } = await setup();
    fx.git(fx.root, "update-ref", "refs/remotes/origin/main", "main");
    for (const f of [...leanFiles(6), "lean/scripts/x.sh", "docs/a.md"]) fx.commit(wt, f);
    const r = await land(BR, opts);
    expect(r.ok).toBe(true);
    expect(r.kind).toBe("done");
    expect(r.lines.at(-1)).toBe("PUSH-DUE 6");
    expect(r.lines.at(-2)).toContain("scan origin/main..main for personal data, then git push origin main");
  });

  it("five Lake-key paths ahead (build-free lean paths and docs do not count): no PUSH-DUE", async () => {
    const { fx, wt, opts } = await setup();
    fx.git(fx.root, "update-ref", "refs/remotes/origin/main", "main");
    for (const f of [...leanFiles(5), "lean/scripts/x.sh", "lean/land-legs.txt", "docs/a.md"]) fx.commit(wt, f);
    const r = await land(BR, opts);
    expect(r.ok).toBe(true);
    expect(r.lines.some((l) => l.startsWith("PUSH-DUE"))).toBe(false);
    expect(unpushedLag(fx.root, fx.git(fx.root, "rev-parse", "main"), "main")).toBe(5);
  });

  it("the lag counts every unpushed land, not only this one", async () => {
    const { fx, wt, opts } = await setup();
    fx.git(fx.root, "update-ref", "refs/remotes/origin/main", "main");
    for (const f of leanFiles(4)) fx.commit(fx.root, f);
    for (const f of ["lean/Fw/X.lean", "lean/FwTest/Y.lean"]) fx.commit(wt, f);
    fx.git(wt, "merge", "-q", "main");
    const r = await land(BR, opts);
    expect(r.lines.at(-1)).toBe("PUSH-DUE 6");
  });

  it("no origin/main ref: no PUSH-DUE, the land still succeeds", async () => {
    const { fx, wt, opts } = await setup();
    for (const f of leanFiles(7)) fx.commit(wt, f);
    const r = await land(BR, opts);
    expect(r.ok).toBe(true);
    expect(unpushedLag(fx.root, "main", "main")).toBe(null);
    expect(r.lines.some((l) => l.startsWith("PUSH-DUE"))).toBe(false);
  });

  it("the line carries the injected lag", async () => {
    const { fx, wt, opts } = await setup();
    fx.commit(wt, "docs/a.md");
    const seen: string[] = [];
    const r = await land(BR, { ...opts, unpushedLag: (_d: string, head: string, main: string) => { seen.push(`${head.length} ${main}`); return 12; } });
    expect(r.lines.at(-1)).toBe("PUSH-DUE 12");
    expect(seen).toEqual(["40 main"]);
  });
});
