// Which run does a wait mean? TS twin of Lean Fw.Ci.Dispatch.wanted / select (lean/Fw/Ci/Dispatch.lean, task ci-push-probe-inputs),
// replayed against the `select` lines of packages/contracts/golden/ci/dispatch.jsonl by test/want.test.ts. The decision is Lean's;
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
