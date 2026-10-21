// Which run did my dispatch start? TS stand-in for Fw.Ci.Dispatch.pick (lean/Fw/Ci/Dispatch.lean, task fw-run-dispatch-pick), replayed
// against packages/contracts/golden/ci/dispatch.jsonl by test/run-pick.test.ts. The decision is Lean's; this file only mirrors it
// so `fw run --trajectory` can use it without a fwcore op (a TS stand-in until the op exists).
import { randomBytes } from "node:crypto";

/** The title the workflow's `run-name` gives a dispatch with this nonce (trajectory-probe.yml). */
export const titleOf = (nonce: string): string => `trajectory-probe dispatch nonce=${nonce}`;

/** A fresh nonce: 16 characters of `0-9a-f`, a valid nonce. */
export const newNonce = (): string => randomBytes(8).toString("hex");

/** 8 to 32 characters of `a-z0-9`. */
export const validNonce = (n: string): boolean => [...n].length >= 8 && [...n].length <= 32 && /^[a-z0-9]+$/.test(n);

export type RunRow = { id: number; event: string; title: string };
export type Pick = { kind: "found"; id: number } | { kind: "absent" } | { kind: "ambiguous"; ids: number[] } | { kind: "badNonce" };

/** The row is a `workflow_dispatch` run with exactly the dispatch's title. */
export const isMine = (nonce: string, r: RunRow): boolean => r.event === "workflow_dispatch" && r.title === titleOf(nonce);

/** Lean `Fw.Ci.Dispatch.pick`: the one row that is the dispatch's; none is `absent`, several are `ambiguous`, never a guess. */
export function pickRun(nonce: string, rows: RunRow[]): Pick {
  if (!validNonce(nonce)) return { kind: "badNonce" };
  const ids = rows.filter((r) => isMine(nonce, r)).map((r) => r.id);
  if (ids.length === 0) return { kind: "absent" };
  if (ids.length === 1) return { kind: "found", id: ids[0] as number };
  return { kind: "ambiguous", ids };
}

/** The rows of `gh run list --json databaseId,displayTitle,event`. */
export function parseRunRows(json: string): RunRow[] {
  const raw = JSON.parse(json) as { databaseId: number; displayTitle?: string; event?: string }[];
  return raw.map((r) => ({ id: r.databaseId, event: r.event ?? "", title: r.displayTitle ?? "" }));
}
