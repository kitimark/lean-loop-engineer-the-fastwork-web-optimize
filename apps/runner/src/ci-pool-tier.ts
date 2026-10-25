import { spawn, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { appendFileSync, copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";
import { jsonArg } from "./ci-pool.ts";
import { MAC_WORKFLOWS } from "./ci-telemetry-mac.ts";
import { parseFlags, UsageError } from "./lib.ts";
import { fwcoreCall, type CmCellDone, type FwCall, type Gh, type RouteDeps } from "./run.ts";

const USAGE = [
  "usage: fw ci pool tier --state <json|@file> --reqs <json|@file> [--over <json|@file>] [--json]",
  "       fw ci pool tier-consts [--over <json|@file>]",
  "       fw ci pool dispatch --branch ci/<name> --state <json|@file> --reqs <json|@file> [--over <json|@file>] [--go]",
].join("\n");

const BRANCH = /^ci\/[A-Za-z0-9._/-]+$/;

export function tierRequest(argv: string[], cwd: string): Record<string, unknown> {
  const [verb, ...rest] = argv;
  const { pos, flags } = parseFlags(rest.filter((a) => a !== "--json" && a !== "--go"));
  if (pos.length) throw new UsageError(`unexpected argument ${pos[0]}\n${USAGE}`);
  const base: Record<string, unknown> = flags.over ? { over: jsonArg(flags.over, cwd, "over") } : {};
  if (verb === "tier-consts") return { op: "ci.poolTierConsts", ...base };
  if (verb !== "tier" && verb !== "dispatch") throw new UsageError(USAGE);
  if (!flags.state || !flags.reqs) throw new UsageError(`${verb} needs --state and --reqs\n${USAGE}`);
  return { op: "ci.poolTier", ...base, state: jsonArg(flags.state, cwd, "state"), reqs: jsonArg(flags.reqs, cwd, "reqs") };
}

export type TierFacts = { cmUsed: number; cmBusy: number; ccSpent: number; ccStorage: number };

export function fillFacts(state: Record<string, unknown>, facts: TierFacts): Record<string, unknown> {
  const out = { ...state };
  for (const [k, v] of Object.entries(facts)) if (out[k] === undefined) out[k] = v;
  return out;
}

type Target = { via: string; os: string; cls: string; engine: string; timeoutMin: number; credits: number };
type Row = { lane: string; rep: number; attempt: number; via: string | null; decision: string; outcome?: string; target?: Target };

export type Step = { lane: string; rep: number; via: string | null; decision: string; cmd: string[] | null; note: string };

export function dispatchPlan(log: Row[], branch: string): Step[] {
  return log.map((r) => {
    const head = { lane: r.lane, rep: r.rep, via: r.via, decision: r.decision };
    if (r.decision === "codemagic") return { ...head, cmd: ["scripts/codemagic.mjs", "trigger", "--pool", "--branch", branch], note: `codemagic ${r.target!.cls}, cap ${r.target!.timeoutMin} min` };
    if (r.decision === "run" && r.via === "circleci") return { ...head, cmd: ["scripts/circleci.mjs", "trigger", "--lane", r.lane, "--branch", branch], note: `circleci ${r.target!.cls}, timeout ${r.target!.timeoutMin} min, ${r.target!.credits} credits` };
    if (r.decision === "run") return { ...head, cmd: null, note: `${r.via} ${r.target!.os} ${r.target!.cls}: the push of ${branch} runs it` };
    return { ...head, cmd: null, note: r.outcome ? `${r.decision} ${r.outcome}` : r.decision };
  });
}

export const stepLine = (s: Step): string => `${s.lane} rep ${s.rep}: ${s.note}${s.cmd ? ` -> node ${s.cmd.join(" ")}` : ""}`;

export async function readFacts(root: string): Promise<TierFacts> {
  const r = spawnSync(process.execPath, [join(root, "scripts/codemagic.mjs"), "facts"], { cwd: root, encoding: "utf8" });
  if (r.status !== 0) throw new Error(`codemagic facts failed: ${r.stderr.trim()}`);
  const cm = JSON.parse(r.stdout.trim().split("\n").pop()!) as { used: number; busy: number };
  const cc = (await import(pathToFileURL(join(root, "scripts/circleci.mjs")).href)) as {
    creditsSoFar: (ctx: { ledgerPath: string }) => number; storageSoFar: (ctx: { ledgerPath: string }) => number };
  const ctx = { ledgerPath: join(root, ".local", "circleci-ledger.json") };
  return { cmUsed: cm.used, cmBusy: cm.busy, ccSpent: cc.creditsSoFar(ctx), ccStorage: cc.storageSoFar(ctx) };
}

export type Io = { call: FwCall; facts: () => Promise<TierFacts>; run: (cmd: string[]) => number; log: (l: string) => void };

export async function tierMain(argv: string[], cwd: string, io: Io): Promise<number> {
  const req = tierRequest(argv, cwd);
  if (req.op === "ci.poolTierConsts") { io.log(JSON.stringify(io.call(req), null, 2)); return 0; }
  const dispatch = argv[0] === "dispatch";
  const branch = parseFlags(argv.slice(1).filter((a) => a !== "--json" && a !== "--go")).flags.branch;
  if (dispatch && !BRANCH.test(branch ?? "")) throw new UsageError(`dispatch needs --branch ci/<name>\n${USAGE}`);
  if (dispatch) req.state = fillFacts(req.state as Record<string, unknown>, await io.facts());
  const reply = io.call(req);
  if (argv.includes("--json")) { io.log(JSON.stringify(reply, null, 2)); if (!dispatch) return 0; }
  const plan = dispatchPlan(reply.log as Row[], branch ?? "ci/<branch>");
  for (const s of plan) io.log(stepLine(s));
  io.log(`counts ${JSON.stringify(reply.counts)}; inflight ${reply.inflight} of ${reply.macCap}; state ${JSON.stringify(reply.state)}`);
  if (!dispatch || !argv.includes("--go")) return 0;
  let code = 0;
  for (const s of plan.filter((p) => p.cmd)) {
    const c = io.run(s.cmd!);
    io.log(`${s.via} ${s.lane} rep ${s.rep}: exit ${c}${c === 5 ? " (the provider's stop rule refused)" : ""}`);
    if (c !== 0 && code === 0) code = c;
  }
  return code;
}

export async function tierCli(argv: string[], cwd: string): Promise<number> {
  const root = new URL("../../..", import.meta.url).pathname;
  return tierMain(argv, cwd, {
    call: fwcoreCall(cwd),
    facts: () => readFacts(root),
    run: (cmd) => spawnSync(process.execPath, [join(root, cmd[0]!), ...cmd.slice(1)], { cwd: root, stdio: "inherit" }).status ?? 1,
    log: (l) => console.log(l),
  });
}

// ---- dispatch time: `fw run` routes the cells of a webkit-sim count job through the Lean pool route (task pool-dispatch-poller) ----
// The decision is Lean's (`ci.poolTier`, Fw.Ci.PoolTier: GitHub first, Codemagic when GitHub has no slot, stop at 400 of 500
// minutes, never the rewrite arm). Everything below reads facts, maps the reply and moves files. TS stand-ins: `lanePool` (the
// lane a target is routed under; `rewrite_never_codemagic` is the Lean side) and the local class merge (the `merge` job of webkit-sim.yml).

/** The pool lane of a count target. The rewrite arm needs the site build of the GitHub site job, so its lane is not in the Codemagic allow-list. */
export const lanePool = (target: string): string => (target === "original" ? "webkit-sim" : "webkit-sim-rewrite");

export type Busy = { ghMacBusy: number; ghTotalBusy: number };

/** GitHub macOS jobs that hold or wait for a slot: the in-progress runs of the macOS workflows, their jobs `in_progress` or `queued`. */
export async function readGhBusy(gh: Gh, macOf: (wf: string, names: string[]) => boolean[]): Promise<Busy> {
  const runs = JSON.parse(await gh(["run", "list", "--status", "in_progress", "--limit", "30", "--json", "databaseId,workflowName"])) as { databaseId: number; workflowName: string }[];
  let mac = 0, total = 0;
  for (const r of runs.filter((x) => MAC_WORKFLOWS.includes(x.workflowName))) {
    const all = (JSON.parse(await gh(["run", "view", String(r.databaseId), "--json", "jobs"])) as { jobs: { name: string; status: string }[] }).jobs;
    const jobs = all.filter((j) => j.status === "in_progress" || j.status === "queued");
    total += jobs.length;
    mac += macOf(r.workflowName, jobs.map((j) => j.name)).filter(Boolean).length;
  }
  return { ghMacBusy: mac, ghTotalBusy: total };
}

export type CmFacts = { cmUsed: number; cmBusy: number };
export type CellRoute = { total: number; codemagic: number; github: number; rows: { rep: number; decision: string; via: string | null }[]; counts: Record<string, number>; busy: Busy; facts: CmFacts };

/** Ask Lean where each of `vms` cells of one count job goes. CircleCI is closed (its allow-list is emptied); a cell that is not Codemagic stays on GitHub, whose queue holds it. */
export function routeCells(call: FwCall, a: { sha: string; key: string; target: string; vms: number; busy: Busy; facts: CmFacts }): CellRoute {
  const reqs = Array.from({ length: a.vms }, (_, rep) => ({ sha: a.sha, lane: lanePool(a.target), cfg: a.key, rep, engine: "iosSimSafari", image: "xcode-27", capMin: 40 }));
  const reply = call({ op: "ci.poolTier", over: { circleMacAllow: [], circleCaps: {} }, state: { ...a.busy, ...a.facts, ccSpent: 0, ccStorage: 0 }, reqs });
  const rows = (reply.log as { rep: number; decision: string; via: string | null }[]).map(({ rep, decision, via }) => ({ rep, decision, via }));
  const codemagic = (reply.counts as Record<string, number>).codemagic ?? 0;
  return { total: a.vms, codemagic, github: a.vms - codemagic, rows, counts: reply.counts as Record<string, number>, busy: a.busy, facts: a.facts };
}

/** The route events: one append-only line per decision (`<console dir>/ci-route.jsonl`, the runner's own log like timings.jsonl). */
export type RouteEvent =
  | { kind: "ci.route"; at: number; sha7: string; lane: string; cells: number; codemagic: number; github: number; rows: CellRoute["rows"]; busy: Busy; facts: CmFacts }
  | { kind: "ci.route.skip"; at: number; why: string }
  | { kind: "ci.codemagic.build"; at: number; build: string; vm: string; status: string; startedAt: number | null; finishedAt: number | null; createdAt: number | null; minutes: number | null }
  | { kind: "ci.codemagic.refused"; at: number; vm: string; code: number };

export function appendRouteEvent(file: string, ev: RouteEvent): void {
  mkdirSync(dirname(file), { recursive: true });
  appendFileSync(file, JSON.stringify(ev) + "\n");
}

export type CmBuildDoc = { status: string; startedAt: number | null; finishedAt: number | null; createdAt: number | null; minutes: number | null; sha: string | null };

/** The Codemagic side of a cell: trigger one build (exit 5 = the Lean stop rule refused), wait for it and fetch its artifacts, read its record. */
export type CmDeps = {
  trigger: (branch: string, vars: Record<string, string>) => Promise<{ code: number; build?: string }>;
  wait: (build: string, out: string) => Promise<number>;
  read: (out: string) => CmBuildDoc;
  facts: () => CmFacts;
};

export function realCmDeps(root: string, log: (l: string) => void): CmDeps {
  const script = join(root, "scripts/codemagic.mjs");
  const run = (args: string[]) => new Promise<{ code: number; out: string }>((res) => {
    const c = spawn(process.execPath, [script, ...args], { cwd: root, stdio: ["ignore", "pipe", "inherit"] });
    let out = "";
    c.stdout.on("data", (b) => { out += String(b); });
    c.on("close", (code) => res({ code: code ?? 1, out }));
  });
  return {
    trigger: async (branch, vars) => {
      const r = await run(["trigger", "--pool", "--branch", branch, "--vars", JSON.stringify(vars)]);
      const id = /build ([0-9a-f]{24}) for /.exec(r.out)?.[1];
      log(r.out.trim());
      return { code: r.code, ...(id ? { build: id } : {}) };
    },
    wait: async (build, out) => { const r = await run(["wait", "--build", build, "--out", out, "--interval", "120", "--timeout", "3000"]); log(r.out.trim()); return r.code; },
    read: (out) => JSON.parse(readFileSync(join(out, "build.json"), "utf8")) as CmBuildDoc,
    facts: () => {
      const r = spawnSync(process.execPath, [script, "facts"], { cwd: root, encoding: "utf8" });
      if (r.status !== 0) throw new Error(`codemagic facts failed: ${r.stderr.trim()}`);
      const f = JSON.parse(r.stdout.trim().split("\n").pop()!) as { used: number; busy: number };
      return { cmUsed: f.used, cmBusy: f.busy };
    },
  };
}

/** Put the artifacts of a fetched Codemagic build where `gh run download --pattern webkit-sim-<vm>` would put them. */
export function placeCmArtifacts(buildOut: string, dir: string, vm: string): number {
  const from = join(buildOut, "artifacts"), to = join(dir, `webkit-sim-${vm}`);
  mkdirSync(to, { recursive: true });
  let n = 0;
  for (const f of existsSync(from) ? readdirSync(from) : []) {
    if (f.startsWith(`${vm}-`) || f === "runner.json" || f === "tools.txt") { copyFileSync(join(from, f), join(to, f)); n++; }
  }
  return n;
}

/** The `merge` job of webkit-sim.yml, run here for a mixed run: classes over every VM and the within-VM tables (`webkit-classes`). */
export function mergeClasses(root: string, dir: string): number {
  const files = readdirSync(dir, { withFileTypes: true }).filter((e) => e.isDirectory() && /^webkit-sim-v\d+$/.test(e.name))
    .flatMap((e) => readdirSync(join(dir, e.name)).filter((f) => /^v\d+-session-\d+\.json$/.test(f)).map((f) => join(dir, e.name, f))).sort();
  if (!files.length) return 0;
  const cli = join(root, "packages/measure-webkit/src/cli.mjs");
  const merge = (fs: string[]) => {
    const r = spawnSync(process.execPath, [cli, "merge", ...fs], { cwd: root, encoding: "utf8", maxBuffer: 1 << 28 });
    if (r.status !== 0) throw new Error(`merge failed: ${r.stderr.trim().split("\n").slice(-3).join("; ")}`);
    return r.stdout;
  };
  const out = join(dir, "webkit-classes");
  mkdirSync(out, { recursive: true });
  writeFileSync(join(out, "classes.md"), merge(files));
  for (const vm of new Set(files.map((f) => /\/(v\d+)-session-/.exec(f)![1]!))) writeFileSync(join(out, `${vm}-classes.md`), merge(files.filter((f) => f.includes(`/${vm}-session-`))));
  writeFileSync(join(out, "sha256.txt"), files.map((f) => `${createHash("sha256").update(readFileSync(f)).digest("hex")}  ${f.split("/").pop()}\n`).join(""));
  return files.length;
}

/** The real `RouteDeps` of `fw run`: read the facts, ask Lean, record the decision, start the Codemagic cells. At most `total - 1` cells leave GitHub:
 *  the GitHub run keeps v1.. and the telemetry pieces `store.download` needs (accepted limit; an all-Codemagic count job is not filed). */
export function realRoute(a: { root: string; consoleDir: string; call: FwCall; gh: Gh; log: (l: string) => void; now: () => number; cm?: CmDeps }): RouteDeps {
  const file = join(a.consoleDir, "ci-route.jsonl");
  const ev = (e: RouteEvent) => appendRouteEvent(file, e);
  const cm = a.cm ?? realCmDeps(a.root, a.log);
  const macOf = (wf: string, names: string[]) => (a.call({ op: "obs.macIs", rows: names.map((name) => ({ wf, name })) }) as unknown as { mac: boolean[] }).mac;
  return {
    split: async (job, ref, sha) => {
      const total = Number(job.inputs.vms ?? "1");
      const keep = (why: string) => { ev({ kind: "ci.route.skip", at: a.now(), why }); a.log(`route: ${why}; all ${total} cells on GitHub`); return { github: total, cm: Promise.resolve([] as CmCellDone[]) }; };
      if ((job.inputs.target ?? "original") !== "original") return keep("rewrite arm is GitHub-only");
      if (!ref.startsWith("ci/")) return keep(`ref ${ref} is not a pushed ci/* branch`);
      if (total < 2) return keep("one cell stays on GitHub");
      let r: CellRoute;
      try { r = routeCells(a.call, { sha, key: /^[0-9a-f]{64}$/.test(String(job.digest)) ? String(job.digest) : createHash("sha256").update(JSON.stringify(job.key ?? job.inputs)).digest("hex"), target: "original", vms: total, busy: await readGhBusy(a.gh, macOf), facts: cm.facts() }); }
      catch (e) { return keep(`facts unavailable (${(e as Error).message.split("\n")[0]})`); }
      const offload = Math.min(r.codemagic, total - 1);
      ev({ kind: "ci.route", at: a.now(), sha7: sha.slice(0, 7), lane: lanePool("original"), cells: total, codemagic: offload, github: total - offload, rows: r.rows, busy: r.busy, facts: r.facts });
      a.log(`route: ${total} cells, ${offload} to Codemagic, ${total - offload} to GitHub (macOS busy ${r.busy.ghMacBusy}, Codemagic used ${r.facts.cmUsed} min)`);
      if (!offload) return { github: total, cm: Promise.resolve([]) };
      const github = total - offload;
      const sessions = job.inputs.sessions ?? "1";
      const started: { vm: string; build: string }[] = [];
      for (let k = github + 1; k <= total; k++) {
        const vm = `v${k}`;
        const t = await cm.trigger(ref, { FW_TARGET: "original", FW_PRESET: "original", FW_FW: "", FW_VM: vm, FW_SESSIONS: sessions });
        if (t.build && t.code === 0) started.push({ vm, build: t.build });
        else { ev({ kind: "ci.codemagic.refused", at: a.now(), vm, code: t.code }); throw new Error(`Codemagic cell ${vm} was not started (exit ${t.code}); rerun with --no-route to keep every cell on GitHub`); }
      }
      const done = Promise.all(started.map(async ({ vm, build }) => {
        const out = join(a.consoleDir, "tmp", `codemagic-${build}`);
        const code = await cm.wait(build, out);
        const doc = cm.read(out);
        ev({ kind: "ci.codemagic.build", at: a.now(), build, vm, status: doc.status, startedAt: doc.startedAt, finishedAt: doc.finishedAt, createdAt: doc.createdAt, minutes: doc.minutes });
        if (code !== 0) throw new Error(`Codemagic build ${build} (${vm}) ended with exit ${code}`);
        if (doc.sha && doc.sha !== sha) throw new Error(`Codemagic build ${build} measured ${doc.sha.slice(0, 7)}, not ${sha.slice(0, 7)}`);
        return { vm, out };
      }));
      return { github, cm: done };
    },
    place: (dir, cells) => {
      for (const c of cells) if (placeCmArtifacts(c.out, dir, c.vm) === 0) throw new Error(`Codemagic cell ${c.vm}: no artifacts in ${c.out}`);
      mergeClasses(a.root, dir);
    },
  };
}
