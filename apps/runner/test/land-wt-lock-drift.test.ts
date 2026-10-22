import "./land-timeout.ts";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createApp } from "../../console-api/src/app.ts";
import { selectCore } from "../../console-api/src/core/index.ts";
import { Reconciler } from "../../console-api/src/reconcile/reconciler.ts";
import { Store } from "../../console-api/src/store.ts";
import { makeRepo } from "../../console-api/test/reconcile-fixture.ts";
import { land, landInstall, landInstallStamped, realStampFs, STAMP_FILE, type Http, type InstallExec, type StampFs } from "../src/land.ts";
import { dryRun, exitCode, parseVerdict } from "../src/land-verdict.ts";

const OFFLINE = "pnpm install --offline --frozen-lockfile";
const ONLINE = "pnpm install --frozen-lockfile";
const memFs = (lock: string | null, stamp: string | null) => {
  const st = { stamp, writes: [] as string[] };
  const fs: StampFs = { lockHash: () => lock, readStamp: () => st.stamp, writeStamp: (_d, h) => { st.stamp = h; st.writes.push(h); } };
  return { st, fs };
};
const stub = (ok: (cmd: string) => boolean, tail = "") => {
  const calls: string[] = [];
  const exec: InstallExec = (argv) => { const c = argv.join(" "); calls.push(c); return ok(c) ? { ok: true } : { ok: false, tail }; };
  return { calls, exec };
};

