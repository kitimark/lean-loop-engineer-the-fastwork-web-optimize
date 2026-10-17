// `fw engine-check --rows <jsonl> --run <artifact dir>`: CI counts as a falsification test of the Lean engine
// models. This file only reads files and calls fwcore (`measure.engineCheck`); every decision (the class rules,
// the margin, pass / model-bug / unusable) is Lean: lean/Fw/Measure/EngineCheck.lean.
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import { spawnSync } from "node:child_process";
import { UsageError } from "./lib.ts";
import { fwcoreCall, type FwCall } from "./run.ts";

export const ENGINE_CHECK_USAGE =
  "usage: fw engine-check --rows <predictions.jsonl> --run <artifact dir> [--classes <classes.frozen.json>] [--json]\n" +
  "  rows: one JSON object per line {engine, scenario, variant, stage, prediction (=0 | =o | <o | ≤o | any), countType, base?}\n" +
  "  run: a directory holding counts.json files (a CI artifact, searched recursively); store refs are not supported yet\n" +
  "  exit code 0 = no model-bug, 3 = at least one model-bug";

export type Row = { engine: string; scenario: string; variant: string; stage: string; prediction: string; countType: string; base?: string };
export type Observed = { scenario: string; variant: string; type: string; runs: number[][] };
export type Verdict = Row & { verdict: "pass" | "model-bug" | "unusable"; reason: string; base: string;
  class: { variant: string; base: string }; runs: { variant: number; base: number }; totals: { variant: number[]; base: number[] } };
export type CheckReply = { verdicts: Verdict[]; tally: { pass: number; modelBug: number; unusable: number } };

export type CheckArgs = { rows: string; run: string; classes?: string; json: boolean };

/** `--rows f --run d [--classes f] [--json]`. */
export function parseCheckArgs(argv: string[]): CheckArgs {
  const a: Partial<CheckArgs> & { json: boolean } = { json: false };
  for (let i = 0; i < argv.length; i++) {
    const f = argv[i]!;
    if (f === "--json") { a.json = true; continue; }
    if (f !== "--rows" && f !== "--run" && f !== "--classes") throw new UsageError(`unknown argument ${f}\n${ENGINE_CHECK_USAGE}`);
    const v = argv[i + 1];
    if (v === undefined || v.startsWith("--")) throw new UsageError(`flag ${f} needs a value\n${ENGINE_CHECK_USAGE}`);
    a[f.slice(2) as "rows" | "run" | "classes"] = v;
    i++;
  }
  if (!a.rows) throw new UsageError(`--rows is required\n${ENGINE_CHECK_USAGE}`);
  if (!a.run) throw new UsageError(`--run is required\n${ENGINE_CHECK_USAGE}`);
  return a as CheckArgs;
}

/** Parse prediction rows (JSON lines; blank lines skipped). The fields are validated by the Lean op. */
export function parseRows(text: string): Row[] {
  const rows: Row[] = [];
  text.split("\n").forEach((line, i) => {
    if (!line.trim()) return;
    try { rows.push(JSON.parse(line) as Row); } catch { throw new UsageError(`rows line ${i + 1}: not JSON`); }
  });
  return rows;
}

export type CountsFile = { profile?: { id?: string }; meta?: { target?: string; search?: string; variant?: string; scenario?: string }; frames?: { counts?: Record<string, number> }[] };

/** Every `counts.json` below `dir`, in sorted path order. */
export function findCounts(dir: string): string[] {
  const out: string[] = [];
  const walk = (d: string) => {
    for (const name of readdirSync(d).sort()) {
      const p = join(d, name);
      if (statSync(p).isDirectory()) walk(p);
      else if (name === "counts.json") out.push(p);
    }
  };
  walk(dir);
  return out;
}

/** The names a run answers to as a variant: `meta.variant` if present, else `target`, and `target+search`
 * when a search string is present (a part-flag variant of the rewrite). */
export function variantKeys(c: CountsFile): string[] {
  const m = c.meta ?? {};
  if (m.variant) return [m.variant];
  if (!m.target) return [];
  return m.search ? [`${m.target}+${m.search}`, m.target] : [m.target];
}

