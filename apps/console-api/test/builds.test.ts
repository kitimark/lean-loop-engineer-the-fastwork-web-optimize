import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it } from "vitest";
import { createApp } from "../src/app.ts";
import { selectCore } from "../src/core/index.ts";
import { Store } from "../src/store.ts";
import { CapStore } from "../src/cap/cap.ts";
import { PreviewManager, defaultHooks, type Hooks } from "../src/preview/manager.ts";
import { OwnerAuth } from "../src/preview/owner.ts";
import { gitIn } from "../src/preview/facts.ts";
import { buildRows, evidenceLands, workGraphTasks, readFlags, readPresets, rowAt } from "../src/preview/builds.ts";
import { choose, picker } from "../src/preview/picker.ts";
import { handler } from "../src/preview/serve-child.ts";

/** Its own port range: preview.test.ts uses 47300-47339. */
const TEST_BASE = 47340;
const GOLDEN = join(dirname(fileURLToPath(import.meta.url)), "../../../packages/contracts/golden/console");
const golden = (op: string) => readFileSync(join(GOLDEN, `${op}.jsonl`), "utf8").trim().split("\n")
  .map((l) => JSON.parse(l) as { name: string; request: Record<string, unknown>; response: Record<string, unknown> });
const pickerOf = (h: string) => h.slice(h.indexOf("<select id=s>"), h.indexOf("</select>"));
const tmp = (p: string) => mkdtempSync(join(tmpdir(), p));
const sh = (cwd: string, ...a: string[]) => execFileSync("git", a, { cwd, stdio: ["ignore", "pipe", "ignore"] }).toString().trim();

let stores: Store[] = [];
let mgrs: PreviewManager[] = [];
let servers: Server[] = [];
afterEach(async () => {
  for (const m of mgrs) await m.shutdown().catch(() => undefined);
  mgrs = [];
  stores.forEach((s) => s.close()); stores = [];
  servers.forEach((s) => s.close()); servers = [];
});

describe("picker: the TS stand-in equals the Lean golden (console.buildsPicker)", () => {
  const cases = golden("console.buildsPicker").filter((c) => c.response.error === undefined);
  it("has cases", () => expect(cases.length).toBeGreaterThan(5));
  for (const c of cases) {
    it(c.name, () => {
      const keys = (c.request.keys as string[] | undefined) ?? [];
      expect({ searches: picker(keys), current: choose(keys, (c.request.current as string | undefined) ?? "") }).toEqual(c.response);
    });
  }
});

describe("compare page picker", () => {
  const compare = async (configs: unknown, search: string) => {
    const root = tmp("fw-cmp-");
    writeFileSync(join(root, "configs.json"), JSON.stringify(configs));
    const srv = createServer(handler({ root, prerendered: true, compare: { rp: 1, op: 2 } }));
    servers.push(srv);
    const port = await new Promise<number>((r) => srv.listen(0, "127.0.0.1", () => r((srv.address() as AddressInfo).port)));
    const t = await (await fetch(`http://127.0.0.1:${port}/__fw/compare${search}`)).text();
    rmSync(root, { recursive: true, force: true });
    return t;
  };
  const configs = { bySearch: { "": "a", "?preset=original": "a", "?fw=hero:x,y:z": "b", "?fw=a\"b": "c", "?other=1": "d" }, byHash: {} };

  it("lists exactly the prerendered default, preset and flag searches, and opens the requested one", async () => {
    const html = await compare(configs, "?fw=hero:x,y:z");
    expect(pickerOf(html).match(/<option value="([^"]*)"/g)).toEqual(['<option value=""', '<option value="?preset=original"', '<option value="?fw=hero:x,y:z"']);
    expect(html).toContain('<option value="?fw=hero:x,y:z" selected>');
    expect(html).toContain(`getElementById('b').src=at(1,"?fw=hero:x,y:z")`); // the task arm's own origin (its port) with the search
    expect(html).toContain(`getElementById('a').src=at(2,'')`); // the original has no search
  });
  it("a search that is not prerendered, or not well formed, opens the default and is never written into the page", async () => {
    for (const bad of ["?fw=zzz", "?preset=%22%3E%3Cscript%3E", "?fw=a%22b"]) {
      const html = await compare(configs, bad);
      expect(html).toContain(`getElementById('b').src=at(1,"")`);
      expect(html).not.toContain("<script>alert");
      expect(html).not.toContain('a"b');
    }
  });
  it("a build with one prerendered page has no picker", async () => {
    expect(await compare({ bySearch: { "": "a" }, byHash: {} }, "")).not.toContain("<select id=s>");
  });
});

