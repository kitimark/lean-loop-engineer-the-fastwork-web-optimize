import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync, existsSync } from "node:fs";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { createApp } from "../src/app.ts";
import { selectCore } from "../src/core/index.ts";
import { Store } from "../src/store.ts";
import { CapStore } from "../src/cap/cap.ts";
import { PreviewManager, defaultHooks, type Hooks } from "../src/preview/manager.ts";
import { branchOfHandoff, partsOf } from "../src/preview/facts.ts";
import { safeFile } from "../src/preview/serve-child.ts";

const tmp = (p: string) => mkdtempSync(join(tmpdir(), p));
const alive = (pid: number) => { try { process.kill(pid, 0); return true; } catch { return false; } };
const sh = (cwd: string, ...a: string[]) => execFileSync("git", a, { cwd, stdio: ["ignore", "pipe", "ignore"] }).toString().trim();

let stores: Store[] = [];
let mgrs: PreviewManager[] = [];
afterEach(async () => {
  for (const m of mgrs) await m.shutdown().catch(() => undefined);
  mgrs = [];
  stores.forEach((s) => s.close()); stores = [];
});

/** a repo with main, a landed task, an integration-only task and an unintegrated task */
function repo() {
  const root = tmp("fw-pv-repo-");
  sh(root, "init", "-q", "-b", "main");
  sh(root, "config", "user.email", ["t", "example.test"].join("\x40")); sh(root, "config", "user.name", "t");
  mkdirSync(join(root, "docs/team/handoffs"), { recursive: true });
  mkdirSync(join(root, "snapshot/site"), { recursive: true });
  writeFileSync(join(root, "snapshot/site/index.html"), "<h1>original</h1>");
  writeFileSync(join(root, "snapshot/site/analytics.js"), "alert(1)");
  writeFileSync(join(root, "docs/team/work-graph.json"), JSON.stringify({ tasks: [
    { id: "port-landed", title: "landed", deps: [], owner: "o", writes: ["apps/site/src/parts/nav/**"] },
    { id: "port-integ", title: "integrated", deps: ["port-landed"], owner: "o", writes: ["apps/site/src/parts/hero/**", "apps/site/src/parts/hero.orbit/**"] },
    { id: "fix-own", title: "unintegrated", deps: [], owner: "o", writes: [] },
    { id: "fix-none", title: "no work", deps: [], owner: "o", writes: [] }] }));
  sh(root, "add", "-A"); sh(root, "commit", "-qm", "base");
  sh(root, "branch", "ci/port-landed"); // at main already
  sh(root, "checkout", "-qb", "integrate-ports-9");
  writeFileSync(join(root, "a.txt"), "1"); sh(root, "add", "-A"); sh(root, "commit", "-qm", "port-integ work");
  sh(root, "branch", "ci/port-integ");
  sh(root, "checkout", "-q", "main");
  sh(root, "checkout", "-qb", "ci/fix-own");
  writeFileSync(join(root, "b.txt"), "1"); sh(root, "add", "-A"); sh(root, "commit", "-qm", "fix-own work");
  sh(root, "checkout", "-q", "main");
  return root;
}

/** build = a tiny rewrite dist and the snapshot, no pnpm: the I/O under test is the server and the kill */
function stubHooks(root: string, dir: string, clock: { t: number }, disk = { mb: 99999 }): Hooks {
  const real = defaultHooks(root, dir);
  return {
    ...real,
    async build(e) {
      mkdirSync(join(e.tree, "apps/site/dist/aot"), { recursive: true });
      mkdirSync(join(e.tree, "snapshot/site"), { recursive: true });
      writeFileSync(join(e.tree, "apps/site/dist/aot/index.html"), `<h1>rewrite ${e.target.sha}</h1>`);
      writeFileSync(join(e.tree, "apps/site/dist/aot/configs.json"), JSON.stringify({ bySearch: { "?fw=x:y": "h" }, byHash: { h: "c/h.html" } }));
      mkdirSync(join(e.tree, "apps/site/dist/aot/c"), { recursive: true });
      writeFileSync(join(e.tree, "apps/site/dist/aot/c/h.html"), "<h1>variant</h1>");
      writeFileSync(join(e.tree, "snapshot/site/index.html"), "<h1>original</h1>");
      writeFileSync(join(e.tree, "snapshot/site/analytics.js"), "alert(1)");
      writeFileSync(join(e.tree, "snapshot/site/pic.png"), "PNG");
    },
    removeTree(e) { rmSync(join(dir, "preview", e.id), { recursive: true, force: true }); },
    diskMb: () => disk.mb,
    now: () => clock.t,
  };
}

