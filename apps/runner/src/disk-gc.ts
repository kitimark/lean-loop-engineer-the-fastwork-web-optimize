import { spawnSync } from "node:child_process";
import { appendFileSync, existsSync, lstatSync, mkdirSync, readdirSync, readFileSync, realpathSync, rmSync, statfsSync, unlinkSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { artifactsRoot, gatherCheckouts, gatherOutputs, gatherProcs, type Checkout, type Fact, type Proc as LakeProc } from "./lake-gc.ts";
import { queuedBranches } from "./land-queue.ts";

export const DISK_GC_USAGE =
  "usage: fw disk-gc [--list | --json | --delete] [--class <n|name>[,...]]... [--idle-h N] [--scratch-h N] [--keep-days N] [--tmp-h N] [--pressure]\n" +
  "  classes: 1 lake, 2 landed, 3 idle, 4 scratch, 5 sim, 6 console, 7 usertmp (default: all)\n" +
  "  (no flag) per-class count and bytes   --list  the listed paths   --json  the Lean reply   --delete  delete them";

export const CLASSES = ["lake", "landed", "idle", "scratch", "sim", "console", "usertmp"] as const;
export type Cls = (typeof CLASSES)[number];
export type Lock = "free" | "unknown" | { pid: number; start: string };
export type Cand = {
  cls: Cls; path: string; bytes: number; uid: number | null; tracked: boolean; newest: number; dir: boolean; sym?: boolean;
  owner?: { task: string; run: string } | null;
  lake?: Fact; branch?: string; merged?: boolean | null; dirty?: boolean | null; lock?: Lock | null; device?: { name: string; state: string };
};
export type Roots = { repo: string; lake: string; scratch: string; devices: string; utmp?: string };
export type Device = { udid: string; name: string; state: string };
export type Reply = {
  items: { cls: Cls; num: number; path: string; bytes: number }[]; classes: { cls: Cls; num: number; count: number; bytes: number }[];
  kept: number; rootsOk: { cls: Cls; num: number; ok: boolean }[]; lakeFallback: string | null;
};
export type Call = (req: Record<string, unknown>) => Record<string, unknown>;
export type Mode = "summary" | "list" | "json" | "delete";
export type Args = { mode: Mode; classes: Cls[]; idleH?: number; scratchH?: number; keepDays?: number; tmpH?: number; pressure?: boolean };

export type Io = {
  opens: () => string[] | null;
  procs: () => { pid: number; start: string }[] | null;
  lakeProcs: () => LakeProc[] | null;
  devices: () => Device[] | null;
  deleteDevice: (udid: string) => boolean;
  lakeRoot: (repo: string) => string | null;
};

export class DiskGcUsage extends Error {}

const secs = (ms: number) => Math.floor(ms / 1000);
const isMissing = (e: unknown) => ["ENOENT", "ENOTDIR"].includes((e as NodeJS.ErrnoException).code ?? "");

export function clsOf(s: string): Cls | null {
  const n = Number(s);
  if (Number.isInteger(n) && n >= 1 && n <= CLASSES.length) return CLASSES[n - 1]!;
  return (CLASSES as readonly string[]).includes(s) ? (s as Cls) : null;
}

export function parseArgs(argv: string[]): Args {
  const a: Args = { mode: "summary", classes: [] };
  const num = (i: number) => { if (!/^\d+$/.test(argv[i + 1] ?? "")) throw new DiskGcUsage(`${argv[i]} needs a number\n${DISK_GC_USAGE}`); return Number(argv[i + 1]); };
  for (let i = 0; i < argv.length; i++) {
    const x = argv[i]!;
    if (x === "--list") a.mode = "list";
    else if (x === "--json") a.mode = "json";
    else if (x === "--delete") a.mode = "delete";
    else if (x === "--class" && argv[i + 1]) {
      for (const s of argv[++i]!.split(",")) {
        const c = clsOf(s);
        if (!c) throw new DiskGcUsage(`unknown class ${s}\n${DISK_GC_USAGE}`);
        if (!a.classes.includes(c)) a.classes.push(c);
      }
    } else if (x === "--idle-h") { a.idleH = num(i); i++; }
    else if (x === "--scratch-h") { a.scratchH = num(i); i++; }
    else if (x === "--keep-days") { a.keepDays = num(i); i++; }
    else if (x === "--tmp-h") { a.tmpH = num(i); i++; }
    else if (x === "--pressure") a.pressure = true;
    else throw new DiskGcUsage(`unknown or incomplete argument: ${x}\n${DISK_GC_USAGE}`);
  }
  if (a.classes.length === 0) a.classes = [...CLASSES];
  return a;
}

function run(cmd: string, args: string[], cwd?: string): { status: number | null; out: string } {
  const r = spawnSync(cmd, args, { cwd, encoding: "utf8", maxBuffer: 1 << 28, env: { ...process.env, LC_ALL: "C" } });
  return { status: r.status, out: r.stdout ?? "" };
}

const git = (cwd: string, args: string[]) => run("git", ["--no-optional-locks", ...args], cwd);

export function walk(p: string): { bytes: number; newest: number } {
  const seen = new Set<string>();
  let bytes = 0, newest = 0;
  const stack = [p];
  while (stack.length) {
    const q = stack.pop()!;
    let s;
    try { s = lstatSync(q); } catch { continue; }
    newest = Math.max(newest, secs(s.mtimeMs));
    const id = `${s.dev}:${s.ino}`;
    if (!seen.has(id)) { seen.add(id); bytes += s.blocks * 512; }
    if (s.isDirectory()) { try { for (const n of readdirSync(q)) stack.push(join(q, n)); } catch {} }
  }
  return { bytes, newest };
}

export function duBytes(p: string): number {
  const r = run("du", ["-sk", p]);
  const k = Number(/^(\d+)/.exec(r.out)?.[1] ?? "0");
  return k * 1024;
}

const ownerOf = (p: string): number | null => { try { return lstatSync(p).uid; } catch { return null; } };
export const isLink = (p: string): boolean | undefined => { try { return lstatSync(p).isSymbolicLink(); } catch { return undefined; } };
const isDir = (p: string): boolean => { try { return lstatSync(p).isDirectory(); } catch { return false; } };
const listDir = (p: string): string[] => { try { return readdirSync(p).sort(); } catch { return []; } };

export function gatherOpens(): string[] | null {
  const r = run("lsof", ["-n", "-w", "-Fn"]);
  if (!r.out) return null;
  return r.out.split("\n").filter((l) => l.startsWith("n/")).map((l) => l.slice(1));
}

export function gatherStarts(): { pid: number; start: string }[] | null {
  const r = run("ps", ["-axo", "pid=,lstart="]);
  if (r.status !== 0) return null;
  const out: { pid: number; start: string }[] = [];
  for (const l of r.out.split("\n")) {
    const m = /^\s*(\d+)\s+(.+?)\s*$/.exec(l);
    if (m) out.push({ pid: Number(m[1]), start: m[2]! });
  }
  return out;
}

export function gatherDevices(): Device[] | null {
  const r = run("xcrun", ["simctl", "list", "devices", "-j"]);
  if (r.status !== 0) return null;
  try {
    const j = JSON.parse(r.out) as { devices: Record<string, { udid: string; name: string; state: string }[]> };
    return Object.values(j.devices).flat().map((d) => ({ udid: d.udid, name: d.name, state: d.state }));
  } catch { return null; }
}

export const realIo: Io = {
  opens: gatherOpens,
  procs: gatherStarts,
  lakeProcs: gatherProcs,
  devices: gatherDevices,
  deleteDevice: (udid) => run("xcrun", ["simctl", "delete", udid]).status === 0,
  lakeRoot: (repo) => { try { return realpathSync(artifactsRoot(repo)); } catch { return null; } },
};

export function defaultRoots(repo: string, io: Io, env: Record<string, string | undefined> = process.env): Roots {
  const tmp = (() => { try { return realpathSync("/tmp"); } catch { return "/tmp"; } })();
  const uid = process.getuid?.() ?? 0;
  return {
    repo,
    lake: io.lakeRoot(repo) ?? "",
    scratch: env.FW_DISK_GC_SCRATCH ?? join(tmp, `claude-${uid}`, repo.replace(/[^A-Za-z0-9-]/g, "-")),
    devices: env.FW_DISK_GC_DEVICES ?? join(homedir(), "Library", "Developer", "CoreSimulator", "Devices"),
    utmp: env.FW_DISK_GC_UTMP ?? (() => { try { return realpathSync(tmpdir()); } catch { return ""; } })(),
  };
}

type Wt = { path: string; branch: string; lock: Lock };

export function worktrees(repo: string): Wt[] | null {
  const r = git(repo, ["worktree", "list", "--porcelain"]);
  if (r.status !== 0) return null;
  const out: Wt[] = [];
  for (const block of r.out.split("\n\n")) {
    const lines = block.split("\n");
    const path = lines.find((l) => l.startsWith("worktree "))?.slice(9);
    if (!path) continue;
    const branch = lines.find((l) => l.startsWith("branch refs/heads/"))?.slice(18) ?? "";
    const locked = lines.find((l) => l === "locked" || l.startsWith("locked "));
    let lock: Lock = "free";
    if (locked !== undefined) {
      const m = /\(pid (\d+) start ([^)]+)\)/.exec(locked);
      lock = m ? { pid: Number(m[1]), start: m[2]! } : "unknown";
    }
    out.push({ path, branch, lock });
  }
  return out;
}

