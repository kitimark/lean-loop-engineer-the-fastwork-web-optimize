// Facts for the Builds tab: main's first-parent log, the work graph, the site registry (variants, presets). I/O only: which
// tasks are listed, their order, the targets and the searches are Lean `console.builds` (`Fw.Console.Builds`).
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import type { Core } from "../core/index.ts";
import type { BuildAt } from "./manager.ts";
import { gitIn, type Git } from "./facts.ts";

export type Target = { kind: string; ref: string | null; sha: string };
export type PortRow = { id: string; task: string; group: string; sha: string; landedAt: number; title: string; slot: string; search: string; target: Target };
export type OptRow = { id: string; kind: string; name: string; search: string; status: string; note: string | null; slot: string; target: Target };
export type Builds = { mainSha: string; ports: PortRow[]; optimize: OptRow[]; searches: string[] };

const LOG_MAX = 2000;

export type Flag = { part: string; variant: string; kind: string; requires: string[] };
export type Preset = { name: string; fw: Record<string, string> };

/** Every variant of each `part.json` below `apps/site/src/parts`, in directory then file order. */
export function readFlags(root: string): Flag[] {
  const dir = join(root, "apps/site/src/parts");
  if (!existsSync(dir)) return [];
  return readdirSync(dir).sort().flatMap((d) => {
    const f = join(dir, d, "part.json");
    if (!existsSync(f)) return [];
    const p = JSON.parse(readFileSync(f, "utf8")) as { id: string; variants?: Record<string, { kind?: string }>; requires?: Record<string, string[]> };
    return Object.entries(p.variants ?? {}).map(([variant, v]) => ({
      part: p.id, variant, kind: v.kind ?? "optimized", requires: p.requires?.[`${p.id}:${variant}`] ?? [],
    }));
  });
}

/** Every `apps/site/src/registry/presets/*.json`, `extends` resolved into `fw` (base first, own entries over it; an unknown base or
 *  a cycle adds nothing). TS stand-in: mirrors `presetEntries` in `apps/site/src/registry/resolve.ts`; the Lean op takes the resolved `fw`. */
export function readPresets(root: string): Preset[] {
  const dir = join(root, "apps/site/src/registry/presets");
  if (!existsSync(dir)) return [];
  const raw = new Map<string, { extends?: string; fw: Record<string, string> }>();
  for (const n of readdirSync(dir).filter((x) => x.endsWith(".json")).sort()) {
    const p = JSON.parse(readFileSync(join(dir, n), "utf8")) as { name?: string; extends?: string; fw?: Record<string, string> };
    raw.set(p.name ?? n.slice(0, -5), { extends: p.extends, fw: p.fw ?? {} });
  }
  const resolve = (name: string, seen: string[]): Record<string, string> => {
    const p = raw.get(name);
    if (!p || seen.includes(name)) return {};
    return { ...(p.extends ? resolve(p.extends, [...seen, name]) : {}), ...p.fw };
  };
  return [...raw.keys()].map((name) => ({ name, fw: resolve(name, []) }));
}

/** The registry facts `console.buildsSearch` reads: parts (variants in file order, impls, rules) and the presets as files give them. */
export type Registry = {
  parts: { id: string; variants: string[]; impls: string[]; requires: Record<string, string[]>; conflicts: Record<string, string[]> }[];
  presets: { name: string; extends?: string; fw: Record<string, string> }[];
};

/** Read `part.json` and the preset files (I/O only). The validity rules are Lean `Fw.Console.BuildsOpen.validate`. */
export function readRegistry(root: string): Registry {
  const parts: Registry["parts"] = [];
  const pdir = join(root, "apps/site/src/parts");
  if (existsSync(pdir)) {
    for (const d of readdirSync(pdir).sort()) {
      const f = join(pdir, d, "part.json");
      if (!existsSync(f)) continue;
      const p = JSON.parse(readFileSync(f, "utf8")) as { id: string; variants?: Record<string, unknown>; impls?: string[]; requires?: Record<string, string[]>; conflicts?: Record<string, string[]> };
      parts.push({ id: p.id, variants: Object.keys(p.variants ?? {}), impls: p.impls ?? [], requires: p.requires ?? {}, conflicts: p.conflicts ?? {} });
    }
  }
  const presets: Registry["presets"] = [];
  const rdir = join(root, "apps/site/src/registry/presets");
  if (existsSync(rdir)) {
    for (const n of readdirSync(rdir).filter((x) => x.endsWith(".json")).sort()) {
      const p = JSON.parse(readFileSync(join(rdir, n), "utf8")) as { name?: string; extends?: string; fw?: Record<string, string> };
      presets.push({ name: p.name ?? n.slice(0, -5), ...(p.extends ? { extends: p.extends } : {}), fw: p.fw ?? {} });
    }
  }
  return { parts, presets };
}

