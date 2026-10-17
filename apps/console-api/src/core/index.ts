// The one interface between the I/O shell and the decisions. All decision logic lives in Lean (`fwcore`), which
// holds the console state (`fwcore serve`, lean/Fw/Serve.lean): `console.replay` loads the log, `console.apply` is the
// reducer on one event, `console.query` the board projection. There is no TS fallback and no TS copy of the state.
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import type { Board, ReducerEvent } from "@fw/contracts";
import { LeanCore, leanBinary, type Incident, type Replayed, type ServeApply } from "./lean.ts";

export interface Core {
  readonly name: "lean";
  /** attach the log (raw events.jsonl lines) and replay it; the core replays it again after every restart */
  open(log: () => string[]): Promise<Replayed>;
  /** `fwcore console.apply`: event -> (outcome, changed rows); fwcore keeps the new state */
  apply(event: ReducerEvent): Promise<ServeApply>;
  /** `fwcore console.query`: (now, seq) -> board of the current state */
  board(now: number, seq: number): Promise<Board>;
  /** drop the process; the next call replays the log into a fresh one */
  restart(): void;
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
