// Task previews: process and git glue around the Lean rules in `Fw.Console.Preview` (via `console.preview*` ops).
// This file holds the table of what the console started and does the I/O: git worktree, build, server child, kill.
// It decides nothing: target, admission (actor, K, disk floor, ports), expiry and the kill lists come from fwcore.
// Kills only the process groups recorded in its own table (verified against `ps` after a restart), never by name.
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
  phase: Phase; pid: number | null; tree: string;
};
export type Failed = { id: string; task: string; error: string; at: number };

export type Hooks = {
  /** make the tree at the sha and build the site into it; `track` records each child process group as it starts */
  build(e: Entry, track: (pid: number | null) => void): Promise<void>;
  /** start the server child (rewrite on rp, original on op); resolves with its process group once both listen */
  serve(e: Entry, track: (pid: number | null) => void): Promise<number>;
  removeTree(e: Entry): void;
  killGroup(pid: number): void;
  isOurs(pid: number, e: Entry): boolean;
  diskMb(): number;
  now(): number;
};

const here = dirname(fileURLToPath(import.meta.url));
export const SERVE_CHILD = join(here, "serve-child.ts");
const BUILD_TIMEOUT_MS = 180_000;

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
    async build(e, track) {
      // a detached checkout of the sha in the console's own preview area: never the main checkout, never a land slot
      await run(e, track, "git", ["worktree", "add", "--detach", e.tree, e.target.sha], root);
      await run(e, track, "pnpm", ["install", "--offline", "--frozen-lockfile", "--filter", "@fw/site...", "--dir", e.tree], e.tree);
      await run(e, track, process.execPath, [join(e.tree, "apps/site/scripts/build.mjs"), "--engine", "aot"], join(e.tree, "apps/site"));
    },
    serve(e, track) {
      return new Promise<number>((resolve, reject) => {
        const snap = join(e.tree, "snapshot/site");
        const c = spawn(process.execPath, [SERVE_CHILD, "--serve", `--fw-preview=${e.id}`, "--rewrite", join(e.tree, "apps/site/dist/aot"),
          "--original", snap, "--media", snap, "--rp", String(e.rp), "--op", String(e.op)], { detached: true, stdio: ["ignore", "pipe", "pipe"] });
        track(c.pid ?? null);
        let out = "";
        const timer = setTimeout(() => { try { process.kill(-c.pid!, "SIGTERM"); } catch { /* gone */ } reject(new Error("server did not start in 10 s")); }, 10_000);
        c.stdout.on("data", (b) => { out += b; if (out.includes('"ready"')) { clearTimeout(timer); resolve(c.pid!); } });
        c.stderr.on("data", (b) => { out += b; });
        c.on("exit", (code) => { clearTimeout(timer); reject(new Error(`server exited ${code}: ${out.slice(-300)}`)); });
        c.unref();
      });
    },
    removeTree(e) {
      try { execFileSync("git", ["worktree", "remove", "--force", e.tree], { cwd: root, stdio: "ignore" }); } catch { /* not registered */ }
      rmSync(join(base, e.id), { recursive: true, force: true });
      try { execFileSync("git", ["worktree", "prune"], { cwd: root, stdio: "ignore" }); } catch { /* ignore */ }
    },
    killGroup(pid) { try { process.kill(-pid, "SIGTERM"); } catch { try { process.kill(pid, "SIGTERM"); } catch { /* gone */ } } },
    isOurs(pid, e) {
      try {
        const cmd = execFileSync("ps", ["-o", "command=", "-p", String(pid)], { stdio: ["ignore", "pipe", "ignore"] }).toString();
        return cmd.includes(`--fw-preview=${e.id}`) || cmd.includes(`/${e.id}/tree`);
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

  async target(task: string, f: TaskFacts = this.facts(task)) {
    const r = await this.core.ops("console.previewTarget", { main: f.mainSha, head: f.head, onMain: f.onMain, cands: f.cands });
    return { kind: String(r.kind), ref: (r.ref as string | null) ?? null, sha: (r.sha as string | null) ?? null };
  }

  start(task: string, actor: string): Promise<StartReply> {
    return this.serial(async () => {
      const t = await this.target(task);
      const now = this.hooks.now();
      const id = `${task}-${now.toString(36)}${(this.seq++).toString(36)}`;
      const r = await this.core.ops("console.previewAdmit", { actor, preview: id, task, now, diskMb: this.hooks.diskMb(), hasTarget: t.kind !== "none", live: this.live() });
      if (r.ok !== true) return { ok: false as const, reason: String(r.reason ?? "refused") };
      const e: Entry = { id, task, target: { kind: t.kind, ref: t.ref, sha: t.sha! }, rp: r.rp as number, op: r.op as number, started: now,
        deadline: r.deadline as number, phase: "building", pid: null, tree: join(this.dir, "preview", id, "tree") };
      this.entries.push(e); this.persist(); this.note({ ev: "start", id, task, target: e.target, rp: e.rp, op: e.op });
      this.runs.set(id, this.go(e));
      return { ok: true as const, id, entry: { ...e } };
    });
  }

  private async go(e: Entry): Promise<void> {
    const track = (pid: number | null) => { e.pid = pid; this.persist(); };
    try {
      await this.hooks.build(e, track);
      if (this.cancelled.has(e.id)) return;
      const pid = await this.hooks.serve(e, track);
      if (this.cancelled.has(e.id)) { this.hooks.killGroup(pid); return; }
      e.pid = pid; e.phase = "serving"; this.persist(); this.note({ ev: "serving", id: e.id, pid });
    } catch (err) {
      if (this.cancelled.has(e.id)) return;
      this.failed.push({ id: e.id, task: e.task, error: (err as Error).message, at: this.hooks.now() });
      this.note({ ev: "failed", id: e.id, error: (err as Error).message });
      await this.serial(async () => { await this.remove([e.id]); });
    }
  }

  /** teardown of recorded entries: kill the group, remove the tree and the table row */
  private async remove(ids: string[]) {
    for (const id of ids) {
      const e = this.entries.find((x) => x.id === id);
      if (!e) continue; // not in our table: nothing to kill
      this.cancelled.add(id);
      if (e.pid !== null) this.hooks.killGroup(e.pid);
      this.hooks.removeTree(e);
      this.entries = this.entries.filter((x) => x.id !== id);
      this.note({ ev: "removed", id });
    }
    this.persist();
  }

  stop(id: string, actor: string): Promise<{ ok: boolean; reason: string | null }> {
    return this.serial(async () => {
      const r = await this.core.ops("console.previewStop", { actor, preview: id, live: this.live() });
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
      if (e.pid !== null && this.hooks.isOurs(e.pid, e)) this.hooks.killGroup(e.pid); // a recorded pid, verified by its command line
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