/** main with two landed tasks (a port and a fix), one landed twice, and an unlanded one; a tiny site registry */
function repo() {
  const root = tmp("fw-builds-repo-");
  sh(root, "init", "-q", "-b", "main");
  sh(root, "config", "user.email", ["t", "example.test"].join("\x40")); sh(root, "config", "user.name", "t");
  mkdirSync(join(root, "docs/team"), { recursive: true });
  mkdirSync(join(root, "snapshot/site"), { recursive: true });
  const part = (id: string, variants: Record<string, { kind: string }>, requires: Record<string, string[]> = {}) => {
    mkdirSync(join(root, "apps/site/src/parts", id), { recursive: true });
    writeFileSync(join(root, "apps/site/src/parts", id, "part.json"), JSON.stringify({ id, variants, requires, conflicts: {} }));
  };
  part("hero", { faithful: { kind: "faithful" }, strip: { kind: "optimized" } });
  part("nav", { faithful: { kind: "faithful" }, skip: { kind: "optimized" } }, { "nav:skip": ["hero:strip"] });
  mkdirSync(join(root, "apps/site/src/registry/presets"), { recursive: true });
  writeFileSync(join(root, "apps/site/src/registry/presets/original.json"), JSON.stringify({ name: "original", fw: { hero: "strip" } }));
  writeFileSync(join(root, "apps/site/src/registry/presets/v2-proved.json"), JSON.stringify({ extends: "original", name: "v2-proved", fw: { nav: "skip" } }));
  sh(root, "add", "-A"); sh(root, "commit", "-qm", "base");
  const at = (time: number) => ({ ...process.env, GIT_COMMITTER_DATE: `@${time} +0000`, GIT_AUTHOR_DATE: `@${time} +0000` });
  const land = (msg: string, time: number) => {
    writeFileSync(join(root, `f${time}.txt`), "1"); sh(root, "add", "-A");
    execFileSync("git", ["commit", "-qm", msg], { cwd: root, env: at(time) });
    return sh(root, "rev-parse", "HEAD");
  };
  const a = land("land hero\n\nTask: port-hero", 1000);
  // port-old: no trailer; its work is a side-branch commit merged into main at M (evidence is not on the first-parent line)
  sh(root, "checkout", "-q", "-b", "side");
  const x = land("old work on a side branch", 1200);
  sh(root, "checkout", "-q", "main");
  execFileSync("git", ["merge", "--no-ff", "-qm", "merge side", "side"], { cwd: root, env: at(1500), stdio: "ignore" });
  const m = sh(root, "rev-parse", "HEAD");
  const b = land("land nav\n\nTask: fix-nav", 2000);
  // fix-old: no trailer; its evidence commit is on main's first-parent line
  const d = land("old fix straight on main", 2500);
  const c = land("land proof\n\nTask: proof-x", 3000);
  writeFileSync(join(root, "docs/team/work-graph.json"), JSON.stringify({ tasks: [
    { id: "port-hero", title: "hero port", evidence: `${a.slice(0, 7)}: trailer wins` }, { id: "fix-nav", title: "nav fix" }, { id: "port-later", title: "later" },
    { id: "proof-x", title: "proof" }, { id: "port-old", title: "old port", evidence: `gate 39184687325 pass; ${x.slice(0, 7)}: on main via merge` },
    { id: "fix-old", title: "old fix", evidence: `${d.slice(0, 7)}: on main` }, { id: "port-gone", title: "gone", evidence: "deadbee: lost" }] }));
  sh(root, "add", "-A"); sh(root, "commit", "-qm", "graph");
  return { root, a, b, c, d, m, x };
}

