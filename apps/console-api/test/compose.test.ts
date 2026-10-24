import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
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
import { composeReply, parsePicks, readComposeRegistry, readLedger, runIdsIn } from "../src/preview/compose.ts";
import { resolve } from "../../site/src/registry/resolve.ts";
import type { PartDef, PresetDef } from "../../site/src/registry/types.ts";

const TEST_BASE = 47420;
const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, "../../..");
const GOLDEN = join(ROOT, "packages/contracts/golden/console/console.compose.jsonl");
const cases = readFileSync(GOLDEN, "utf8").trim().split("\n").map((l) => JSON.parse(l) as { name: string; request: Record<string, unknown>; response: Record<string, any> });
const core = selectCore();
const sh = (cwd: string, ...a: string[]) => execFileSync("git", a, { cwd, stdio: ["ignore", "pipe", "ignore"] }).toString().trim();

let stores: Store[] = [];
let mgrs: PreviewManager[] = [];
afterEach(async () => {
  for (const m of mgrs) await m.shutdown().catch(() => undefined);
  mgrs = [];
  stores.forEach((s) => s.close()); stores = [];
});

describe("console.compose golden: fwcore gives Lean's answer for every vector", () => {
  it("the vector set has the cases the task names", () => {
    const names = cases.map((c) => c.name).join("|");
    for (const w of ["no picks", "measured pick", "any order", "look-change", "refuted", "unrated", "requires violation", "conflicts violation", "unknown part", "unknown variant", "coupled"]) expect(names).toContain(w);
  });
  for (const c of cases) {
    it(c.name, async () => {
      if (c.response.error !== undefined) {
        const got = await core.ops("console.compose", c.request).then((r) => r, (e: Error) => ({ error: String(e.message) }));
        expect((got as { error?: string }).error ?? JSON.stringify(got)).toContain(c.response.error);
      } else {
        const { id: _id, ...got } = await core.ops("console.compose", c.request) as Record<string, unknown>;
        expect(JSON.parse(JSON.stringify(got))).toEqual(c.response);
      }
    });
  }
  it("a link is exactly the canonical search, and a refusal has no link", () => {
    for (const c of cases.filter((x) => x.response.error === undefined)) {
      const d = c.response.decision;
      expect(d.ok).toBe(d.link !== null);
      expect(d.ok).toBe(d.reasons.length === 0);
      if (d.ok) expect(d.link === "" || d.link.startsWith("?fw=")).toBe(true);
    }
  });
});

describe("compose glue", () => {
  it("parsePicks is syntax only", () => {
    expect(parsePicks(undefined)).toEqual([]);
    expect(parsePicks("a.b:c-d,e:f")).toEqual([{ part: "a.b", variant: "c-d" }, { part: "e", variant: "f" }]);
    for (const bad of ["a", "a:b:c", "a b:c", "a:b,,c:d", "<x>:y"]) expect(parsePicks(bad)).toBeNull();
  });
  it("runIdsIn finds Actions run ids in strings and arrays, once each", () => {
    expect(runIdsIn(["run 24123456789 and 24123456789", ["chromium 24987654321", "short 12345"], undefined])).toEqual(["24123456789", "24987654321"]);
  });
});

