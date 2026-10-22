// The verdict of an `fw land`: one kind, one `VERDICT <kind> <task>` line, one exit code (task land-dry).
// TS stand-in for Lean `Fw.Console.LandVerdict` and `Fw.Console.LandDry`; marked for replacement by an `fwcore` op. Checked against
// the Lean golden `packages/contracts/golden/console/land-dry.jsonl` (test/land-verdict.test.ts). No decision lives anywhere else:
// the land code only names the kind of each refusal; scripts decide from the exit code or the word after `VERDICT`, never from prose.

/** Lean `Kind`: refusals busy dirty scope reads conflict checks stale unknown lint; successes done dry queued empty; rebuild: the queue stopped after a failed fwcore rebuild. */
export type Kind = "busy" | "dirty" | "scope" | "reads" | "conflict" | "checks" | "stale" | "unknown" | "done" | "dry" | "queued" | "empty" | "lint" | "rebuild";
export const KINDS: Kind[] = ["busy", "dirty", "scope", "reads", "conflict", "checks", "stale", "unknown", "done", "dry", "queued", "empty", "lint", "rebuild"];

/** Lean `Kind.ok`: a finished land, a passing dry land, an accepted queue entry. */
export const isOk = (k: Kind): boolean => k === "done" || k === "dry" || k === "queued" || k === "empty";
/** Lean `Kind.exitCode`: 0 for a success, a distinct number for each refusal (`unknown` is 2, the code `fw land` always used). */
export const EXIT: Record<Kind, number> = { busy: 10, dirty: 11, scope: 12, reads: 13, conflict: 14, checks: 15, stale: 16, unknown: 2, done: 0, dry: 0, queued: 0, empty: 0, lint: 17, rebuild: 18 };
export const exitCode = (k: Kind): number => EXIT[k];
/** Lean `Kind.retryable`: only `busy` and `dirty` (the world, not the branch, is in the way). */
export const retryable = (k: Kind): boolean => k === "busy" || k === "dirty";
/** Lean `verdictLine`. */
export const verdictLine = (k: Kind, task: string): string => `VERDICT ${k} ${task === "" ? "-" : task}`;
/** Parse a `VERDICT` line (the last one in `text`); null when there is none. The only way a script reads an outcome. */
export function parseVerdict(text: string): { kind: Kind; task: string } | null {
  let out: { kind: Kind; task: string } | null = null;
  for (const l of text.split("\n")) {
    const m = /^VERDICT (\S+) (\S+)$/.exec(l);
    if (m && (KINDS as string[]).includes(m[1]!)) out = { kind: m[1] as Kind, task: m[2] === "-" ? "" : m[2]! };
  }
  return out;
}

/** Lean `dryKind`: the kind of a dry land from the stage verdicts: `stale` when the branch lacks main, `empty` when it has no commit
 *  of its own, else the first refusal in land order (scope, conflict, reads), else `lint` when a fast lint fails, else `dry`. A reads
 *  test that the change does not select cannot refuse (`Stages.reads`). */
export function dryKind(f: { containsMain: boolean; scope: boolean; merges: boolean; readsSelected: boolean; readsTest: boolean; own: boolean; lints: boolean }): Kind {
  return outcomeKind(outcome({ fresh: f.containsMain, own: f.own, scope: f.scope, merges: f.merges, reads: !f.readsSelected || f.readsTest, lints: f.lints }));
}
/** Lean `handbackAllowed`: an agent hands back only on a `dry` verdict. */
export const handbackAllowed = (k: Kind): boolean => k === "dry";

// ---- The dry run as a function of its stage outcomes (Lean `Fw.Console.LandDry.dryRun`, task land-dry-full) ----
// `land.ts` computes the Outcome (I/O), `fw.ts` prints `dryRun(outcome, task)`; nothing else decides a dry kind, a log line or the
// exit code. Checked row by row against the Lean golden (all 128 outcomes) in test/land-verdict.test.ts.

/** Lean `Outcome`: `threw` is true when something outside the modelled stages stopped the run; the others are true when that stage
 *  did not stop the run (a stage never reached is true). */
export type Outcome = { threw: boolean; fresh: boolean; own: boolean; scope: boolean; merges: boolean; reads: boolean; lints: boolean };
/** The all-pass outcome with the given fields changed. */
export const outcome = (p: Partial<Outcome> = {}): Outcome => ({ threw: false, fresh: true, own: true, scope: true, merges: true, reads: true, lints: true, ...p });
/** Lean `Outcome.first` then `DStage.kind`, in the fixed order exception, stale, empty, scope, conflict, reads, lint. */
export function outcomeKind(o: Outcome): Kind {
  if (o.threw) return "unknown";
  if (!o.fresh) return "stale";
  if (!o.own) return "empty";
  if (!o.scope) return "scope";
  if (!o.merges) return "conflict";
  if (!o.reads) return "reads";
  if (!o.lints) return "lint";
  return "dry";
}
const STAGES: [keyof Outcome, string, boolean][] = [["threw", "exception", true], ["fresh", "stale", false], ["own", "empty", false], ["scope", "scope", false],
  ["merges", "conflict", false], ["reads", "reads", false], ["lints", "lint", false]];
/** Lean `Outcome.log`: `dry: <stage> ok` for each stage before the first stopping one. */
export function dryLog(o: Outcome): string[] {
  const out: string[] = [];
  for (const [f, name, inverted] of STAGES) { if (inverted ? o[f] : !o[f]) break; out.push(`dry: ${name} ok`); }
  return out;
}
/** Lean `dryRun`: every stdout line of a dry run: the log lines, then the one verdict line. */
export const dryRun = (o: Outcome, task: string): string[] => [...dryLog(o), verdictLine(outcomeKind(o), task)];

