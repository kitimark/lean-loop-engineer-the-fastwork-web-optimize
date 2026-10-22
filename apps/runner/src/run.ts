import { createHash } from "node:crypto";
import { spawnSync } from "node:child_process";
import { ghCharged, realEnv, titleFor, waitFor, type Env, type Target, type Waited } from "@fw/gh-budget";
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { GateReply, ManifestReply, PlanReply, ReduceReply, type PlanJob, type RunManifest } from "@fw/contracts";
import { UsageError } from "./lib.ts";
import { begin as beginSpan, recordRunKind } from "./timing.ts";
import { runPhases } from "./run-phases.ts";
import { dispatchIn, enginesOf, legsOf, newNonce, parseRunRows, pickRun, refusalText, titleOf } from "./run-pick.ts";

export type RunArgs = {
  target: string; preset: string; fw: string[]; engines: string[]; profile?: string; runs?: number; dry: boolean;
  ref?: string; sha?: string; images: Record<string, string>; fromRun: Record<string, string>;
  gate?: boolean; presetGiven?: boolean;
  trajectory?: boolean; widths?: string;
  diagnostic?: boolean;
};

export const RUN_USAGE = "usage: fw run --target original|rewrite [--preset <name>] [--fw part:variant,...] --engines chromium,webkit\n" +
  "       fw run --gate [--engines both|chromium|playwright-webkit] [--preset <name> | --fw part:variant,...] [--ref <branch>]\n" +
  "       fw run --trajectory [--engines both|chromium|playwright-webkit] [--preset <name> | --fw part:variant,...] [--widths 390,640,641,1280 [--diagnostic]] [--ref <branch>]\n" +
  "              [--profile <id>] [--runs 2..10]\n" +
  "              [--ref <pushed branch>] [--sha <git sha>] [--image engine=sha256:...] [--from-run engine=<run id>] [--dry]";

export function parseRunArgs(argv: string[]): RunArgs {
  const a: RunArgs = { target: "", preset: "original", fw: [], engines: [], dry: false, images: {}, fromRun: {} };
  const val = (i: number, flag: string) => {
    const v = argv[i + 1];
    if (v === undefined || v.startsWith("--")) throw new UsageError(`flag ${flag} needs a value\n${RUN_USAGE}`);
    return v;
  };
  const kv = (v: string, flag: string): [string, string] => {
    const at = v.indexOf("=");
    if (at <= 0) throw new UsageError(`flag ${flag} wants engine=value, got ${v}`);
    return [v.slice(0, at), v.slice(at + 1)];
  };
  for (let i = 0; i < argv.length; i++) {
    const f = argv[i]!;
    if (f === "--dry") a.dry = true;
    else if (f === "--target") a.target = val(i++, f);
    else if (f === "--gate") a.gate = true;
    else if (f === "--trajectory") a.trajectory = true;
    else if (f === "--widths") a.widths = val(i++, f);
    else if (f === "--diagnostic") a.diagnostic = true;
    else if (f === "--preset") { a.preset = val(i++, f); a.presetGiven = true; }
    else if (f === "--fw") a.fw.push(...val(i++, f).split(",").filter(Boolean));
    else if (f === "--engines") a.engines = val(i++, f).split(",").filter(Boolean);
    else if (f === "--profile") a.profile = val(i++, f);
    else if (f === "--runs") { const n = Number(val(i++, f)); if (!Number.isInteger(n)) throw new UsageError("--runs wants an integer"); a.runs = n; }
    else if (f === "--ref") a.ref = val(i++, f);
    else if (f === "--sha") a.sha = val(i++, f);
    else if (f === "--image") { const [k, v] = kv(val(i++, f), f); a.images[k] = v; }
    else if (f === "--from-run") { const [k, v] = kv(val(i++, f), f); a.fromRun[k] = v; }
    else throw new UsageError(`unknown flag ${f}\n${RUN_USAGE}`);
  }
  if (a.gate && a.trajectory) throw new UsageError(`--gate and --trajectory are separate lanes\n${RUN_USAGE}`);
  if (a.widths !== undefined && !a.trajectory) throw new UsageError(`--widths belongs to --trajectory\n${RUN_USAGE}`);
  if (a.diagnostic && !a.trajectory) throw new UsageError(`--diagnostic belongs to --trajectory\n${RUN_USAGE}`);
  if (a.trajectory) {
    if (a.engines.length > 1) throw new UsageError(`--trajectory takes one --engines value (both, chromium or playwright-webkit)\n${RUN_USAGE}`);
    if (a.target || a.profile || a.runs !== undefined) throw new UsageError(`--trajectory takes no --target, --profile or --runs\n${RUN_USAGE}`);
    return a;
  }
  if (a.gate) {
    if (a.engines.length > 1) throw new UsageError(`--gate takes one --engines value (both, chromium or playwright-webkit)\n${RUN_USAGE}`);
    if (a.target || a.profile || a.runs !== undefined) throw new UsageError(`--gate takes no --target, --profile or --runs (breakpoint-gate has none)\n${RUN_USAGE}`);
    return a;
  }
  if (a.engines.length === 0) throw new UsageError(`--engines is required\n${RUN_USAGE}`);
  if (!a.target) throw new UsageError(`--target is required (original = the snapshot, rewrite = apps/site)\n${RUN_USAGE}`);
  return a;
}

