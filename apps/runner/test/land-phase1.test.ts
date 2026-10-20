// Land phase 1 (task land-phase1-slow): when the local fwcore build is needed. The rule is Lean `Fw.Console.LandTier.phase1Build`
// (golden land-phase1.jsonl); the premise that makes a skip sound is that no build-free path is read by a default Lake target,
// checked here against the import closure of the lakefile's roots.
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { BUILD_FREE, binaryChange, inScope, phase1Build, selectBin } from "../src/land.ts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
const lean = join(root, "lean");
type Row = { name: string; request: { changed: string[]; d0: string | null; d1: string | null; decls: { id: string; reads: string[] }[] }; response: { build: boolean; binaryChange: string[]; select: string[] } };
const rows: Row[] = readFileSync(join(root, "packages/contracts/golden/console/land-phase1.jsonl"), "utf8").trim().split("\n").map((l) => JSON.parse(l));

describe("phase 1 follows the Lean golden", () => {
  it("has a case for each branch", () => {
    expect(rows.some((r) => r.response.build)).toBe(true);
    expect(rows.some((r) => !r.response.build && r.request.changed.some((p) => p.startsWith("lean/")))).toBe(true);
    expect(rows.some((r) => !r.response.build && !r.request.changed.some((p) => p.startsWith("lean/")))).toBe(true);
  });
  for (const r of rows) {
    it(r.name, () => {
      expect(phase1Build(r.request.changed)).toBe(r.response.build);
      expect(binaryChange(r.request.changed)).toEqual(r.response.binaryChange);
      expect(selectBin(r.request.decls, r.request.changed, r.request.d0, r.request.d1)).toEqual(r.response.select);
    });
  }
});

/** The Lake roots of the default targets (lean/lakefile.toml): the `Fw` globs, the executables' roots and `FwCoreCli`'s roots. */
const modules = (dir: string, base: string): string[] =>
  readdirSync(join(dir, base), { withFileTypes: true }).flatMap((e) =>
    e.isDirectory() ? modules(dir, `${base}/${e.name}`) : e.name.endsWith(".lean") ? [`${base}/${e.name.slice(0, -5)}`] : []);
const rootsOf = (dir: string): string[] => {
  const toml = readFileSync(join(dir, "lakefile.toml"), "utf8");
  const roots = [...toml.matchAll(/^root = "(\w+)"/gm)].map((m) => m[1]!);
  const libs = [...toml.matchAll(/^roots = \[([^\]]*)\]/gm)].flatMap((m) => [...m[1]!.matchAll(/"(\w+)"/g)].map((x) => x[1]!));
  return [...roots, ...libs, "Fw", ...modules(dir, "Fw").map((m) => m.replaceAll("/", "."))];
};
const closure = (dir: string, roots: string[]): Set<string> => {
  const seen = new Set<string>();
  const todo = [...roots];
  while (todo.length) {
    const m = todo.pop()!;
    if (seen.has(m)) continue;
    seen.add(m);
    const f = join(dir, `${m.replaceAll(".", "/")}.lean`);
    if (!existsSync(f)) continue;
    for (const x of readFileSync(f, "utf8").matchAll(/^(?:public\s+)?import\s+(\S+)/gm)) todo.push(x[1]!);
  }
  return seen;
};

describe("no build-free path is a build input", () => {
  const files = (dir: string, base: string): string[] => readdirSync(join(dir, base), { withFileTypes: true })
    .filter((e) => e.name !== ".lake" && e.name !== ".serena")
    .flatMap((e) => (e.isDirectory() ? files(dir, `${base}/${e.name}`) : [`${base}/${e.name}`]));
  const all = files(root, "lean");
  const free = all.filter((f) => inScope(BUILD_FREE, f));
  it("the build-free set is not empty and every file of it exists", () => {
    expect(free.length).toBeGreaterThan(40);
    for (const g of BUILD_FREE.filter((g) => !g.endsWith("**"))) expect(existsSync(join(root, g))).toBe(true);
  });
  it("no Lake module of the import closure of the default targets is build-free", () => {
    const mods = closure(lean, rootsOf(lean));
    const files = [...mods].map((m) => `lean/${m.replaceAll(".", "/")}.lean`).filter((f) => existsSync(join(root, f)));
    expect(files.length).toBeGreaterThan(250);
    expect(files.filter((f) => inScope(BUILD_FREE, f))).toEqual([]);
  });
  it("no Lean source embeds a build-free file at elaboration time", () => {
    const bad: string[] = [];
    for (const f of all.filter((x) => x.endsWith(".lean") && !inScope(BUILD_FREE, x))) {
      const src = readFileSync(join(root, f), "utf8");
      for (const m of src.matchAll(/include_str\s+"([^"]+)"/g)) {
        const target = relative(root, join(root, dirname(f), m[1]!));
        if (inScope(BUILD_FREE, target)) bad.push(`${f} -> ${target}`);
      }
    }
    expect(bad).toEqual([]);
  });
});
