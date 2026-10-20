// Task land-render-guard (Lean Fw.Land.RenderGuard, op console.landRenderGuard): fw land refuses, before any check, a branch
// whose history writes a media file outside snapshot/, also when a later commit removes it, and merges only the checked tip.
import "./land-timeout.ts";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createApp } from "../../console-api/src/app.ts";
import { selectCore } from "../../console-api/src/core/index.ts";
import { Reconciler } from "../../console-api/src/reconcile/reconciler.ts";
import { Store } from "../../console-api/src/store.ts";
import { makeRepo } from "../../console-api/test/reconcile-fixture.ts";
import { askCore } from "../hooks/land-guard.mjs";
import { land, renderGuard, type Http } from "../src/land.ts";

let stores: Store[] = [];
afterEach(() => { stores.forEach((s) => s.close()); stores = []; });
const BR = "worktree-agent-t1";
const WRITES = ["src/**", "results/**", "snapshot/**"];

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
  await store.submit({ type: "task.define", key: "d", actor: "lead", task: "t1", title: "t", stream: "s", milestone: null, deps: [], owner: "builder", writes: WRITES, devices: [], evidence: null } as never);
  mkdirSync(join(fx.root, "docs/team"), { recursive: true });
  writeFileSync(join(fx.root, "docs/team/work-graph.json"), JSON.stringify({ tasks: [{ id: "t1", owner: "builder", stream: "s", writes: WRITES, evidence: null }] }, null, 1) + "\n");
  fx.git(fx.root, "add", "--", "docs/team/work-graph.json");
  fx.git(fx.root, "commit", "-q", "-m", "work graph");
  const wt = fx.worktree(BR);
  const marker = join(fx.root, "..", "check-ran");
  const opts = { http, cwd: fx.root, checks: [["sh", "-c", `touch '${marker}'`]], ci: false as const, task: "t1", retryMs: 1, lockWaitMs: 0 };
  return { fx, wt, opts, marker };
}
const text = (r: { lines: string[] }) => r.lines.join("\n");
/** A check that commits a render on the branch in `wt` while the land runs its checks. */
const lateRender = (wt: string) => ["sh", "-c", `cd '${wt}' && mkdir -p results && printf x > results/late.png && git add -- results/late.png && git commit -q -m late`];
const isAncestor = (fx: ReturnType<typeof makeRepo>, a: string, b: string) => { try { fx.git(fx.root, "merge-base", "--is-ancestor", a, b); return true; } catch { return false; } };
/** The branch moved past the checked tip during the checks, and main holds the checked tip but neither the late commit nor its render. */
function onlyCheckedTip(fx: ReturnType<typeof makeRepo>, branch: string, sha: string) {
  const late = fx.git(fx.root, "rev-parse", branch);
  expect(late).not.toBe(sha);
  expect(isAncestor(fx, sha, "main")).toBe(true);
  expect(isAncestor(fx, late, "main")).toBe(false);
  expect(fx.git(fx.root, "ls-tree", "-r", "--name-only", "main")).not.toContain("results/late.png");
}

describe("render guard golden (fwcore console.landRenderGuard)", () => {
  const rows = readFileSync(new URL("../../../packages/contracts/golden/land/render-guard.jsonl", import.meta.url), "utf8")
    .split("\n").filter(Boolean).map((l) => JSON.parse(l) as { name: string; request: Record<string, unknown>; response: Record<string, unknown> });
  it("has the history-wide, snapshot and error cases", () => {
    expect(rows.length).toBeGreaterThanOrEqual(15);
    expect(rows.some((g) => g.response.error)).toBe(true);
  });
  for (const g of rows) {
    it(g.name, () => {
      const { op, ...req } = g.request;
      const r = askCore(op as string, req);
      if (g.response.error) expect(r).toBeNull();
      else { const { id: _id, ...rest } = r ?? {}; expect(rest).toEqual(g.response); }
    });
  }
});

