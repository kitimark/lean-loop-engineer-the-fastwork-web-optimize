import { execFileSync } from "node:child_process";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import type { LintFinding } from "./plan.ts";

export type Kind = "module" | "workflow" | "other";
export type Gap = { script: string; path: string };
export type Fresh = "new" | "existing" | "open";
export type ClosureTask = { id: string; owner: string; stream: string; writes: string[]; done: boolean };
export type ScopeReq = { op: "console.landScope"; writes: string[]; names: string[]; allow: string[]; paths: string[]; task: string; stream: string };
export type ScopeBatch = (reqs: ScopeReq[]) => Promise<{ violations: string[] }[]>;

const segs = (s: string) => s.split("/").filter((x) => x !== "" && x !== ".");
const segMatch = (g: string, s: string): boolean =>
  g === "" ? s === "" : g[0] === "*" ? segMatch(g.slice(1), s) || (s !== "" && segMatch(g, s.slice(1))) : s !== "" && g[0] === s[0] && segMatch(g.slice(1), s.slice(1));
const globMatch = (g: string[], p: string[]): boolean =>
  g.length === 0 ? p.length === 0 : g[0] === "**" ? globMatch(g.slice(1), p) || (p.length > 0 && globMatch(g, p.slice(1))) : p.length > 0 && segMatch(g[0]!, p[0]!) && globMatch(g.slice(1), p.slice(1));
const matchesPath = (g: string[], p: string[]) => p.some((_, k) => globMatch(g, p.slice(0, k + 1)));

export function inOne(w: string, f: string | string[]): boolean {
  if (w.startsWith("!")) return false;
  const p = typeof f === "string" ? segs(f) : f, g = segs(w);
  const lit = g.findIndex((x) => x.includes("*"));
  for (let i = 0; i < (lit < 0 ? g.length : lit); i++) if (p[i] !== g[i]) return false;
  return p.length > 0 && !p.includes("..") && matchesPath(g, p);
}

const memo = new WeakMap<string[], { segs: string[][]; fresh: Map<string, Fresh> }>();
const memoOf = (tracked: string[]) => {
  let c = memo.get(tracked);
  if (!c) memo.set(tracked, (c = { segs: tracked.map(segs), fresh: new Map() }));
  return c;
};

const lastSeg = (w: string) => w.split("/").at(-1) ?? "";
const wild = (s: string) => s === "*" || s === "**";
const leanFile = (w: string) => lastSeg(w).endsWith(".lean") || wild(lastSeg(w));
const ymlFile = (w: string) => lastSeg(w).endsWith(".yml") || lastSeg(w).endsWith(".yaml") || wild(lastSeg(w));

export function kindOf(w: string): Kind {
  if (w.startsWith("lean/Fw/") && leanFile(w)) return "module";
  if (w.startsWith(".github/workflows/") && ymlFile(w)) return "workflow";
  return "other";
}

const triggerFix = ["lean/Fw/Ci/Trigger.lean", "packages/contracts/golden/ci/triggers.jsonl"];
const wfTables = [...triggerFix, "lean/Fw/Ci/Intent.lean", "packages/contracts/golden/ci/intent.jsonl", "lean/Fw/Ci/Overflow.lean"];

export function implied(k: Kind): string[] {
  return k === "module" ? ["lean/Fw.lean"] : k === "workflow" ? wfTables : [];
}

export function freshOf(tracked: string[], w: string): Fresh {
  const m = memoOf(tracked);
  let r = m.fresh.get(w);
  if (!r) m.fresh.set(w, (r = m.segs.some((f) => inOne(w, f)) ? (w.includes("*") ? "open" : "existing") : "new"));
  return r;
}

const needs = (tracked: string[], writes: string[], f: Fresh) =>
  [...new Set(writes.filter((w) => kindOf(w) !== "other" && freshOf(tracked, w) === f).flatMap((w) => implied(kindOf(w))))];
const names = (writes: string[], p: string) => !writes.some((w) => w.startsWith("!") && inOne(w.slice(1), p)) && writes.some((w) => inOne(w, p));
export const owned = (writes: string[], gaps: Gap[]) => gaps.filter((g) => names(writes, g.path) || names(writes, g.script));
export const required = (tracked: string[], writes: string[], gaps: Gap[]) =>
  [...new Set([...needs(tracked, writes, "new"), ...(owned(writes, gaps).length > 0 ? triggerFix : [])])];
