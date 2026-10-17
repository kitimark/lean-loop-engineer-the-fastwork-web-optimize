// Lean backend: one long-lived, stateful `fwcore` child speaking JSON lines (lean/README.md, lean/Fw/Serve.lean).
// fwcore holds the console state; console-api sends one event per call, never the state:
//   -> {"id":N,"op":"console.replay","events":[Event,...]}\n   <- {"id":N,"replayed":{"accepted","duplicate","refused"}}\n
//   -> {"id":N,"op":"console.apply","event":ReducerEvent}\n     <- {"id":N,"outcome":Outcome,"changed":{cards,steps,runs}}\n
//   -> {"id":N,"op":"console.query","now":T,"seq":S}\n          <- {"id":N,"board":Board}\n
// Stateless ops stay available (console.apply with a `state`, console.board) for the golden tests.
// Failure: {"id":N,"error":"..."}. A crash (exit, abort on panic) fails the in-flight calls, is logged as an incident,
// and the process is restarted on the next call; a restarted process first replays the whole log (`open`), so it never
// answers from a partial state. A failed replay kills that process too.
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { createInterface } from "node:readline";
import { z } from "zod";
import { ApplyResponse, Board, Card, Outcome, Run, Step, type ReducerEvent, type State } from "@fw/contracts";
import type { Core } from "./index.ts";

export type LeanBin = { path: string };
export type Incident = { at: number; kind: "exit" | "stderr" | "bad-line" | "replay" | "timeout"; detail: string };

export const BUILD_HINT = "cd lean && lake build";

/** Reply of the stateful `console.apply`: the outcome and the rows the event touched (empty unless accepted fresh). */
export const ServeApply = z.object({
  outcome: Outcome,
  changed: z.object({ cards: z.array(Card), steps: z.array(Step), runs: z.array(Run) }),
});
export type ServeApply = z.infer<typeof ServeApply>;

/** Reply of `console.replay`: how many events were accepted fresh, accepted as duplicates, or refused. */
export const Replayed = z.object({
  accepted: z.number().int().nonnegative(),
  duplicate: z.number().int().nonnegative(),
  refused: z.number().int().nonnegative(),
});
export type Replayed = z.infer<typeof Replayed>;

/** Events per `console.replay` request (one JSON line each; keeps lines a few MB). */
export const REPLAY_CHUNK = 20_000;

/** Where fwcore lives. FW_CORE_BIN overrides (tests). Throws when it is not built. */
export function leanBinary(root: string, env: Record<string, string | undefined>): LeanBin {
  const path = env.FW_CORE_BIN ?? join(root, "lean/.lake/build/bin/fwcore");
  if (!existsSync(path)) {
    throw new Error(`fwcore binary not found at ${path}. console-api needs it for every decision; build it with: ${BUILD_HINT}`);
  }
  return { path };
}

/** The raw JSON lines of an events.jsonl file (each line one event object, as console-api wrote it). */
export function logLines(path: string): string[] {
  if (!existsSync(path)) return [];
  return readFileSync(path, "utf8").split("\n").filter((l) => l.length > 0);
}

type Pending = { ok: (v: Record<string, unknown>) => void; err: (e: Error) => void; timer: NodeJS.Timeout };

/** Per-call deadline (ms). A call that exceeds it kills the child (crash-restart with replay). Replay chunks get more. */
export const CALL_TIMEOUT_MS = 10_000;
export const REPLAY_TIMEOUT_MS = 120_000;

export class LeanCore implements Core {
  readonly name = "lean" as const;
  private child: ChildProcessWithoutNullStreams | null = null;
  private nextId = 1;
  private pending = new Map<number, Pending>();
  private closed = false;
  restarts = 0;
  /** replays sent so far (startup and after each restart) */
  replays = 0;
  private exitedOf = new Map<ChildProcessWithoutNullStreams, { promise: Promise<void>; done: () => void }>();
  /** the event log; set by open(), replayed into every fresh child before its first call */
  private log: (() => string[]) | null = null;
  private replayDone: Promise<Replayed> = Promise.resolve({ accepted: 0, duplicate: 0, refused: 0 });