describe("GET /api/compose over the real registry and ledger", () => {
  const reg = readComposeRegistry(ROOT);
  const ledger = readLedger(ROOT);
  const parts = reg.parts.map((p) => JSON.parse(readFileSync(join(ROOT, "apps/site/src/parts", p.id, "part.json"), "utf8")) as PartDef);
  const presets: Record<string, PresetDef> = {};
  for (const p of reg.presets) presets[p.name] = p as PresetDef;

  it("every part is listed in page order with its default first and classed variants", async () => {
    const r = await composeReply(ROOT, core, []) as any;
    expect(r.ok).toBe(true);
    expect(r.parts.map((p: any) => p.id).sort()).toEqual(reg.parts.map((p) => p.id).sort());
    const regionIdx = (id: string) => r.regions.indexOf(r.parts.find((p: any) => p.id === id).slot);
    const idx = r.parts.map((p: any) => (r.regions.indexOf(p.slot) < 0 ? r.regions.length : r.regions.indexOf(p.slot)));
    expect(idx).toEqual([...idx].sort((a: number, b: number) => a - b));
    void regionIdx;
    const classes = new Set<string>();
    for (const p of r.parts) {
      expect(p.variants[0].isDefault).toBe(true);
      for (const v of p.variants) { classes.add(v.class); expect(v.why.length).toBeGreaterThan(0); }
    }
    expect([...classes].every((c) => Object.keys(r.rules).includes(c))).toBe(true);
    expect(classes.has("original")).toBe(true);
    expect(classes.has("refuted")).toBe(true);
    expect(r.decision).toMatchObject({ ok: true, link: "" });
  });

  it("rows attach by their flags, and no variant says the proof is incomplete without the rows saying so", async () => {
    const r = await composeReply(ROOT, core, []) as any;
    const v = (part: string, name: string) => r.parts.find((p: any) => p.id === part).variants.find((x: any) => x.name === name);
    expect(v("morph.columns", "hidden-pause").class).not.toBe("unrated");
    expect(v("morph.columns", "hidden-pause").rows.length).toBeGreaterThanOrEqual(2);
    expect(v("morph.countdown", "hidden-pause").rows.length).toBeGreaterThanOrEqual(1);
    for (const p of r.parts) for (const x of p.variants) expect(x.why).not.toContain("not complete");
    expect(r.parts.flatMap((p: any) => p.variants).filter((x: any) => x.class === "unrated").map((x: any) => x.name)).toEqual([]);
    for (const p of r.parts) for (const x of p.variants) for (const i of x.rows) expect(ledger.findings[i]!.flags).toContain(`${p.id}:${x.name}`);
    expect(ledger.findings.every((x) => Array.isArray(x.flags))).toBe(true);
  });

  it("the gpu field carries the Lean mechanism for GPU variants and null for the rest", async () => {
    const r = await composeReply(ROOT, core, []) as any;
    const gpu = r.parts.flatMap((p: any) => p.variants.map((x: any) => [`${p.id}:${x.name}`, x.gpu])) as [string, string | null][];
    expect(gpu.filter(([, g]) => g !== null).map(([k]) => k).sort()).toEqual(
      ["hero.countdown:strip", "hero.exit:threaded", "hero:scene-pause", "morph.columns:idle-none", "morph.countdown:strip", "morph.panel:const-bounds",
        "morph.panel:threaded", "nav:bar-fixed", "nav:clip-box", "nav:logo-3d", "pain:dark-scroll", "people.o:preview-translate", "platform:fade-threaded"]);
    const eng = (k: string) => r.parts.flatMap((p: any) => p.variants.map((x: any) => [`${p.id}:${x.name}`, x.gpuEngines])).find(([a]: string[]) => a === k)[1];
    expect(eng("platform:fade-threaded")).toBe("WebKit only");
    expect(eng("hero.exit:threaded")).toBe("both engines");
    expect(eng("hero.countdown:faithful")).toBeNull();
    expect(gpu.find(([k]) => k === "engine.scroll:unthrottle")![1]).toBeNull();
    for (const [, g] of gpu) expect(g === null || (typeof g === "string" && g.length > 0)).toBe(true);
    expect(gpu.find(([k]) => k === "hero.countdown:faithful")![1]).toBeNull();
  });

  it("a refuted variant is classed refuted, cites its ledger row, and a pick of it is refused", async () => {
    const r = await composeReply(ROOT, core, [{ part: "morph.tween", variant: "waapi" }]) as any;
    const tween = r.parts.find((p: any) => p.id === "morph.tween");
    const v = tween.variants.find((x: any) => x.name === "waapi");
    expect(v.class).toBe("refuted");
    expect(v.rows.length).toBeGreaterThan(0);
    const mine = v.rows.map((i: number) => r.rows[String(i)]);
    expect(mine.some((row: any) => row.status === "refuted")).toBe(true);
    for (const row of mine) expect(row.part === "morph.tween" || row.candidate.includes("morph.tween")).toBe(true);
    expect(r.decision.ok).toBe(false);
    expect(r.decision.link).toBeNull();
    expect(r.decision.reasons.join("|")).toContain("refuted");
  });

  it("a superseded refuted row does not refute: hero.exit:scoped takes the class of the row that superseded it", async () => {
    const r = await composeReply(ROOT, core, [{ part: "hero.exit", variant: "scoped" }]) as any;
    const v = r.parts.find((p: any) => p.id === "hero.exit").variants.find((x: any) => x.name === "scoped");
    const idx = (id: string) => ledger.findings.findIndex((x) => x.id === id);
    expect(ledger.findings[idx("hero.exit.scoped.falsified")]!.supersededBy).toBe("hero.exit.scoped.inline");
    expect(v.rows).toContain(idx("hero.exit.scoped.falsified"));
    expect(v.rows).toContain(idx("hero.exit.scoped.inline"));
    expect(v.class).toBe("ledger-proved");
    expect(v.refusal).toBeNull();
    expect(r.decision).toMatchObject({ ok: true, link: "?fw=hero.exit:scoped" });
  });

  it("every ledger row an explanation cites exists in the ledger, with its own words", async () => {
    const r = await composeReply(ROOT, core, []) as any;
    for (const [i, row] of Object.entries<any>(r.rows)) {
      const src = ledger.findings[Number(i)]!;
      expect(row.candidate).toBe(src.candidate);
      expect(row.status).toBe(src.status);
      expect(row.lesson).toBe(src.lesson ?? "");
      expect(Array.isArray(row.leanFor)).toBe(true);
    }
  });

  it("an allowed combination of non-refuted variants validates against the site's resolve.ts, canonical", async () => {
    const r0 = await composeReply(ROOT, core, []) as any;
    const picks = r0.parts.flatMap((p: any) => p.variants.filter((v: any) => v.class === "measured" || v.class === "proved").slice(0, 1).map((v: any) => ({ part: p.id, variant: v.name })));
    expect(picks.length).toBeGreaterThan(2);
    const kept: { part: string; variant: string }[] = [];
    for (const p of picks) {
      const d = ((await composeReply(ROOT, core, [...kept, p])) as any).decision;
      if (d.ok) kept.push(p);
    }
    expect(kept.length).toBeGreaterThan(1);
    const d = ((await composeReply(ROOT, core, kept)) as any).decision;
    expect(d.ok).toBe(true);
    expect(d.link.startsWith("?fw=")).toBe(true);
    const site = resolve(d.link, parts, presets);
    expect(site.ok).toBe(true);
    expect((((await composeReply(ROOT, core, [...kept].reverse())) as any).decision).link).toBe(d.link);
  });

  it("whatever Lean refuses on rules, the site refuses too; whatever Lean allows, the site accepts", async () => {
    const r0 = await composeReply(ROOT, core, []) as any;
    for (const p of r0.parts) for (const v of p.variants) {
      const d = ((await composeReply(ROOT, core, [{ part: p.id, variant: v.name }])) as any).decision;
      if (d.ok) expect(resolve(d.link, parts, presets).ok).toBe(true);
      else if (v.class !== "refuted") expect(resolve(`?fw=${p.id}:${v.name}`, parts, presets).ok).toBe(false);
    }
  });

  it("the presets come with their decision", async () => {
    const r = await composeReply(ROOT, core, []) as any;
    const names = r.presets.map((p: any) => p.name);
    expect(names).toContain("original");
    expect(names).toContain("v2-proved");
    for (const p of r.presets.filter((x: any) => x.ok)) expect(resolve(p.link, parts, presets).ok).toBe(true);
  });
});