export function mayNeed(tracked: string[], writes: string[], gaps: Gap[]): string[] {
  const r = required(tracked, writes, gaps);
  return needs(tracked, writes, "open").filter((p) => !r.includes(p));
}

function source(tracked: string[], writes: string[], gaps: Gap[], f: Fresh, p: string): string {
  const w = writes.find((x) => freshOf(tracked, x) === f && implied(kindOf(x)).includes(p));
  if (w !== undefined) return w;
  const g = f === "new" ? owned(writes, gaps)[0] : undefined;
  return g ? `../${g.path} in ${g.script}` : "";
}

export function closureFindings(tracked: string[], gaps: Gap[], t: ClosureTask, violations: string[]): LintFinding[] {
  if (t.done) return [];
  const req = required(tracked, t.writes, gaps), may = mayNeed(tracked, t.writes, gaps);
  const f = (code: string, severity: string, fr: Fresh) => (p: string) => ({ task: t.id, code, severity, detail: `${p} for ${source(tracked, t.writes, gaps, fr, p)}` });
  return [...violations.filter((p) => req.includes(p)).map(f("writesClosure", "error", "new")),
    ...violations.filter((p) => may.includes(p)).map(f("writesClosureOpen", "warn", "open"))];
}

type CiPaths = {
  loadGolden: (root: string) => { table: unknown };
  leanInputGaps: (root: string, table: unknown) => { script: string; path: string | null }[];
};

export async function gapsOf(root: string, code = root): Promise<Gap[]> {
  const cp = (await import(pathToFileURL(join(code, "scripts/ci-paths.mjs")).href)) as CiPaths;
  return cp.leanInputGaps(root, cp.loadGolden(root).table).flatMap((g) => (g.path === null ? [] : [{ script: g.script, path: g.path }]));
}

const isError = (f: LintFinding) => f.code === "writesClosure" && f.severity === "error";
const same = (a: LintFinding, b: LintFinding) => a.task === b.task && a.code === b.code && a.severity === b.severity && a.detail === b.detail;

export function newErrors(before: LintFinding[], after: LintFinding[]): LintFinding[] {
  return after.filter((f) => isError(f) && !before.some((b) => same(b, f)));
}

export function scopeBatch(bins: string[]): ScopeBatch {
  return async (reqs) => {
    if (reqs.length === 0) return [];
    let last = "fwcore not built: sh scripts/fwcore-build.sh";
    for (const b of bins) {
      try {
        const out = execFileSync(b, [], { input: reqs.map((r, i) => JSON.stringify({ id: i + 1, ...r })).join("\n") + "\n",
          env: { ...process.env, LEAN_ABORT_ON_PANIC: "1" }, encoding: "utf8", maxBuffer: 1 << 28, timeout: 60000 });
        const rs = out.split("\n").filter(Boolean).map((l) => JSON.parse(l) as { violations?: string[]; error?: string });
        const bad = rs.find((r) => typeof r.error === "string" || !Array.isArray(r.violations));
        if (rs.length === reqs.length && !bad) return rs as { violations: string[] }[];
        last = bad?.error ?? `fwcore answered ${rs.length} of ${reqs.length} scope requests`;
      } catch (e) { last = e instanceof Error ? e.message : String(e); }
    }
    throw new Error(`plan lint: writes closure: ${last}`);
  };
}

export async function lintClosure(tasks: ClosureTask[], tracked: string[], gaps: Gap[], batch: ScopeBatch): Promise<LintFinding[]> {
  const open = tasks.map((t) => ({ t, paths: [...required(tracked, t.writes, gaps), ...mayNeed(tracked, t.writes, gaps)] }))
    .filter((x) => !x.t.done && x.paths.length > 0);
  if (open.length === 0) return [];
  const rs = await batch(open.map(({ t, paths }) => ({ op: "console.landScope", writes: t.writes, names: [t.id, t.owner], allow: [], paths, task: t.id, stream: t.stream })));
  return open.flatMap(({ t }, i) => closureFindings(tracked, gaps, t, rs[i]!.violations));
}