  private bin: LeanBin;
  private onIncident: (i: Incident) => void;
  private callTimeoutMs: number;

  constructor(bin: LeanBin, onIncident: (i: Incident) => void = (i) => console.error("fwcore incident:", JSON.stringify(i)),
    callTimeoutMs = CALL_TIMEOUT_MS) {
    this.bin = bin;
    this.onIncident = onIncident;
    this.callTimeoutMs = callTimeoutMs;
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
    let done!: () => void;
    this.exitedOf.set(child, { promise: new Promise<void>((r) => { done = r; }), done });
    createInterface({ input: child.stdout }).on("line", (line) => {
      if (this.child !== child) return; // a dead or poisoned child: its late lines answer nobody
      let msg: { id?: unknown; error?: string };
      // An unparsable line or a reply that answers no pending call means the stream is out of step with our
      // requests: the child's answers can no longer be trusted, so kill it (the restart replays the log).
      try { msg = JSON.parse(line); } catch { this.incident("bad-line", line.slice(0, 200)); this.poison(child, "unparsable reply line"); return; }
      const p = typeof msg.id === "number" ? this.pending.get(msg.id) : undefined;
      if (!p) {
        this.incident("bad-line", `reply without a pending call: ${line.slice(0, 200)}`);
        this.poison(child, "reply id mismatch");
        return;
      }
      this.pending.delete(msg.id as number);
      clearTimeout(p.timer);
      if (msg.error !== undefined) p.err(new Error(`fwcore: ${msg.error}`));
      else p.ok(msg as Record<string, unknown>);
    });
    createInterface({ input: child.stderr }).on("line", (l) => this.incident("stderr", l));
    // A write error (EPIPE) never fails calls by itself: it only makes sure the child is dead. Calls fail in
    // crashed(), which runs once per child on exit or error, so "process known dead" always precedes rejection.
    child.stdin.on("error", () => { child.kill("SIGKILL"); });
    child.on("error", (e) => this.crashed(child, `spawn error: ${e.message}`));
    child.on("exit", (code, sig) => this.crashed(child, `exit code=${code} signal=${sig}`));
    if (this.log) this.replayInto(child, this.log());
    return child;
  }

  /** Write the log into a fresh child, in chunks, before anything else is written to it. Requests are answered in
   *  order, so every later call sees the full state. A replay error poisons the child (no partial state). */
  private replayInto(child: ChildProcessWithoutNullStreams, lines: string[]) {
    this.replays++;
    const parts: Promise<Record<string, unknown>>[] = [];
    for (let i = 0; i < lines.length; i += REPLAY_CHUNK) {
      parts.push(this.send(child, `"op":"console.replay","events":[${lines.slice(i, i + REPLAY_CHUNK).join(",")}]`, REPLAY_TIMEOUT_MS));
    }
    this.replayDone = Promise.all(parts).then(
      (rs) => {
        const t = rs.map((r) => Replayed.parse(r.replayed)).reduce(
          (a, b) => ({ accepted: a.accepted + b.accepted, duplicate: a.duplicate + b.duplicate, refused: a.refused + b.refused }),
          { accepted: 0, duplicate: 0, refused: 0 });
        if (t.refused > 0 || t.duplicate > 0) this.incident("replay", `log replay: ${JSON.stringify(t)} of ${lines.length} events`);
        return t;
      },
      (e: Error) => { this.poison(child, `replay failed: ${e.message}`); throw e; },
    );
    this.replayDone.catch(() => undefined); // the failure is reported through the calls queued behind it
  }

  /** Kill a child whose state is not trusted; fail every outstanding call now. */
  private poison(child: ChildProcessWithoutNullStreams, detail: string) {
    if (this.child === child) this.crashed(child, detail);
    child.kill("SIGKILL");
  }