export type FwCall = (req: Record<string, unknown>) => Record<string, unknown>;

function fwcoreBin(cwd: string): string {
  const rel = "lean/.lake/build/bin/fwcore";
  const common = spawnSync("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd, encoding: "utf8" }).stdout.trim();
  const top = spawnSync("git", ["rev-parse", "--show-toplevel"], { cwd, encoding: "utf8" }).stdout.trim();
  const cands = [process.env.FW_CORE_BIN, top && join(top, rel), common && join(dirname(common), rel)].filter((x): x is string => !!x);
  const bin = cands.find((p) => existsSync(p));
  if (!bin) throw new Error("fwcore not built: sh scripts/fwcore-build.sh");
  return bin;
}

export function fwcoreCall(cwd: string): FwCall {
  const bin = fwcoreBin(cwd);
  return (req) => {
    const r = spawnSync(bin, [], { input: JSON.stringify({ ...req, id: 0 }) + "\n", env: { ...process.env, LEAN_ABORT_ON_PANIC: "1" }, maxBuffer: 1 << 30 });
    if (r.status !== 0) throw new Error(`fwcore exited with ${r.status ?? r.signal}: ${r.stderr}`);
    const { id: _id, ...rest } = JSON.parse(r.stdout.toString().trim().split("\n")[0]!) as Record<string, unknown>;
    if (typeof rest.error === "string") throw new UsageError(`fwcore ${String(req.op)}: ${rest.error}`);
    return rest;
  };
}

export const sha256 = (b: Buffer | string) => createHash("sha256").update(b).digest("hex");

export const keyDigest = (key: [string, string][]) => sha256(JSON.stringify(key));

export function presentRuns(store: string): string[] {
  const d = join(store, "runs");
  return existsSync(d) ? readdirSync(d).filter((n) => existsSync(join(d, n, "manifest.json"))) : [];
}

const walk = (dir: string): string[] =>
  readdirSync(dir, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? walk(join(dir, e.name)) : [join(dir, e.name)]));

export type Ingest = { manifest: RunManifest; path: string; objects: number; reused: number; digest: string; unchanged?: boolean };

