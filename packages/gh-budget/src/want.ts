// Which run does a wait mean? TS twin of Lean Fw.Ci.Dispatch.wanted / select (lean/Fw/Ci/Dispatch.lean, task ci-push-probe-inputs),
// replayed against the `select` lines of packages/contracts/golden/ci/dispatch.jsonl by test/want.test.ts. The decision is Lean's;
// this file only mirrors it until a fwcore op exists (a TS stand-in).
export type Want = { kind: "push"; sha: string } | { kind: "dispatch"; nonce: string };
export type WRun = { id: number; event: string; title: string; sha: string };

/** The title a dispatch with this nonce gets (`run-name` of trajectory-probe.yml). */
export const titleOf = (nonce: string): string => `trajectory-probe dispatch nonce=${nonce}`;
/** 8 to 32 characters of `a-z0-9`. */
export const validNonce = (n: string): boolean => [...n].length >= 8 && [...n].length <= 32 && /^[a-z0-9]+$/.test(n);
/** 7 to 40 characters of `0-9a-f`. */
export const validSha = (s: string): boolean => s.length >= 7 && s.length <= 40 && /^[0-9a-f]+$/.test(s);

/** Lean `Fw.Ci.Dispatch.wanted`. */
export function wanted(w: Want, r: WRun): boolean {
  if (w.kind === "push") return validSha(w.sha) && r.event === "push" && r.sha.startsWith(w.sha);
  return validNonce(w.nonce) && r.event === "workflow_dispatch" && r.title === titleOf(w.nonce);
}

/** Lean `Fw.Ci.Dispatch.select`: the ids of the wanted runs, in list order. */
export const select = (w: Want, rows: WRun[]): number[] => rows.filter((r) => wanted(w, r)).map((r) => r.id);