  private crashed(child: ChildProcessWithoutNullStreams, detail: string) {
    const ex = this.exitedOf.get(child);
    if (!ex || this.child !== child) { ex?.done(); return; } // already handled or closed
    this.child = null; // restart lazily on the next call (no hot loop)
    this.restarts++;
    this.incident("exit", detail);
    const err = new Error(`fwcore crashed (${detail}); it restarts on the next call`);
    for (const p of this.pending.values()) { clearTimeout(p.timer); p.err(err); }
    this.pending.clear();
    this.exitedOf.delete(child);
    ex.done(); // after incident, restart count and rejections
  }

  /** Write one request (its fields as a JSON fragment) to `child`; resolves with the reply. */
  private send(child: ChildProcessWithoutNullStreams, fields: string, timeoutMs = this.callTimeoutMs): Promise<Record<string, unknown>> {
    return new Promise((ok, err) => {
      const id = this.nextId++;
      const timer = setTimeout(() => {
        this.incident("timeout", `call ${id} unanswered after ${timeoutMs} ms`);
        this.poison(child, `call ${id} timed out after ${timeoutMs} ms`);
      }, timeoutMs);
      timer.unref();
      this.pending.set(id, { ok, err, timer });
      child.stdin.write(`{"id":${id},${fields}}\n`, (e) => { if (e) child.kill("SIGKILL"); });
    });
  }

  private call(op: string, fields: Record<string, unknown>): Promise<Record<string, unknown>> {
    let child: ChildProcessWithoutNullStreams;
    try { child = this.ensure(); } catch (e) { return Promise.reject(e as Error); }
    return this.send(child, JSON.stringify({ op, ...fields }).slice(1, -1));
  }

  /** Attach the event log (raw JSON lines) and replay it into a fresh fwcore. Every later restart replays it again
   *  before the next call. Rejects if the replay fails. */
  async open(log: () => string[]): Promise<Replayed> {
    this.log = log;
    const c = this.child;
    if (c) this.poison(c, "reopened: replaying the log into a fresh process");
    this.ensure();
    return this.replayDone;
  }

  /** `console.apply` (stateful): one event in, the outcome and the changed rows out. */
  async apply(event: ReducerEvent): Promise<ServeApply> {
    return ServeApply.parse(await this.call("console.apply", { event }));
  }

  /** `console.query`: the board of the current state. */
  async board(now: number, seq: number): Promise<Board> {
    return Board.parse((await this.call("console.query", { now, seq })).board);
  }

  /** Drop the current process; the next call starts a fresh one and replays the log (use when the log and the
   *  process may disagree, e.g. an append failed after fwcore accepted the event). */
  restart() {
    const c = this.child;
    if (c) this.poison(c, "restart requested");
  }

  /** stateless `console.apply` (state in, state out): golden conformance only */
  async applyPure(state: State, event: ReducerEvent): Promise<ApplyResponse> {
    return ApplyResponse.parse(await this.call("console.apply", { state, event }));
  }

  /** stateless `console.board`: golden conformance only */
  async boardPure(state: State, now: number, seq: number): Promise<Board> {
    return Board.parse((await this.call("console.board", { state, now, seq })).board);
  }

  /** any other op (`ops.*`, stateless `console.*`): fields in, reply fields out */
  ops(op: string, fields: Record<string, unknown> = {}) { return this.call(op, fields); }

  /** raw op, for the samples test */
  raw(op: string, fields: Record<string, unknown> = {}) { return this.call(op, fields); }

  /** test hook: freeze the child (SIGSTOP) so a call written next cannot be answered before killForTest() */
  stopForTest() { this.child?.kill("SIGSTOP"); }

  /** test hook: change the per-call deadline */
  callTimeoutForTest(ms: number) { this.callTimeoutMs = ms; }

  /** test hook: kill the child as a crash would; resolves once the crash is fully handled (incident logged,
   *  restarts counted, in-flight calls rejected). */
  killForTest(): Promise<void> {
    const c = this.child;
    if (!c) return Promise.resolve();
    const ex = this.exitedOf.get(c)!.promise;
    c.kill("SIGKILL");
    return ex;
  }

  close() {
    this.closed = true;
    const c = this.child;
    this.child = null;
    c?.kill();
    for (const p of this.pending.values()) { clearTimeout(p.timer); p.err(new Error("fwcore: core closed")); }
    this.pending.clear();
  }
}