export function landedOf(repo: string, branch: string): boolean | null {
  const tip = git(repo, ["rev-parse", "--verify", "-q", `refs/heads/${branch}`]).out.trim();
  const log = git(repo, ["reflog", "show", "--format=%H", `refs/heads/${branch}`]);
  const created = log.out.trim().split("\n").filter(Boolean).at(-1);
  if (!tip || log.status !== 0 || !created) return null;
  if (tip === created) return false;
  const a = git(repo, ["merge-base", "--is-ancestor", tip, "refs/heads/main"]).status;
  return a === 0 ? true : a === 1 ? false : null;
}

export function wtState(wt: string): { dirty: boolean | null; newest: number } {
  const st = git(wt, ["status", "--porcelain", "-z", "--untracked-files=normal"]);
  const head = Number(git(wt, ["log", "-1", "--format=%ct"]).out.trim() || "0");
  if (st.status !== 0) return { dirty: null, newest: Number.MAX_SAFE_INTEGER };
  const files = st.out.split("\0").filter(Boolean).filter((e) => /^.. /.test(e)).map((e) => e.slice(3));
  let newest = head;
  for (const f of files) { try { newest = Math.max(newest, secs(lstatSync(join(wt, f)).mtimeMs)); } catch {} }
  return { dirty: files.length > 0, newest };
}

