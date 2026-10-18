// lean/Fw.lean is the library root (`import Fw` in FwTest and MathView), kept by hand. This check (run by check.sh)
// guards what a hand-kept list, merged with `merge=union`, can get wrong:
//   1. no `import` line is repeated in Fw.lean (union can duplicate a line both branches added);
//   2. every import of Fw.lean names a module that exists;
//   3. every module lean/Fw/**/*.lean is imported by Fw.lean, directly or through the modules it imports, or else by
//      another root that is not a library file (FwTest/**, FwTestMain, Main, BreakgenMain, scripts/*.lean: golden
//      generators and executables, which `import Fw` users must not pull in), or defines its own `main`. A module
//      reached by no root is built by the `Fw.*` glob but unused: a forgotten registration.
// Usage: node scripts/check-imports.mjs [<lean dir>]   (default: the directory above this script)
import { readFileSync, readdirSync, existsSync, statSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const root = process.argv[2] ?? join(dirname(fileURLToPath(import.meta.url)), "..");

const walk = (d) => !existsSync(d) ? [] : readdirSync(d).flatMap((n) => {
  const p = join(d, n);
  return statSync(p).isDirectory() ? walk(p) : p.endsWith(".lean") ? [p] : [];
});
const modOf = (f) => relative(root, f).replace(/\.lean$/, "").split("/").join(".");
const fileOf = (m) => join(root, ...m.split(".")) + ".lean";
/** the `import X` lines of a source (a trailing `-- comment` is ignored; only `Fw...` modules matter) */
const importsOf = (src) => src.split("\n").flatMap((l) => {
  const m = /^import\s+(Fw(?:\.[A-Za-z0-9_]+)*)\s*(?:--.*)?$/.exec(l);
  return m ? [m[1]] : [];
});

const errors = [];
const rootSrc = readFileSync(join(root, "Fw.lean"), "utf8");
const direct = importsOf(rootSrc);
const seen = new Set();
for (const m of direct) {
  if (seen.has(m)) errors.push(`Fw.lean imports ${m} more than once`);
  seen.add(m);
  if (!existsSync(fileOf(m))) errors.push(`Fw.lean imports ${m}, but ${relative(root, fileOf(m))} does not exist`);
}

const all = walk(join(root, "Fw")).map(modOf).sort();
const closure = new Set();
const stack = [...direct];
while (stack.length) {
  const m = stack.pop();
  if (closure.has(m) || !existsSync(fileOf(m))) continue;
  closure.add(m);
  stack.push(...importsOf(readFileSync(fileOf(m), "utf8")));
}
const other = new Set();
const others = [...walk(join(root, "FwTest")), ...["FwTestMain", "Main", "BreakgenMain", "SweepsgenMain"].map((n) => join(root, n + ".lean")),
  ...walk(join(root, "scripts"))].filter(existsSync);
const st2 = others.flatMap((f) => importsOf(readFileSync(f, "utf8")));
while (st2.length) {
  const m = st2.pop();
  if (other.has(m) || !existsSync(fileOf(m))) continue;
  other.add(m);
  st2.push(...importsOf(readFileSync(fileOf(m), "utf8")));
}
/** library modules run by a one-line driver (`lean --run`), so no root imports them; each with the reason */
const DRIVER_RUN = new Map([
  ["Fw.Gate.Scope", "run by packages/gate-breakpoints/scripts/scopegen.mjs through Fw.Gate.ScopeGen"],
  ["Fw.Gate.ScopeGen", "run by packages/gate-breakpoints/scripts/scopegen.mjs (a two-line driver)"],
  ["Fw.Parts.MorphMountGolden", "run with a one-line driver (see its header)"],
]);
for (const m of DRIVER_RUN.keys()) if (process.argv[2] === undefined && !existsSync(fileOf(m))) errors.push(`DRIVER_RUN names ${m}, which does not exist (remove it from scripts/check-imports.mjs)`);
const own = (m) => /^def main\b/m.test(readFileSync(fileOf(m), "utf8"));
for (const m of all) {
  if (!closure.has(m) && !other.has(m) && !own(m) && !DRIVER_RUN.has(m)) errors.push(`${m} is imported by no root (add "import ${m}" to lean/Fw.lean, or to the test or script that uses it)`);
}

if (errors.length) {
  console.error(`check-imports: ${errors.length} problem(s):\n  ${errors.join("\n  ")}`);
  process.exit(1);
}
console.log(`check-imports: ok (${all.length} modules under Fw/, ${direct.length} direct imports in Fw.lean, each module reachable, no repeated import)`);
