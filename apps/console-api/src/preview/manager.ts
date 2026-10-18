// Task previews: process and git glue around the Lean rules in `Fw.Console.Preview` (via `console.preview*` ops).
// This file holds the table of what the console started and does the I/O: git worktree, build, server child, kill.
// It decides nothing: head and target, admission (owner proof, K, disk floor, ports), expiry, the failure teardown and
// the kill lists come from fwcore. Kills only process groups recorded in its own table, and only when the process
// still has the start time recorded at spawn (a recycled pid is never signalled), never by name.
import { spawn, execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, rmSync, statfsSync, writeFileSync, appendFileSync, openSync, closeSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import type { Core } from "../core/index.ts";
import { taskFacts, type TaskFacts, refsKey, gitIn } from "./facts.ts";

export type Phase = "building" | "serving";
export type Entry = {
  id: string; task: string;
  target: { kind: string; ref: string | null; sha: string };
  rp: number; op: number; started: number; deadline: number;
  phase: Phase; pid: number | null; pstart: string | null; tree: string;
};
export type Failed = { id: string; task: string; error: string; at: number };
/** What the route saw of a request (Lean `Fw.Console.Preview.Proof`); Lean maps it to an actor. */
export type Proof = { secret: boolean; cookie: boolean; origin: boolean };
/** The Lean answer of `console.previewTarget`: the head commit found and what a preview of the task shows. */
export type Decision = { head: string | null; headSrc: string | null; kind: string; ref: string | null; sha: string | null };

export type Hooks = {
  /** make the tree at the sha and build the site into it; `track` records each child process group as it starts;
   *  `cancelled` is true once a stop asked for the build to end: the remaining steps must not run */
  build(e: Entry, track: (pid: number | null) => void, cancelled: () => boolean): Promise<void>;
  /** start the server child (rewrite on rp, original on op); resolves with its process group once both listen */
  serve(e: Entry, track: (pid: number | null) => void): Promise<number>;
  removeTree(e: Entry): void;
  killGroup(pid: number): void;
  /** the start time of a process (`ps lstart`), null when it is gone */
  startOf(pid: number): string | null;
  /** the process is still the one recorded at spawn: same start time, own process group, our command line */
  isOurs(pid: number, e: Entry): boolean;
  diskMb(): number;
  now(): number;
};

const here = dirname(fileURLToPath(import.meta.url));
export const SERVE_CHILD = join(here, "serve-child.ts");
const BUILD_TIMEOUT_MS = 180_000;

const startOf = (pid: number): string | null => {
  try { return execFileSync("ps", ["-o", "lstart=", "-p", String(pid)], { stdio: ["ignore", "pipe", "ignore"] }).toString().trim() || null; } catch { return null; }
};

export function defaultHooks(root: string, dir: string): Hooks {
  const base = join(dir, "preview");
  const run = (e: Entry, track: (pid: number | null) => void, cmd: string, args: string[], cwd: string) =>
    new Promise<void>((resolve, reject) => {
      mkdirSync(join(base, e.id), { recursive: true });
      const logPath = join(base, e.id, "build.log");
      const fd = openSync(logPath, "a");
      const c = spawn(cmd, args, { cwd, detached: true, stdio: ["ignore", fd, fd], env: { ...process.env, CI: "1" } });
      closeSync(fd);
      track(c.pid ?? null);
      const timer = setTimeout(() => { try { process.kill(-c.pid!, "SIGTERM"); } catch { /* gone */ } }, BUILD_TIMEOUT_MS);
      c.on("error", (err) => { clearTimeout(timer); reject(err); });
      c.on("exit", (code, sig) => {
        clearTimeout(timer); track(null);
        if (code === 0) return resolve();
        const tail = existsSync(logPath) ? readFileSync(logPath, "utf8").split("\n").filter(Boolean).slice(-6).join(" | ") : "";
        reject(new Error(`${cmd} ${args[0] ?? ""} ${sig ? `killed by ${sig}` : `exited ${code}`}: ${tail.slice(0, 400)}`));
      });
    });
  return {
    async build(e, track, cancelled) {
      const step = (cmd: string, args: string[], cwd: string) => {
        if (cancelled()) throw new Error("cancelled"); // a stop during the build ends the remaining steps
        return run(e, track, cmd, args, cwd);
      };
      // a detached checkout of the sha in the console's own preview area: never the main checkout, never a land slot
      await step("git", ["worktree", "add", "--detach", e.tree, e.target.sha], root);
      await step("pnpm", ["install", "--offline", "--frozen-lockfile", "--filter", "@fw/site...", "--dir", e.tree], e.tree);
      await step(process.execPath, [join(e.tree, "apps/site/scripts/build.mjs"), "--engine", "aot"], join(e.tree, "apps/site"));
    },
    serve(e, track) {
      return new Promise<number>((resolve, reject) => {
        const snap = join(e.tree, "snapshot/site");
        const c = spawn(process.execPath, [SERVE_CHILD, "--serve", `--fw-preview=${e.id}`, "--rewrite", join(e.tree, "apps/site/dist/aot"),
          "--original", snap, "--media", snap, "--rp", String(e.rp), "--op", String(e.op)], { detached: true, stdio: ["ignore", "pipe", "pipe"] });
        track(c.pid ?? null);
        let out = ""; let ready = false;
        const timer = setTimeout(() => { try { process.kill(-c.pid!, "SIGTERM"); } catch { /* gone */ } reject(new Error("server did not start in 10 s")); }, 10_000);
        c.stdout.on("data", (b) => { out += b; if (out.includes('"ready"')) { ready = true; clearTimeout(timer); resolve(c.pid!); } });
        c.stderr.on("data", (b) => { out += b; });
        c.on("exit", (code) => {
          clearTimeout(timer);
          if (ready) track(null); // a crashed server: forget its pid, so no later signal reaches a recycled one
          else reject(new Error(`server exited ${code}: ${out.slice(-300)}`));
        });
        c.unref();
      });
    },
    removeTree(e) {
      try { execFileSync("git", ["worktree", "remove", "--force", e.tree], { cwd: root, stdio: "ignore" }); } catch { /* not registered */ }
      rmSync(join(base, e.id), { recursive: true, force: true });
      try { execFileSync("git", ["worktree", "prune"], { cwd: root, stdio: "ignore" }); } catch { /* ignore */ }
    },
    killGroup(pid) { try { process.kill(-pid, "SIGTERM"); } catch { try { process.kill(pid, "SIGTERM"); } catch { /* gone */ } } },
    startOf,
    isOurs(pid, e) {
      if (e.pstart === null || startOf(pid) !== e.pstart) return false; // not the process recorded at spawn
      try {
        const [pgid = "", ...cmd] = execFileSync("ps", ["-o", "pgid=,command=", "-p", String(pid)], { stdio: ["ignore", "pipe", "ignore"] }).toString().trim().split(/\s+/);
        const line = cmd.join(" ");
        return Number(pgid) === pid && (line.includes(`--fw-preview=${e.id}`) || line.includes(`/${e.id}/tree`) || e.phase === "building");
      } catch { return false; }
    },
    diskMb() { const s = statfsSync(dir); return Math.floor((s.bavail * s.bsize) / (1024 * 1024)); },
    now: () => Date.now(),
  };
}

export type StartReply =
  | { ok: true; id: string; entry: Entry }
  | { ok: false; reason: string; detail?: string };

export class PreviewManager {
  private entries: Entry[] = [];
  private failed: Failed[] = [];
  private cancelled = new Set<string>();
  private chain: Promise<unknown> = Promise.resolve();
  private runs = new Map<string, Promise<void>>();
  private factsCache = new Map<string, { key: string; at: number; facts: TaskFacts }>();
  private seq = 0;
  readonly root: string;
  readonly dir: string;
  private core: Core;
  private hooks: Hooks;

  constructor(root: string, dir: string, core: Core, hooks: Hooks = defaultHooks(root, dir)) {
    this.root = root; this.dir = dir; this.core = core; this.hooks = hooks;
    mkdirSync(join(dir, "preview"), { recursive: true });
  }

  private get tablePath() { return join(this.dir, "preview", "table.json"); }
  private persist() { writeFileSync(this.tablePath, JSON.stringify(this.entries)); }
  private note(rec: Record<string, unknown>) { appendFileSync(join(this.dir, "preview", "log.jsonl"), JSON.stringify({ at: this.hooks.now(), ...rec }) + "\n"); }
  /** the Lean table: only what Lean reads */
  private live() { return this.entries.map(({ id, task, rp, op, started }) => ({ id, task, rp, op, started })); }
  private serial<T>(f: () => Promise<T>): Promise<T> { const p = this.chain.then(f, f); this.chain = p.catch(() => undefined); return p; }

  list() { return { previews: this.entries.map((e) => ({ ...e })), failed: this.failed.slice(-5) }; }
  /** resolves when the build/serve of `id` has ended (tests) */
  settled(id: string): Promise<void> { return this.runs.get(id) ?? Promise.resolve(); }

  facts(task: string): TaskFacts {
    const git = gitIn(this.root);
    const key = refsKey(git);
    const c = this.factsCache.get(task);
    if (c && c.key === key && this.hooks.now() - c.at < 30_000) return c.facts;
    const facts = taskFacts(this.root, task, git);
    this.factsCache.set(task, { key, at: this.hooks.now(), facts });
    return facts;
  }

  /** The head and the target of a task: Lean `console.previewTarget` over the gathered facts. */
  async decision(task: string, f: TaskFacts = this.facts(task)): Promise<Decision> {
    const r = await this.core.ops("console.previewTarget", { main: f.mainSha, facts: f.facts, children: f.children.map((c) => ({ facts: c.facts })) });
    return { head: (r.head as string | null) ?? null, headSrc: (r.headSrc as string | null) ?? null, kind: String(r.kind),
      ref: (r.ref as string | null) ?? null, sha: (r.sha as string | null) ?? null };
  }

  start(task: string, proof: Proof): Promise<StartReply> {
    return this.serial(async () => {
      const t = await this.decision(task);
      const now = this.hooks.now();
      const id = `${task}-${now.toString(36)}${(this.seq++).toString(36)}`;
      const r = await this.core.ops("console.previewAdmit", { ...proof, preview: id, task, now, diskMb: this.hooks.diskMb(), hasTarget: t.kind !== "none", live: this.live() });
      if (r.ok !== true) return { ok: false as const, reason: String(r.reason ?? "refused") };
      const e: Entry = { id, task, target: { kind: t.kind, ref: t.ref, sha: t.sha! }, rp: r.rp as number, op: r.op as number, started: now,
        deadline: r.deadline as number, phase: "building", pid: null, pstart: null, tree: join(this.dir, "preview", id, "tree") };
      this.entries.push(e); this.persist(); this.note({ ev: "start", id, task, target: e.target, rp: e.rp, op: e.op });
      this.runs.set(id, this.go(e));
      return { ok: true as const, id, entry: { ...e } };
    });
  }

  private async go(e: Entry): Promise<void> {
    const track = (pid: number | null) => { e.pid = pid; e.pstart = pid === null ? null : this.hooks.startOf(pid); this.persist(); };
    const cancelled = () => this.cancelled.has(e.id);
    try {
      await this.hooks.build(e, track, cancelled);
      if (cancelled()) { this.hooks.removeTree(e); return; } // a stop came during the build: nothing started, the tree goes
      const pid = await this.hooks.serve(e, track);
      if (cancelled()) { this.hooks.killGroup(pid); this.hooks.removeTree(e); return; }
      e.pid = pid; e.pstart = this.hooks.startOf(pid); e.phase = "serving"; this.persist(); this.note({ ev: "serving", id: e.id, pid });
    } catch (err) {
      if (cancelled()) { this.hooks.removeTree(e); return; } // the build step died because of the stop: clean up what it left
      this.failed.push({ id: e.id, task: e.task, error: (err as Error).message, at: this.hooks.now() });
      this.note({ ev: "failed", id: e.id, error: (err as Error).message });
      await this.serial(async () => { await this.failTeardown(e.id); });
    }
  }

  /** A failed build leaves the table through Lean (`console.previewFail`: `fail`, `own`); no TypeScript-only path. */
  private async failTeardown(id: string) {
    const r = await this.core.ops("console.previewFail", { preview: id, live: this.live() });
    await this.remove(r.kill as string[]);
  }

  /** teardown of recorded entries: kill the group (if it is still ours), remove the tree and the table row */
  private async remove(ids: string[]) {
    for (const id of ids) {
      const e = this.entries.find((x) => x.id === id);
      if (!e) continue; // not in our table: nothing to kill
      this.cancelled.add(id);
      if (e.pid !== null) {
        if (this.hooks.isOurs(e.pid, e)) this.hooks.killGroup(e.pid);
        else this.note({ ev: "pidNotOurs", id, pid: e.pid }); // gone or recycled: never signalled
      }
      this.hooks.removeTree(e);
      this.entries = this.entries.filter((x) => x.id !== id);
      this.note({ ev: "removed", id });
    }
    this.persist();
  }

  stop(id: string, proof: Proof): Promise<{ ok: boolean; reason: string | null }> {
    return this.serial(async () => {
      const r = await this.core.ops("console.previewStop", { ...proof, preview: id, live: this.live() });
      if (r.ok !== true) return { ok: false, reason: String(r.reason) };
      await this.remove(r.kill as string[]);
      return { ok: true, reason: null };
    });
  }

  /** every preview past its deadline is stopped (Lean `console.previewTick`) */
  tick(): Promise<string[]> {
    return this.serial(async () => {
      const r = await this.core.ops("console.previewTick", { now: this.hooks.now(), live: this.live() });
      const kill = r.kill as string[];
      await this.remove(kill);
      return kill;
    });
  }

  /** console start: the previous run's recorded previews are stopped (Lean `console.previewReap`) */
  async reapRecorded(): Promise<string[]> {
    if (!existsSync(this.tablePath)) return [];
    let rec: Entry[] = [];
    try { rec = JSON.parse(readFileSync(this.tablePath, "utf8")); } catch { rec = []; }
    const r = await this.core.ops("console.previewReap", { live: rec.map(({ id, task, rp, op, started }) => ({ id, task, rp, op, started })) });
    for (const id of r.kill as string[]) {
      const e = rec.find((x) => x.id === id)!;
      if (e.pid !== null && this.hooks.isOurs(e.pid, e)) this.hooks.killGroup(e.pid); // a recorded pid with its recorded start time
      this.hooks.removeTree(e);
      this.note({ ev: "reaped", id });
    }
    this.entries = []; this.persist();
    return r.kill as string[];
  }

  /** console shutdown: everything in the table */
  async shutdown(): Promise<void> {
    const r = await this.core.ops("console.previewReap", { live: this.live() });
    await this.remove(r.kill as string[]);
  }
}