describe("buildRows (Lean console.builds over the gathered facts)", () => {
  it("port rows: landed port and fix tasks, newest first, each at its land commit; optimize rows: presets then every variant", async () => {
    const { root, a, b, d, m } = repo();
    const core = selectCore();
    try {
      const r = await buildRows(root, core);
      expect(r.ports.map((p) => [p.task, p.sha, p.landedAt, p.title, p.group])).toEqual([["fix-old", d, 2500, "old fix", "fix"], ["fix-nav", b, 2000, "nav fix", "fix"], ["port-old", m, 1500, "old port", "port"], ["port-hero", a, 1000, "hero port", "port"]]);
      expect(r.ports.map((p) => p.slot)).toEqual(["land-fix-old", "land-fix-nav", "land-port-old", "land-port-hero"]);
      expect(evidenceLands(workGraphTasks(root), gitIn(root)).missing.sort()).toEqual(["fix-nav", "port-gone", "port-later"]);
      for (const p of r.ports) expect(p.target).toEqual({ kind: "main", ref: "main", sha: p.sha });
      expect(r.optimize.map((o) => [o.id, o.search, o.status])).toEqual([
        ["preset:original", "?preset=original", "preset"], ["preset:v2-proved", "?preset=v2-proved", "the v2-proved preset"],
        ["flag:hero:faithful", "?fw=hero:faithful", "baseline"], ["flag:hero:strip", "?fw=hero:strip", "v2-proved"],
        ["flag:nav:faithful", "?fw=nav:faithful", "baseline"], ["flag:nav:skip", "?fw=nav:skip,hero:strip", "v2-proved"]]);
      for (const o of r.optimize) { expect(o.target.sha).toBe(r.mainSha); expect(r.searches).toContain(o.search); }
      expect(r.searches[0]).toBe("");
      expect(readFlags(root).length).toBe(4);
      expect(readPresets(root).map((p) => p.name)).toEqual(["original", "v2-proved"]);
      expect(rowAt(r, "port:port-hero")).toEqual({ slot: "land-port-hero", target: { kind: "main", ref: "main", sha: a }, search: "" });
      expect(rowAt(r, "flag:nav:skip")?.search).toBe("?fw=nav:skip,hero:strip");
      expect(rowAt(r, "port:port-later")).toBeNull();
      expect(rowAt(r, "port:proof-x")).toBeNull();
    } finally { core.close(); rmSync(root, { recursive: true, force: true }); }
  });

  it("the real site registry: every row's search is prerendered, hero.countdown:strip is out (C3), the v2-proved preset is a row", async () => {
    const root = join(dirname(fileURLToPath(import.meta.url)), "../../..");
    const core = selectCore();
    try {
      const r = await buildRows(root, core);
      expect(r.optimize.length).toBe(readPresets(root).length + readFlags(root).length);
      for (const o of r.optimize) expect(r.searches).toContain(o.search);
      expect(r.optimize.find((o) => o.id === "preset:v2-proved")?.status).toBe("the v2-proved preset");
      const c3 = r.optimize.find((o) => o.id === "flag:hero.countdown:strip")!;
      expect(c3.status).toBe("out of v2-proved (C3)");
      expect(c3.note).toContain("C3");
      const v2 = readPresets(root).find((p) => p.name === "v2-proved")!;
      expect(r.optimize.filter((o) => o.status === "v2-proved").length).toBe(Object.keys(v2.fw).length);
    } finally { core.close(); }
  });
});

