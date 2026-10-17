// Declared inputs of the land checks (task checksfor-inputs). Two things are tested:
//  1. the choice of checks equals the Lean decision (`landSpeed.select` golden, from `Fw.Console.LandSpeed.selectChecks`);
//  2. the empirical premise `land.readsOnly` that `cache_sound` / `skip_sound` rest on: a check reads only its declared
//     inputs. Static form: scan every source file a check runs for paths that leave its own directory and fail on any not
//     covered by the check's globs. Dynamic form: the key over the declared inputs moves for a change inside them and
//     stays for a change outside them.
// The scan is static, so reads built at run time (an environment variable, a `git` call, a path computed from data) are
// invisible to it; those are listed in docs/team/handoffs/checksfor-inputs.md.
import "./land-timeout.ts";
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, relative, resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { candidateChecks, CHECK_SH_READS, FWCORE_USERS, checksFor, checksWithReads, inScope, inputKey, selectChecks, type Check } from "../src/land.ts";

const root = join(dirname(new URL(import.meta.url).pathname), "../../..");

type Decl = { id: string; reads: string[] };
const golden = readFileSync(join(root, "packages/contracts/golden/console/land-speed.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l));
const selects = golden.filter((c) => c.request.op === "landSpeed.select");

describe("the choice of checks equals the Lean decision", () => {
  it("the golden has select cases", () => expect(selects.length).toBeGreaterThan(3));
  for (const c of selects) {
    it(`golden: ${c.name}`, () => {
      expect(selectChecks(c.request.checks as Decl[], c.request.changed as string[])).toEqual(c.response.selected);
    });
  }
  it("check.sh declares what Lean declares (checkShReads)", () => {
    const decl = (selects[0].request.checks as Decl[]).find((d) => d.id === "check.sh")!;
    expect(CHECK_SH_READS).toEqual(decl.reads);
  });
  it("checksFor is the argv of the selected checks, in table order", () => {
    const all = candidateChecks(root);
    expect(all.map((c) => c.id).slice(0, 2)).toEqual(["install", "check.sh"]);
    expect(all.some((c) => c.id === "apps/runner")).toBe(true);
    const changed = ["lean/Fw/A.lean", "apps/runner/src/land.ts"];
    expect(checksFor(root, changed)).toEqual(all.filter((c) => selectChecks(all, changed).includes(c.id)).map((c) => c.argv));
    expect(checksWithReads(root, ["docs/team/handoffs/x.md"])).toEqual([]);
    expect(checksWithReads(root, ["lean/Fw/A.lean"]).map((c) => c.id)).toContain("check.sh");
    // a golden or a generated site file is read by check.sh: the old rule (lean/ only) missed these
    expect(checksWithReads(root, ["packages/contracts/golden/obs/timing.jsonl"]).map((c) => c.id)).toContain("check.sh");
    expect(checksWithReads(root, ["apps/site/src/breakpoints.gen.json"]).map((c) => c.id)).toContain("check.sh");
  });
});

/** The old `checksFor` (before checksfor-inputs), kept as a fixture. */
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
/** old checks the new selection lacks, for one changed-path set */
const superset = (changed: string[]) => {
  const n = new Set(checksFor(root, changed).map((a) => a.join(" ")));
  return oldChecksFor(root, changed).map((a) => a.join(" ")).filter((k) => !n.has(k));
};

// ---- the static scan -------------------------------------------------------------------------------------------------

const walk = (d: string, exts: RegExp): string[] =>
  readdirSync(d, { withFileTypes: true }).flatMap((e) =>
    e.name === "node_modules" || e.name === "dist" || e.name.startsWith(".") ? [] : e.isDirectory() ? walk(join(d, e.name), exts) : exts.test(e.name) ? [join(d, e.name)] : []);

/** Existing repo paths, outside `base`, that a file of `base` names through `../` strings, TS `join(.., "..", "x")` lists or Lean
 *  `".." / "x"` paths. Each is resolved against the file's directory and against `base` (a script's cwd). */
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

/** Reads a script has but a `check.sh` run never executes, each with the reason. */
const NOT_REACHED_BY_CHECK_SH: Record<string, string> = {
  "docs/team/work-graph.json": "lean/Fw/Plan/Golden.lean reads it only in write mode (`lake test -- --write-plan-golden`); check.sh runs `lake test` without it",
};

describe("premise land.readsOnly: no read outside the declared inputs (static)", () => {
  it("lean/scripts/check.sh and everything it runs read only CHECK_SH_READS or lean/", () => {
    const found = uniq(escapes("lean", /\.(lean|sh|mjs|toml)$/)).filter((x) => !(x.path in NOT_REACHED_BY_CHECK_SH));
    const undeclared = found.filter((x) => !inScope(CHECK_SH_READS, x.path));
    expect(undeclared).toEqual([]);
    expect(found.length).toBeGreaterThan(5); // the scan sees the golden and span.sh reads
    // the exceptions are real: the path exists and is outside the declared inputs
    for (const k of Object.keys(NOT_REACHED_BY_CHECK_SH)) expect(inScope(CHECK_SH_READS, k)).toBe(false);
    expect(readFileSync(join(root, "lean/scripts/check.sh"), "utf8")).not.toContain("write-plan-golden");
  });
  for (const c of candidateChecks(root).filter((x) => /^(apps|packages)\//.test(x.id))) {
    it(`${c.id}: sources and tests read only ${c.reads.length} declared globs`, () => {
      const found = uniq(escapes(c.id, /\.(ts|tsx|mjs|js|sh)$/));
      // the fwcore binary (lean/.lake) is the next test's business
      expect(found.filter((x) => !x.path.startsWith("lean/.lake/") && !inScope(c.reads, x.path))).toEqual([]);
    });
  }
  it("the packages that run the fwcore binary are exactly FWCORE_USERS; declaring lean/** for them covers the binary", () => {
    const users = candidateChecks(root).filter((c) => /^(apps|packages)\//.test(c.id) && walk(join(root, c.id), /\.(ts|tsx|mjs|js)$/)
      .some((f) => /\.lake|["'/]fwcore["']|FWCORE|bin\/fwcore/.test(readFileSync(f, "utf8")))).map((c) => c.id);
    // measure-wktr runs the binary through measure-chromium/src/fwcore.mjs (a declared extra read), not by itself
    expect([...users, "packages/measure-wktr"].sort()).toEqual([...FWCORE_USERS].sort());
    for (const c of candidateChecks(root, true)) expect(inScope(c.reads, "lean/.lake/build/bin/fwcore"), c.id).toBe(FWCORE_USERS.includes(c.id) || c.id === "check.sh");
    // a Lean change selects check.sh and every fwcore user
    expect(checksWithReads(root, ["lean/Fw/A.lean"]).map((c) => c.id).sort()).toEqual(["check.sh", ...FWCORE_USERS].sort());
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
    for (const c of candidateChecks(root)) for (const g of c.reads) expect(tracked.some((f) => inScope([g], f)), `${c.id}: ${g}`).toBe(true);
  });
});

// ---- the key over the declared inputs --------------------------------------------------------------------------------

/** A concrete file inside a glob: `a/**` -> `a/f.txt`, an exact path stays. */
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
      expect(fx.checks.map((c) => c.id)).toEqual(["install", "check.sh", "apps/runner", "packages/contracts", "packages/lone"]);
      expect(fx.checks.find((c) => c.id === "apps/runner")!.reads).toContain("packages/contracts/**");
    } finally { fx.done(); }
  });
  it("a change outside the inputs leaves the key; a change inside moves it (every glob of every check)", () => {
    const fx = fixture();
    try {
      for (const c of fx.checks) {
        const k0 = inputKey(fx.dir, c.reads);
        // outside: a file no glob selects, and the declared inputs of every check that does not overlap this one
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