function trackedUnder(top: string, rel: string): Set<string> | null {
  const r = git(top, ["ls-files", "-z", "--", rel]);
  return r.status === 0 ? new Set(r.out.split("\0").filter(Boolean)) : null;
}

const trackedIn = (set: Set<string> | null, rel: string): boolean =>
  set === null || [...set].some((f) => f === rel || f.startsWith(`${rel}/`));

export function gatherCited(repo: string): string[] | null {
  const r = git(repo, ["grep", "-h", "-o", "-E", "scratchpad/[A-Za-z0-9._-]+", "refs/heads/main"]);
  if (r.status !== 0 && r.status !== 1) return null;
  const out = new Set<string>();
  for (const l of r.out.split("\n").filter(Boolean)) {
    const m = l.slice(l.indexOf("scratchpad/"));
    out.add(m); out.add(m.replace(/\.+$/, ""));
  }
  return [...out];
}

export function gatherNamed(repo: string): string[] | null {
  const r = git(repo, ["grep", "-h", "-o", "-E", "fw-[A-Za-z0-9._-]+", "refs/heads/main", "--", ".github", "packages", "apps", "scripts"]);
  if (r.status !== 0 && r.status !== 1) return null;
  return [...new Set(r.out.split("\n").filter(Boolean).map((l) => l.slice(l.indexOf("fw-"))))];
}

export type EventFacts = { liveAgents: string[]; landedTasks: string[]; finishedRuns: string[]; liveRuns: string[]; landedRuns: string[] };

