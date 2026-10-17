// Lean backend: one long-lived `lake exe fwcore` child speaking JSON lines.
// Assumed protocol (to be matched with lean/ by the lead):
//   -> {"id":N,"op":"console.apply","state":State,"event":ReducerEvent}\n
//   <- {"id":N,"state":State,"outcome":Outcome}\n      (or {"id":N,"error":"..."})
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { createInterface } from "node:readline";
import { ApplyResponse, type Board, type ReducerEvent, type State } from "@fw/contracts";
import type { Core } from "./index.ts";

export type LeanBin = { cwd: string; cmd: string; args: string[] };

/** Where fwcore lives. FW_CORE_CMD overrides (a space-separated command run in lean/). */
export function leanBinary(root: string, env: Record<string, string | undefined>): LeanBin | null {
  const cwd = join(root, "lean");
  if (env.FW_CORE_CMD) {
    const [cmd, ...args] = env.FW_CORE_CMD.split(" ");
    return { cwd: existsSync(cwd) ? cwd : root, cmd: cmd!, args };
  }
  if (!existsSync(join(cwd, ".lake/build/bin/fwcore"))) return null;
  return { cwd, cmd: "lake", args: ["exe", "fwcore"] };
}

export class LeanCore implements Core {
  readonly name = "lean" as const;
  private child: ChildProcessWithoutNullStreams;
  private nextId = 1;
  private pending = new Map<number, { ok: (v: ApplyResponse) => void; err: (e: Error) => void }>();

  private boardFn: (s: State, now: number, seq: number) => Board;

  constructor(bin: LeanBin, boardFn: (s: State, now: number, seq: number) => Board) {
    this.boardFn = boardFn;
    this.child = spawn(bin.cmd, bin.args, { cwd: bin.cwd, stdio: ["pipe", "pipe", "inherit"] }) as unknown as ChildProcessWithoutNullStreams;
    createInterface({ input: this.child.stdout }).on("line", (line) => {
      const msg = JSON.parse(line) as { id: number; error?: string };
      const p = this.pending.get(msg.id);
      if (!p) return;
      this.pending.delete(msg.id);
      if (msg.error) p.err(new Error(`fwcore: ${msg.error}`));
      else p.ok(ApplyResponse.parse(msg));
    });
    this.child.on("exit", (code) => {
      for (const p of this.pending.values()) p.err(new Error(`fwcore exited (${code})`));
      this.pending.clear();
    });
  }

  apply(state: State, event: ReducerEvent): Promise<ApplyResponse> {
    const id = this.nextId++;
    return new Promise((ok, err) => {
      this.pending.set(id, { ok, err });
      this.child.stdin.write(JSON.stringify({ id, op: "console.apply", state, event }) + "\n");
    });
  }

  board(state: State, now: number, seq: number): Board { return this.boardFn(state, now, seq); }
  close() { this.child.kill(); }
}
