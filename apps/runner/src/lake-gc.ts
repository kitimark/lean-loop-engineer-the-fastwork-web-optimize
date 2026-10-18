// fw lake-gc (task lean-bin-slim): which files of the Lake artifact cache no checkout uses any more. This file only
// gathers facts (one lstat per cache entry) and prints; what is listed, and whether the cache is over budget, is Lean
// (`fwcore` op ops.lakeGc, rules and proofs in lean/Fw/Ops/LakeGc.lean, golden packages/contracts/golden/ops/lakegc.jsonl).
// It never deletes: it prints the command, the user runs it. Docs: docs/team/tools/lake-gc.md.
import { spawnSync } from "node:child_process";
import { lstatSync, readdirSync } from "node:fs";
import { join } from "node:path";

export const LAKE_GC_USAGE =
  "usage: fw lake-gc [--list | --json] [--check] [--age-floor <seconds>] [--root <cache>/artifacts]\n" +
  "  (no flag)  summary and the delete command      --list   the listed paths, one per line\n" +
  "  --json     the Lean reply                       --check  exit 1 when the cache is over the Lean budget";

export type Fact = { name: string; file: boolean; links: number; mtime: number; size: number };
export type LakeGcReply = {
  rootOk: boolean; paths: string[]; listed: number; listBytes: number; cacheBytes: number; files: number;
  ageFloor: number; budget: number; alert: boolean;
};
export type LakeGcArgs = { mode: "summary" | "list" | "json"; check: boolean; ageFloor?: number; root?: string };
export type Call = (req: Record<string, unknown>) => Record<string, unknown>;

export class LakeGcUsage extends Error {}

export function parseLakeGcArgs(argv: string[]): LakeGcArgs {
  const a: LakeGcArgs = { mode: "summary", check: false };
  for (let i = 0; i < argv.length; i++) {
    const x = argv[i];
    if (x === "--list") a.mode = "list";
    else if (x === "--json") a.mode = "json";
    else if (x === "--check") a.check = true;
    else if (x === "--age-floor" && /^\d+$/.test(argv[i + 1] ?? "")) a.ageFloor = Number(argv[++i]);
    else if (x === "--root" && argv[i + 1]) a.root = argv[++i];
    else throw new LakeGcUsage(`unknown or incomplete argument: ${x}\n${LAKE_GC_USAGE}`);
  }
  return a;
}

/** The artifacts dir of the cache Lake uses for `lean/` (Lake sets LAKE_CACHE_DIR in `lake env`,
 *  Lake/Config/Env.lean:310@v4.35.0). */
export function artifactsRoot(top: string): string {
  const r = spawnSync("lake", ["env", "printenv", "LAKE_CACHE_DIR"], { cwd: join(top, "lean"), encoding: "utf8" });
  const dir = (r.stdout ?? "").trim();
  if (r.status !== 0 || !dir) throw new Error(`lake env printenv LAKE_CACHE_DIR failed in lean/: ${(r.stderr ?? "").trim()}`);
  return join(dir, "artifacts");
}

/** One fact per entry of `root` (lstat: a symlink is not a file); an entry that vanished meanwhile is skipped. */
export function gatherFacts(root: string): Fact[] {
  const out: Fact[] = [];
  for (const name of readdirSync(root)) {
    try {
      const s = lstatSync(join(root, name));
      out.push({ name, file: s.isFile(), links: s.nlink, mtime: Math.floor(s.mtimeMs / 1000), size: s.size });
    } catch { /* removed between readdir and lstat */ }
  }
  return out;
}

const gb = (n: number) => (n / 1e9).toFixed(2);

/** The printed lines of a reply in `mode`. */
export function render(root: string, r: LakeGcReply, mode: LakeGcArgs["mode"]): string[] {
  if (mode === "json") return [JSON.stringify(r)];
  if (mode === "list") return r.paths;
  const lines = [
    `lake-gc: ${root}`,
    `  cache:  ${r.files} entries, ${gb(r.cacheBytes)} GB (budget ${gb(r.budget)} GB)${r.alert ? "  OVER BUDGET" : ""}`,
  ];
  if (!r.rootOk) return [...lines, "  root refused by Lean (not an absolute <...>/artifacts path of plain names): nothing listed"];
  lines.push(`  listed: ${r.listed} files, ${gb(r.listBytes)} GB (no checkout links them, unchanged for >= ${r.ageFloor} s)`);
  if (r.listed > 0) lines.push("  to delete them, run:", "    pnpm -s fw lake-gc --list | xargs rm -f --");
  return lines;
}

/** `fw lake-gc`: gather, ask Lean, print. Exit 1 only with --check and an over-budget cache. */
export function lakeGcCli(argv: string[], top: string, call: Call, print: (s: string) => void = console.log): number {
  const a = parseLakeGcArgs(argv);
  const root = a.root ?? artifactsRoot(top);
  const req: Record<string, unknown> = { op: "ops.lakeGc", root, now: Math.floor(Date.now() / 1000), files: gatherFacts(root) };
  if (a.ageFloor !== undefined) req.ageFloor = a.ageFloor;
  const r = call(req) as unknown as LakeGcReply;
  for (const l of render(root, r, a.mode)) print(l);
  return a.check && r.alert ? 1 : 0;
}