export function landSubjects(repo: string): string[] | null {
  const r = git(repo, ["log", "refs/heads/main", "--format=%s"]);
  if (r.status !== 0) return null;
  return r.out.split("\n").filter((l) => l.startsWith("land "));
}

export function gatherEventFacts(repo: string, call: Call): EventFacts | null {
  let text: string;
  try { text = readFileSync(join(repo, ".fw-console", "events.jsonl"), "utf8"); } catch { return null; }
  const events: Record<string, unknown>[] = [];
  for (const l of text.split("\n")) {
    if (!l.includes('"type":"agent.') && !l.includes('"type":"task.done"')) continue;
    let e: { seq?: unknown; type?: unknown; key?: unknown; agent?: unknown; name?: unknown; task?: unknown };
    try { e = JSON.parse(l); } catch { continue; }
    if (typeof e.seq !== "number" || typeof e.type !== "string") return null;
    const o: Record<string, unknown> = { seq: e.seq, type: e.type };
    for (const k of ["key", "agent", "name", "task"] as const) if (typeof e[k] === "string") o[k] = e[k];
    events.push(o);
  }
  try {
    const r = call({ op: "ops.diskGcFacts", events });
    const strs = (v: unknown): string[] | null => Array.isArray(v) && v.every((x) => typeof x === "string") ? (v as string[]) : null;
    const liveAgents = strs(r.liveAgents), landedTasks = strs(r.landedTasks), finishedRuns = strs(r.finishedRuns);
    const liveRuns = strs(r.liveRuns), landedRuns = strs(r.landedRuns);
    return liveAgents && landedTasks && finishedRuns && liveRuns && landedRuns
      ? { liveAgents, landedTasks, finishedRuns, liveRuns, landedRuns } : null;
  } catch { return null; }
}

export function ownerMarker(dir: string): { task: string; run: string } | null {
  try {
    const j = JSON.parse(readFileSync(join(dir, ".fw-owner"), "utf8").slice(0, 2000)) as { task?: unknown; run?: unknown };
    return typeof j.task === "string" && typeof j.run === "string" ? { task: j.task, run: j.run } : null;
  } catch { return null; }
}

export type Facts = { req: Record<string, unknown>; cands: Cand[]; lazy: Map<string, () => number>; outputs: () => string[] | null };