describe("Builds routes and the manager", () => {
  async function setup() {
    const { root, a } = repo();
    const dir = join(root, ".fw-console");
    const store = await Store.open(dir, selectCore()); stores.push(store);
    new CapStore(dir).ensureSecret();
    const real = defaultHooks(root, dir);
    const hooks: Hooks = {
      ...real,
      async build(e) {
        mkdirSync(join(e.tree, "apps/site/dist/aot"), { recursive: true });
        mkdirSync(join(e.tree, "snapshot/site"), { recursive: true });
        writeFileSync(join(e.tree, "apps/site/dist/aot/index.html"), `<h1>rewrite ${e.target.sha}</h1>`);
        writeFileSync(join(e.tree, "apps/site/dist/aot/configs.json"), JSON.stringify({ bySearch: { "": "d", "?preset=original": "d", "?fw=hero:strip,nav:skip": "h" }, byHash: {} }));
        writeFileSync(join(e.tree, "snapshot/site/index.html"), "<h1>original</h1>");
      },
      removeTree(e) { rmSync(join(dir, "preview", e.id), { recursive: true, force: true }); },
    };
    const pm = new PreviewManager(root, dir, store.core, hooks, { portBase: TEST_BASE }); mgrs.push(pm);
    const owner = new OwnerAuth(["http://127.0.0.1:5173"]); owner.setPorts(4000, 4001);
    const app = createApp(store, undefined, undefined, pm, owner);
    const H = "127.0.0.1:4000"; const O = `http://${H}`;
    const link = await app.request(`/owner?t=${owner.token()}`);
    const authorization = `Bearer ${link.headers.get("location")!.slice("/#owner=".length)}`;
    const post = (body: unknown, h: Record<string, string> = { authorization, origin: O }) =>
      app.request("/api/previews", { method: "POST", body: JSON.stringify(body), headers: { "content-type": "application/json", host: H, ...h } });
    return { app, pm, post, root, a, H, authorization, owner, O };
  }

  it("GET /api/builds lists the rows; a port row's Preview builds main at its land commit; a flag row opens at its search", async () => {
    const { app, pm, post, a } = await setup();
    const j = await (await app.request("/api/builds")).json() as any;
    expect(j.ok).toBe(true);
    expect(j.ports.map((p: any) => p.id)).toEqual(["port:fix-old", "port:fix-nav", "port:port-old", "port:port-hero"]);
    const r1 = await post({ build: "port:port-hero" });
    expect(r1.status).toBe(202);
    const { id: id1 } = await r1.json() as { id: string };
    await pm.settled(id1);
    const e1 = pm.list().previews.find((p) => p.id === id1)!;
    expect(e1.task).toBe("land-port-hero");
    expect(e1.target).toEqual({ kind: "main", ref: "main", sha: a });
    expect(e1.search).toBe("");
    const r2 = await post({ build: "flag:nav:skip" });
    expect(r2.status).toBe(202);
    const { id: id2 } = await r2.json() as { id: string };
    await pm.settled(id2);
    const e2 = pm.list().previews.find((p) => p.id === id2)!;
    expect(e2.search).toBe("?fw=nav:skip,hero:strip");
    expect(e2.target.sha).toBe(j.mainSha);
    expect(e2.phase).toBe("serving");
    const html = await (await fetch(`http://127.0.0.1:${e2.brp}/__fw/compare${e2.search}`)).text();
    expect(html).toContain('<option value="?fw=hero:strip,nav:skip" selected>');
    expect(pickerOf(html).match(/<option value="/g)?.length).toBe(3);
  });

  it("refusals: an unknown row is 404, a body that names a sha or search is not a request, a non-owner is 403", async () => {
    const { post, pm } = await setup();
    expect((await post({ build: "port:port-later" })).status).toBe(404); // not landed
    expect((await post({ build: "flag:nav:nope" })).status).toBe(404);
    expect((await post({ build: "port:port-hero", sha: "abc", search: "?fw=x" })).status).toBe(202); // extra keys are ignored: the row decides
    expect((await post({ build: "port:fix-nav" }, {})).status).toBe(403);
    expect((await post({ sha: "abc" })).status).toBe(400);
    expect(pm.list().previews.length).toBe(1);
    expect(pm.list().previews[0]!.search).toBe("");
  });

  describe("POST /api/builds/open (Lean console.buildsOpen, console.buildsSearch)", () => {
    const J = { "content-type": "application/json" };
    async function rig() {
      const t = await setup();
      const open = (body: unknown, h?: Record<string, string>) =>
        t.app.request("/api/builds/open", { method: "POST", body: JSON.stringify(body), headers: { ...J, host: t.H, ...(h ?? { authorization: t.authorization, origin: t.O }) } });
      return { ...t, open };
    }

    it("a row starts its build (202 pending), never a second one, then opens with a path and no token", async () => {
      const { open, pm, root } = await rig();
      const r1 = await open({ row: "flag:nav:skip" });
      expect(r1.status).toBe(202);
      const j1 = await r1.json() as any;
      expect(j1).toMatchObject({ ok: true, state: "pending", canonical: "?fw=nav:skip,hero:strip" });
      const again = await open({ row: "flag:nav:skip" });
      expect([200, 202]).toContain(again.status);
      await pm.settled(j1.preview);
      expect(pm.list().previews.length).toBe(1);
      const r2 = await open({ row: "flag:nav:skip" });
      expect(r2.status).toBe(200);
      const j2 = await r2.json() as any;
      expect(j2.state).toBe("open");
      expect(j2.preview).toBe(j1.preview);
      expect(j2.path).toBe(`/preview/${j1.preview}/r/?fw=nav:skip,hero:strip`);
      expect(j2.url).toBe(`http://127.0.0.1:4001${j2.path}`);
      expect(JSON.stringify(j2)).not.toMatch(/token|cookie|owner=|authorization/i);
      expect(pm.list().previews[0]!.target.sha).toBe(sh(root, "rev-parse", "main"));
      const c = await (await open({ row: "flag:nav:skip", arm: "compare" })).json() as any;
      expect(c.path).toBe(`/preview/${j1.preview}/compare?fw=nav:skip,hero:strip`);
    });

    it("a pasted search is checked first; a refused one opens nothing and starts nothing", async () => {
      const { open, pm } = await rig();
      for (const [search, reason] of [["?fw=nope:x", "unknown part"], ["?preset=original&preset=v2-proved", "only one ?preset="], ["?fw=nav:skip", "requires hero:strip"], ["?fw=hero:strip%20x", "character outside"]] as const) {
        const r = await open({ search });
        expect(r.status).toBe(422);
        const j = await r.json() as any;
        expect(j.ok).toBe(false);
        expect(j.reasons.join("|")).toContain(reason);
      }
      expect(pm.list().previews.length).toBe(0);
    });

    it("a valid pasted search builds main once, then opens in canonical form (preset first)", async () => {
      const { open, pm, root } = await rig();
      const r1 = await open({ search: "?fw=nav:skip&preset=v2-proved" });
      expect(r1.status).toBe(202);
      const j1 = await r1.json() as any;
      expect(j1.canonical).toBe("?preset=v2-proved&fw=nav:skip");
      await pm.settled(j1.preview);
      const e = pm.list().previews[0]!;
      expect(e.task).toBe("open-main");
      expect(e.target).toEqual({ kind: "main", ref: "main", sha: sh(root, "rev-parse", "main") });
      const j2 = await (await open({ search: "?fw=nav:skip&preset=v2-proved" })).json() as any;
      expect(j2).toMatchObject({ ok: true, state: "open", preview: j1.preview, path: `/preview/${j1.preview}/r/?preset=v2-proved&fw=nav:skip` });
      expect(pm.list().previews.length).toBe(1);
    });

    it("the owner gate is unchanged: a non-owner cannot start (403); a request names no commit or path (400)", async () => {
      const { open, pm } = await rig();
      expect((await open({ row: "flag:nav:skip" }, {})).status).toBe(403);
      expect((await open({ search: "?preset=v2-proved" }, {})).status).toBe(403);
      expect((await open({ sha: "abc" })).status).toBe(400);
      expect((await open({ row: "flag:nav:nope" })).status).toBe(404);
      expect(pm.list().previews.length).toBe(0);
    });

    it("the link uses the LAN address when LAN is on, else loopback", async () => {
      const { open, pm, owner } = await rig();
      const j1 = await (await open({ row: "flag:nav:skip" })).json() as any;
      await pm.settled(j1.preview);
      owner.setLanHosts(["192.0.2.10:4000"], ["192.0.2.10:4001"]);
      const j2 = await (await open({ row: "flag:nav:skip" })).json() as any;
      expect(j2.url).toBe(`http://192.0.2.10:4001/preview/${j1.preview}/r/?fw=nav:skip,hero:strip`);
      owner.setLanHosts([], []);
      const j3 = await (await open({ row: "flag:nav:skip" })).json() as any;
      expect(j3.url.startsWith("http://127.0.0.1:4001/")).toBe(true);
    });
  });
});
