// The verdict of an `fw land`: one kind, one `VERDICT <kind> <task>` line, one exit code (task land-dry).
// TS stand-in for Lean `Fw.Console.LandVerdict` and `Fw.Console.LandDry`; marked for replacement by an `fwcore` op. Checked against
// the Lean golden `packages/contracts/golden/console/land-dry.jsonl` (test/land-verdict.test.ts). No decision lives anywhere else:
// the land code only names the kind of each refusal; scripts decide from the exit code or the word after `VERDICT`, never from prose.

/** Lean `Kind`: refusals busy dirty scope reads conflict checks stale unknown lint; successes done dry queued empty. */
export type Kind = "busy" | "dirty" | "scope" | "reads" | "conflict" | "checks" | "stale" | "unknown" | "done" | "dry" | "queued" | "empty" | "lint";
export const KINDS: Kind[] = ["busy", "dirty", "scope", "reads", "conflict", "checks", "stale", "unknown", "done", "dry", "queued", "empty", "lint"];

/** Lean `Kind.ok`: a finished land, a passing dry land, an accepted queue entry. */
export const isOk = (k: Kind): boolean => k === "done" || k === "dry" || k === "queued" || k === "empty";
/** Lean `Kind.exitCode`: 0 for a success, a distinct number for each refusal (`unknown` is 2, the code `fw land` always used). */
export const EXIT: Record<Kind, number> = { busy: 10, dirty: 11, scope: 12, reads: 13, conflict: 14, checks: 15, stale: 16, unknown: 2, done: 0, dry: 0, queued: 0, empty: 0, lint: 17 };
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
  if (!f.containsMain) return "stale";
  if (!f.own) return "empty";
  if (!f.scope) return "scope";
  if (!f.merges) return "conflict";
  if (f.readsSelected && !f.readsTest) return "reads";
  if (!f.lints) return "lint";
  return "dry";
}
/** Lean `handbackAllowed`: an agent hands back only on a `dry` verdict. */
export const handbackAllowed = (k: Kind): boolean => k === "dry";