export function gather(roots: Roots, a: Args, io: Io, now: number, uid: number, call: Call): Facts {
  const on = (c: Cls) => a.classes.includes(c);
  const cands: Cand[] = [];
  const lazy = new Map<string, () => number>();
  const req: Record<string, unknown> = { roots, classes: a.classes, uid, now };
  if (a.idleH !== undefined) req.idleH = a.idleH;
  if (a.scratchH !== undefined) req.scratchH = a.scratchH;
  if (a.keepDays !== undefined) req.keepDays = a.keepDays;
  if (a.tmpH !== undefined) req.tmpH = a.tmpH;
  if (a.pressure) req.pressure = true;
  const base = (cls: Cls, path: string, extra: Partial<Cand> = {}): Cand =>
    ({ cls, path, bytes: 0, uid: ownerOf(path), tracked: false, newest: 0, dir: isDir(path), ...extra });
  let outputs: () => string[] | null = () => null;

  if (on("lake") && roots.lake) {
    const checkouts: Checkout[] | null = gatherCheckouts(roots.repo);
    const procs = io.lakeProcs();
    req.lake = { ...(checkouts !== null ? { checkouts } : {}), ...(procs !== null ? { procs } : {}) };
    outputs = () => gatherOutputs(dirname(roots.lake));
    for (const name of listDir(roots.lake)) {
      const path = join(roots.lake, name);
      try {
        const s = lstatSync(path);
        cands.push({ cls: "lake", path, bytes: s.blocks * 512, uid: s.uid, tracked: false, newest: secs(s.mtimeMs), dir: s.isDirectory(),
          lake: { name, file: s.isFile(), links: s.nlink, mtime: secs(s.mtimeMs), ctime: secs(s.ctimeMs), size: s.size } });
      } catch {}
    }
  }

  if (on("landed") || on("idle")) {
    const wtRoot = join(roots.repo, ".claude", "worktrees");
    const wts = (worktrees(roots.repo) ?? []).filter((w) => w.path.startsWith(`${wtRoot}/`) && isDir(w.path));
    const tracked = trackedUnder(roots.repo, ".claude/worktrees");
    for (const w of wts) {
      const merged = w.branch ? landedOf(roots.repo, w.branch) : null;
      const st = wtState(w.path);
      const facts = { branch: w.branch, merged, dirty: st.dirty, lock: w.lock };
      if (on("landed")) {
        cands.push(base("landed", w.path, { ...facts, tracked: trackedIn(tracked, w.path.slice(roots.repo.length + 1)) }));
        lazy.set(`landed ${w.path}`, () => duBytes(w.path));
      }
      if (on("idle") && merged === false) {
        const subs = ["node_modules", "lean/.lake", ...["apps", "packages"].flatMap((g) => listDir(join(w.path, g)).map((x) => `${g}/${x}/node_modules`))];
        const wtTracked = trackedUnder(w.path, ".");
        for (const rel of subs) {
          const p = join(w.path, rel);
          if (!isDir(p)) continue;
          cands.push(base("idle", p, { ...facts, newest: st.newest, tracked: trackedIn(wtTracked, rel) }));
          lazy.set(`idle ${p}`, () => duBytes(p));
        }
      }
    }
    req.queued = (() => { try { return queuedBranches(join(roots.repo, ".fw-console")); } catch { return null; } })();
    if (on("landed")) {
      req.landSubjects = landSubjects(roots.repo);
      const evl = gatherEventFacts(roots.repo, call);
      req.liveRuns = evl ? evl.liveRuns : null;
      req.landedRuns = evl ? evl.landedRuns : null;
    }
  }

  if (on("scratch")) {
    req.cited = gatherCited(roots.repo);
    const ev = gatherEventFacts(roots.repo, call);
    if (ev) { req.liveAgents = ev.liveAgents; req.landedTasks = ev.landedTasks; req.finishedRuns = ev.finishedRuns; }
    for (const s of listDir(roots.scratch)) {
      const pad = join(roots.scratch, s, "scratchpad");
      for (const d of listDir(pad)) {
        const p = join(pad, d);
        const dir = isDir(p);
        const w = dir ? walk(p) : { bytes: 0, newest: 0 };
        cands.push(base("scratch", p, { bytes: w.bytes, newest: w.newest, ...(dir ? { owner: ownerMarker(p) } : {}) }));
      }
    }
  }

  if (on("sim")) {
    req.named = gatherNamed(roots.repo);
    req.simLock = existsSync(join(roots.repo, ".local", "locks", "sim"));
    for (const d of io.devices() ?? []) {
      if (!d.name.startsWith("fw-")) continue;
      const p = join(roots.devices, d.udid);
      cands.push(base("sim", p, { device: { name: d.name, state: d.state } }));
      lazy.set(`sim ${p}`, () => duBytes(p));
    }
  }

  if (on("console")) {
    const croot = join(roots.repo, ".fw-console");
    const tracked = trackedUnder(roots.repo, ".fw-console");
    for (const sub of ["tmp", "land-logs"]) {
      for (const n of listDir(join(croot, sub))) {
        const p = join(croot, sub, n);
        const w = walk(p);
        cands.push(base("console", p, { bytes: w.bytes, newest: w.newest, sym: isLink(p), tracked: trackedIn(tracked, `.fw-console/${sub}/${n}`) }));
      }
    }
  }

  if (on("usertmp") && roots.utmp) {
    for (const n of listDir(roots.utmp)) {
      const p = join(roots.utmp, n);
      const w = walk(p);
      cands.push(base("usertmp", p, { bytes: w.bytes, newest: w.newest, sym: isLink(p) }));
    }
  }

  const prefixes = [roots.lake, roots.repo, roots.scratch, roots.devices, roots.utmp ?? ""].filter(Boolean);
  const opens = io.opens();
  req.opens = opens === null ? null : [...new Set(opens.filter((o) => prefixes.some((r) => o === r || o.startsWith(`${r}/`))))];
  req.procs = io.procs();
  for (const k of ["opens", "procs", "queued", "cited", "named"]) if (req[k] === null) delete req[k];
  return { req, cands, lazy, outputs };
}

