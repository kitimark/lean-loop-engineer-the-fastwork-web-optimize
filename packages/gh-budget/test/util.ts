// Test helpers: a world (state dir + fake gh + simulated clock) and a virtual-time driver for the glue's async loops.
import { chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { spawnSync } from "node:child_process";
import { Worker } from "node:worker_threads";
import { fwcoreBin, fwcoreCall, type Env, type FwCall, type Json } from "../src/core.ts";
import { fakeGh } from "./fake-gh-core.ts";

const here = dirname(fileURLToPath(import.meta.url));
export const repoRoot = join(here, "..", "..", "..");
export const goldenDir = join(repoRoot, "packages", "contracts", "golden", "ci-budget");

export type Call = { t: number; args: string[]; cost: number; refused: boolean; empty: boolean };

export type World = {
  root: string; bin: string; fakeDir: string; stateDir: string; ghPath: string; sim: Sim; env: Env;
  config(c: Record<string, unknown>): void;
  calls(): Call[];
};

/** A simulated clock: sleepers resolve when the driver advances time to them. The fake gh reads the same time. */
export class Sim {
  t: number;
  clockFile: string | null;
  sleepers: { at: number; resolve: () => void }[] = [];
  constructor(t: number, clockFile: string | null) { this.t = t; this.clockFile = clockFile; this.set(t); }
  set(t: number) { this.t = Math.max(this.t, t); if (this.clockFile) writeFileSync(this.clockFile, String(this.t)); }
  now = () => this.t;
  sleepUntil = (at: number) => (at <= this.t ? Promise.resolve() : new Promise<void>((resolve) => this.sleepers.push({ at, resolve })));
  /** Advance to the earliest sleeper (or `cap`), waking everyone due. Returns false when nobody sleeps. */
  advance(cap = Infinity): boolean {
    if (this.sleepers.length === 0) return false;
    const at = Math.min(cap, Math.min(...this.sleepers.map((s) => s.at)));
    this.set(at);
    const due = this.sleepers.filter((s) => s.at <= this.t);
    this.sleepers = this.sleepers.filter((s) => s.at > this.t);
    for (const s of due) s.resolve();
    return true;
  }
}

const tick = () => new Promise<void>((r) => setImmediate(r));

/** Run the promises to completion on virtual time: drain microtasks, jump to the next sleeper, repeat. */
export async function drive<T>(sim: Sim, ps: Promise<T>[], maxSteps = 200_000): Promise<T[]> {
  let done = 0;
  const out: T[] = [];
  ps.forEach((p, i) => p.then((v) => { out[i] = v; done++; }, (e) => { out[i] = e; done = -Infinity; }));
  for (let i = 0; i < maxSteps; i++) {
    await tick();
    if (done === -Infinity) throw out.find((x) => x instanceof Error);
    if (done === ps.length) return out;
    if (!sim.advance()) { await tick(); if (done === ps.length) return out; throw new Error("deadlock: nobody sleeps and the waits are not done"); }
  }
  throw new Error("drive: too many steps");
}

let shared: FwCall | null = null;
/** One persistent fwcore (a private copy of the binary, so a rebuild in the main checkout cannot pull it away), behind
 *  a synchronous bridge: the replays make thousands of decisions. The production glue spawns fwcore once per decision. */
export function fastCore(): FwCall {
  if (shared) return shared;
  const bin = join(mkdtempSync(join(tmpdir(), "ghb-core-")), "fwcore");
  const src = fwcoreBin(repoRoot);
  if (spawnSync("cp", ["-c", src, bin]).status !== 0) copyFileSync(src, bin);
  chmodSync(bin, 0o755);
  process.env.FW_CORE_BIN = bin; // the spawned CLI processes use the same private copy
  const sab = new SharedArrayBuffer(8 + (64 << 20));
  const worker = new Worker(join(here, "core-worker.mjs"), { workerData: { bin, sab } });
  worker.unref();
  const flag = new Int32Array(sab, 0, 2);
  const data = new Uint8Array(sab, 8);
  shared = (req: Json) => {
    Atomics.store(flag, 0, 0);
    worker.postMessage(JSON.stringify({ ...req, id: 0 }));
    Atomics.wait(flag, 0, 0, 60_000);
    if (Atomics.load(flag, 0) !== 1 || flag[1]! < 0) throw new Error("fastCore: no reply");
    const { id: _id, ...rest } = JSON.parse(new TextDecoder().decode(data.slice(0, flag[1]))) as Json;
    if (typeof rest.error === "string") throw new Error(`fwcore ${String(req.op)}: ${rest.error}`);
    return rest;
  };
  return shared;
}

/** `fastGh`: answer `gh` in this process (`fakeGh`, the code the spawned fake runs too) instead of spawning a node
 *  process per call. For replays of thousands of calls; a test of the spawn itself (env, stderr capture) leaves it off. */
export function mkWorld(start: number, opts: { realClock?: boolean; spawnCore?: boolean; fastGh?: boolean } = {}): World {
  const root = mkdtempSync(join(tmpdir(), "ghb-"));
  const bin = join(root, "bin");
  const fakeDir = join(root, "fake");
  const stateDir = join(root, "state");
  mkdirSync(bin); mkdirSync(fakeDir);
  const ghPath = join(bin, "gh");
  // the spawned fake: a short wrapper over the same function the in-process fake calls
  writeFileSync(ghPath, [
    "#!/usr/bin/env node",
    `import { fakeGh } from ${JSON.stringify(pathToFileURL(join(here, "fake-gh-core.ts")).href)};`,
    "const r = fakeGh(process.env.FAKE_GH_DIR, process.argv.slice(2), process.env.FAKE_GH_COST);",
    "process.stdout.write(r.stdout); process.stderr.write(r.stderr); process.exitCode = r.status;", "",
  ].join("\n"));
  chmodSync(ghPath, 0o755);
  process.env.FAKE_GH_DIR = fakeDir;
  delete process.env.FAKE_GH_COST;
  const sim = new Sim(start, opts.realClock ? null : join(fakeDir, "clock"));
  const env: Env = {
    dir: stateDir, core: opts.spawnCore ? fwcoreCall(repoRoot) : fastCore(), gh: ghPath,
    ...(opts.fastGh ? { exec: (args: string[]) => fakeGh(fakeDir, args, process.env.FAKE_GH_COST, Math.floor(Date.now() / 1000)) } : {}),
    now: opts.realClock ? () => Math.floor(Date.now() / 1000) : sim.now,
    sleepUntil: opts.realClock ? (t) => new Promise((r) => setTimeout(r, Math.max(10, t * 1000 - Date.now()))) : sim.sleepUntil,
  };
  const world: World = {
    root, bin, fakeDir, stateDir, ghPath, sim, env,
    config: (c) => writeFileSync(join(fakeDir, "config.json"), JSON.stringify(c)),
    calls: () => (existsSync(join(fakeDir, "calls.jsonl")) ? readFileSync(join(fakeDir, "calls.jsonl"), "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l) as Call) : []),
  };
  return world;
}
