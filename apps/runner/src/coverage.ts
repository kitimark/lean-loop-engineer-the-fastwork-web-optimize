// `fw coverage`: which gate-probed values have a Lean source. A probe is (part, role, class, key, breakpoint class);
// a source is a claim from lean/Fw/Gate/Coverage.lean (`claims`, exported into the golden's "claims" line) whose file
// evidence holds in the repo. This module only collects facts (anchors.json, run header props, breakpoint classes,
// which claimed files exist and are used) and mirrors the Lean lint; the mirror is checked against the Lean golden
// vectors packages/contracts/golden/gate/coverage.jsonl (test/coverage.test.ts). TS stand-in: the lint runs here, not
// in fwcore. Warn mode: exit 1 when any probe is uncovered, but land does not call it.
import { execFileSync } from "node:child_process";
import { closeSync, existsSync, openSync, readFileSync, readSync, readdirSync, statSync } from "node:fs";
import { basename, join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { UsageError } from "./lib.ts";

export const COVERAGE_USAGE =
  "usage: fw coverage [--root <tree>] [--run <engine.json|dir>]... [--failures <summary.json>]... [--summary] [--json]   (exit 1 when any probe is uncovered)";
export const GOLDEN = "packages/contracts/golden/gate/coverage.jsonl";

export type Cls = "count" | "box" | "style";
export type Probe = { part: string; role: string; cls: Cls; key: string; bp: string };
export type Source = { kind: "generated" | "golden"; file: string } | { kind: "exempt"; why: string };
/** Wire claim: patterns are "*" (any), "s*" (prefix s), else exact; cls "*" is any class. */
export type Claim = { part: string; role: string; cls: Cls | "*"; key: string; bp: string; src: Source };
export type RoleSpec = { role: string; dims: string[]; skipProps: string[]; skipSets: string[] };
export type Anchors = {
  parts: Record<string, { roles: RoleSpec[] }>;
  style: { skipPrefixes: { prefix: string }[]; skipSets: Record<string, { props: string[] }> };
};
export type RoleProps = { restated: string[]; originOnly?: string[] };
export type Props = Record<string, Record<string, RoleProps>>;
export type Tally = { generated: number; golden: number; exempt: number; uncovered: number };

// ---- mirror of Fw.Gate.Coverage (decisions) ----

/** Pat.ok on the wire spelling. */
export function patOk(pat: string, s: string): boolean {
  if (pat === "*") return true;
  if (pat.endsWith("*")) return s.startsWith(pat.slice(0, -1));
  return pat === s;
}
/** Source.ok: a file source needs its file in the evidence; an exemption always holds. */
export function srcOk(ev: ReadonlySet<string>, src: Source): boolean {
  return src.kind === "exempt" ? true : ev.has(src.file);
}
export function hits(c: Claim, p: Probe): boolean {
  return c.part === p.part && patOk(c.role, p.role) && (c.cls === "*" || c.cls === p.cls) && patOk(c.key, p.key) && patOk(c.bp, p.bp);
}
export const usable = (ev: ReadonlySet<string>, c: Claim, p: Probe): boolean => srcOk(ev, c.src) && hits(c, p);
/** The first usable claim's source, or null when the probe is uncovered. */
export function sourceOf(ev: ReadonlySet<string>, cs: readonly Claim[], p: Probe): Source | null {
  return cs.find((c) => usable(ev, c, p))?.src ?? null;
}
export const covered = (ev: ReadonlySet<string>, cs: readonly Claim[], p: Probe): boolean => cs.some((c) => usable(ev, c, p));
export const lint = (ev: ReadonlySet<string>, cs: readonly Claim[], ps: readonly Probe[]): Probe[] => ps.filter((p) => !covered(ev, cs, p));
export function tally(ev: ReadonlySet<string>, cs: readonly Claim[], ps: readonly Probe[]): Tally {
  const t: Tally = { generated: 0, golden: 0, exempt: 0, uncovered: 0 };
  for (const p of ps) t[sourceOf(ev, cs, p)?.kind ?? "uncovered"]++;
  return t;
}

// ---- mirror of Fw.Gate.Items.comparedProps and the Coverage probe set ----

function skipNames(a: Anchors, rs: RoleSpec): string[] {
  return [...rs.skipProps, ...rs.skipSets.flatMap((s) => a.style.skipSets[s]?.props ?? [])];
}
export function comparedProps(a: Anchors, rs: RoleSpec, restated: readonly string[]): string[] {
  const names = skipNames(a, rs);
  const pres = a.style.skipPrefixes.map((q) => q.prefix);
  return restated.filter((p) => !(names.includes(p) || pres.some((q) => p === q || p.startsWith(`${q}-`))));
}
export function roleKeys(a: Anchors, rs: RoleSpec, props: RoleProps | undefined): [Cls, string][] {
  return [["count", "count"], ...rs.dims.map((d): [Cls, string] => ["box", d]), ...comparedProps(a, rs, props?.restated ?? []).map((k): [Cls, string] => ["style", k])];
}
export function partProbes(a: Anchors, part: string, props: Record<string, RoleProps>, bps: readonly string[]): Probe[] {
  return (a.parts[part]?.roles ?? []).flatMap((rs) => roleKeys(a, rs, props[rs.role]).flatMap(([cls, key]) => bps.map((bp) => ({ part, role: rs.role, cls, key, bp }))));
}
/** All probes, parts in anchors.json key order; a part with no recorded props has only count and box probes. */
export function allProbes(a: Anchors, props: Props, bps: readonly string[]): Probe[] {
  return Object.keys(a.parts).flatMap((part) => partProbes(a, part, props[part] ?? {}, bps));
}

// ---- fact collection (no decisions) ----

export function readGolden(file: string): { claims: Claim[]; cases: any[] } {
  const lines = readFileSync(file, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
  const cl = lines.find((l) => Array.isArray(l.claims));
  if (!cl) throw new Error(`${file}: no claims line`);
  return { claims: cl.claims as Claim[], cases: lines.filter((l) => l.kind === "case") };
}

function walk(dir: string, keep: (f: string) => boolean, out: string[] = []): string[] {
  if (!existsSync(dir)) return out;
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    if (e.name === "node_modules" || e.name.startsWith(".")) continue;
    const p = join(dir, e.name);
    if (e.isDirectory()) walk(p, keep, out);
    else if (keep(p)) out.push(p);
  }
  return out;
}

/**
 * Evidence: the claimed files that hold in `root`. A generated file counts when it exists and a non-test source under
 * apps/site/src names it (its basename); a golden file counts when it exists and a test names it (its basename, or
 * `goldenConformance('<id>'` for packages/contracts/golden/parts/<id>.jsonl).
 */
export function collectEvidence(root: string, claims: readonly Claim[]): Set<string> {
  const files = new Map<string, "generated" | "golden">();
  for (const c of claims) if (c.src.kind !== "exempt") files.set(c.src.file, c.src.kind);
  const isTest = (f: string) => /\.test\.tsx?$/.test(f);
  const code = (f: string) => /\.(tsx?|mjs|js|json|css)$/.test(f);
  let site: string[] | null = null, tests: string[] | null = null;
  const ev = new Set<string>();
  for (const [file, kind] of files) {
    if (!existsSync(join(root, file))) continue;
    const name = basename(file);
    if (kind === "generated") {
      site ??= walk(join(root, "apps/site/src"), (f) => code(f) && !isTest(f)).map((f) => readFileSync(f, "utf8"));
      if (site.some((t) => t.includes(name))) ev.add(file);
    } else {
      tests ??= ["apps", "packages"].flatMap((d) => walk(join(root, d), isTest)).map((f) => readFileSync(f, "utf8"));
      const id = /golden\/parts\/(.+)\.jsonl$/.exec(file)?.[1];
      const conf = id ? [`goldenConformance('${id}'`, `goldenConformance("${id}"`] : [];
      if (tests.some((t) => t.includes(name) || conf.some((c) => t.includes(c)))) ev.add(file);
    }
  }
  return ev;
}

export type RunFacts = { engine: string; props: Props; blocks: string[]; sweeps: string[]; probeBlock: Map<string, string> };

/** One raw gate run file `<engine>.json`: header props, probe blocks (first-seen order), sweep ids. */
export function readRun(file: string): RunFacts {
  const raw = JSON.parse(readFileSync(file, "utf8"));
  if (!raw?.header?.props) throw new Error(`${file}: no header.props (not a raw gate run file)`);
  const probeBlock = new Map<string, string>();
  for (const p of raw.probes ?? []) probeBlock.set(p.id, p.block);
  return {
    engine: basename(file, ".json"), props: raw.header.props,
    blocks: [...new Set<string>((raw.probes ?? []).map((p: any) => p.block as string))], sweeps: (raw.sweeps ?? []).map((s: any) => s.id as string), probeBlock,
  };
}

function runFiles(arg: string): string[] {
  if (!statSync(arg).isDirectory()) return [arg];
  return walk(arg, (f) => f.endsWith(".json") && !/(summary|sha256|anchors)\.json$/.test(f) && !f.endsWith(".gen.json"))
    .filter((f) => { const b = Buffer.alloc(4096); const fd = openSync(f, "r"); try { return b.subarray(0, readSync(fd, b, 0, 4096, 0)).toString("utf8").includes('"header"'); } finally { closeSync(fd); } });
}

/** Union of header props over runs: per part and role, restated names in first-seen order. */
export function unionProps(runs: readonly RunFacts[]): Props {
  const out: Props = {};
  for (const r of runs) for (const [part, roles] of Object.entries(r.props)) for (const [role, rp] of Object.entries(roles)) {
    const cur = ((out[part] ??= {})[role] ??= { restated: [] });
    for (const k of rp.restated ?? []) if (!cur.restated.includes(k)) cur.restated.push(k);
  }
  return out;
}

/** Breakpoint classes from the gate spec (matrix blocks, then sweep ids), for runs not given. */
export async function staticClasses(root: string): Promise<{ bps: string[]; probeBlock: Map<string, string> }> {
  const spec = await import(pathToFileURL(join(root, "packages/gate-breakpoints/src/spec.mjs")).href);
  const { gen } = spec.loadGen(join(root, "apps/site/src/breakpoints.gen.json"));
  const probeBlock = new Map<string, string>(gen.matrix.probes.map((p: any) => [p.id, p.block]));
  return { bps: [...new Set<string>(gen.matrix.probes.map((p: any) => p.block)), ...spec.sweepDefs(gen).map((s: any) => s.id as string)], probeBlock };
}

type Failure = { part: string; cls: Cls; role: string; key: string; labels: string[] };
export type Cell = Probe & { engine: string; src: Source | null };

/** Failing cells of a gate summary: one per (engine, part, role, class, key, breakpoint class) with its source. */
export function failingCells(summary: any, blockOf: (engine: string, label: string) => string, ev: ReadonlySet<string>, cs: readonly Claim[]): Cell[] {
  const seen = new Map<string, Cell>();
  for (const [engine, e] of Object.entries<any>(summary.engines ?? {})) for (const f of (e.failures ?? []) as Failure[]) {
    for (const l of f.labels ?? []) {
      const bp = l.includes("#") ? l.slice(0, l.indexOf("#")) : blockOf(engine, l);
      const p: Probe = { part: f.part, role: f.role, cls: f.cls, key: f.key, bp };
      const id = `${engine}\t${f.part}\t${f.role}\t${f.cls}\t${f.key}\t${bp}`;
      if (!seen.has(id)) seen.set(id, { ...p, engine, src: sourceOf(ev, cs, p) });
    }
  }
  return [...seen.values()];
}

// ---- rendering ----

const srcName = (s: Source | null) => (s === null ? "UNCOVERED" : s.kind === "exempt" ? `exempt(${s.why})` : `${s.kind} ${s.file}`);

export function renderTable(parts: readonly string[], ev: ReadonlySet<string>, cs: readonly Claim[], ps: readonly Probe[]): string[] {
  const rows = [["part", "probes", "generated", "golden", "exempt", "uncovered"]];
  for (const part of parts) {
    const mine = ps.filter((p) => p.part === part);
    const t = tally(ev, cs, mine);
    rows.push([part, String(mine.length), String(t.generated), String(t.golden), String(t.exempt), String(t.uncovered)]);
  }
  const t = tally(ev, cs, ps);
  rows.push(["TOTAL", String(ps.length), String(t.generated), String(t.golden), String(t.exempt), String(t.uncovered)]);
  const w = rows[0]!.map((_, i) => Math.max(...rows.map((r) => r[i]!.length)));
  return rows.map((r) => r.map((c, i) => (i === 0 ? c.padEnd(w[i]!) : c.padStart(w[i]!))).join("  "));
}

/** Uncovered probes grouped per part and role; classes collapse to "all" when every class is uncovered. */
export function renderUncovered(bps: readonly string[], bad: readonly Probe[]): string[] {
  const by = new Map<string, Map<string, Set<string>>>();
  for (const p of bad) {
    const r = by.get(`${p.part} ${p.role}`) ?? new Map<string, Set<string>>();
    by.set(`${p.part} ${p.role}`, r);
    const k = `${p.cls}:${p.key}`;
    r.set(k, (r.get(k) ?? new Set()).add(p.bp));
  }
  const out: string[] = [];
  for (const [pr, keys] of by) {
    const parts = [...keys].map(([k, s]) => (s.size === bps.length ? k : `${k}[${[...s].join(",")}]`));
    out.push(`  ${pr}: ${parts.join(" ")}`);
  }
  return out;
}

export async function coverageCli(args: string[], cwd: string): Promise<number> {
  const opt = (name: string) => args.flatMap((a, i) => (a === name ? [args[i + 1] ?? ""] : []));
  if (args.includes("--help") || args.includes("-h")) throw new UsageError(COVERAGE_USAGE);
  const repo = execFileSync("git", ["rev-parse", "--show-toplevel"], { cwd, encoding: "utf8" }).trim();
  const root = resolve(cwd, opt("--root")[0] ?? repo);
  const { claims } = readGolden(join(repo, GOLDEN));
  const anchors = JSON.parse(readFileSync(join(root, "packages/gate-breakpoints/src/anchors.json"), "utf8")) as Anchors;
  const runs = opt("--run").flatMap((a) => runFiles(resolve(cwd, a))).map(readRun);
  const st = runs.length ? null : await staticClasses(root);
  const bps = st ? st.bps : [...new Set(runs.flatMap((r) => [...r.blocks, ...r.sweeps]))];
  const props = unionProps(runs);
  const ev = collectEvidence(root, claims);
  const ps = allProbes(anchors, props, bps);
  const bad = lint(ev, claims, ps);
  const parts = Object.keys(anchors.parts);
  const sums = opt("--failures").map((f) => JSON.parse(readFileSync(resolve(cwd, f), "utf8")));
  const blockOf = (engine: string, label: string) =>
    (runs.find((r) => r.engine === engine) ?? runs[0])?.probeBlock.get(label) ?? st?.probeBlock.get(label) ?? label;
  const cells = sums.flatMap((s) => failingCells(s, blockOf, ev, claims));
  if (args.includes("--json")) {
    console.log(JSON.stringify({ root, runs: runs.map((r) => r.engine), bps, evidence: [...ev], tally: tally(ev, claims, ps), uncovered: bad, failingCells: cells }));
    return bad.length ? 1 : 0;
  }
  const out: string[] = [];
  if (!runs.length) out.push("warn: no --run given: style probes need a gate run header (header.props); counting count and box probes only");
  out.push(`root ${root}; runs ${runs.map((r) => r.engine).join(",") || "none"}; ${bps.length} breakpoint classes; evidence ${ev.size}/${new Set(claims.flatMap((c) => (c.src.kind === "exempt" ? [] : [c.src.file]))).size} claimed files`);
  out.push(...renderTable(parts, ev, claims, ps));
  if (!args.includes("--summary") && bad.length) out.push("uncovered (part role: cls:key[classes]; no list = all classes):", ...renderUncovered(bps, bad));
  if (cells.length) {
    const unc = cells.filter((c) => c.src === null);
    out.push(`failing cells: ${cells.length}; uncovered ${unc.length}; with a source ${cells.length - unc.length}`);
    const items = new Map<string, { n: number; unc: number; src: Set<string> }>();
    for (const c of cells) {
      const k = `${c.engine} ${c.part} ${c.role} ${c.cls}:${c.key}`;
      const v = items.get(k) ?? { n: 0, unc: 0, src: new Set<string>() };
      v.n++; if (c.src === null) v.unc++; v.src.add(srcName(c.src));
      items.set(k, v);
    }
    for (const [k, v] of items) out.push(`  ${k}: ${v.n} classes, ${v.unc === v.n ? "UNCOVERED" : [...v.src].join(" | ")}`);
  }
  console.log(out.join("\n"));
  return bad.length ? 1 : 0;
}