const candJson = (c: Cand): Record<string, unknown> => {
  const j: Record<string, unknown> = { ...c };
  for (const k of Object.keys(j)) if (j[k] === null || j[k] === undefined) delete j[k];
  return j;
};

export function decide(call: Call, f: Facts): Reply {
  const ask = () => call({ op: "ops.diskGc", ...f.req, cands: f.cands.map(candJson) }) as unknown as Reply;
  let r = ask();
  if (r.lakeFallback === "noOutputsMap") {
    const outputs = f.outputs();
    if (outputs !== null) { f.req.lake = { ...(f.req.lake as object), outputs }; r = ask(); }
  }
  const sizes = r.items.flatMap((i) => { const m = f.lazy.get(`${i.cls} ${i.path}`); return m ? [[`${i.cls} ${i.path}`, m()] as const] : []; });
  if (sizes.length === 0) return r;
  const by = new Map(sizes);
  for (const c of f.cands) { const b = by.get(`${c.cls} ${c.path}`); if (b !== undefined) c.bytes = b; }
  return ask();
}

const gib = (n: number) => (n / 2 ** 30).toFixed(2);

export function freeBytes(p: string): number | null {
  try { const s = statfsSync(p); return Number(s.bavail) * Number(s.bsize); } catch { return null; }
}

export function deleteItem(item: { cls: Cls; path: string }, repo: string, uid: number, io: Io, lock?: Lock | null): string | null {
  let real: string;
  try { real = realpathSync(item.path); } catch (e) { return isMissing(e) ? null : (e as Error).message; }
  if (real !== item.path) return "path resolves elsewhere (symlink)";
  if (ownerOf(item.path) !== uid) return "owner changed";
  if (item.cls === "landed") {
    if (lock && lock !== "free" && lock !== "unknown") git(repo, ["worktree", "unlock", item.path]);
    const r = spawnSync("git", ["worktree", "remove", item.path], { cwd: repo, encoding: "utf8" });
    return r.status === 0 ? null : (r.stderr ?? "").trim() || `git worktree remove exited ${r.status}`;
  }
  if (item.cls === "sim") {
    const udid = item.path.slice(item.path.lastIndexOf("/") + 1);
    return io.deleteDevice(udid) ? null : "simctl delete failed";
  }
  try {
    if (lstatSync(item.path).isDirectory()) rmSync(item.path, { recursive: true, force: false });
    else unlinkSync(item.path);
    return null;
  } catch (e) { return isMissing(e) ? null : (e as Error).message; }
}

export type RunResult = { reply: Reply; lines: string[]; ok: boolean; freeBefore: number | null; freeAfter: number | null; deleted: number; failed: number; freed: { cls: Cls; num: number; bytes: number }[] };

export type RunOpts = { repo: string; args: Args; call: Call; io?: Io; roots?: Roots; now?: number; uid?: number; env?: Record<string, string | undefined> };

