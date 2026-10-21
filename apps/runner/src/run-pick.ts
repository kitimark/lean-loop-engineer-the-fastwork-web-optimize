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

// Which widths may a trajectory dispatch walk? TS stand-in for Fw.Gate.Trajectory.Dispatch (lean/Fw/Gate/Trajectory/Dispatch.lean, task
// traj-dispatch-scope), replayed against packages/contracts/golden/gate/trajectory-dispatch.jsonl by test/run-dispatch.test.ts.

export type Mark = "verdict" | "diagnostic";
export type Why = "emptyWidths" | "badInput" | "scopedVerdict";
export type Decision = { kind: "accepted"; widths: number[] } | { kind: "refused"; why: Why };
export type Engine = "chromium" | "linux-webkit" | "mac-webkit";

/** The widths the lane may run (Lean `allowedWidths`). */
export const ALLOWED_WIDTHS: readonly number[] = [390, 640, 641, 1280];

/** Lean `pickWidths`: empty is all four; else each entry digits only, in the lane, no repeat; null is a refusal. */
export function pickWidths(s: string): number[] | null {
  if (s === "") return [...ALLOWED_WIDTHS];
  const parts = s.split(",");
  if (!parts.every((p) => /^[0-9]+$/.test(p))) return null;
  const ns = parts.map((p) => Number(p));
  return ns.every((n) => ALLOWED_WIDTHS.includes(n)) && new Set(ns).size === ns.length ? ns : null;
}

/** Lean `dispatch`: none is empty, a width outside the lane is bad, a verdict run short of a lane width is scoped. */
export function dispatch(mark: Mark, ws: number[]): Decision {
  if (ws.length === 0) return { kind: "refused", why: "emptyWidths" };
  if (!ws.every((w) => ALLOWED_WIDTHS.includes(w))) return { kind: "refused", why: "badInput" };
  if (mark === "verdict" && !ALLOWED_WIDTHS.every((w) => ws.includes(w))) return { kind: "refused", why: "scopedVerdict" };
  return { kind: "accepted", widths: ws };
}

/** Lean `dispatchIn`: the decision on a mark and the `widths` input. */
export function dispatchIn(mark: Mark, s: string): Decision {
  const ws = pickWidths(s);
  return ws === null ? { kind: "refused", why: "badInput" } : dispatch(mark, ws);
}

const LEG_TABLE: Record<Engine, number[][]> = {
  chromium: [[390], [640], [641], [1280]],
  "linux-webkit": [[390], [640], [641], [1280]],
  "mac-webkit": [[390, 641], [640, 1280]],
};

/** Lean `legs`: each table leg cut to the picked widths, empty legs dropped. */
export function legsOf(engine: Engine, ws: number[]): number[][] {
  return LEG_TABLE[engine].map((l) => l.filter((w) => ws.includes(w))).filter((l) => l.length > 0);
}

/** Lean `enginesOf`: the engines a trajectory dispatch runs for its `engines` input; null is a refusal. */
export function enginesOf(s: string): Engine[] | null {
  if (s === "both") return ["chromium", "linux-webkit", "mac-webkit"];
  if (s === "chromium") return ["chromium"];
  if (s === "playwright-webkit") return ["linux-webkit", "mac-webkit"];
  return null;
}

/** The refusal of a dispatch, worded for the command line. */
export function refusalText(why: Why, widths: string): string {
  if (why === "scopedVerdict") {
    return `refused: --widths ${widths} is a scoped dispatch, and a verdict run (stored, judged) walks all four widths (${ALLOWED_WIDTHS.join(",")}); ` +
      "a run short of a width gets no verdict. Drop --widths, or pass --diagnostic for a run read by hand.";
  }
  if (why === "emptyWidths") return "refused: no widths to walk";
  return `refused: --widths ${widths} must be a comma list from ${ALLOWED_WIDTHS.join(", ")} without repeats`;
}
