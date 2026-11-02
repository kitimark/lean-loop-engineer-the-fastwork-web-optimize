// Task scratch-link-check (Lean Fw.Ops.LandLink, op ops.landLink; incident inc-scratch-symlink-wait): the golden rows replay through fwcore,
// the added links are read from git (a temp repo with one escaping and one inside link), and fw land --dry refuses an escaping link.
import "./land-timeout.ts";
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createApp } from "../../console-api/src/app.ts";
import { selectCore } from "../../console-api/src/core/index.ts";
import { Reconciler } from "../../console-api/src/reconcile/reconciler.ts";
import { Store } from "../../console-api/src/store.ts";
import { makeRepo } from "../../console-api/test/reconcile-fixture.ts";
import { askCore } from "../hooks/land-guard.mjs";
import { land, type Http } from "../src/land.ts";
import { addedLinks, linkRefusal, refusedLinks } from "../src/land-link.ts";

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

describe("land link golden (fwcore ops.landLink)", () => {
  const rows = readFileSync(new URL("../../../packages/contracts/golden/ops/land-link.jsonl", import.meta.url), "utf8")
    .split("\n").filter(Boolean).map((l) => JSON.parse(l) as { name: string; request: Record<string, unknown>; response: Record<string, unknown> });
  it("has a pass and every refusal reason", () => {
    const reasons = new Set(rows.flatMap((g) => (g.response.refused as { reason: string }[]).map((r) => r.reason)));
    expect([...reasons].sort()).toEqual(["absolute", "empty", "escapes"]);
    expect(rows.some((g) => g.response.ok === true)).toBe(true);
  });
  for (const g of rows) {
    it(g.name, () => {
      const { op, ...req } = g.request;
      const r = askCore(op as string, req);
      const { id: _id, ...rest } = r ?? {};
      expect(rest).toEqual(g.response);
    });
  }
});

const sh = (cwd: string, ...a: string[]) => execFileSync("git", a, { cwd, encoding: "utf8" }).trim();
let dirs: string[] = [];
afterEach(() => { dirs.forEach((d) => rmSync(d, { recursive: true, force: true })); dirs = []; });

describe("added links read from git (temp repo)", () => {
  function repo() {
    const d = mkdtempSync(join(tmpdir(), "land-link-"));
    dirs.push(d);
    sh(d, "init", "-q", "-b", "main");
    sh(d, "config", "user.email", "t@example.invalid");
    sh(d, "config", "user.name", "t");
    sh(d, "config", "commit.gpgsign", "false");
    mkdirSync(join(d, "docs"));
    writeFileSync(join(d, "docs/file.md"), "x\n");
    symlinkSync("/etc", join(d, "old-abs"));
    sh(d, "add", "-A");
    sh(d, "commit", "-q", "-m", "base");
    sh(d, "checkout", "-q", "-b", "br");
    return d;
  }
  it("one escaping and one inside link: only the escaping one is refused; a link already on main is not checked", () => {
    const d = repo();
    mkdirSync(join(d, "a"));
    symlinkSync("../docs/file.md", join(d, "a/inside"));
    symlinkSync("../../scratch", join(d, "a/escape"));
    writeFileSync(join(d, "a/plain.txt"), "p\n");
    sh(d, "add", "-A");
    sh(d, "commit", "-q", "-m", "links");
    const added = addedLinks(d, "main", "br");
    expect(added).toEqual([{ path: "a/escape", target: "../../scratch" }, { path: "a/inside", target: "../docs/file.md" }]);
    expect(refusedLinks(added)).toEqual({ refused: [{ path: "a/escape", target: "../../scratch", reason: "escapes" }] });
    const msg = linkRefusal(d, "main", "br", "br");
    expect(msg).toContain("a/escape -> ../../scratch (escapes)");
    expect(msg).not.toContain("a/inside");
    expect(msg).not.toContain("old-abs");
  });
  it("an absolute link is refused; a branch with no links passes", () => {
    const d = repo();
    writeFileSync(join(d, "n.txt"), "n\n");
    sh(d, "add", "-A");
    sh(d, "commit", "-q", "-m", "plain");
    expect(linkRefusal(d, "main", "br", "br")).toBeNull();
    symlinkSync("/private/tmp/scratchpad", join(d, ".scr"));
    sh(d, "add", "-A");
    sh(d, "commit", "-q", "-m", "abs");
    expect(linkRefusal(d, "main", "br", "br")).toContain(".scr -> /private/tmp/scratchpad (absolute)");
  });
});

const text = (r: { lines: string[] }) => r.lines.join("\n");
describe("fw land --dry refuses an escaping added link", () => {
  it("VERDICT scope with a land-link line; an inside link lands", async () => {
    const { fx, wt, opts } = await setup();
    fx.commit(wt, "src/a.ts");
    symlinkSync("../../scratchpad", join(wt, "src/escape"));
    fx.git(wt, "add", "--", "src/escape");
    fx.git(wt, "commit", "-q", "-m", "escaping link");
    const dry = await land(BR, { ...opts, dry: true, dryReads: { argv: ["true"], selected: false } });
    expect(dry.ok).toBe(false);
    expect(dry.kind, text(dry)).toBe("scope");
    expect(dry.lines.find((l) => l.startsWith("REFUSED: land-link:")), text(dry)).toContain("src/escape -> ../../scratchpad (escapes)");
    fx.git(wt, "rm", "-q", "--", "src/escape");
    symlinkSync("a.ts", join(wt, "src/inside"));
    fx.git(wt, "add", "--", "src/inside");
    fx.git(wt, "commit", "-q", "-m", "inside link");
    const ok = await land(BR, { ...opts, dry: true, dryReads: { argv: ["true"], selected: false } });
    expect(ok.lines.some((l) => l.startsWith("REFUSED: land-link:")), text(ok)).toBe(false);
  });
});