/** Lean `Lint.argv` of the lints in `lintPlan`. */
export const LINT_ARGV = {
  ciPaths: ["node", "scripts/ci-paths.mjs", "--check"],
  footprint: ["node", "apps/site/scripts/part-footprint.mjs", "--check"],
  axioms: ["sh", "-c", "cd lean && . ../scripts/lake-slot-lib.sh && (lake_slot .. lake build) >&2 && sh scripts/axiom-check.sh"],
};
/** Lean `footprintInput`: a path the part footprint generator reads or writes. */
export const footprintInput = (p: string): boolean =>
  p.startsWith("apps/site/src/parts/") || p === "apps/site/src/App.tsx" || p === "apps/site/scripts/part-footprint.mjs" ||
  p === "lean/Fw/Parts/FootprintData.lean" || p === "packages/contracts/golden/parts/footprint.gen.json";
/** Lean `lintPlan`: the argv of the lints a dry run runs. */
export function lintPlan(changed: string[], hasCiPaths: boolean, hasAxioms: boolean, hasFootprint: boolean): string[][] {
  return [
    ...(hasCiPaths ? [LINT_ARGV.ciPaths] : []),
    ...(hasFootprint && changed.some(footprintInput) ? [LINT_ARGV.footprint] : []),
    ...(hasAxioms && changed.some((p) => p.startsWith("lean/")) ? [LINT_ARGV.axioms] : []),
  ];
}

/** Lean `lintStages`: the `check.sh` stages the dry lint stage runs. */
export const LINT_STAGES = ["lake build", "axiom check"];
/** Lean `checkFailKind`: the kind of a real land's `checks` refusal from its failed checks (reads-test match, failed stages). */
export function checkFailKind(fs: { reads: boolean; stages: string[] }[]): Kind {
  if (fs.some((f) => f.reads)) return "reads";
  return fs.length > 0 && fs.every((f) => f.stages.length > 0 && f.stages.every((n) => LINT_STAGES.includes(n))) ? "lint" : "checks";
}
/** The `check.sh` stage names a failed check's output reports (parsing only; the decision is `checkFailKind`):
 *  `check: FAILED stage: <name>` lines and the `  - <name>` lines after `check: FAILED:`. */
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

// ---- Refusal reasons and the fwcore preflight (Lean `Fw.Console.LandQueue.reasonOf`, `refusedLine`, `fwcoreStale`; task land-queue-why) ----
// Checked against the golden ops `landQueue.reason` and `landQueue.fwcoreStale` (test/land-queue.test.ts).
/** Lean `reasonOf`: the message of a refusal, or a fixed text when it is empty (`reasonOf_nonempty`). */
export const reasonOf = (msg: string): string => (msg === "" ? "no message" : msg);
/** Lean `refusalReason`: the reason the queue records for a result of kind `k` with the attempt's optional reason. A refusal always has one
 *  (`refusal_has_reason`); a success keeps what it has. */
export const refusalReason = (k: Kind, r: string | undefined): string | undefined => (isOk(k) ? (r === undefined ? undefined : reasonOf(r)) : reasonOf(r ?? ""));
/** Lean `refusedLine`: the stderr line printed before the `VERDICT` line. */
export const refusedLine = (msg: string): string => `REFUSED: ${reasonOf(msg)}`;
/** Lean `fwcoreStaleReason`. */
export const FWCORE_STALE_REASON = "fwcore-stale: run sh scripts/fwcore-build.sh";
/** Lean `fwcoreStale`: no build record, or a record of another commit with a Lean source or the build script changed since. */
export const fwcoreStale = (recorded: string | null, same: boolean, moved: boolean): boolean => recorded === null || (!same && moved);

// ---- The queue's fwcore rebuild between two entries (Lean `Fw.Console.LandQueue.afterLand`, `stopKind`; task land-queue-fwcore-rebuild) ----
// Checked against the golden op `landQueue.afterLand` (test/land-queue.test.ts).
/** Lean `coreSource`: a path fwcore is built from (TS `FWCORE_BUILD_READS`: `lean/**`, the build script and its record rule). */
export const coreSource = (p: string): boolean => p.startsWith("lean/") || p === "scripts/fwcore-build.sh" || p === "scripts/fwcore-record-rule.sh";
/** Lean `touchesCore`. */
export const touchesCore = (paths: string[]): boolean => paths.some(coreSource);
/** Lean `needsRebuild`: only a finished land whose merged diff touched a core path. */
export const needsRebuild = (k: Kind, paths: string[]): boolean => k === "done" && touchesCore(paths);
/** Lean `After`. */
export type After = { proceed: true; rebuilt: boolean } | { proceed: false };
/** Lean `afterLand`: `ok` (the rebuild result) is read only when a rebuild is needed. */
export const afterLand = (k: Kind, paths: string[], ok: () => boolean): After =>
  needsRebuild(k, paths) ? (ok() ? { proceed: true, rebuilt: true } : { proceed: false }) : { proceed: true, rebuilt: false };
/** Lean `stopKind`: the kind the next entry gets when the queue stops. */
export const stopKind = (a: After): Kind | null => (a.proceed ? null : "rebuild");
/** Lean `rebuildReason`. */
export const REBUILD_REASON = "fwcore-rebuild-failed: sh scripts/fwcore-build.sh failed after a land that changed lean/";