export type WorkTask = { id: string; title: string; evidence?: string };

export function workGraphTasks(root: string): WorkTask[] {
  const f = join(root, "docs/team/work-graph.json");
  if (!existsSync(f)) return [];
  const g = JSON.parse(readFileSync(f, "utf8")) as { tasks?: { id: string; title?: string; evidence?: string }[] } | { id: string; title?: string; evidence?: string }[];
  return (Array.isArray(g) ? g : g.tasks ?? []).map((t) => ({ id: t.id, title: t.title ?? "", evidence: t.evidence }));
}

const landCache = new Map<string, string>();

/** Evidence land facts: for each port or fix task whose `evidence` names a commit on main (the first hex token that is a
 *  commit), the land commit: the evidence commit when it is on the first-parent line, else the oldest first-parent commit of main
 *  that has it as an ancestor (found by binary search: `--first-parent --ancestry-path` lists nothing across a merge). Lean decides the row; this only resolves shas. Tasks without a resolvable commit are returned in `missing`. */
export function evidenceLands(tasks: WorkTask[], git: Git): { evidence: { task: string; sha: string }[]; missing: string[] } {
  const evidence: { task: string; sha: string }[] = [];
  const missing: string[] = [];
  const fp = (git(["rev-list", "--first-parent", "main"]) ?? "").split("\n").filter(Boolean); // newest first
  const firstParent = new Set(fp);
  // `has(i)`: ev is an ancestor of fp[i]; true for i <= k along the line, so the oldest such commit is fp[k] (binary search)
  const oldestWith = (ev: string): string | null => {
    const hit = landCache.get(ev);
    if (hit) return hit;
    const has = (i: number) => git(["merge-base", "--is-ancestor", ev, fp[i]!]) !== null;
    if (fp.length === 0 || !has(0)) return null;
    let lo = 0, hi = fp.length - 1; // has(lo) true; find the last true
    while (lo < hi) { const mid = (lo + hi + 1) >> 1; if (has(mid)) lo = mid; else hi = mid - 1; }
    landCache.set(ev, fp[lo]!);
    return fp[lo]!;
  };
  for (const t of tasks) {
    if (!/^(port|fix)-/.test(t.id)) continue;
    let land: string | null = null;
    for (const tok of (t.evidence ?? "").match(/\b[0-9a-f]{7,40}\b/g) ?? []) {
      const full = (git(["rev-parse", "--verify", "--quiet", `${tok}^{commit}`]) ?? "").trim();
      if (!full) continue;
      land = firstParent.has(full) ? full : oldestWith(full);
      if (land) break;
    }
    if (land) evidence.push({ task: t.id, sha: land }); else missing.push(t.id);
  }
  return { evidence, missing };
}

/** main's first-parent log, newest first: sha, committer time (s), full message. */
export function mainLog(git: Git, max = LOG_MAX): { sha: string; time: number; body: string }[] {
  const out = git(["log", "--first-parent", `-n${max}`, "--format=%H%x1f%ct%x1f%B%x1e", "main"]);
  if (out === null) return [];
  const res: { sha: string; time: number; body: string }[] = [];
  for (const rec of out.split("\x1e")) {
    const [sha, time, body] = rec.trim().split("\x1f");
    if (sha && /^[0-9a-f]{7,64}$/.test(sha)) res.push({ sha, time: Number(time) || 0, body: body ?? "" });
  }
  return res;
}

/** The rows of the Builds tab: Lean `console.builds` over the gathered facts. */
export async function buildRows(root: string, core: Pick<Core, "ops">, git: Git = gitIn(root)): Promise<Builds> {
  const mainSha = (git(["rev-parse", "main"]) ?? "").trim();
  const log = mainLog(git);
  const tasks = workGraphTasks(root);
  const r = await core.ops("console.builds", {
    main: mainSha, log, known: tasks.map((t) => ({ id: t.id, title: t.title })), evidence: evidenceLands(tasks, git).evidence, flags: readFlags(root), presets: readPresets(root),
  });
  return { mainSha, ports: r.ports as PortRow[], optimize: r.optimize as OptRow[], searches: r.searches as string[] };
}

/** The row a start request names (`port:<task>`, `flag:<part:variant>`, `preset:<name>`), or null: the id is only a key into
 *  the rows Lean just decided, so a request cannot choose a commit or a search. */
export function rowAt(b: Builds, id: string): BuildAt | null {
  const p = b.ports.find((x) => x.id === id);
  if (p) return { slot: p.slot, target: p.target, search: p.search };
  const o = b.optimize.find((x) => x.id === id);
  return o ? { slot: o.slot, target: o.target, search: o.search } : null;
}
