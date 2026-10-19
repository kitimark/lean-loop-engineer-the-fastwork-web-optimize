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

/** Every `apps/site/src/registry/presets/*.json`. */
export function readPresets(root: string): Preset[] {
  const dir = join(root, "apps/site/src/registry/presets");
  if (!existsSync(dir)) return [];
  return readdirSync(dir).filter((n) => n.endsWith(".json")).sort().map((n) => {
    const p = JSON.parse(readFileSync(join(dir, n), "utf8")) as { name?: string; fw?: Record<string, string> };
    return { name: p.name ?? n.slice(0, -5), fw: p.fw ?? {} };
  });
}

export function workGraphTasks(root: string): { id: string; title: string }[] {
  const f = join(root, "docs/team/work-graph.json");
  if (!existsSync(f)) return [];
  const g = JSON.parse(readFileSync(f, "utf8")) as { tasks?: { id: string; title?: string }[] } | { id: string; title?: string }[];
  return (Array.isArray(g) ? g : g.tasks ?? []).map((t) => ({ id: t.id, title: t.title ?? "" }));
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
  const r = await core.ops("console.builds", {
    main: mainSha, log: mainLog(git), known: workGraphTasks(root), flags: readFlags(root), presets: readPresets(root),
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
