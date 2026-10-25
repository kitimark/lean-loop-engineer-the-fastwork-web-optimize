// Which run does a wait mean? TS twin of Lean Fw.Ci.Dispatch.wanted / select (lean/Fw/Ci/Dispatch.lean, task ci-push-probe-inputs),
// replayed against the `select`, `one` and `dedup` lines of packages/contracts/golden/ci/dispatch.jsonl by test/want.test.ts. The decision is Lean's;
// this file only mirrors it until a fwcore op exists (a TS stand-in).
export type Want = { kind: "push"; sha: string } | { kind: "dispatch"; workflow: string; nonce: string };
export type WRun = { id: number; event: string; title: string; sha: string };

/** Lean `Fw.Ci.Dispatch.dispatchWorkflows` (a `workflows` line of the golden): the workflows whose `run-name` echoes a dispatch nonce. */
export const DISPATCH_WORKFLOWS: readonly string[] = ["trajectory-probe", "breakpoint-gate", "chromium-counts", "webkit-sim"];
/** Lean `titleFor`: the title a dispatch of `workflow` with this nonce gets (`run-name` of the workflow's yml). */
export const titleFor = (workflow: string, nonce: string): string => `${workflow} dispatch nonce=${nonce}`;
/** The title of a trajectory-probe dispatch. */
export const titleOf = (nonce: string): string => titleFor("trajectory-probe", nonce);
/** 8 to 32 characters of `a-z0-9`. */
export const validNonce = (n: string): boolean => [...n].length >= 8 && [...n].length <= 32 && /^[a-z0-9]+$/.test(n);
/** 7 to 40 characters of `0-9a-f`. */
export const validSha = (s: string): boolean => s.length >= 7 && s.length <= 40 && /^[0-9a-f]+$/.test(s);

/** Lean `Fw.Ci.Dispatch.wanted`. */
export function wanted(w: Want, r: WRun): boolean {
  if (w.kind === "push") return validSha(w.sha) && r.event === "push" && r.sha.startsWith(w.sha);
  return DISPATCH_WORKFLOWS.includes(w.workflow) && validNonce(w.nonce) && r.event === "workflow_dispatch" && r.title === titleFor(w.workflow, w.nonce);
}

/** Lean `Fw.Ci.Dispatch.select`: the ids of the wanted runs, in list order. */
export const select = (w: Want, rows: WRun[]): number[] => rows.filter((r) => wanted(w, r)).map((r) => r.id);

/** Lean `Fw.Ci.Dispatch.dispatchOnly`: a push wait selects no run, yet the commit has `workflow_dispatch` runs (the hint of `fw ci wait`). */
export function dispatchOnly(w: Want, rows: WRun[]): boolean {
  if (w.kind !== "push") return false;
  return validSha(w.sha) && select(w, rows).length === 0 && rows.some((r) => r.event === "workflow_dispatch" && r.sha.startsWith(w.sha));
}

/** Lean `Fw.Ci.Dispatch.One`: the one run a wait means, or why there is none. */
export type One = { kind: "found"; id: number } | { kind: "absent" } | { kind: "ambiguous"; ids: number[] };

/** Lean `Fw.Ci.Dispatch.selectOne`: no wanted run is `absent`; a push wait takes the greatest id of its commit's push runs;
 *  a dispatch wait takes its only run, and several runs of one nonce are `ambiguous` (an error, never the newest). */
export function selectOne(w: Want, rows: WRun[]): One {
  const ids = select(w, rows);
  if (ids.length === 0) return { kind: "absent" };
  if (w.kind === "push") return { kind: "found", id: ids.reduce((a, b) => Math.max(a, b), ids[0] as number) };
  if (ids.length === 1) return { kind: "found", id: ids[0] as number };
  return { kind: "ambiguous", ids };
}

/** Lean `Fw.Ci.Dispatch.dedupById` (`keepNewest` folded over the rows): one row per id, the one with the newest `at`, at the
 *  place of the id's first row; a tie keeps the row already kept. */
export function dedupById<T>(rows: readonly T[], id: (r: T) => number, at: (r: T) => number): T[] {
  const kept: T[] = [];
  const place = new Map<number, number>();
  for (const r of rows) {
    const k = place.get(id(r));
    if (k === undefined) { place.set(id(r), kept.length); kept.push(r); }
    else if (at(kept[k] as T) < at(r)) kept[k] = r;
  }
  return kept;
}

/** Lean `Fw.Ci.Dispatch.dupIds`: the ids listed more than once, each once, in the order of `dedupById`. */
export function dupIds<T>(rows: readonly T[], id: (r: T) => number): number[] {
  const count = new Map<number, number>();
  for (const r of rows) count.set(id(r), (count.get(id(r)) ?? 0) + 1);
  return [...count].filter(([, n]) => n >= 2).map(([i]) => i);
}