describe("Compose routes, and the open path with a composed search", () => {
  function repo() {
    const root = mkdtempSync(join(tmpdir(), "fw-compose-repo-"));
    sh(root, "init", "-q", "-b", "main");
    sh(root, "config", "user.email", ["t", "example.test"].join("\x40")); sh(root, "config", "user.name", "t");
    mkdirSync(join(root, "docs/team"), { recursive: true });
    mkdirSync(join(root, "snapshot/site"), { recursive: true });
    const part = (id: string, slot: string, variants: Record<string, { kind: string }>, requires: Record<string, string[]> = {}) => {
      mkdirSync(join(root, "apps/site/src/parts", id), { recursive: true });
      writeFileSync(join(root, "apps/site/src/parts", id, "part.json"), JSON.stringify({ id, slot, variants, requires, conflicts: {} }));
    };
    part("hero", "hero", { faithful: { kind: "faithful" }, strip: { kind: "optimized" } });
    part("nav", "nav", { faithful: { kind: "faithful" }, skip: { kind: "optimized" } }, { "nav:skip": ["hero:strip"] });
    mkdirSync(join(root, "apps/site/src/registry/presets"), { recursive: true });
    writeFileSync(join(root, "apps/site/src/registry/presets/original.json"), JSON.stringify({ name: "original", fw: {} }));
    writeFileSync(join(root, "apps/site/src/registry/presets/v2-proved.json"), JSON.stringify({ extends: "original", name: "v2-proved", fw: { nav: "skip", hero: "strip" } }));
    mkdirSync(join(root, "research/findings"), { recursive: true });
    writeFileSync(join(root, "research/findings/ledger.json"), JSON.stringify({ findings: [
      { part: "hero", candidate: "hero `strip`", status: "measured", flags: ["hero:strip"], visual: "same", lesson: "run 24123456789 shows it" },
      { part: "nav", candidate: "nav `skip`", status: "refuted", flags: ["nav:skip"], flag: "nav:skip", leanFor: ["a"], leanAgainst: ["b"] }], notes: [] }));
    sh(root, "add", "-A"); sh(root, "commit", "-qm", "base");
    return root;
  }
  async function setup() {
    const root = repo();
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
        writeFileSync(join(e.tree, "apps/site/dist/aot/configs.json"), JSON.stringify({ bySearch: { "": "d", "?fw=hero:strip": "h" }, byHash: {} }));
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
    const open = (body: unknown) => app.request("/api/builds/open", { method: "POST", body: JSON.stringify(body), headers: { "content-type": "application/json", host: H, authorization, origin: O } });
    return { app, pm, open };
  }

  it("GET /api/compose returns the table, the presets and the decision; a bad pick query is 400", async () => {
    const { app } = await setup();
    const j = await (await app.request("/api/compose")).json() as any;
    expect(j.ok).toBe(true);
    expect(j).toMatchObject({ canPreview: false, previewPort: 4001 });
    expect(j.parts.map((p: any) => p.id)).toEqual(["nav", "hero"]);
    expect(j.parts[1].variants.map((v: any) => [v.name, v.class])).toEqual([["faithful", "original"], ["strip", "proved"]]);
    expect(Object.values<any>(j.rows).find((r) => r.candidate === "hero `strip`").runs).toEqual(["24123456789"]);
    expect(j.presets.find((p: any) => p.name === "v2-proved")).toMatchObject({ ok: false });
    expect((await app.request("/api/compose?pick=hero")).status).toBe(400);
    const d = await (await app.request("/api/compose/decision?pick=hero:strip")).json() as any;
    expect(d).toEqual({ ok: true, decision: { ok: true, link: "?fw=hero:strip", reasons: [], notes: [] } });
    const rf = await (await app.request("/api/compose/decision?pick=nav:skip,hero:strip")).json() as any;
    expect(rf.decision.ok).toBe(false);
    expect(rf.decision.link).toBeNull();
  });

  it("an allowed combination's link opens through POST /api/builds/open, in canonical form, on the preview port", async () => {
    const { app, pm, open } = await setup();
    const d = (await (await app.request("/api/compose/decision?pick=hero:strip")).json() as any).decision;
    expect(d.link).toBe("?fw=hero:strip");
    const r1 = await open({ search: d.link });
    expect(r1.status).toBe(202);
    const j1 = await r1.json() as any;
    expect(j1.canonical).toBe(d.link);
    await pm.settled(j1.preview);
    const j2 = await (await open({ search: d.link })).json() as any;
    expect(j2).toMatchObject({ ok: true, state: "open", path: `/preview/${j1.preview}/r/?fw=hero:strip` });
    expect(j2.url).toBe(`http://127.0.0.1:4001${j2.path}`);
    const c = await (await open({ search: d.link, arm: "compare" })).json() as any;
    expect(c.path).toBe(`/preview/${j1.preview}/compare?fw=hero:strip`);
    expect(pm.list().previews.length).toBe(1);
  });

  it("a refused combination has no link to open", async () => {
    const { app, pm } = await setup();
    const d = (await (await app.request("/api/compose/decision?pick=nav:skip")).json() as any).decision;
    expect(d.link).toBeNull();
    expect(d.reasons.join("|")).toMatch(/refuted|requires/);
    expect(pm.list().previews.length).toBe(0);
  });
});