export function ingest(call: FwCall, store: string, dir: string, job: PlanJob, meta: { target: string; preset: string; fw: string[]; profile: string; gitSha: string; runId: string }, opts: { keepSameRun?: boolean } = {}): Ingest {
  const files = walk(dir).map((p) => ({ p, name: relative(dir, p).split("\\").join("/") })).sort((x, y) => (x.name < y.name ? -1 : x.name > y.name ? 1 : 0));
  const entries = files.map(({ p, name }) => { const b = readFileSync(p); return { name, digest: sha256(b), bytes: b.length, p }; });
  const manifest: RunManifest = {
    engine: job.engine, target: meta.target as RunManifest["target"], preset: meta.preset, fw: meta.fw, profile: meta.profile, gitSha: meta.gitSha, image: job.image as RunManifest["image"],
    runId: meta.runId, entries: entries.map(({ name, digest, bytes }) => ({ name, digest, bytes })),
  };
  const checked = ManifestReply.parse(call({ op: "store.manifest", manifest }));
  if (!checked.valid) throw new UsageError(`manifest refused: ${checked.problems.join("; ")}`);
  const digest = keyDigest(checked.key as [string, string][]);
  const mpath = join(store, "runs", digest, "manifest.json");
  if (opts.keepSameRun && existsSync(mpath)) {
    const old = JSON.parse(readFileSync(mpath, "utf8")) as RunManifest;
    if (old.runId !== manifest.runId) throw new UsageError(`key ${digest.slice(0, 12)} is already stored from run ${old.runId}; run ${manifest.runId} has the same key (not overwritten)`);
    return { manifest: old, path: mpath, objects: 0, reused: entries.length, digest, unchanged: true };
  }
  let reused = 0;
  entries.forEach((e, i) => {
    const dest = join(store, checked.paths![i]!);
    if (existsSync(dest)) { reused++; return; }
    mkdirSync(dirname(dest), { recursive: true });
    copyFileSync(e.p, dest);
  });
  mkdirSync(dirname(mpath), { recursive: true });
  writeFileSync(mpath, JSON.stringify(manifest, null, 2) + "\n");
  return { manifest, path: mpath, objects: entries.length - reused, reused, digest };
}

export type GhOpts = { deadline?: number; signal?: AbortSignal };
export type Gh = (args: string[], o?: GhOpts) => Promise<string>;

export function ghCost(args: string[]): number {
  const [a, b] = args;
  if (a === "run" && b === "list") return args.includes("--workflow") ? 2 : 3;
  if (a === "run" && b === "view") return args.some((x) => x.includes("jobs")) ? 3 : 2;
  if (a === "run" && b === "download") return 15;
  if (a === "workflow" && b === "run") return 2;
  return 1;
}

export function chargedGh(env: Env): Gh {
  return async (args, o) => {
    const what = args.slice(0, 3).join(" ");
    if (o?.signal?.aborted) throw new Error(`gh ${what} not made: aborted`);
    const res = await ghCharged(env, args, { cost: ghCost(args), block: true, ...(o?.deadline !== undefined ? { deadline: o.deadline } : {}) });
    if (!res.ran) throw new Error(`gh ${what} not made: the request budget says ${res.decision} (${res.reason}); see \`fw ci budget\``);
    if (res.code !== 0) throw new Error(`gh ${what} failed: ${res.error ?? "unknown"}`);
    return res.stdout;
  };
}

export type WaitFn = (t: Target, timeoutS: number) => Promise<Waited>;

const WAIT_SLICE_S = 540;
const WAIT_CAP_S = 4 * 3600;

export async function waitDecided(wait: WaitFn, t: Target, now: () => number, capS = WAIT_CAP_S): Promise<Waited> {
  const start = now();
  for (;;) {
    const t0 = now();
    const w = await wait(t, WAIT_SLICE_S);
    if (w.code !== 3) return w;
    if (now() - t0 < WAIT_SLICE_S) throw new Error(w.lines.join("; "));
    if (now() - start >= capS) throw new Error(`gave up waiting after ${capS} s: ${w.lines.join("; ")}`);
  }
}

export const dispatchArgs = (job: Pick<PlanJob, "workflow" | "inputs">, ref: string): string[] =>
  ["workflow", "run", job.workflow, "--ref", ref, ...Object.entries(job.inputs).flatMap(([k, v]) => ["-f", `${k}=${v}`])];

export type Planned = { reply: PlanReply; sha: string; args: RunArgs };

export function planRun(call: FwCall, args: RunArgs, sha: string, store: string): Planned {
  const base = { op: "store.plan", target: args.target, preset: args.preset, fw: args.fw, engines: args.engines, sha, images: args.images,
    ...(args.profile ? { profile: args.profile } : {}), ...(args.runs !== undefined ? { runs: args.runs } : {}) };
  const first = PlanReply.parse(call(base));
  const digests = Object.fromEntries(first.jobs.map((j) => [j.engine, keyDigest(j.key as [string, string][])]));
  const reply = first.jobs.length ? PlanReply.parse(call({ ...base, digests, present: presentRuns(store) })) : first;
  return { reply, sha, args };
}

