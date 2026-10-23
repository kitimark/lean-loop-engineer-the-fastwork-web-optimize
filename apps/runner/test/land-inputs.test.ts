import "./land-timeout.ts";
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, relative, resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { LOCAL_GATES, LOCAL_TESTS, binMoved, candidateChecks, CHECK_SH_READS, FWCORE_BIN, FWCORE_USERS, checksFor, selectTwoPhase, checksWithReads, inScope, inputKey, READS_SCAN_ARGV, READS_SCAN_ID, selectChecks, withScan, type Check } from "../src/land.ts";

const root = join(dirname(new URL(import.meta.url).pathname), "../../..");

type Decl = { id: string; reads: string[] };
const golden = readFileSync(join(root, "packages/contracts/golden/console/land-speed.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l));
const selects = golden.filter((c) => c.request.op === "landSpeed.select");
const select2s = golden.filter((c) => c.request.op === "landSpeed.select2");

describe("the choice of checks equals the Lean decision", () => {
  it("the golden has select cases", () => expect(selects.length).toBeGreaterThan(3));
  for (const c of selects) {
    it(`golden: ${c.name}`, () => {
      expect(selectChecks(c.request.checks as Decl[], c.request.changed as string[])).toEqual(c.response.selected);
    });
  }
  for (const c of selects) {
    const cs = c.request.checks as Decl[];
    if (cs.at(-1)?.id !== "reads-scan") continue;
    it(`golden scan: ${c.name}`, () => {
      const w = withScan(cs.slice(0, -1) as unknown as Check[]);
      expect(READS_SCAN_ID).toBe(cs.at(-1)!.id);
      expect(w.map((x) => ({ id: x.id, reads: x.reads }))).toEqual(cs);
    });
  }
  it("the golden has two-phase cases", () => expect(select2s.length).toBeGreaterThan(5));
  for (const c of select2s) {
    it(`golden two-phase: ${c.name}`, () => {
      const { checks, changed, main0Digest, mergeDigest } = c.request as { checks: Decl[]; changed: string[]; main0Digest: string | null; mergeDigest: string | null };
      expect(binMoved(changed, main0Digest, mergeDigest)).toBe(c.response.binMoved);
      expect(selectTwoPhase(checks, changed, main0Digest, mergeDigest)).toEqual(c.response.selected);
    });
  }
  it("check.sh declares what Lean declares (checkShReads)", () => {
    const decl = (selects[0].request.checks as Decl[]).find((d) => d.id === "check.sh")!;
    expect(CHECK_SH_READS).toEqual(decl.reads);
  });
  it("apps/site declares a read for every snapshot asset of its manifest (listed <=> read)", () => {
    const m = JSON.parse(readFileSync(join(root, "apps/site/assets.manifest.json"), "utf8")) as { files: { src: string }[]; bundled: string[] };
    const site = candidateChecks(root).find((c) => c.id === "apps/site")!;
    for (const f of m.files) expect(inScope(site.reads, f.src), f.src).toBe(true);
    for (const g of m.bundled) expect(site.reads).toContain(g);
    expect(inScope(site.reads, "snapshot/site/selling/hero/not-listed.jpg")).toBe(false);
  });
  it("checksFor is the argv of the two-phase selection with unknown digests, in table order", () => {
    const all = candidateChecks(root);
    expect(all.map((c) => c.id).slice(0, 2)).toEqual(["install", "check.sh"]);
    expect(all.some((c) => c.id === "apps/runner")).toBe(true);
    const changed = ["lean/Fw/A.lean", "apps/runner/src/land.ts"];
    expect(checksFor(root, changed)).toEqual(all.filter((c) => selectTwoPhase(all, changed, null, null).includes(c.id)).map((c) => c.argv));
    expect(checksWithReads(root, ["docs/team/handoffs/x.md"])).toEqual([]);
    expect(checksWithReads(root, ["lean/Fw/A.lean"]).map((c) => c.id)).toContain("check.sh");
    expect(checksWithReads(root, ["packages/contracts/golden/obs/timing.jsonl"]).map((c) => c.id)).toContain("check.sh");
    expect(checksWithReads(root, ["apps/site/src/breakpoints.gen.json"]).map((c) => c.id)).toContain("check.sh");
    expect(checksFor(root, ["packages/gate-breakpoints/src/scope.gen.json"])).toContainEqual(["sh", "lean/scripts/check.sh"]);
    expect(checksFor(root, [".github/workflows/lean.yml"])).toContainEqual(["sh", "lean/scripts/check.sh"]);
  });
  it("the read-set scan is selected by every change a check can read (Lean scan_selected), as its own cheap check", () => {
    const all = candidateChecks(root);
    const scan = all.find((c) => c.id === READS_SCAN_ID)!;
    expect(all[all.length - 1]).toBe(scan);
    expect(scan.argv).toEqual(READS_SCAN_ARGV);
    expect(scan.argv).not.toContain("test");
    expect(scan.reads).toEqual(withScan(all.slice(0, -1)).at(-1)!.reads);
    const ids = checksWithReads(root, ["apps/site/src/registry/presets/original.json"]).map((c) => c.id);
    expect(ids).toContain(READS_SCAN_ID);
    expect(ids).not.toContain("apps/runner");
    expect(checksWithReads(root, ["docs/team/handoffs/x.md"])).toEqual([]);
    const tracked = execFileSync("git", ["ls-files", "-z"], { cwd: root, encoding: "utf8" }).split("\0").filter(Boolean);
    const missing = tracked.filter((f) => all.some((c) => c.id !== READS_SCAN_ID && inScope(c.reads, f)) && !inScope(scan.reads, f));
    expect(missing).toEqual([]);
  });
});

function oldChecksFor(r: string, changed: string[]): string[][] {
  const out: string[][] = [];
  if (changed.some((f) => f === "pnpm-lock.yaml" || /(^|\/)package\.json$/.test(f))) out.push(["pnpm", "install", "--frozen-lockfile"]);
  if (changed.some((f) => f.startsWith("lean/"))) out.push(["sh", "lean/scripts/check.sh"]);
  const pkgs = new Set<string>();
  for (const f of changed) { const m = /^(apps|packages)\/([^/]+)\//.exec(f); if (m) pkgs.add(`${m[1]}/${m[2]}`); }
  for (const p of [...pkgs].sort()) {
    try { if (JSON.parse(readFileSync(join(r, p, "package.json"), "utf8")).scripts?.test) out.push(["pnpm", "--filter", `./${p}`, "test"]); } catch { /* none */ }
  }
  return out;
}
const superset = (changed: string[]) => {
  const n = new Set(checksFor(root, changed).map((a) => a.join(" ")));
  return oldChecksFor(root, changed).map((a) => a.join(" ")).filter((k) => !n.has(k));
};


const walk = (d: string, exts: RegExp): string[] =>
  readdirSync(d, { withFileTypes: true }).flatMap((e) =>
    e.name === "node_modules" || e.name === "dist" || e.name.startsWith(".") ? [] : e.isDirectory() ? walk(join(d, e.name), exts) : exts.test(e.name) ? [join(d, e.name)] : []);

function escapes(base: string, exts: RegExp): { path: string; file: string }[] {
  const out: { path: string; file: string }[] = [];
  const bd = join(root, base);
  for (const f of walk(bd, exts)) {
    const src = readFileSync(f, "utf8");
    const cands: string[] = [];
    for (const m of src.matchAll(/(?:\.\.\/)+[\w./-]*/g)) cands.push(m[0]);
    for (const m of src.matchAll(/"\.\."(?:\s*,\s*"[^"\n]*")+/g)) cands.push((JSON.parse(`[${m[0]}]`) as string[]).join("/"));
    for (const m of src.matchAll(/"\.\."(?:\s*\/\s*"[^"\n]*")+/g)) cands.push([...m[0].matchAll(/"([^"\n]*)"/g)].map((x) => x[1]).join("/"));
    for (const s of cands) for (const b of [dirname(f), bd]) {
      const t = resolve(b, s);
      const r = relative(root, t);
      if (r.startsWith("..") || r === "" || r.split("/").length < 2 || r.includes("node_modules") || existsSync(t) === false) continue;
      if (r === base || r.startsWith(base + "/")) continue;
      out.push({ path: r, file: relative(root, f) });
    }
  }
  return out;
}
const uniq = (xs: { path: string; file: string }[]) => [...new Map(xs.map((x) => [`${x.path} <- ${x.file}`, x])).values()];

const NOT_REACHED_BY_CHECK_SH: Record<string, string> = {
  "docs/team/work-graph.json": "lean/Fw/Plan/Golden.lean reads it only in write mode (`lake test -- --write-plan-golden`); check.sh runs `lake test` without it",
};

const BUILD_OUTPUT_READS: Record<string, string> = {
  "apps/site/dist/aot": "output of `pnpm --filter @fw/site build`; read by gate-breakpoints/src/serve.mjs and the measure-webkit site/stamped lane scripts",
};

const LEAN_NAMED_NOT_READ: Record<string, string> = {
  "lean/Fw/Parts/FootprintData.lean <- apps/site/scripts/part-footprint.mjs": "the generator writes it; `pnpm test` does not run the generator",
  "lean/Fw/Measure/Classes.lean <- packages/measure-wktr/test/runset.test.mjs": "a classifier input path, not a file read",
  "lean/Fw/Measure/WktrLayout.lean <- packages/measure-wktr/test/runset.test.mjs": "a classifier input path, not a file read",
  "lean/Fw/Measure/Retry.lean <- packages/measure-wktr/test/runset.test.mjs": "a classifier input path, not a file read",
  "lean/Fw/Wire/WktrFixturesGolden.lean <- packages/measure-wktr/fixtures/runset.mjs": "a classifier input path, not a file read",
  "lean/Fw/Measure/Classes.lean <- packages/measure-chromium/src/freeze.mjs": "a provenance string in the frozen output",
};
const LAKE_NOT_IN_TEST: Record<string, string> = {
  "apps/site/scripts/check-breakpoints.mjs": "runs in the `build` scripts only; the land runs `test`",
};

const codeOnly = (src: string) => src.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:\\])\/\/.*$/gm, "$1");

function leanReadMisses(checks: Check[], tracked: Set<string>): { missing: string[]; seen: number } {
  const missing: string[] = [];
  let seen = 0;
  for (const c of checks.filter((x) => /^(apps|packages)\//.test(x.id))) {
    const allLean = inScope(c.reads, "lean/Fw/A.lean");
    for (const f of walk(join(root, c.id), /\.(ts|tsx|mjs|js)$/)) {
      const rel = relative(root, f), src = codeOnly(readFileSync(f, "utf8"));
      for (const [, p] of src.matchAll(/["'`](?:\.\.\/)*(lean\/[\w./-]+\.lean)["'`]/g) as Iterable<[string, string]>) {
        if (!tracked.has(p) || `${p} <- ${rel}` in LEAN_NAMED_NOT_READ) continue;
        seen++;
        if (!inScope(c.reads, p)) missing.push(`${c.id}: ${p} <- ${rel}`);
      }
      for (const [call] of src.matchAll(/\b(?:join|resolve)\((?:[^()]|\([^()]*\))*\)/g)) {
        if (/["'`]lean["'`]/.test(call) && !/["'`]lean["'`]\s*,\s*["'`]\.lake["'`]/.test(call) && !allLean && !(rel in LAKE_NOT_IN_TEST))
          missing.push(`${c.id}: joins a lean/ segment <- ${rel}`);
      }
      if (/(?:spawnSync|execFileSync|spawn)\(\s*["']lake["']/.test(src) && !allLean && !(rel in LAKE_NOT_IN_TEST)) missing.push(`${c.id}: runs lake <- ${rel}`);
    }
  }
  return { missing, seen };
}
const trackedLean = () => new Set(execFileSync("git", ["ls-files", "-z", "--", "lean"], { cwd: root, encoding: "utf8" }).split("\0").filter(Boolean));

describe("premise land.readsOnly: no read outside the declared inputs (static)", () => {
  it("lean/scripts/check.sh and everything it runs read only CHECK_SH_READS or lean/", () => {
    const found = uniq(escapes("lean", /\.(lean|sh|mjs|toml)$/)).filter((x) => !(x.path in NOT_REACHED_BY_CHECK_SH));
    const undeclared = found.filter((x) => !inScope(CHECK_SH_READS, x.path));
    expect(undeclared).toEqual([]);
    expect(found.length).toBeGreaterThan(5);
    for (const k of Object.keys(NOT_REACHED_BY_CHECK_SH)) expect(inScope(CHECK_SH_READS, k)).toBe(false);
    expect(readFileSync(join(root, "lean/scripts/check.sh"), "utf8")).not.toContain("write-plan-golden");
  });
  for (const c of candidateChecks(root).filter((x) => /^(apps|packages)\//.test(x.id))) {
    it(`${c.id}: sources and tests read only ${c.reads.length} declared globs`, () => {
      const found = uniq(escapes(c.id, /\.(ts|tsx|mjs|js|sh)$/)).filter((x) => !(x.path in BUILD_OUTPUT_READS));
      expect(found.filter((x) => !x.path.startsWith("lean/.lake/") && !inScope(c.reads, x.path))).toEqual([]);
    });
  }
  it("the packages that run the fwcore binary are exactly FWCORE_USERS; declaring lean/** for them covers the binary", () => {
    const users = candidateChecks(root).filter((c) => /^(apps|packages)\//.test(c.id) && walk(join(root, c.id), /\.(ts|tsx|mjs|js)$/)
      .some((f) => /\.lake|["'/]fwcore["']|FWCORE|bin\/fwcore/.test(readFileSync(f, "utf8")))).map((c) => c.id);
    expect([...users, "packages/measure-wktr", ...LOCAL_TESTS.map((t) => t.id)].sort()).toEqual([...FWCORE_USERS].sort());
    for (const c of candidateChecks(root)) expect(inScope(c.reads, FWCORE_BIN), c.id).toBe(FWCORE_USERS.includes(c.id) || c.id === "check.sh" || c.id === READS_SCAN_ID);
    expect(checksWithReads(root, ["lean/Fw/A.lean"]).map((c) => c.id).sort()).toEqual(["check.sh", READS_SCAN_ID, ...FWCORE_USERS].sort());
    expect(checksWithReads(root, ["lean/Fw/A.lean"], "a".repeat(64), "b".repeat(64)).map((c) => c.id).sort()).toEqual(["check.sh", READS_SCAN_ID, ...FWCORE_USERS].sort());
  });
  it("a Lean change with an equal digest selects only the packages that read Lean sources (Lean fwcore_digest_skip)", () => {
    const d = "a".repeat(64);
    const leanReaders = candidateChecks(root).filter((c) => /^(apps|packages)\//.test(c.id) && inScope(c.reads, "lean/Fw/A.lean")).map((c) => c.id);
    expect(leanReaders.sort()).toEqual(["apps/runner", "packages/gate-breakpoints"]);
    expect(checksWithReads(root, ["lean/Fw/A.lean"], d, d).map((c) => c.id).sort()).toEqual(["check.sh", READS_SCAN_ID, ...leanReaders].sort());
    expect(checksWithReads(root, ["lean/Fw/Console/PreviewFacts.lean"], d, d).map((c) => c.id)).toContain("apps/console-api");
  });
  it("every Lean source a package names by a repo path is a declared read, and a package that joins a lean/ segment or runs lake declares lean/**", () => {
    const tracked = trackedLean();
    const { missing, seen } = leanReadMisses(candidateChecks(root), tracked);
    expect(missing).toEqual([]);
    expect(seen).toBeGreaterThan(3);
    for (const k of Object.keys(LEAN_NAMED_NOT_READ)) expect(tracked.has(k.split(" <- ")[0]!), k).toBe(true);
  });
  it("mutation: dropping measure-chromium's read of lean/Fw/Store/Layout.lean (named as ../../../lean/...) is reported", () => {
    const layout = "lean/Fw/Store/Layout.lean";
    const cs = candidateChecks(root).map((c) => c.id === "packages/measure-chromium" ? { ...c, reads: c.reads.filter((g) => g !== layout) } : c);
    expect(candidateChecks(root).find((c) => c.id === "packages/measure-chromium")!.reads).toContain(layout);
    expect(leanReadMisses(cs, trackedLean()).missing).toContain(`packages/measure-chromium: ${layout} <- packages/measure-chromium/test/stage-mode.test.mjs`);
  });
  it("mutation: dropping lean/** from apps/runner reports its lean/ segment joins (src/premises.ts)", () => {
    const cs = candidateChecks(root).map((c) => c.id === "apps/runner" ? { ...c, reads: c.reads.filter((g) => g !== "lean/**") } : c);
    expect(leanReadMisses(cs, trackedLean()).missing).toContain("apps/runner: joins a lean/ segment <- apps/runner/src/premises.ts");
  });

  it("new selection is a superset of the old one: every tracked path alone, and the last 30 land diffs", () => {
    const tracked = execFileSync("git", ["ls-files", "-z"], { cwd: root, encoding: "utf8" }).split("\0").filter(Boolean);
    expect(tracked.length).toBeGreaterThan(100);
    const missing = tracked.map((f) => ({ f, m: superset([f]) })).filter((x) => x.m.length > 0);
    expect(missing).toEqual([]);
    const git = (...a: string[]) => execFileSync("git", a, { cwd: root, encoding: "utf8" }).trim();
    let ref = "main";
    try { git("rev-parse", "--verify", "main"); } catch { ref = "HEAD"; }
    const lands = git("log", ref, "--first-parent", "--merges", "-30", "--format=%H").split("\n").filter(Boolean);
    expect(lands.length).toBeGreaterThan(0);
    for (const h of lands) {
      const changed = git("diff", "--name-only", `${h}^1`, h).split("\n").filter(Boolean);
      expect(superset(changed), h.slice(0, 7)).toEqual([]);
    }
  });
  it("every PACKAGE_EXTRA_READS entry is exercised: it matches a tracked file or is a deliberate directory", () => {
    const tracked = execFileSync("git", ["ls-files", "-z"], { cwd: root, encoding: "utf8" }).split("\0").filter(Boolean);
    const untrackedOk = [FWCORE_BIN, ".github/workflows/*.yaml"];
    for (const c of candidateChecks(root)) for (const g of c.reads.filter((x) => !untrackedOk.includes(x))) expect(tracked.some((f) => inScope([g], f)), `${c.id}: ${g}`).toBe(true);
  });
});


const inside = (g: string) => g.replace(/\*\*\/?$/, "f.txt").replace(/\*\*/g, "d").replace(/\*/g, "x");

function fixture(): { dir: string; write: (f: string, s: string) => void; checks: Check[]; done: () => void } {
  const dir = mkdtempSync(join(tmpdir(), "fw-inputs-"));
  const git = (...a: string[]) => execFileSync("git", a, { cwd: dir, stdio: "ignore" });
  git("init", "-q");
  const write = (f: string, s: string) => { mkdirSync(dirname(join(dir, f)), { recursive: true }); writeFileSync(join(dir, f), s); };
  write("apps/runner/package.json", JSON.stringify({ name: "@fw/runner", scripts: { test: "x" }, devDependencies: { "@fw/contracts": "workspace:*" } }));
  write("packages/contracts/package.json", JSON.stringify({ name: "@fw/contracts", scripts: { test: "x" } }));
  write("packages/lone/package.json", JSON.stringify({ name: "@fw/lone", scripts: { test: "x" } }));
  const checks = candidateChecks(dir);
  for (const c of checks) for (const g of c.reads) write(inside(g), "v0");
  write("docs/a.md", "v0");
  write("misc/zzz/outside.txt", "v0");
  git("add", "-A");
  return { dir, write, checks, done: () => rmSync(dir, { recursive: true, force: true }) };
}

describe("premise land.readsOnly: the key over the declared inputs (dynamic)", () => {
  it("the fixture holds install, check.sh and three package tests; a workspace dependency is declared", () => {
    const fx = fixture();
    try {
      expect(fx.checks.map((c) => c.id)).toEqual(["install", "check.sh", "apps/runner", "packages/contracts", "packages/lone", ...LOCAL_GATES.map((t) => t.id), READS_SCAN_ID]);
      expect(fx.checks.find((c) => c.id === "apps/runner")!.reads).toContain("packages/contracts/**");
    } finally { fx.done(); }
  });
  it("a change outside the inputs leaves the key; a change inside moves it (every glob of every check)", () => {
    const fx = fixture();
    try {
      for (const c of fx.checks) {
        const k0 = inputKey(fx.dir, c.reads);
        const outsiders = ["docs/a.md", "misc/zzz/outside.txt", ...fx.checks.flatMap((o) => o.reads.map(inside)).filter((f) => !inScope(c.reads, f))];
        for (const f of outsiders) {
          fx.write(f, "changed");
          expect(inputKey(fx.dir, c.reads), `${c.id}: outside ${f}`).toBe(k0);
          fx.write(f, "v0");
        }
        for (const g of c.reads) {
          const f = inside(g);
          fx.write(f, "changed");
          expect(inputKey(fx.dir, c.reads), `${c.id}: inside ${g}`).not.toBe(k0);
          fx.write(f, "v0");
          expect(inputKey(fx.dir, c.reads)).toBe(k0);
        }
      }
    } finally { fx.done(); }
  });
  it("the real key is stable between two calls and differs between checks", () => {
    const a = candidateChecks(root).map((c) => inputKey(root, c.reads));
    expect(candidateChecks(root).map((c) => inputKey(root, c.reads))).toEqual(a);
    expect(new Set(a).size).toBe(a.length);
  });
});