/** The observed series of every (scenario, variant, type) in the given counts files that a row asks for. */
export function observedFor(files: CountsFile[], rows: Row[]): Observed[] {
  const want = new Map<string, Set<string>>(); // [scenario, variant] -> the count types asked for
  for (const r of rows) {
    for (const v of [r.variant, r.base ?? "original"]) {
      const k = JSON.stringify([r.scenario, v]);
      want.set(k, (want.get(k) ?? new Set<string>()).add(r.countType));
    }
  }
  const acc = new Map<string, Observed>();
  for (const c of files) {
    const scenario = c.meta?.scenario ?? c.profile?.id;
    if (!scenario) continue;
    const frames = c.frames ?? [];
    for (const v of variantKeys(c)) {
      for (const t of want.get(JSON.stringify([scenario, v])) ?? []) {
        const key = JSON.stringify([scenario, v, t]);
        const o = acc.get(key) ?? { scenario, variant: v, type: t, runs: [] };
        o.runs.push(frames.map((f) => f.counts?.[t] ?? 0));
        acc.set(key, o);
      }
    }
  }
  return [...acc.values()];
}

export type CheckDeps = { call: FwCall; read: (p: string) => string; findCounts: (d: string) => string[]; defaultClasses: string; log: (l: string) => void };

/** Rows + a run directory + the frozen classes -> verdicts (through fwcore). */
export function engineCheck(args: CheckArgs, d: CheckDeps): CheckReply {
  const rows = parseRows(d.read(args.rows));
  const paths = d.findCounts(args.run);
  if (!paths.length) throw new UsageError(`no counts.json under ${args.run} (store refs are not supported; pass a downloaded artifact directory)`);
  const files = paths.map((p) => JSON.parse(d.read(p)) as CountsFile);
  const frozen = JSON.parse(d.read(args.classes ?? d.defaultClasses)) as { profiles?: Record<string, unknown> };
  if (!frozen.profiles) throw new UsageError(`${args.classes ?? d.defaultClasses}: no "profiles" (not a frozen classes file)`);
  const r = d.call({ op: "measure.engineCheck", rows, classes: frozen.profiles, observed: observedFor(files, rows) });
  return r as unknown as CheckReply;
}

const mark = (v: Verdict["verdict"]) => (v === "pass" ? "PASS" : v === "model-bug" ? "MODEL-BUG" : "unusable");

/** The text report: one line per row, then the tally. */
export function renderCheck(r: CheckReply): string[] {
  const lines = r.verdicts.map((v) => {
    const obs = v.runs.variant ? `Σ ${v.totals.variant.join("/")} vs ${v.totals.base.join("/")}` : "no observation";
    return `${mark(v.verdict).padEnd(9)} ${v.engine}/${v.scenario}/${v.variant}  ${v.stage}  ${v.countType} ${v.prediction}${v.base === "original" ? "" : ` (base ${v.base})`}  [${v.class.variant}]  ${obs}  ${v.reason}`;
  });
  lines.push(`engine-check: ${r.tally.pass} pass, ${r.tally.modelBug} model-bug, ${r.tally.unusable} unusable (${r.verdicts.length} rows)`);
  return lines;
}

/** The CLI entry. Exit code 3 when any row is a model-bug. */
export function engineCheckCli(argv: string[], cwd: string, log: (l: string) => void = (l) => console.log(l)): number {
  const args = parseCheckArgs(argv);
  const common = spawnSync("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd, encoding: "utf8" }).stdout.trim();
  const top = spawnSync("git", ["rev-parse", "--show-toplevel"], { cwd, encoding: "utf8" }).stdout.trim();
  const rel = "packages/measure-chromium/classes.frozen.json";
  const defaultClasses = [top && join(top, rel), common && join(dirname(common), rel)].find((p) => p && existsSync(p)) ?? rel;
  const reply = engineCheck(args, { call: fwcoreCall(cwd), read: (p) => readFileSync(p, "utf8"), findCounts, defaultClasses, log });
  if (args.json) log(JSON.stringify(reply, null, 1));
  else for (const l of renderCheck(reply)) log(l);
  return reply.tally.modelBug > 0 ? 3 : 0;
}