export function renderPlan(p: Planned, dry: boolean): string[] {
  const { reply, args } = p;
  const out = [`fw run${dry ? " (dry)" : ""}: target ${args.target}, preset ${args.preset}, flags ${reply.fw.join(",") || "-"}, sha ${p.sha.slice(0, 7)}`];
  for (const pr of reply.problems) out.push(`  problem: ${pr}`);
  for (const j of reply.jobs) {
    const ins = Object.entries(j.inputs).map(([k, v]) => `${k}=${v}`).join(" ") || "-";
    out.push(`  ${j.engine.padEnd(8)} ${j.workflow}  key ${(j.digest ?? "").slice(0, 12)}  cache ${j.cache ?? "?"}  inputs ${ins}  image ${j.image}` +
      (j.blocked ? `  BLOCKED: ${j.workflow} has no input "${j.blocked}" yet` : ""));
  }
  return out;
}

export type RunDeps = {
  call: FwCall; gh: Gh; wait: WaitFn; store: string; sha: string; branch: string; tmp: string; log: (l: string) => void;
  now: () => number;
  workflowName?: (file: string) => string | undefined;
  refSha?: (ref: string) => string | undefined;
  recordKind?: (runId: number, inputs: PlanJob["inputs"]) => void;
  capS?: number;
  refWorkflowText?: (ref: string, file: string) => string | undefined;
  nonce?: () => string;
  sleep?: (seconds: number) => Promise<void>;
};

const epoch = (iso: string) => Math.floor(Date.parse(iso) / 1000);
const runLine = /^run (\d+) /;

export async function runMain(args: RunArgs, d: RunDeps): Promise<number> {
  const sha = refShaOf(args, d);
  if (args.gate) return runGate(args, d, sha);
  if (args.trajectory) return runGate(args, d, sha, "trajectory");
  const planned = planRun(d.call, args, sha, d.store);
  for (const l of renderPlan(planned, args.dry)) d.log(l);
  if (planned.reply.problems.length) return 2;
  if (args.dry) return 0;
  const blocked = planned.reply.jobs.filter((j) => j.blocked && !args.fromRun[j.engine]);
  if (blocked.length) { d.log(`refused: ${blocked.map((j) => `${j.engine} (${j.blocked})`).join(", ")} cannot express this request; add the input to the workflow first`); return 2; }
  const ref = args.ref ?? d.branch;
  for (const j of planned.reply.jobs) {
    if (j.cache === "hit") { d.log(`${j.engine}: cached at ${j.manifest}`); continue; }
    let runId = args.fromRun[j.engine];
    if (!runId) {
      runId = decided(j.engine, await dispatchAndWait(d, j, ref, sha, j.engine));
      d.recordKind?.(Number(runId), j.inputs);
    } else {
      runId = decided(j.engine, await waitDecided(d.wait, { kind: "run", runId: Number(runId) }, d.now, d.capS));
    }
    const head = (JSON.parse(await d.gh(["run", "view", runId, "--json", "headSha"])) as { headSha: string }).headSha;
    if (head !== sha) throw new UsageError(`${j.engine}: run ${runId} measured ${head.slice(0, 7)}, not ${sha.slice(0, 7)}`);
    mkdirSync(d.tmp, { recursive: true });
    const dir = mkdtempSync(join(d.tmp, `${j.engine}-${runId}-`));
    let r: ReturnType<typeof ingest>;
    try {
      await d.gh(["run", "download", runId, "-D", dir]);
      r = ingest(d.call, d.store, dir, j, { target: args.target, preset: args.preset, fw: planned.reply.fw, profile: args.profile ?? "swipe-v1", gitSha: sha, runId });
    } finally { rmSync(dir, { recursive: true, force: true }); }
    d.log(`${j.engine}: run ${runId} filed, ${r.manifest.entries.length} artifacts (${r.objects} new, ${r.reused} already stored) -> ${relative(d.store, r.path)}`);
  }
  return 0;
}

