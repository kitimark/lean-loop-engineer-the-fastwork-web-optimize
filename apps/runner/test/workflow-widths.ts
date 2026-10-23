// Test helper of land-overflow-widths.test.ts (task land-lane-circleci): the most jobs one run of a workflow can hold at once, derived from
// its file in .github/workflows. TS stand-in: this is a check on the table of Lean `Fw.Ci.Overflow.widths`, not a decision.
//
// The bound: a job counts min(matrix size, max-parallel, 5 when its runner is a macOS one). Two jobs run at the same time only if neither
// is an ancestor of the other in the `needs` graph, so the width is the heaviest set of jobs no two of which are related (a maximum
// weight antichain). Every job counts, whatever its `if:` (a conditional job is counted as if it ran: over-count is the safe side).
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join } from "node:path";

/** The macOS jobs a Free account runs at once (CONFIRMED: https://docs.github.com/en/actions/reference/limits, "Job concurrency limits", Free). */
export const MACOS_CAP = 5;

export type Job = { name: string; line: number; needs: string[]; macos: boolean; /** matrix size: a number, or "dynamic" (an axis or the whole matrix comes from fromJSON/outputs) */ size: number | "dynamic"; /** max-parallel: a number, "dynamic", or null for none */ maxParallel: number | "dynamic" | null };
export type Workflow = { file: string; name: string; jobs: Job[] };

const indentOf = (l: string): number => l.length - l.trimStart().length;