async function setup(opts: { disk?: { mb: number } } = {}) {
  const root = repo();
  const dir = join(root, ".fw-console");
  const store = await Store.open(dir, selectCore());
  stores.push(store);
  new CapStore(dir).ensureSecret();
  const clock = { t: 1_000_000 };
  const pm = new PreviewManager(root, dir, store.core, stubHooks(root, dir, clock, opts.disk));
  mgrs.push(pm);
  return { root, dir, store, pm, clock, secret: readFileSync(join(dir, "secret"), "utf8").trim() };
}

describe("PreviewManager (Lean console.preview* decisions, real server child)", () => {
  it("target: landed -> main, integrated only -> integration ref, unintegrated -> own head, no work -> none", async () => {
    const { pm } = await setup();
    expect((await pm.target("port-landed")).kind).toBe("main");
    const i = await pm.target("port-integ");
    expect(i.kind).toBe("integration");
    expect(i.ref).toBe("integrate-ports-9");
    const o = await pm.target("fix-own");
    expect(o.kind).toBe("own");
    expect((await pm.target("fix-none")).kind).toBe("none");
  });

  it("starts a preview: two servers on distinct loopback ports, the snapshot media fallback, analytics stubbed; stop kills the group", async () => {
    const { pm, dir } = await setup();
    const r = await pm.start("port-landed", "user");
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    await pm.settled(r.id);
    const [p] = pm.list().previews;
    expect(p!.phase).toBe("serving");
    expect(new Set([p!.rp, p!.op]).size).toBe(2);
    const rw = await fetch(`http://127.0.0.1:${p!.rp}/`); expect(await rw.text()).toContain("rewrite");
    expect(rw.headers.get("cache-control")).toBe("no-store");
    expect(await (await fetch(`http://127.0.0.1:${p!.rp}/?fw=x:y`)).text()).toContain("variant");
    expect(await (await fetch(`http://127.0.0.1:${p!.rp}/pic.png`)).text()).toBe("PNG"); // media from the snapshot
    expect((await fetch(`http://127.0.0.1:${p!.rp}/analytics.js`)).status).toBe(200);
    expect(await (await fetch(`http://127.0.0.1:${p!.op}/analytics.js`)).text()).toBe(""); // GTM loader stubbed
    expect(await (await fetch(`http://127.0.0.1:${p!.op}/`)).text()).toContain("original");
    expect((await fetch(`http://127.0.0.1:${p!.op}/`, { method: "POST" })).status).toBe(405);
    expect((await fetch(`http://127.0.0.1:${p!.rp}/__fw/compare`)).status).toBe(200);
    expect((await fetch(`http://127.0.0.1:${p!.rp}/..%2f..%2fetc/passwd`)).status).toBe(404);
    const pid = p!.pid!;
    expect(alive(pid)).toBe(true);
    expect(await pm.stop(r.id, "user")).toEqual({ ok: true, reason: null });
    await new Promise((res) => setTimeout(res, 300));
    expect(alive(pid)).toBe(false);
    expect(pm.list().previews).toEqual([]);
    expect(existsSync(join(dir, "preview", r.id))).toBe(false);
    await expect(fetch(`http://127.0.0.1:${p!.rp}/`)).rejects.toThrow();
  });

  it("agents are refused (lead, owner, reviewer); K = 2; same task twice; low disk; no target", async () => {
    const disk = { mb: 99999 };
    const { pm } = await setup({ disk });
    for (const a of ["lead", "owner", "reviewer"]) expect(await pm.start("port-landed", a)).toEqual({ ok: false, reason: "notOwner" });
    expect(pm.list().previews).toEqual([]);
    const a = await pm.start("port-landed", "user"); expect(a.ok).toBe(true);
    expect(await pm.start("port-landed", "user")).toEqual({ ok: false, reason: "taskBusy" });
    const b = await pm.start("fix-own", "user"); expect(b.ok).toBe(true);
    expect(await pm.start("port-integ", "user")).toEqual({ ok: false, reason: "tooMany" });
    const ports = pm.list().previews.flatMap((p) => [p.rp, p.op]);
    expect(new Set(ports).size).toBe(4);
    if (a.ok) await pm.settled(a.id); if (b.ok) await pm.settled(b.id);
    await pm.shutdown();
    disk.mb = 10;
    expect(await pm.start("port-landed", "user")).toEqual({ ok: false, reason: "lowDisk" });
    disk.mb = 99999;
    expect(await pm.start("fix-none", "user")).toEqual({ ok: false, reason: "noTarget" });
  });

  it("tick stops every preview past its TTL (and only those); stop of an unknown id kills nothing", async () => {
    const { pm, clock } = await setup();
    const a = await pm.start("port-landed", "user");
    if (!a.ok) throw new Error("start");
    await pm.settled(a.id);
    const pid = pm.list().previews[0]!.pid!;
    clock.t += 59 * 60_000;
    expect(await pm.tick()).toEqual([]);
    expect(await pm.stop("nope", "user")).toEqual({ ok: false, reason: "unknown" });
    expect(alive(pid)).toBe(true);
    clock.t += 2 * 60_000;
    expect(await pm.tick()).toEqual([a.id]);
    await new Promise((res) => setTimeout(res, 300));
    expect(alive(pid)).toBe(false);
    expect(pm.list().previews).toEqual([]);
  });

  it("a failed build frees the slot and reports the error", async () => {
    const root = repo(); const dir = join(root, ".fw-console");
    const store = await Store.open(dir, selectCore()); stores.push(store);
    const hooks = { ...stubHooks(root, dir, { t: 5 }), build: async () => { throw new Error("pnpm install exited 1"); } };
    const pm = new PreviewManager(root, dir, store.core, hooks); mgrs.push(pm);
    const r = await pm.start("port-landed", "user");
    if (!r.ok) throw new Error("start");
    await pm.settled(r.id);
    await pm.stop("x", "user"); // drains the serial queue
    expect(pm.list().previews).toEqual([]);
    expect(pm.list().failed[0]?.error).toContain("pnpm install exited 1");
  });

  it("reapRecorded stops a previous run's recorded process group, verified by its command line", async () => {
    const { pm, dir, root, store, clock } = await setup();
    const a = await pm.start("port-landed", "user");
    if (!a.ok) throw new Error("start");
    await pm.settled(a.id);
    const pid = pm.list().previews[0]!.pid!;
    // a new console process: a fresh manager reading the same table
    const pm2 = new PreviewManager(root, dir, store.core, stubHooks(root, dir, clock));
    expect(await pm2.reapRecorded()).toEqual([a.id]);
    await new Promise((res) => setTimeout(res, 300));
    expect(alive(pid)).toBe(false);
  });
});