describe("land worktree lockfile stamp (Lean installStep)", () => {
  it("a reused worktree behind main's lockfile installs, then stamps the new hash", () => {
    const m = memFs("L2", "L1");
    const s = stub(() => true);
    expect(landInstallStamped("/d", true, s.exec, m.fs)).toBeNull();
    expect(s.calls).toEqual([OFFLINE]);
    expect(m.st.stamp).toBe("L2");
  });
  it("a reused worktree whose stamp equals the lockfile does not install", () => {
    const m = memFs("L2", "L2");
    const s = stub(() => false);
    expect(landInstallStamped("/d", true, s.exec, m.fs)).toBeNull();
    expect(s.calls).toEqual([]);
    expect(m.st.writes).toEqual([]);
  });
  it("a reused worktree without a stamp installs; a new worktree installs whatever the stamp", () => {
    const a = stub(() => true), b = stub(() => true);
    expect(landInstallStamped("/d", true, a.exec, memFs("L2", null).fs)).toBeNull();
    expect(landInstallStamped("/d", false, b.exec, memFs("L2", "L2").fs)).toBeNull();
    expect(a.calls).toEqual([OFFLINE]);
    expect(b.calls).toEqual([OFFLINE]);
  });
  it("offline fails, online ok: stamps after the online install", () => {
    const m = memFs("L2", "L1");
    const s = stub((c) => c === ONLINE);
    expect(landInstallStamped("/d", true, s.exec, m.fs)).toBeNull();
    expect(s.calls).toEqual([OFFLINE, ONLINE]);
    expect(m.st.stamp).toBe("L2");
  });
  it("both fail: refuses, never writes the stamp, and the next land installs again", () => {
    const m = memFs("L2", "L1");
    const s = stub(() => false, "ERR_PNPM_NO_OFFLINE_TARBALL");
    const why = landInstallStamped("/d", true, s.exec, m.fs);
    expect(why).toContain("install failed in /d");
    expect(m.st.stamp).toBe("L1");
    expect(m.st.writes).toEqual([]);
    const again = stub(() => true);
    expect(landInstallStamped("/d", true, again.exec, m.fs)).toBeNull();
    expect(again.calls).toEqual([OFFLINE]);
    expect(m.st.stamp).toBe("L2");
  });
  it("no lockfile: nothing to install, no stamp written", () => {
    const m = memFs(null, null);
    const s = stub(() => false);
    expect(landInstallStamped("/d", false, s.exec, m.fs)).toBeNull();
    expect(s.calls).toEqual([]);
  });
  it("the REFUSED reason carries the stderr tail of both attempts", () => {
    const why = landInstall("/d", (argv) => ({ ok: false, tail: argv.includes("--offline") ? "offline boom" : "online boom" }))!;
    expect(why).toContain("offline stderr: offline boom");
    expect(why).toContain("online stderr: online boom");
  });
  it("the real stamp fs hashes the lockfile and keeps the stamp inside node_modules", () => {
    const dir = mkdtempSync(join(tmpdir(), "fw-stamp-"));
    try {
      expect(realStampFs.lockHash(dir)).toBeNull();
      writeFileSync(join(dir, "pnpm-lock.yaml"), "a");
      const h = realStampFs.lockHash(dir)!;
      expect(h).toMatch(/^[0-9a-f]{64}$/);
      expect(realStampFs.readStamp(dir)).toBeNull();
      realStampFs.writeStamp(dir, h);
      expect(readFileSync(join(dir, STAMP_FILE), "utf8").trim()).toBe(h);
      expect(realStampFs.readStamp(dir)).toBe(h);
    } finally { rmSync(dir, { recursive: true, force: true }); }
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
  const writes = ["src/**"];
  await store.submit({ type: "task.define", key: "d", actor: "lead", task: "t1", title: "t", stream: "s", milestone: null, deps: [], owner: "builder", writes, devices: [], evidence: null } as never);
  mkdirSync(join(fx.root, "docs/team"), { recursive: true });
  writeFileSync(join(fx.root, "docs/team/work-graph.json"), JSON.stringify({ tasks: [{ id: "t1", owner: "builder", stream: "s", writes, evidence: null }] }, null, 1) + "\n");
  fx.git(fx.root, "add", "--", "docs/team/work-graph.json");
  fx.git(fx.root, "commit", "-q", "-m", "work graph");
  fx.commit(fx.root, "pnpm-lock.yaml", "lock v1\n");
  const wt = fx.worktree(BR);
  fx.commit(wt, "src/a.ts");
  return { fx, http };
}

describe("land() through the install step (inc-land-wt-lock-drift, land-install-fallback follow-up)", () => {
  it("dry land, both installs fail: VERDICT install, exit 19, the stderr tail in the REFUSED line, outcome has the install stage", async () => {
    const { fx, http } = await setup();
    const calls: string[] = [];
    const installExec: InstallExec = (argv) => { calls.push(argv.join(" ")); return { ok: false, tail: "ERR_PNPM_FETCH_404 no network" }; };
    const r = await land(BR, { http, cwd: fx.root, ci: false, task: "t1", dry: true, retryMs: 1, lockWaitMs: 0, installExec });
    expect(calls).toEqual([OFFLINE, ONLINE]);
    expect(r.ok).toBe(false);
    expect(r.kind).toBe("install");
    const text = r.lines.join("\n");
    expect(text).toMatch(/REFUSED: install failed in .*both failed/);
    expect(text).toContain("online stderr: ERR_PNPM_FETCH_404 no network");
    expect(r.outcome?.installs).toBe(false);
    const out = dryRun(r.outcome!, "t1");
    expect(out.at(-1)).toBe("VERDICT install t1");
    expect(out).toContain("dry: conflict ok");
    expect(out).not.toContain("dry: install ok");
    expect(parseVerdict(out.join("\n"))?.kind).toBe("install");
    expect(exitCode("install")).toBe(19);
  });
  it("real land, both installs fail: refused with kind install before any check runs", async () => {
    const { fx, http } = await setup();
    const installExec: InstallExec = () => ({ ok: false, tail: "boom" });
    const r = await land(BR, { http, cwd: fx.root, ci: false, task: "t1", retryMs: 1, lockWaitMs: 0, installExec, retries: 0 });
    expect(r.ok).toBe(false);
    expect(r.kind).toBe("install");
    expect(r.lines.join("\n")).toContain("offline stderr: boom");
    expect(existsSync(fx.root)).toBe(true);
  });
  it("a later land in the reused worktree installs again when main's lockfile moved past the stamp", async () => {
    const { fx, http } = await setup();
    const calls: string[] = [];
    const stamps = new Map<string, string>();
    const installFs: StampFs = {
      lockHash: (d) => { try { return readFileSync(join(d, "pnpm-lock.yaml"), "utf8").trim(); } catch { return null; } },
      readStamp: (d) => stamps.get(d) ?? null,
      writeStamp: (d, h) => { stamps.set(d, h); },
    };
    const installExec: InstallExec = (argv) => { calls.push(argv.join(" ")); return { ok: true }; };
    const base = { http, cwd: fx.root, ci: false as const, task: "t1", dry: true, retryMs: 1, lockWaitMs: 0, installExec, installFs };
    await land(BR, base);
    expect(calls).toEqual([OFFLINE]);
    expect([...stamps.values()]).toEqual(["lock v1"]);
    await land(BR, base);
    expect(calls).toEqual([OFFLINE]);
    fx.commit(fx.root, "pnpm-lock.yaml", "lock v2\n");
    await land(BR, base);
    expect(calls).toEqual([OFFLINE, OFFLINE]);
    expect([...stamps.values()]).toEqual(["lock v2"]);
  });
});
