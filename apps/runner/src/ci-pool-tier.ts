import { spawn, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { appendFileSync, copyFileSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
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

export type CellFacts = { lane: string | null; routable: boolean; needsDigest: boolean; filed: boolean };

export function poolCell(call: FwCall, target: string, ghDigest?: string | null, cmDigest?: string | null): CellFacts {
  const r = call({ op: "ci.poolCell", target, ...(ghDigest ? { ghDigest } : {}), ...(cmDigest ? { cmDigest } : {}) }) as unknown as CellFacts;
  return { lane: r.lane, routable: r.routable, needsDigest: r.needsDigest, filed: r.filed };
}

export function planCells(call: FwCall, a: { target: string; vms: number; sessions: string; preset: string; fw: string; sha: string }): { vm: string; search: string }[] {
  const r = call({ op: "measure.simPlan", id: "sim-plan", target: a.target, vms: String(a.vms), sessions: a.sessions, preset: a.preset, fw: a.fw, experiment: "determinism", sha: a.sha }) as unknown as { matrix: { vm: string; search: string }[]; problems: string[] };
  if (r.problems.length) throw new Error(`plan refused: ${r.problems.join("; ")}`);
  return r.matrix.map(({ vm, search }) => ({ vm, search }));
}

export type Busy = { ghMacBusy: number; ghTotalBusy: number };

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

export function routeCells(call: FwCall, a: { sha: string; key: string; target: string; vms: number; busy: Busy; facts: CmFacts }): CellRoute {
  const lane = poolCell(call, a.target).lane;
  if (!lane) throw new Error(`target ${a.target} has no pool lane`);
  const reqs = Array.from({ length: a.vms }, (_, rep) => ({ sha: a.sha, lane, cfg: a.key, rep, engine: "iosSimSafari", image: "xcode-27", capMin: 40 }));
  const reply = call({ op: "ci.poolTier", over: { circleMacAllow: [], circleCaps: {} }, state: { ...a.busy, ...a.facts, ccSpent: 0, ccStorage: 0 }, reqs });
  const rows = (reply.log as { rep: number; decision: string; via: string | null }[]).map(({ rep, decision, via }) => ({ rep, decision, via }));
  const codemagic = (reply.counts as Record<string, number>).codemagic ?? 0;
  return { total: a.vms, codemagic, github: a.vms - codemagic, rows, counts: reply.counts as Record<string, number>, busy: a.busy, facts: a.facts };
}

export type RouteEvent =
  | { kind: "ci.site.digest"; at: number; vm: string; github: string | null; codemagic: string | null; filed: boolean }
  | { kind: "ci.route"; at: number; sha7: string; lane: string; target: string; cells: number; codemagic: number; github: number; rows: CellRoute["rows"]; busy: Busy; facts: CmFacts }
  | { kind: "ci.route.skip"; at: number; why: string }
  | { kind: "ci.codemagic.build"; at: number; build: string; vm: string; status: string; startedAt: number | null; finishedAt: number | null; createdAt: number | null; minutes: number | null }
  | { kind: "ci.codemagic.refused"; at: number; vm: string; code: number }
  | { kind: "ci.cell.platform"; at: number; vm: string; ref: PlatformKey; key: PlatformKey; merged: boolean; hw: { ref: Hw; cell: Hw } };

export function appendRouteEvent(file: string, ev: RouteEvent): void {
  mkdirSync(dirname(file), { recursive: true });
  appendFileSync(file, JSON.stringify(ev) + "\n");
}

export type PlatformKey = { macosBuild: string; xcodeBuild: string; runtimeBuild: string };
export type Hw = { cpus: number | null; memsize: number | null };

export function parsePlatformKey(tools: string | null, iosVersion = "27.0"): PlatformKey {
  const t = tools ?? "";
  const one = (re: RegExp) => { const m = [...t.matchAll(re)]; return m.length === 1 ? m[0]![1]! : ""; };
  const esc = iosVersion.replace(/\./g, "\\.");
  return {
    macosBuild: one(/^BuildVersion:\s*(\S+)\s*$/gm),
    xcodeBuild: one(/^Build version\s+(\S+)\s*$/gm),
    runtimeBuild: one(new RegExp(`^iOS ${esc} \\(${esc} - (\\w+)\\)`, "gm")),
  };
}

export function parseHw(dir: string): Hw {
  const rj = join(dir, "runner.json");
  let cpus: number | null = null;
  if (existsSync(rj)) { try { const c = Number((JSON.parse(readFileSync(rj, "utf8")) as { cpus?: unknown }).cpus); if (Number.isFinite(c) && c > 0) cpus = c; } catch { /* unreadable: unrecorded */ } }
  const tf = join(dir, "tools.txt");
  const nums = existsSync(tf) ? readFileSync(tf, "utf8").split("\n").filter((l) => /^\d+$/.test(l.trim())).map((l) => Number(l.trim())) : [];
  return { cpus: cpus ?? nums[0] ?? null, memsize: nums[1] ?? null };
}

const readOr = (f: string): string | null => (existsSync(f) ? readFileSync(f, "utf8") : null);

export function cellMerged(call: FwCall, ref: PlatformKey, cell: PlatformKey): boolean {
  return (call({ op: "ci.cellMerged", ref, cell }) as unknown as { merged: boolean }).merged;
}

export type CmBuildDoc = { status: string; startedAt: number | null; finishedAt: number | null; createdAt: number | null; minutes: number | null; sha: string | null };

export type CmDeps = {
  trigger: (branch: string, vars: Record<string, string>) => Promise<{ code: number; build?: string }>;
  wait: (build: string, out: string) => Promise<number>;
  read: (out: string) => CmBuildDoc;
  facts: () => CmFacts;
  githubSiteDigest: (runId: string, tmp: string) => Promise<string | null>;
  siteDigestOf: (out: string) => string | null;
};

export function realCmDeps(root: string, log: (l: string) => void, gh?: Gh): CmDeps {
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
    githubSiteDigest: async (runId, tmp) => {
      if (!gh) return null;
      rmSync(tmp, { recursive: true, force: true });
      mkdirSync(tmp, { recursive: true });
      try { await gh(["run", "download", runId, "-D", tmp, "--pattern", "site-dist"]); } catch { return null; }
      const sub = join(tmp, "site-dist");
      const dir = existsSync(sub) ? sub : tmp;
      const r = await run(["site-digest", dir]);
      rmSync(tmp, { recursive: true, force: true });
      return r.code === 0 ? (/^([0-9a-f]{64})\b/.exec(r.out.trim())?.[1] ?? null) : null;
    },
    siteDigestOf: (out) => {
      const f = join(out, "artifacts", "site-digest.txt");
      return existsSync(f) ? (/^([0-9a-f]{64})\b/.exec(readFileSync(f, "utf8").trim())?.[1] ?? null) : null;
    },
    facts: () => {
      const r = spawnSync(process.execPath, [script, "facts"], { cwd: root, encoding: "utf8" });
      if (r.status !== 0) throw new Error(`codemagic facts failed: ${r.stderr.trim()}`);
      const f = JSON.parse(r.stdout.trim().split("\n").pop()!) as { used: number; busy: number };
      return { cmUsed: f.used, cmBusy: f.busy };
    },
  };
}

export function placeCmArtifacts(buildOut: string, dir: string, vm: string): number {
  const from = join(buildOut, "artifacts"), to = join(dir, `webkit-sim-${vm}`);
  mkdirSync(to, { recursive: true });
  let n = 0;
  for (const f of existsSync(from) ? readdirSync(from) : []) {
    if (f.startsWith(`${vm}-`) || f === "runner.json" || f === "tools.txt") { copyFileSync(join(from, f), join(to, f)); n++; }
  }
  return n;
}

export function mergeClasses(root: string, dir: string, refused: { vm: string; key: PlatformKey }[] = []): number {
  const cli = join(root, "packages/measure-webkit/src/cli.mjs");
  const files = readdirSync(dir, { withFileTypes: true }).filter((e) => e.isDirectory() && /^webkit-sim-[vr]\d+$/.test(e.name))
    .flatMap((e) => readdirSync(join(dir, e.name)).filter((f) => /^[vr]\d+-session-\d+\.json$/.test(f)).map((f) => join(dir, e.name, f))).sort();
  const merge = (fs: string[]) => {
    const r = spawnSync(process.execPath, [cli, "merge", ...fs], { cwd: root, encoding: "utf8", maxBuffer: 1 << 28 });
    if (r.status !== 0) throw new Error(`merge failed: ${r.stderr.trim().split("\n").slice(-3).join("; ")}`);
    return r.stdout;
  };
  const out = join(dir, "webkit-classes");
  mkdirSync(out, { recursive: true });
  for (const r of refused) {
    const rf = (existsSync(join(dir, "refused", `webkit-sim-${r.vm}`)) ? readdirSync(join(dir, "refused", `webkit-sim-${r.vm}`)) : [])
      .filter((f) => /^[vr]\d+-session-\d+\.json$/.test(f)).map((f) => join(dir, "refused", `webkit-sim-${r.vm}`, f)).sort();
    mkdirSync(join(out, "refused"), { recursive: true });
    writeFileSync(join(out, "refused", `${r.vm}-key.json`), JSON.stringify(r.key) + "\n");
    if (rf.length) writeFileSync(join(out, "refused", `${r.vm}-classes.md`), merge(rf));
  }
  if (!files.length) return 0;
  writeFileSync(join(out, "classes.md"), merge(files));
  for (const vm of new Set(files.map((f) => /\/([vr]\d+)-session-/.exec(f)![1]!))) writeFileSync(join(out, `${vm}-classes.md`), merge(files.filter((f) => f.includes(`/${vm}-session-`))));
  writeFileSync(join(out, "sha256.txt"), files.map((f) => `${createHash("sha256").update(readFileSync(f)).digest("hex")}  ${f.split("/").pop()}\n`).join(""));
  return files.length;
}

export function realRoute(a: { root: string; consoleDir: string; call: FwCall; gh: Gh; log: (l: string) => void; now: () => number; cm?: CmDeps }): RouteDeps {
  const file = join(a.consoleDir, "ci-route.jsonl");
  const ev = (e: RouteEvent) => appendRouteEvent(file, e);
  const cm = a.cm ?? realCmDeps(a.root, a.log, a.gh);
  const macOf = (wf: string, names: string[]) => (a.call({ op: "obs.macIs", rows: names.map((name) => ({ wf, name })) }) as unknown as { mac: boolean[] }).mac;
  return {
    split: async (job, ref, sha) => {
      const total = Number(job.inputs.vms ?? "1");
      const target = job.inputs.target ?? "original";
      const keep = (why: string) => { ev({ kind: "ci.route.skip", at: a.now(), why }); a.log(`route: ${why}; all ${total} cells on GitHub`); return { github: total, cm: Promise.resolve([] as CmCellDone[]) }; };
      if (!poolCell(a.call, target).routable) return keep(`target ${target} is not routable (Lean ci.poolCell)`);
      if (!ref.startsWith("ci/")) return keep(`ref ${ref} is not a pushed ci/* branch`);
      if (total < 2) return keep("one cell stays on GitHub");
      let r: CellRoute;
      let cells: { vm: string; search: string }[];
      try {
        cells = planCells(a.call, { target, vms: total, sessions: job.inputs.sessions ?? "1", preset: job.inputs.preset ?? "original", fw: job.inputs.fw ?? "", sha });
        r = routeCells(a.call, { sha, key: /^[0-9a-f]{64}$/.test(String(job.digest)) ? String(job.digest) : createHash("sha256").update(JSON.stringify(job.key ?? job.inputs)).digest("hex"), target, vms: total, busy: await readGhBusy(a.gh, macOf), facts: cm.facts() });
      } catch (e) { return keep(`facts unavailable (${(e as Error).message.split("\n")[0]})`); }
      const offload = Math.min(r.codemagic, total - 1);
      ev({ kind: "ci.route", at: a.now(), sha7: sha.slice(0, 7), lane: poolCell(a.call, target).lane ?? "", target, cells: total, codemagic: offload, github: total - offload, rows: r.rows, busy: r.busy, facts: r.facts });
      a.log(`route: ${total} ${target} cells, ${offload} to Codemagic, ${total - offload} to GitHub (macOS busy ${r.busy.ghMacBusy}, Codemagic used ${r.facts.cmUsed} min)`);
      if (!offload) return { github: total, cm: Promise.resolve([]) };
      const github = total - offload;
      const sessions = job.inputs.sessions ?? "1";
      const started: { vm: string; build: string }[] = [];
      for (const c of cells.slice(github)) {
        const t = await cm.trigger(ref, { FW_TARGET: target, FW_PRESET: job.inputs.preset ?? "original", FW_FW: job.inputs.fw ?? "", FW_VM: c.vm, FW_SESSIONS: sessions, ...(target === "rewrite" ? { FW_SEARCH: c.search } : {}) });
        if (t.build && t.code === 0) started.push({ vm: c.vm, build: t.build });
        else { ev({ kind: "ci.codemagic.refused", at: a.now(), vm: c.vm, code: t.code }); throw new Error(`Codemagic cell ${c.vm} was not started (exit ${t.code}); rerun with --no-route to keep every cell on GitHub`); }
      }
      const done = Promise.all(started.map(async ({ vm, build }) => {
        const out = join(a.consoleDir, "tmp", `codemagic-${build}`);
        const code = await cm.wait(build, out);
        const doc = cm.read(out);
        ev({ kind: "ci.codemagic.build", at: a.now(), build, vm, status: doc.status, startedAt: doc.startedAt, finishedAt: doc.finishedAt, createdAt: doc.createdAt, minutes: doc.minutes });
        if (code !== 0) throw new Error(`Codemagic build ${build} (${vm}) ended with exit ${code}`);
        if (!doc.sha) throw new Error(`Codemagic build ${build} (${vm}) reports no commit sha; its cell is refused`);
        if (doc.sha !== sha) throw new Error(`Codemagic build ${build} measured ${doc.sha.slice(0, 7)}, not ${sha.slice(0, 7)}`);
        return { vm, out, target };
      }));
      return { github, cm: done };
    },
    place: async (dir, cells, runId) => {
      const rewrite = cells.filter((c) => poolCell(a.call, c.target ?? "original").needsDigest);
      if (rewrite.length) {
        const gh = await cm.githubSiteDigest(runId, join(a.consoleDir, "tmp", `site-${runId}`));
        for (const c of rewrite) {
          const mine = cm.siteDigestOf(c.out);
          const v = poolCell(a.call, c.target!, gh, mine);
          ev({ kind: "ci.site.digest", at: a.now(), vm: c.vm, github: gh, codemagic: mine, filed: v.filed });
          if (!v.filed) throw new Error(`Codemagic cell ${c.vm}: site digest ${mine ?? "missing"} is not the GitHub site job digest ${gh ?? "missing"}; the rewrite cell is not routable, rerun with --no-route`);
        }
      }
      const refVm = (cells[0]?.target ?? "original") === "rewrite" ? "r1" : "v1";
      const refDir = join(dir, `webkit-sim-${refVm}`);
      const ref = parsePlatformKey(readOr(join(refDir, "tools.txt")));
      const refused: { vm: string; key: PlatformKey }[] = [];
      for (const c of cells) {
        const cellDir = join(c.out, "artifacts");
        const key = parsePlatformKey(readOr(join(cellDir, "tools.txt")));
        const merged = cellMerged(a.call, ref, key);
        ev({ kind: "ci.cell.platform", at: a.now(), vm: c.vm, ref, key, merged, hw: { ref: parseHw(refDir), cell: parseHw(cellDir) } });
        a.log(`route: cell ${c.vm} toolchain ${merged ? "merged" : "refused, filed aside"} (macOS ${key.macosBuild || "?"}, Xcode ${key.xcodeBuild || "?"}, runtime ${key.runtimeBuild || "?"})`);
        const where = merged ? dir : join(dir, "refused");
        if (placeCmArtifacts(c.out, where, c.vm) === 0) throw new Error(`Codemagic cell ${c.vm}: no artifacts in ${c.out}`);
        if (!merged) refused.push({ vm: c.vm, key });
      }
      mergeClasses(a.root, dir, refused);
    },
  };
}