describe("routes", () => {
  it("detail: parts, git facts, handoff, preview target; unknown task 404; bad id 400", async () => {
    const { pm, store, root } = await setup();
    writeFileSync(join(root, "docs/team/handoffs/port-integ.md"), "Branch `ci/port-integ` at abc\nline 2\n");
    sh(root, "add", "-A"); sh(root, "commit", "-qm", "handoff");
    const app = createApp(store, undefined, undefined, pm);
    const d = await (await app.request("/api/tasks/port-integ/detail")).json() as any;
    expect(d.kind).toBe("port");
    expect(d.parts).toEqual(["hero", "hero.orbit"]);
    expect(d.git.branch).toBe("ci/port-integ");
    expect(d.git.headSource).toBe("handoff branch line");
    expect(d.handoff.excerpt).toContain("Branch");
    expect(d.preview.target.kind).toBe("integration");
    expect((await app.request("/api/tasks/nope-x/detail")).status).toBe(404);
    expect((await app.request("/api/tasks/Bad%20id/detail")).status).toBe(400);
    const none = await (await app.request("/api/tasks/fix-none/detail")).json() as any;
    expect(none.preview.target.kind).toBe("none");
  });

  it("start: the browser (no secret) is the user; a caller with the console secret is stamped lead and refused; foreign Origin and non-JSON are refused", async () => {
    const { pm, store, secret } = await setup();
    const app = createApp(store, undefined, undefined, pm);
    const post = (body: unknown, h: Record<string, string> = {}) =>
      app.request("/api/previews", { method: "POST", body: JSON.stringify(body), headers: { "content-type": "application/json", ...h } });
    const asLead = await post({ task: "port-landed" }, { "x-fw-secret": secret });
    expect(asLead.status).toBe(403);
    expect(await asLead.json()).toEqual({ ok: false, reason: "notOwner" });
    expect((await post({ task: "port-landed", actor: "user" }, { "x-fw-secret": secret })).status).toBe(403); // the body cannot claim user
    expect((await post({ task: "port-landed" }, { origin: "https://evil.example" })).status).toBe(403);
    expect((await app.request("/api/previews", { method: "POST", body: "{\"task\":\"port-landed\"}" })).status).toBe(403);
    expect((await post({ task: "../x" })).status).toBe(400);
    const ok = await post({ task: "port-landed" }, { origin: "http://localhost:5173" });
    expect(ok.status).toBe(202);
    const { id } = await ok.json() as { id: string };
    await pm.settled(id);
    const list = await (await app.request("/api/previews")).json() as any;
    expect(list.previews[0].phase).toBe("serving");
    const stopLead = await app.request(`/api/previews/${id}/stop`, { method: "POST", headers: { "content-type": "application/json", "x-fw-secret": secret } });
    expect(stopLead.status).toBe(403);
    const stop = await app.request(`/api/previews/${id}/stop`, { method: "POST", headers: { "content-type": "application/json" } });
    expect(stop.status).toBe(200);
    expect((await (await app.request("/api/previews")).json() as any).previews).toEqual([]);
  });
});

