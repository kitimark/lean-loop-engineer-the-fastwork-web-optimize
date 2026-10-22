
export type Kind = "busy" | "dirty" | "scope" | "reads" | "conflict" | "checks" | "stale" | "unknown" | "done" | "dry" | "queued" | "empty" | "lint" | "rebuild" | "install";
export const KINDS: Kind[] = ["busy", "dirty", "scope", "reads", "conflict", "checks", "stale", "unknown", "done", "dry", "queued", "empty", "lint", "rebuild", "install"];

export const isOk = (k: Kind): boolean => k === "done" || k === "dry" || k === "queued" || k === "empty";
export const EXIT: Record<Kind, number> = { busy: 10, dirty: 11, scope: 12, reads: 13, conflict: 14, checks: 15, stale: 16, unknown: 2, done: 0, dry: 0, queued: 0, empty: 0, lint: 17, rebuild: 18, install: 19 };
export const installRunsOnline = (offlineOk: boolean): boolean => !offlineOk;
export const installKind = (offlineOk: boolean, onlineOk: boolean): Kind | null => (offlineOk || onlineOk ? null : "install");
export const installNeeded = (known: boolean, lock: string, stamp: string | null): boolean => !known || stamp !== lock;
/** TS stand-in for Lean `installStep` (golden op `landVerdict.installStamp`); marked for replacement by an fwcore op. */
export function installStep(known: boolean, lock: string | null, stamp: string | null, offlineOk: boolean, onlineOk: boolean): { kind: Kind | null; stampAfter: string | null } {
  if (lock === null || !installNeeded(known, lock, stamp)) return { kind: null, stampAfter: stamp };
  return installKind(offlineOk, onlineOk) === null ? { kind: null, stampAfter: lock } : { kind: "install", stampAfter: stamp };
}
export const exitCode = (k: Kind): number => EXIT[k];
export const retryable = (k: Kind): boolean => k === "busy" || k === "dirty";
export const verdictLine = (k: Kind, task: string): string => `VERDICT ${k} ${task === "" ? "-" : task}`;
export function parseVerdict(text: string): { kind: Kind; task: string } | null {
  let out: { kind: Kind; task: string } | null = null;
  for (const l of text.split("\n")) {
    const m = /^VERDICT (\S+) (\S+)$/.exec(l);
    if (m && (KINDS as string[]).includes(m[1]!)) out = { kind: m[1] as Kind, task: m[2] === "-" ? "" : m[2]! };
  }
  return out;
}

export function dryKind(f: { containsMain: boolean; scope: boolean; merges: boolean; readsSelected: boolean; readsTest: boolean; own: boolean; lints: boolean }): Kind {
  return outcomeKind(outcome({ fresh: f.containsMain, own: f.own, scope: f.scope, merges: f.merges, reads: !f.readsSelected || f.readsTest, lints: f.lints }));
}
export const handbackAllowed = (k: Kind): boolean => k === "dry";


export type Outcome = { threw: boolean; fresh: boolean; own: boolean; scope: boolean; merges: boolean; installs: boolean; reads: boolean; lints: boolean };
export const outcome = (p: Partial<Outcome> = {}): Outcome => ({ threw: false, fresh: true, own: true, scope: true, merges: true, installs: true, reads: true, lints: true, ...p });
export function outcomeKind(o: Outcome): Kind {
  if (o.threw) return "unknown";
  if (!o.fresh) return "stale";
  if (!o.own) return "empty";
  if (!o.scope) return "scope";
  if (!o.merges) return "conflict";
  if (!o.installs) return "install";
  if (!o.reads) return "reads";
  if (!o.lints) return "lint";
  return "dry";
}
const STAGES: [keyof Outcome, string, boolean][] = [["threw", "exception", true], ["fresh", "stale", false], ["own", "empty", false], ["scope", "scope", false],
  ["merges", "conflict", false], ["installs", "install", false], ["reads", "reads", false], ["lints", "lint", false]];