/** Count the items of an inline list `[a, b, c]` (no nesting in the workflow files). */
const inlineLen = (s: string): number | null => { const m = /^\[(.*)\]\s*(#.*)?$/.exec(s.trim()); return m ? m[1]!.split(",").filter((x) => x.trim() !== "").length : null; };

export function parseWorkflow(root: string, file: string): Workflow {
  const text = readFileSync(join(root, ".github/workflows", file), "utf8");
  const L = text.split("\n");
  const name = /^name:\s*(\S+)/m.exec(text)![1]!;
  const jobsAt = L.findIndex((l) => l === "jobs:");
  if (jobsAt < 0) throw new Error(`${file}: no jobs:`);
  const starts: { name: string; at: number }[] = [];
  for (let i = jobsAt + 1; i < L.length; i++) { const m = /^  ([A-Za-z0-9_-]+):\s*$/.exec(L[i]!); if (m) starts.push({ name: m[1]!, at: i }); }
  const jobs: Job[] = starts.map((s, k) => {
    const end = k + 1 < starts.length ? starts[k + 1]!.at : L.length;
    const body = L.slice(s.at + 1, end);
    const own = (re: RegExp) => body.map((l) => (indentOf(l) === 4 ? re.exec(l) : null)).find((m) => m !== null) ?? null;
    const nm = own(/^    needs:\s*(.*)$/);
    const needs = !nm ? [] : (() => {
      const v = nm[1]!.trim();
      if (v.startsWith("[")) return v.slice(1, v.indexOf("]")).split(",").map((x) => x.trim()).filter(Boolean);
      if (v !== "") return [v];
      throw new Error(`${file}:${s.name}: needs: in block form is not parsed; use [a, b]`);
    })();
    const runsOn = own(/^    runs-on:\s*(.*)$/)?.[1] ?? "";
    // strategy block: lines indented deeper than 4 after `    strategy:`
    const st = body.findIndex((l) => /^    strategy:\s*$/.test(l));
    let size: number | "dynamic" = 1, maxParallel: number | "dynamic" | null = null;
    if (st >= 0) {
      const sb: string[] = [];
      for (let i = st + 1; i < body.length && (body[i]!.trim() === "" || indentOf(body[i]!) > 4); i++) sb.push(body[i]!);
      const mp = sb.map((l) => /^      max-parallel:\s*(.+)$/.exec(l)).find((m) => m);
      if (mp) maxParallel = /^\d+$/.test(mp[1]!.trim()) ? Number(mp[1]!.trim()) : "dynamic";
      const mi = sb.findIndex((l) => /^      matrix:/.test(l));
      if (mi >= 0) {
        const rest = /^      matrix:\s*(.*)$/.exec(sb[mi]!)![1]!.trim();
        if (rest !== "") size = "dynamic"; // matrix: ${{ ... }}
        else {
          let prod = 1, axes = 0, include = 0, dyn = false;
          for (let i = mi + 1; i < sb.length && (sb[i]!.trim() === "" || indentOf(sb[i]!) > 6); i++) {
            const l = sb[i]!;
            if (indentOf(l) !== 8) continue;
            const km = /^        ([A-Za-z0-9_-]+):\s*(.*)$/.exec(l);
            if (!km) continue;
            if (km[1] === "exclude") continue; // an exclusion only removes jobs: ignored (over-count)
            if (km[1] === "include") {
              for (let j = i + 1; j < sb.length && indentOf(sb[j]!) > 8; j++) if (/^          - /.test(sb[j]!)) include++;
              continue;
            }
            const n = inlineLen(km[2]!);
            if (n === null) dyn = true; else { prod *= n; axes++; }
          }
          size = dyn ? "dynamic" : (axes > 0 ? prod : 0) + include;
        }
      }
    }
    return { name: s.name, line: s.at + 1, needs, macos: /^(macos|xcode)/.test(runsOn.trim()), size, maxParallel };
  });
  return { file, name, jobs };
}

/** Jobs a job can hold at once; `maxSizeOf` gives the largest matrix of a dynamic one. */
export function weight(j: Job, maxSizeOf: (j: Job) => number): number {
  const size = j.size === "dynamic" ? maxSizeOf(j) : j.size;
  const mp = j.maxParallel === null ? Infinity : j.maxParallel === "dynamic" ? Infinity : j.maxParallel;
  return Math.min(size, mp, j.macos ? MACOS_CAP : Infinity);
}

/** The heaviest set of jobs no two of which are ancestor and descendant (they cannot run at once). */
export function width(w: Workflow, maxSizeOf: (j: Job) => number): number { return widest(w, maxSizeOf).n; }

/** `width` and the jobs (name, weight) of one heaviest set. */
export function widest(w: Workflow, maxSizeOf: (j: Job) => number): { n: number; jobs: string[] } {
  const idx = new Map(w.jobs.map((j, i) => [j.name, i]));
  const n = w.jobs.length;
  const anc: Set<number>[] = w.jobs.map(() => new Set());
  const up = (i: number, seen: Set<number>) => { for (const p of w.jobs[i]!.needs) { const k = idx.get(p); if (k === undefined) throw new Error(`${w.file}: ${w.jobs[i]!.name} needs unknown job ${p}`); if (!seen.has(k)) { seen.add(k); up(k, seen); } } };
  for (let i = 0; i < n; i++) up(i, anc[i]!);
  const related = (a: number, b: number) => anc[a]!.has(b) || anc[b]!.has(a);
  const wt = w.jobs.map((j) => weight(j, maxSizeOf));
  let best = 0, pick: number[] = [];
  const go = (i: number, chosen: number[], sum: number) => {
    if (sum > best) { best = sum; pick = chosen; }
    for (let k = i; k < n; k++) if (chosen.every((c) => !related(c, k))) go(k + 1, [...chosen, k], sum + wt[k]!);
  };
  go(0, [], 0);
  return { n: best, jobs: pick.map((k) => `${w.jobs[k]!.name}=${wt[k]}`) };
}

/** The largest matrix `gate-jobs.mjs` plans over every input the breakpoint-gate workflow accepts
 *  (breakpoint-gate.yml: runs 1|2|3, free 4|8|12|20, times measured|base|cached|reduced, engines both|chromium|playwright-webkit). */
export function gateJobsMax(root: string, node = process.execPath): number {
  let best = 0;
  for (const runs of [1, 2, 3]) for (const free of [4, 8, 12, 20]) for (const times of ["measured", "base", "cached", "reduced"]) for (const engines of ["both", "chromium", "playwright-webkit"]) {
    const out = execFileSync(node, [join(root, ".github/scripts/gate-jobs.mjs"), "--params", times, "--runs", String(runs), "--free", String(free), "--engines", engines], { cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
    best = Math.max(best, (JSON.parse(out) as { include: unknown[] }).include.length);
  }
  return best;
}

/** The largest linux and apple leg counts `plan.mjs` plans for the trajectory-probe workflow over every engines and widths input (a comma list of
 *  390, 640, 641, 1280 without repeats, or empty). */
export function trajectoryMax(root: string, node = process.execPath): { linux: number; apple: number } {
  const ws = [390, 640, 641, 1280];
  const subsets: number[][] = [];
  for (let m = 0; m < 16; m++) subsets.push(ws.filter((_, i) => m & (1 << i)));
  let linux = 0, apple = 0;
  for (const engines of ["both", "chromium", "playwright-webkit"]) for (const s of subsets) {
    const out = execFileSync(node, [join(root, "packages/gate-breakpoints/src/trajectory/plan.mjs"), engines, s.join(",")], { cwd: root, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
    const p = JSON.parse(out) as { linux: { include: unknown[] }; apple: { include: unknown[] } };
    linux = Math.max(linux, p.linux.include.length); apple = Math.max(apple, p.apple.include.length);
  }
  return { linux, apple };
}

/** The `(name, width)` rows of `def widths` in lean/Fw/Ci/Overflow.lean. */
export function widthTable(lean: string): Map<string, number> {
  return new Map([...(/def widths[\s\S]*?\]\n/.exec(lean)![0]).matchAll(/\("([a-z0-9-]+)", (\d+)\)/g)].map((m) => [m[1]!, Number(m[2])]));
}

/** The one table check: the row of workflow `w` is at least the derived width (exactly it when `exact`); throws with the derived width in the message. */
export function checkRow(table: Map<string, number>, w: Workflow, derived: number, exact = false): void {
  const row = table.get(w.name);
  if (row === undefined || (exact ? row !== derived : row < derived)) throw new Error(`${w.file}: Lean widths row ${row ?? "missing"} (derived ${derived}${exact ? ", must be equal" : ""})`);
}
