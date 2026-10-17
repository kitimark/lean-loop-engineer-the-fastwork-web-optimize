// Lean backend: one long-lived `fwcore` child speaking JSON lines (lean/README.md).
//   -> {"id":N,"op":"console.apply","state":State,"event":ReducerEvent}\n  <- {"id":N,"state":State,"outcome":Outcome}\n
//   -> {"id":N,"op":"console.board","state":State,"now":T,"seq":S}\n        <- {"id":N,"board":Board}\n
// Failure: {"id":N,"error":"..."}. A crash (exit, abort on panic) fails the in-flight calls, is logged as an
// incident, and the process is restarted on the next call.
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { createInterface } from "node:readline";
import { ApplyResponse, Board, type ReducerEvent, type State } from "@fw/contracts";
import type { Core } from "./index.ts";

export type LeanBin = { path: string };
export type Incident = { at: number; kind: "exit" | "stderr" | "bad-line"; detail: string };

export const BUILD_HINT = "cd lean && lake build";

/** Where fwcore lives. FW_CORE_BIN overrides (tests). Throws when it is not built. */
export function leanBinary(root: string, env: Record<string, string | undefined>): LeanBin {
  const path = env.FW_CORE_BIN ?? join(root, "lean/.lake/build/bin/fwcore");
  if (!existsSync(path)) {
    throw new Error(`fwcore binary not found at ${path}. console-api needs it for every decision; build it with: ${BUILD_HINT}`);
  }
  return { path };
}

type Pending = { ok: (v: Record<string, unknown>) => void; err: (e: Error) => void };

export class LeanCore implements Core {
  readonly name = "lean" as const;
  private child: ChildProcessWithoutNullStreams | null = null;
  private nextId = 1;
  private pending = new Map<number, Pending>();
  private closed = false;
  restarts = 0;

  private bin: LeanBin;
  private onIncident: (i: Incident) => void;

  constructor(bin: LeanBin, onIncident: (i: Incident) => void = (i) => console.error("fwcore incident:", JSON.stringify(i))) {
    this.bin = bin;
    this.onIncident = onIncident;
  }

  private incident(kind: Incident["kind"], detail: string) { this.onIncident({ at: Date.now(), kind, detail }); }

  private ensure(): ChildProcessWithoutNullStreams {
    if (this.child) return this.child;
    if (this.closed) throw new Error("fwcore: core is closed");
    const child = spawn(this.bin.path, [], {
      env: { ...process.env, LEAN_ABORT_ON_PANIC: "1" }, // a panic must abort, not return a default value
      stdio: ["pipe", "pipe", "pipe"],
    }) as ChildProcessWithoutNullStreams;
    this.child = child;
    createInterface({ input: child.stdout }).on("line", (line) => {
      let msg: { id?: unknown; error?: string };
      try { msg = JSON.parse(line); } catch { this.incident("bad-line", line.slice(0, 200)); return; }
      const p = typeof msg.id === "number" ? this.pending.get(msg.id) : undefined;
      if (!p) { this.incident("bad-line", `reply without a pending call: ${line.slice(0, 200)}`); return; }
      this.pending.delete(msg.id as number);
      if (msg.error !== undefined) p.err(new Error(`fwcore: ${msg.error}`));
      else p.ok(msg as Record<string, unknown>);
    });
    createInterface({ input: child.stderr }).on("line", (l) => this.incident("stderr", l));
    child.stdin.on("error", () => {}); // EPIPE after a crash is reported through exit
    child.on("error", (e) => this.crashed(child, `spawn error: ${e.message}`));
    child.on("exit", (code, sig) => this.crashed(child, `exit code=${code} signal=${sig}`));
    return child;
  }

  private crashed(child: ChildProcessWithoutNullStreams, detail: string) {
    if (this.child !== child) return; // already handled or closed
    this.child = null; // restart lazily on the next call (no hot loop)
    this.restarts++;
    this.incident("exit", detail);
    const err = new Error(`fwcore crashed (${detail}); it restarts on the next call`);
    for (const p of this.pending.values()) p.err(err);
    this.pending.clear();
  }

  private call(op: string, fields: Record<string, unknown>): Promise<Record<string, unknown>> {
    return new Promise((ok, err) => {
      let child: ChildProcessWithoutNullStreams;
      try { child = this.ensure(); } catch (e) { err(e as Error); return; }
      const id = this.nextId++;
      this.pending.set(id, { ok, err });
      child.stdin.write(JSON.stringify({ id, op, ...fields }) + "\n");
    });
  }

  async apply(state: State, event: ReducerEvent): Promise<ApplyResponse> {
    return ApplyResponse.parse(await this.call("console.apply", { state, event }));
  }

  async board(state: State, now: number, seq: number): Promise<Board> {
    return Board.parse((await this.call("console.board", { state, now, seq })).board);
  }

  /** raw op, for the samples test */
  raw(op: string, fields: Record<string, unknown> = {}) { return this.call(op, fields); }

  /** test hook: kill the child as a crash would */
  killForTest() { this.child?.kill("SIGKILL"); }

  close() {
    this.closed = true;
    const c = this.child;
    this.child = null;
    c?.kill();
    for (const p of this.pending.values()) p.err(new Error("fwcore: core closed"));
    this.pending.clear();
  }
}
