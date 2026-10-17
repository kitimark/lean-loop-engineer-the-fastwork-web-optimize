// The single writer of <main checkout>/.fw-console/events.jsonl.
import { execFileSync } from "node:child_process";
import { closeSync, existsSync, fsyncSync, mkdirSync, openSync, readFileSync, rmSync, writeFileSync, writeSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { Event, type LiveBoard, type Command, type CommandReply } from "@fw/contracts";
import type { Core } from "./core/index.ts";
import { logLines } from "./core/lean.ts";

/** `.fw-console/` lives at the main checkout root, even when run from a worktree. */
export function consoleDir(cwd = process.cwd()): string {
  if (process.env.FW_CONSOLE_DIR) return resolve(process.env.FW_CONSOLE_DIR);
  const common = execFileSync("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd })
    .toString().trim();
  return join(dirname(common), ".fw-console");
}

/** A client's legacy `live` on a `task.define` is dropped (claim-order-lean): the board binds agents from agent.spawn /
 *  agent.stop (Lean `Fw.Plan.agentOf`), and the console no longer adds `live`. Logged events that carry it still replay
 *  to the same board. Other commands pass unchanged. No decision here. */
export function withoutLive(cmd: Command): Command {
  if (cmd.type !== "task.define" || cmd.live === undefined) return cmd;
  const { live: _legacy, ...rest } = cmd;
  return rest;
}

export class Store {
  seq = 0;
  private fd: number;
  private refusedFd: number;
  private listeners = new Set<() => void>();

  private queue: Promise<unknown> = Promise.resolve();

  readonly dir: string;
  readonly core: Core;
  private clock: () => number;

  private constructor(dir: string, core: Core, clock: () => number) {
    this.dir = dir; this.core = core; this.clock = clock;
    this.fd = openSync(join(dir, "events.jsonl"), "a");
    this.refusedFd = openSync(join(dir, "refused.jsonl"), "a");
  }

  /** Opens the log, takes the writer lock, replays events into the projection. */
  static async open(dir: string, core: Core, clock: () => number = Date.now): Promise<Store> {
    mkdirSync(dir, { recursive: true });
    const lock = join(dir, "api.lock");
    if (existsSync(lock)) {
      const pid = Number(readFileSync(lock, "utf8"));
      let alive = false;
      try { process.kill(pid, 0); alive = true; } catch { /* dead */ }
      if (alive && pid !== process.pid) throw new Error(`another console-api (pid ${pid}) is the writer`);
    }
    writeFileSync(lock, String(process.pid));
    const path = join(dir, "events.jsonl");
    if (existsSync(path)) {
      const lines = readFileSync(path, "utf8").split("\n").filter((l) => l.length > 0);
      const good: string[] = [];
      for (const l of lines) {
        try { Event.parse(JSON.parse(l)); good.push(l); } catch { break; } // torn tail line: drop it
      }
      if (good.length !== lines.length) writeFileSync(path, good.map((l) => l + "\n").join(""));
    }
    const s = new Store(dir, core, clock);
    // fwcore holds the projection: replay the log once now; the core replays it again after any restart
    await core.open(() => logLines(path));
    for (const e of s.readEvents()) s.seq = Math.max(s.seq, e.seq);
    return s;
  }

  readEvents(): Event[] {
    const path = join(this.dir, "events.jsonl");
    if (!existsSync(path)) return [];
    return readFileSync(path, "utf8").split("\n").filter(Boolean).map((l) => Event.parse(JSON.parse(l)));
  }

  /** check -> append + fsync -> commit to the projection -> notify. */
  /** Commands are serialized: one at a time through the core, then the log. */
  submit(cmd: Command): Promise<CommandReply> {
    const run = this.queue.then(() => this.submitNow(cmd));
    this.queue = run.catch(() => undefined);
    return run;
  }

  private async submitNow(sent: Command): Promise<CommandReply> {
    const cmd = withoutLive(sent);
    const ts = this.clock();
    const { outcome } = await this.core.apply({ ...cmd, ts });
    if (!outcome.accepted) {
      writeSync(this.refusedFd, JSON.stringify({ ts, command: cmd, reason: outcome.reason }) + "\n");
      return { ok: false, reason: outcome.reason };
    }
    if (outcome.duplicate) return { ok: true, seq: null, duplicate: true };
    const seq = this.seq + 1;
    try {
      writeSync(this.fd, JSON.stringify({ ...cmd, seq, ts }) + "\n");
      fsyncSync(this.fd);
    } catch (e) {
      this.core.restart(); // fwcore accepted an event the log does not hold: rebuild it from the log
      throw e;
    }
    this.seq = seq;
    for (const l of this.listeners) l();
    return { ok: true, seq, duplicate: false };
  }

  board(): Promise<LiveBoard> { return this.core.board(this.clock(), this.seq); }

  subscribe(fn: () => void): () => void {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  close() {
    closeSync(this.fd);
    closeSync(this.refusedFd);
    this.core.close();
    rmSync(join(this.dir, "api.lock"), { force: true });
  }
}
