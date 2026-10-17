// The one interface between the I/O shell and the decisions. All decision logic lives in Lean (`fwcore`):
// `console.apply` is the reducer, `console.board` the board projection. There is no TS fallback.
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import type { ApplyResponse, Board, ReducerEvent, State } from "@fw/contracts";
import { LeanCore, leanBinary, type Incident } from "./lean.ts";

export interface Core {
  readonly name: "lean";
  /** `fwcore console.apply`: (state, event) -> (state', outcome) */
  apply(state: State, event: ReducerEvent): Promise<ApplyResponse>;
  /** `fwcore console.board`: (state, now, seq) -> board */
  board(state: State, now: number, seq: number): Promise<Board>;
  close(): void;
}

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "../../../..");

/** Throws (with the build command) when the fwcore binary is missing. */
export function selectCore(
  env: Record<string, string | undefined> = process.env,
  root = repoRoot,
  onIncident?: (i: Incident) => void,
): LeanCore {
  return new LeanCore(leanBinary(root, env), onIncident);
}