export function declaresNonce(text: string): boolean {
  return declaresInput(text, "nonce");
}

export function declaresInput(text: string, name: string): boolean {
  const lines = text.split("\n");
  const ind = (l: string) => l.length - l.trimStart().length;
  const at = lines.findIndex((l) => /^\s*workflow_dispatch:\s*(#.*)?$/.test(l));
  if (at < 0) return false;
  const base = ind(lines[at] as string);
  let inInputs = false;
  let inputsIndent = -1;
  for (const l of lines.slice(at + 1)) {
    if (l.trim() === "" || l.trim().startsWith("#")) continue;
    if (ind(l) <= base) return false;
    if (!inInputs) { if (/^\s*inputs:\s*(#.*)?$/.test(l)) { inInputs = true; inputsIndent = ind(l); } continue; }
    if (ind(l) <= inputsIndent) return false;
    if (ind(l) === inputsIndent + 2 && new RegExp(`^\\s*${name}:\\s*(#.*)?$`).test(l)) return true;
  }
  return false;
}

function refDeclaresNonce(d: RunDeps, workflow: string, ref: string): boolean {
  if (!d.refWorkflowText) return true;
  const t = d.refWorkflowText(ref, workflow);
  return t !== undefined && declaresNonce(t);
}

async function dispatchAndWait(d: RunDeps, job: Pick<PlanJob, "workflow" | "inputs">, ref: string, sha: string, label: string): Promise<Waited> {
  const stem = job.workflow.replace(/\.ya?ml$/, "");
  if (!refDeclaresNonce(d, job.workflow, ref)) {
    d.log(`${label}: ${ref} has no nonce input in ${job.workflow} (a ref older than the nonce inputs); dispatching without it and taking the newest run created after the dispatch (the old pick, not identity; rebase the ref to get identity)`);
    const before = await latestRun(d.gh, job.workflow, ref);
    const at = d.now();
    await d.gh(dispatchArgs(job, ref));
    d.log(`${label}: dispatched ${job.workflow} on ${ref}; waiting for the run`);
    const name = before?.workflowName || d.workflowName?.(job.workflow);
    return waitDecided(d.wait, { kind: "branch", branch: ref, ...(name ? { workflow: name } : {}), sha, since: before ? epoch(before.createdAt) + 1 : at - 60 }, d.now, d.capS);
  }
  const nonce = d.nonce?.() ?? newNonce();
  await d.gh(dispatchArgs({ workflow: job.workflow, inputs: { ...job.inputs, nonce } }, ref));
  d.log(`${label}: dispatched ${job.workflow} on ${ref} with nonce ${nonce} (run title "${titleFor(stem, nonce)}"); waiting for that run`);
  const name = d.workflowName?.(job.workflow) ?? stem;
  return waitDecided(d.wait, { kind: "branch", branch: ref, workflow: name, sha, since: d.now() - 60, want: { kind: "dispatch", workflow: stem, nonce } }, d.now, d.capS);
}

function refShaOf(args: RunArgs, d: RunDeps): string {
  if (args.sha) return args.sha;
  if (args.ref && d.refSha) {
    const r = d.refSha(args.ref);
    if (!r) throw new UsageError(`cannot resolve --ref ${args.ref} to a commit (not fetched?); pass --sha <40 hex>`);
    return r;
  }
  return d.sha;
}

export function planGate(call: FwCall, args: RunArgs, lane: "gate" | "trajectory" = "gate"): GateReply {
  return GateReply.parse(call({ op: lane === "gate" ? "store.gate" : "store.trajectory", ...(args.engines[0] ? { engines: args.engines[0] } : {}),
    ...(args.presetGiven ? { preset: args.preset } : {}), ...(args.fw.length ? { fw: args.fw } : {}),
    ...(lane === "trajectory" && args.widths !== undefined ? { widths: args.widths } : {}) }));
}

async function runGate(args: RunArgs, d: RunDeps, sha: string, lane: "gate" | "trajectory" = "gate"): Promise<number> {
  if (lane === "trajectory") {
    const mark = args.diagnostic ? "diagnostic" : "verdict";
    const decision = dispatchIn(mark, args.widths ?? "");
    if (decision.kind === "refused") { d.log(refusalText(decision.why, args.widths ?? "")); return 2; }
    const legs = (enginesOf(args.engines[0] ?? "both") ?? []).map((e) => `${e} ${legsOf(e, decision.widths).length}`).join(", ");
    d.log(`fw run: trajectory ${mark}, widths ${decision.widths.join(",")}, legs ${legs}`);
  }
  const reply = planGate(d.call, args, lane);
  const refText = reply.job ? d.refWorkflowText?.(args.ref ?? d.branch, reply.job.workflow) : undefined;
  const sendMark = !!args.diagnostic && lane === "trajectory" && (!d.refWorkflowText || (refText !== undefined && declaresInput(refText, "diagnostic")));
  if (args.diagnostic && lane === "trajectory" && !sendMark) d.log(`trajectory: ${args.ref ?? d.branch} has no diagnostic input in trajectory-probe.yml (a ref older than the mark rule); dispatching without it`);
  const job = reply.job && sendMark ? { ...reply.job, inputs: { ...reply.job.inputs, diagnostic: "true" } } : reply.job;
  d.log(`fw run${args.dry ? " (dry)" : ""}: ${lane}, sha ${sha.slice(0, 7)}`);
  for (const pr of reply.problems) d.log(`  problem: ${pr}`);
  if (!job) return 2;
  d.log(`  ${lane.padEnd(8)} ${job.workflow}  inputs ${Object.entries(job.inputs).map(([k, v]) => `${k}=${v}`).join(" ")}` + (job.blocked ? `  BLOCKED: ${job.workflow} has no input "${job.blocked}" yet` : ""));
  if (args.dry) return 0;
  if (job.blocked) { d.log(`refused: ${lane} (${job.blocked}) cannot express this request; add the input to the workflow first`); return 2; }
  const ref = args.ref ?? d.branch;
  let runId = args.fromRun[lane];
  if (!runId && lane === "trajectory" && refDeclaresNonce(d, job.workflow, ref)) {
    const nonce = d.nonce?.() ?? newNonce();
    await d.gh(dispatchArgs({ workflow: job.workflow, inputs: { ...job.inputs, nonce } }, ref));
    d.log(`${lane}: dispatched ${job.workflow} on ${ref} with nonce ${nonce} (run title "${titleOf(nonce)}"); looking for the run`);
    const picked = await findDispatched(d, job.workflow, ref, nonce);
    d.log(`${lane}: the run with nonce ${nonce} is ${picked}`);
    runId = decided(lane, await waitDecided(d.wait, { kind: "run", runId: Number(picked) }, d.now, d.capS));
  } else if (!runId) {
    runId = decided(lane, await dispatchAndWait(d, job, ref, sha, lane));
  } else {
    runId = decided(lane, await waitDecided(d.wait, { kind: "run", runId: Number(runId) }, d.now, d.capS));
  }
  const head = (JSON.parse(await d.gh(["run", "view", runId, "--json", "headSha"])) as { headSha: string }).headSha;
  if (head !== sha) throw new UsageError(`${lane}: run ${runId} measured ${head.slice(0, 7)}, not ${sha.slice(0, 7)}`);
  d.log(`${lane}: run ${runId} succeeded at ${sha.slice(0, 7)} (tables: gh run download ${runId})`);
  return 0;
}

const FIND_EVERY_S = 120;
const FIND_TRIES = 5;

export async function findDispatched(d: Pick<RunDeps, "gh" | "sleep">, workflow: string, ref: string, nonce: string): Promise<string> {
  const sleep = d.sleep ?? ((s: number) => new Promise<void>((res) => setTimeout(res, s * 1000)));
  for (let i = 0; i < FIND_TRIES; i++) {
    await sleep(FIND_EVERY_S);
    const rows = parseRunRows(await d.gh(["run", "list", "--workflow", workflow, "--branch", ref, "--event", "workflow_dispatch", "--limit", "30", "--json", "databaseId,displayTitle,event"]));
    const p = pickRun(nonce, rows);
    if (p.kind === "found") return String(p.id);
    if (p.kind === "ambiguous") throw new Error(`nonce ${nonce} matches several runs (${p.ids.join(", ")}); not guessing`);
    if (p.kind === "badNonce") throw new Error(`nonce ${nonce} is not valid`);
  }
  throw new Error(`no run titled "${titleOf(nonce)}" on ${ref} after ${FIND_TRIES} looks; the dispatch may have failed (gh run list --workflow ${workflow} --event workflow_dispatch)`);
}

export type LatestRun = { id: string; createdAt: string; workflowName: string };

export async function latestRun(gh: Gh, workflow: string, ref: string): Promise<LatestRun | null> {
  const rows = JSON.parse(await gh(["run", "list", "--workflow", workflow, "--branch", ref, "--limit", "1", "--json", "databaseId,createdAt,workflowName"])) as { databaseId: number; createdAt?: string; workflowName?: string }[];
  return rows[0] ? { id: String(rows[0].databaseId), createdAt: rows[0].createdAt ?? "", workflowName: rows[0].workflowName ?? "" } : null;
}

function decided(engine: string, w: Waited): string {
  const id = runLine.exec(w.lines[0] ?? "")?.[1];
  if (w.code === 0 && id) return id;
  const why = w.code === 1 ? "the run did not succeed: " : w.code === 4 ? "the run did not run (its guard skipped): " : "cannot wait for the run: ";
  throw new Error(`${engine}: ${why}${w.lines.join("; ")}`);
}

export function reduceArms(call: FwCall, arms: { engine: string; base: unknown[]; var: unknown[] }[], kMax = 4, tMax = 24): ReduceReply {
  return ReduceReply.parse(call({ op: "store.reduce", kMax, tMax, arms }));
}

export const storeDir = (consoleDir: string) => join(consoleDir, "store");
export const isDir = (p: string) => existsSync(p) && statSync(p).isDirectory();

export async function runCli(argv: string[], cwd: string, env: Record<string, string | undefined> = process.env, begin: typeof beginSpan = beginSpan): Promise<number> {
  const vcs = (...a: string[]) => spawnSync("git", a, { cwd, encoding: "utf8" }).stdout.trim();
  const ph = runPhases(begin, argv.includes("--dry"));  let code = 1;
  try {
  const args = parseRunArgs(argv);
  const consoleDir = env.FW_CONSOLE_DIR ?? join(dirname(vcs("rev-parse", "--path-format=absolute", "--git-common-dir")), ".fw-console");
  const genv = args.dry ? null : realEnv(cwd);
  const unused = (): never => { throw new Error("no gh call in --dry"); };
  code = await runMain(args, {
    call: fwcoreCall(cwd), gh: genv ? ph.gh(chargedGh(genv)) : unused, wait: genv ? ph.wait((t, timeoutS) => waitFor(genv, t, { timeoutS })) : unused,
    now: genv ? genv.now : () => Math.floor(Date.now() / 1000),
    recordKind: (id, inputs) => { recordRunKind(id, inputs, cwd); },
    refSha: (r) => vcs("rev-parse", "--verify", "--quiet", `refs/remotes/origin/${r}^{commit}`) || vcs("rev-parse", "--verify", "--quiet", `refs/heads/${r}^{commit}`) || undefined,
    refWorkflowText: (r, f) => { const o = spawnSync("git", ["show", `${vcs("rev-parse", "--verify", "--quiet", `refs/remotes/origin/${r}^{commit}`) || vcs("rev-parse", "--verify", "--quiet", `refs/heads/${r}^{commit}`) || r}:.github/workflows/${f}`], { cwd, encoding: "utf8" }); return o.status === 0 ? o.stdout : undefined; },
    workflowName: (f) => { try { return /^name:\s*["']?([^"'\n#]+?)["']?\s*(?:#.*)?$/m.exec(readFileSync(join(cwd, ".github", "workflows", f), "utf8"))?.[1]; } catch { return undefined; } },
    store: storeDir(consoleDir), sha: vcs("rev-parse", "HEAD"), branch: vcs("rev-parse", "--abbrev-ref", "HEAD"),
    tmp: join(consoleDir, "tmp"), log: (l) => console.log(l),
  }); return code; } finally { ph.finish(code); }
}