describe("fw land render guard (temp repo)", () => {
  it("a render added and removed in a later commit is refused before any check, naming the path and the commit; main is untouched", async () => {
    const { fx, wt, opts, marker } = await setup();
    fx.commit(wt, "src/a.ts");
    const add = fx.commit(wt, "results/hero.png", "\x89PNG\r\n");
    fx.git(wt, "rm", "-q", "--", "results/hero.png");
    fx.git(wt, "commit", "-q", "-m", "remove the render");
    const main0 = fx.git(fx.root, "rev-parse", "main");
    const dry = await land(BR, { ...opts, dry: true, dryReads: { argv: ["true"], selected: false } });
    expect(dry.ok).toBe(false);
    expect(dry.kind, text(dry)).toBe("scope");
    const real = await land(BR, opts);
    expect(real.ok).toBe(false);
    expect(real.kind, text(real)).toBe("scope");
    const line = real.lines.find((l) => l.startsWith("REFUSED: render guard:"));
    expect(line, text(real)).toBeDefined();
    expect(line).toContain(`results/hero.png (image) in ${add}`);
    expect(existsSync(marker)).toBe(false);
    expect(fx.git(fx.root, "rev-parse", "main")).toBe(main0);
  });
  it("media under snapshot/ and source files pass the guard and the land runs its checks", async () => {
    const { fx, wt, opts, marker } = await setup();
    fx.commit(wt, "snapshot/fastwork.co/a.png", "png\n");
    fx.commit(wt, "src/a.ts");
    expect(renderGuard(fx.root, "main", BR)).toEqual({ hits: [] });
    const real = await land(BR, opts);
    expect(real.ok, text(real)).toBe(true);
    expect(existsSync(marker)).toBe(true);
  });
  it("a rename out of snapshot/ is read as an add outside it", async () => {
    const { fx, wt } = await setup();
    fx.commit(wt, "snapshot/s.woff2", "font\n");
    mkdirSync(join(wt, "results"), { recursive: true });
    fx.git(wt, "mv", "snapshot/s.woff2", "results/s.woff2");
    fx.git(wt, "commit", "-q", "-m", "move");
    const mv = fx.git(wt, "rev-parse", "HEAD");
    expect(renderGuard(fx.root, "main", BR)).toEqual({ hits: [{ commit: mv, path: "results/s.woff2", media: "font" }] });
  });
  it("a merge that adds a render of its own is refused by its first-parent diff", async () => {
    const { fx, wt } = await setup();
    fx.commit(wt, "src/a.ts");
    fx.git(fx.root, "checkout", "-q", "-b", "side");
    fx.commit(fx.root, "src/side.ts");
    fx.git(fx.root, "checkout", "-q", "main");
    fx.git(wt, "merge", "-q", "--no-commit", "side");
    mkdirSync(join(wt, "results"), { recursive: true });
    writeFileSync(join(wt, "results", "evil.mp4"), "v\n");
    fx.git(wt, "add", "--", "results/evil.mp4");
    fx.git(wt, "commit", "-q", "-m", "merge side");
    const m = fx.git(wt, "rev-parse", "HEAD");
    expect(renderGuard(fx.root, "main", BR)).toEqual({ hits: [{ commit: m, path: "results/evil.mp4", media: "video" }] });
  });
  it("a branch git cannot read is refused, not passed", async () => {
    const { fx } = await setup();
    expect(renderGuard(fx.root, "main", "no-such-branch")).toHaveProperty("error");
  });
});

describe("fw land merges only the tip the render guard checked (temp repo)", () => {
  it("pre-lock falls back to the locked protocol (main moved during its check): the render committed meanwhile stays out of main", async () => {
    const { fx, wt, opts } = await setup();
    const sha = fx.commit(wt, "src/a.ts");
    const once = join(fx.root, "..", "late-once");
    const late = ["sh", "-c", `[ -e '${once}' ] || { touch '${once}' && ${lateRender(wt)[2]} && git -C '${fx.root}' commit -q --allow-empty -m moved; }`];
    const r = await land(BR, { ...opts, retries: 0, checks: [late] });
    expect(r.ok, text(r)).toBe(true);
    expect(text(r)).toContain("using the locked protocol");
    expect(fx.git(fx.root, "rev-parse", "main^2")).toBe(sha);
    onlyCheckedTip(fx, BR, sha);
  });
  it("pre-lock protocol: a render committed on the branch while a check runs stays out of main", async () => {
    const { fx, wt, opts } = await setup();
    const sha = fx.commit(wt, "src/a.ts");
    const r = await land(BR, { ...opts, checks: [lateRender(wt)] });
    expect(r.ok, text(r)).toBe(true);
    expect(fx.git(fx.root, "rev-parse", "main^2")).toBe(sha);
    onlyCheckedTip(fx, BR, sha);
  });
  it("card fast-forward: a render committed on the branch while a check runs stays out of main", async () => {
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
    const wt = fx.worktree("card/A");
    const sha = fx.commit(wt, "a.txt");
    await http.post("/api/reconcile", {});
    await cmd({ type: "card.screen", key: `s${sha}`, actor: "script", card: "A", sha, pass: true });
    await cmd({ type: "card.review", key: `r${sha}`, actor: "reviewer", card: "A", sha, signedBy: "rev", accept: true });
    const r = await land("card/A", { http, cwd: fx.root, checks: [lateRender(wt)], submit: (c: object) => http.post("/api/commands", c), ci: false as const, allow: ["**"] });
    expect(r.ok, text(r)).toBe(true);
    expect(fx.git(fx.root, "rev-parse", "main")).toBe(sha);
    onlyCheckedTip(fx, "card/A", sha);
  });
});