describe("helpers", () => {
  it("branchOfHandoff / partsOf / safeFile", () => {
    expect(branchOfHandoff("# x\nBranch `worktree-agent-af532f9c9a68e864f` (deleted)")).toBe("worktree-agent-af532f9c9a68e864f");
    expect(branchOfHandoff("no branch here")).toBeNull();
    expect(partsOf(["apps/site/src/parts/nav/**", "apps/site/src/parts/nav.langMenu/**", "lean/Fw/x.lean"])).toEqual(["nav", "nav.langMenu"]);
    const root = tmp("fw-pv-safe-");
    writeFileSync(join(root, "a.txt"), "x");
    expect(safeFile(root, "/a.txt")).toBe(join(root, "a.txt"));
    writeFileSync(join(root, "../fw-pv-outside.txt"), "x");
    expect(safeFile(root, "/../fw-pv-outside.txt")).toBeNull(); // normalised inside the root, where it does not exist
    expect(safeFile(root, "/a.txt/../../fw-pv-outside.txt")).toBeNull();
    expect(safeFile(root, "/%2e%2e/%2e%2e/fw-pv-outside.txt")).toBeNull();
    expect(safeFile(root, "/a%00.txt")).toBeNull();
  });
  it("ports for the child are free to bind (sanity for the test machine)", async () => {
    const free = await new Promise<number>((res) => { const s = createServer().listen(0, "127.0.0.1", () => { const p = (s.address() as { port: number }).port; s.close(() => res(p)); }); });
    expect(free).toBeGreaterThan(0);
  });
});