export function dryLog(o: Outcome): string[] {
  const out: string[] = [];
  for (const [f, name, inverted] of STAGES) { if (inverted ? o[f] : !o[f]) break; out.push(`dry: ${name} ok`); }
  return out;
}
export const dryRun = (o: Outcome, task: string): string[] => [...dryLog(o), verdictLine(outcomeKind(o), task)];

export const LINT_ARGV = {
  ciPaths: ["node", "scripts/ci-paths.mjs", "--check"],
  footprint: ["node", "apps/site/scripts/part-footprint.mjs", "--check"],
  axioms: ["sh", "-c", "cd lean && . ../scripts/lake-slot-lib.sh && (lake_slot .. lake build) >&2 && sh scripts/axiom-check.sh"],
};
export const footprintInput = (p: string): boolean =>
  p.startsWith("apps/site/src/parts/") || p === "apps/site/src/App.tsx" || p === "apps/site/scripts/part-footprint.mjs" ||
  p === "lean/Fw/Parts/FootprintData.lean" || p === "packages/contracts/golden/parts/footprint.gen.json";
export function lintPlan(changed: string[], hasCiPaths: boolean, hasAxioms: boolean, hasFootprint: boolean): string[][] {
  return [
    ...(hasCiPaths ? [LINT_ARGV.ciPaths] : []),
    ...(hasFootprint && changed.some(footprintInput) ? [LINT_ARGV.footprint] : []),
    ...(hasAxioms && changed.some((p) => p.startsWith("lean/")) ? [LINT_ARGV.axioms] : []),
  ];
}

export const LINT_STAGES = ["lake build", "axiom check"];
export function checkFailKind(fs: { reads: boolean; stages: string[] }[]): Kind {
  if (fs.some((f) => f.reads)) return "reads";
  return fs.length > 0 && fs.every((f) => f.stages.length > 0 && f.stages.every((n) => LINT_STAGES.includes(n))) ? "lint" : "checks";
}
export function failedStages(out: string): string[] {
  const names = new Set<string>();
  let inList = false;
  for (const l of out.split("\n")) {
    let m = /^check: FAILED stage: (.+)$/.exec(l);
    if (m) { names.add(m[1]!); continue; }
    if (/^check: FAILED:/.test(l)) { inList = true; continue; }
    m = /^ {2}- (.+)$/.exec(l);
    if (inList && m) names.add(m[1]!); else if (!m) inList = false;
  }
  return [...names];
}

export const reasonOf = (msg: string): string => (msg === "" ? "no message" : msg);
export const refusalReason = (k: Kind, r: string | undefined): string | undefined => (isOk(k) ? (r === undefined ? undefined : reasonOf(r)) : reasonOf(r ?? ""));
export const refusedLine = (msg: string): string => `REFUSED: ${reasonOf(msg)}`;
export const FWCORE_STALE_REASON = "fwcore-stale: run sh scripts/fwcore-build.sh";
export const fwcoreStale = (recorded: string | null, same: boolean, moved: boolean): boolean => recorded === null || (!same && moved);

export const coreSource = (p: string): boolean => p.startsWith("lean/") || p === "scripts/fwcore-build.sh" || p === "scripts/fwcore-record-rule.sh";
export const touchesCore = (paths: string[]): boolean => paths.some(coreSource);
export const needsRebuild = (k: Kind, paths: string[]): boolean => k === "done" && touchesCore(paths);
export type After = { proceed: true; rebuilt: boolean } | { proceed: false };
export const afterLand = (k: Kind, paths: string[], ok: () => boolean): After =>
  needsRebuild(k, paths) ? (ok() ? { proceed: true, rebuilt: true } : { proceed: false }) : { proceed: true, rebuilt: false };
export const stopKind = (a: After): Kind | null => (a.proceed ? null : "rebuild");
export const REBUILD_REASON = "fwcore-rebuild-failed: sh scripts/fwcore-build.sh failed after a land that changed lean/";
