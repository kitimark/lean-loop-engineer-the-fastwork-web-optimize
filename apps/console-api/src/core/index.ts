// The one interface between the I/O shell and the decisions. All decision logic lives behind it.
//   FW_CORE=ts    pure TS stand-in (./reducer.ts), to be deleted when fwcore is complete
//   FW_CORE=lean  spawn `lake exe fwcore` in lean/ (./lean.ts)
//   unset         lean when the built binary exists, else ts
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import type { ApplyResponse, Board, ReducerEvent, State } from "@fw/contracts";
import { board } from "./board.ts";
import { apply } from "./reducer.ts";
import { LeanCore, leanBinary } from "./lean.ts";

export interface Core {
  readonly name: "ts" | "lean";
  /** `fwcore console.apply`: (state, event) -> (state', outcome) */
  apply(state: State, event: ReducerEvent): Promise<ApplyResponse>;
  /** Board projection. TS for both backends until fwcore grows `console.board`. */
  board(state: State, now: number, seq: number): Board;
  close(): void;
}

export const tsCore = (): Core => ({
  name: "ts",
  apply: async (s, e) => apply(s, e),
  board,
  close() {},
});

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "../../../..");

export function selectCore(env: Record<string, string | undefined> = process.env, root = repoRoot): Core {
  const want = env.FW_CORE;
  if (want === "ts") return tsCore();
  const bin = leanBinary(root, env);
  if (want === "lean") {
    if (!bin) throw new Error("FW_CORE=lean but no fwcore binary (build it: cd lean && lake build fwcore)");
    return new LeanCore(bin, board);
  }
  return bin && existsSync(bin.cwd) ? new LeanCore(bin, board) : tsCore();
}