export function diskGc(o: RunOpts): RunResult {
  const io = o.io ?? realIo, env = o.env ?? process.env;
  const uid = o.uid ?? process.getuid?.() ?? 0;
  const roots = o.roots ?? defaultRoots(o.repo, io, env);
  const now = o.now ?? secs(Date.now());
  const freeBefore = freeBytes(roots.repo);
  const f = gather(roots, o.args, io, now, uid, o.call);
  const reply = decide(o.call, f);
  const lines: string[] = [];
  let deleted = 0, failed = 0;
  const freed = new Map<Cls, number>();
  if (o.args.mode === "json") lines.push(JSON.stringify(reply));
  else if (o.args.mode === "list") for (const i of reply.items) lines.push(`${i.num} ${i.cls} ${i.bytes} ${i.path}`);
  else {
    for (const r of reply.rootsOk) if (o.args.classes.includes(r.cls) && !r.ok) lines.push(`disk-gc: class ${r.num} ${r.cls}: root refused by Lean, nothing listed`);
    for (const c of reply.classes) lines.push(`disk-gc: class ${c.num} ${c.cls}: ${c.count} item(s), ${gib(c.bytes)} GiB`);
    if (reply.lakeFallback) lines.push(`disk-gc: class 1 lake decided by the age floor (fallback ${reply.lakeFallback})`);
  }
  if (o.args.mode === "delete" && reply.items.length > 0) {
    const ok = (o.call({ op: "ops.diskGcPath", roots, items: reply.items.map((i) => ({ cls: i.cls, path: i.path })) }).ok ?? []) as boolean[];
    const locks = new Map(f.cands.map((c) => [`${c.cls} ${c.path}`, c.lock]));
    for (const [k, i] of reply.items.entries()) {
      const err = ok[k] === true ? deleteItem(i, roots.repo, uid, io, locks.get(`${i.cls} ${i.path}`)) : "path refused by ops.diskGcPath";
      if (err === null) { deleted++; freed.set(i.cls, (freed.get(i.cls) ?? 0) + i.bytes); }
      else { failed++; lines.push(`disk-gc: kept ${i.path}: ${err}`); }
    }
  }
  const freeAfter = o.args.mode === "delete" ? freeBytes(roots.repo) : freeBefore;
  const freedBy = [...freed].map(([cls, b]) => ({ cls, num: CLASSES.indexOf(cls) + 1, bytes: b }));
  if (o.args.mode === "delete") for (const f of freedBy) lines.push(`disk-gc: freed class ${f.num} ${f.cls}: ${gib(f.bytes)} GiB`);
  const free = (n: number | null) => (n === null ? "?" : gib(n));
  if (o.args.mode === "delete") lines.push(`disk-gc: deleted ${deleted}, failed ${failed}; free ${free(freeBefore)} GiB before, ${free(freeAfter)} GiB after`);
  else if (o.args.mode === "summary") lines.push(`disk-gc: free ${free(freeBefore)} GiB${reply.items.length ? "; to delete: pnpm -s fw disk-gc --delete" : ""}`);
  const res = { reply, lines, ok: failed === 0, freeBefore, freeAfter, deleted, failed, freed: freedBy };
  if (o.args.mode === "delete") record(roots.repo, o.args, res, now);
  return res;
}

export function record(repo: string, a: Args, r: RunResult, now: number): void {
  try {
    const p = join(repo, ".fw-console", "disk-gc.jsonl");
    mkdirSync(dirname(p), { recursive: true });
    appendFileSync(p, JSON.stringify({ type: "diskgc.run", at: now, mode: a.mode, classes: r.reply.classes, deleted: r.deleted,
      failed: r.failed, freed: r.freed, freeBefore: r.freeBefore, freeAfter: r.freeAfter }) + "\n");
  } catch {}
}

export function mainOf(cwd: string): string {
  const r = git(cwd, ["rev-parse", "--path-format=absolute", "--git-common-dir"]);
  return realpathSync(dirname(r.out.trim()));
}

export function diskGcCli(argv: string[], cwd: string, call: Call, print: (s: string) => void = console.log): number {
  const r = diskGc({ repo: mainOf(cwd), args: parseArgs(argv), call });
  for (const l of r.lines) print(l);
  return r.ok ? 0 : 1;
}

export function diskGcTick(repo: string, classes: Cls[], call: Call, env: Record<string, string | undefined> = process.env,
  opts: Partial<RunOpts> & { pressure?: boolean } = {}): string[] {
  if (env.FW_DISK_GC === "0") return [];
  try {
    const { pressure, ...rest } = opts;
    const r = diskGc({ ...rest, repo, args: { mode: "delete", classes, ...(pressure ? { pressure: true } : {}) }, call, env });
    const by = r.reply.classes.filter((c) => c.count > 0).map((c) => `${c.num} ${c.cls} ${c.count} (${gib(c.bytes)} GiB)`).join(", ");
    return [`DISKGC classes ${classes.map((c) => CLASSES.indexOf(c) + 1).join(",")}: ${by || "nothing to delete"}; deleted ${r.deleted}, failed ${r.failed}${r.freed.length ? `; freed ${r.freed.map((f) => `${f.num} ${gib(f.bytes)} GiB`).join(", ")}` : ""}`];
  } catch (e) {
    return [`DISKGC error ${e instanceof Error ? e.message.split("\n")[0] : String(e)}`];
  }
}
