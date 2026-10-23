import { Command } from "@fw/contracts";
import { NO_API_GROUPS, UsageError, apiBase, gitFullRef, renderBoard, send, stepCommand, taskCommand } from "./lib.ts";
import { CARD_USAGE, cardCommand } from "./card.ts";
import { dryLandReport, fwcorePreflight, httpFor, land, landExit, lastDryStep, loopback, type LandResult } from "./land.ts";
import { dryRun, exitCode, outcome, outcomeKind, verdictLine } from "./land-verdict.ts";
import { gitOnMain, lintCli, renderPlan, syncCommands, syncRefusal, type WorkGraph } from "./plan.ts";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { nextMain, watchMain } from "./watch.ts";
import { fwcoreCall, runCli } from "./run.ts";
import { execFileSync } from "node:child_process";
import { ciCli } from "./ci.ts";
import { ghBudgetCli, lastWaitPhases } from "@fw/gh-budget";
import { engineCheckCli } from "./engine-check.ts";
import { begin, span, timingsView } from "./timing.ts";
import { spanStep } from "./fw-groups.ts";
import { backfill, ingestRuns, lagCli, runIdsOf, waitSpanExtra } from "./timing-ci.ts";

const [group, ...rest] = process.argv.slice(2);
let spanExtra: ReturnType<typeof waitSpanExtra> & { step?: string } = {};
if (group && group !== "watch" && group !== "timings" && group !== "run" && !(group === "slot" && rest[0] === "run")) { const end = begin("fw", spanStep(group, rest)); process.once("exit", (c) => end(c, spanExtra)); }
async function postLandGc(mainDir: string): Promise<void> {
  const { diskGcTick } = await import("./disk-gc.ts");
  const lines = span("fw land", "disk-gc (post-land)", () => diskGcTick(mainDir, ["lake", "landed", "console", "usertmp"], fwcoreCall(mainDir)));
  for (const l of lines) console.error(l);
}
try {
  const base = NO_API_GROUPS.includes(group ?? "") || group === "disk-gc" || group === "oracle" || group === "slot" || group === "polish" || (group === "plan" && rest[0] === "overlap") || (group === "review" && (rest[0] === "ready" || rest[0] === "verdict")) ? "" : apiBase(process.env);
  if (group === "timings") {
    console.log(rest.includes("--backfill") ? await backfill(rest, process.cwd()) : rest.includes("--lag") ? lagCli(rest, process.cwd()) : timingsView(rest, process.cwd()));
  } else if (group === "checks") {
    const { checksCli } = await import("./checks.ts");
    process.exitCode = await checksCli(rest, process.cwd());
  } else if (group === "engine-check") {
    process.exitCode = engineCheckCli(rest, process.cwd());
  } else if (group === "run") {
    process.exitCode = await runCli(rest, process.cwd());
  } else if (group === "ci" && (rest[0] === "circleci" || (rest[0] === "wait" && rest[rest.indexOf("--provider") + 1] === "circleci"))) {
    const script = new URL("../../../scripts/circleci.mjs", import.meta.url).pathname;
    process.exitCode = spawnSync(process.execPath, [script, ...(rest[0] === "circleci" ? rest.slice(1) : rest)], { cwd: process.cwd(), stdio: "inherit" }).status ?? 1;
  } else if (group === "ci" && (rest[0] === "codemagic" || (rest[0] === "wait" && rest[rest.indexOf("--provider") + 1] === "codemagic"))) {
    const script = new URL("../../../scripts/codemagic.mjs", import.meta.url).pathname;
    const args = rest[0] === "codemagic" ? rest.slice(1) : rest.filter((a, i) => a !== "--provider" && rest[i - 1] !== "--provider");
    process.exitCode = spawnSync(process.execPath, [script, ...args], { cwd: process.cwd(), stdio: "inherit" }).status ?? 1;
  } else if (group === "ci" && (rest[0] === "wait" || rest[0] === "budget")) {
    const seen: string[] = []; const log = console.log;
    if (rest[0] === "wait") console.log = (...a: unknown[]) => { seen.push(String(a[0])); log(...a); };
    process.exitCode = await ghBudgetCli(rest, process.cwd());
    console.log = log;
    if (rest[0] === "wait") {
      const i0 = Date.now();
      await ingestRuns(runIdsOf(seen.flatMap((x) => x.split("\n"))), process.cwd());
      spanExtra = waitSpanExtra(lastWaitPhases(), i0, Date.now());
    }
  } else if (group === "ci" && rest[0] === "push") {
    const script = new URL("../../../scripts/ci-push.mjs", import.meta.url).pathname;
    process.exitCode = spawnSync(process.execPath, [script, ...rest.slice(1)], { cwd: process.cwd(), stdio: "inherit" }).status ?? 1;
  } else if (group === "ci" && rest[0] === "telemetry") {
    process.exitCode = await (await import("./ci-telemetry.ts")).telemetryCli(rest.slice(1), process.cwd());
  } else if (group === "ci" && rest[0] === "pool") {
    process.exitCode = await (await import("./ci-pool.ts")).poolCli(rest.slice(1), process.cwd());
  } else if (group === "ci" && rest[0] === "state") {
    process.exitCode = await (await import("./ci.ts")).ciStateCli(rest.slice(1), process.cwd());
  } else if (group === "ci") {
    process.exitCode = await ciCli(rest, process.cwd());
  } else if (group === "oracle") {
    process.exitCode = await (await import("./oracle.ts")).oracleCli(rest, process.cwd());  } else if (group === "incidents") {
    process.exitCode = await (await import("./incidents.ts")).incidentsCli(rest, process.cwd());
  } else if (group === "premises") { process.exitCode = await (await import("./premises.ts")).premisesCli(rest, process.cwd());
  } else if (group === "coverage") {
    process.exitCode = await (await import("./coverage.ts")).coverageCli(rest, process.cwd());
  } else if (group === "lake-gc") {
    const { LakeGcUsage, lakeGcCli } = await import("./lake-gc.ts");
    const top = execFileSync("git", ["rev-parse", "--show-toplevel"], { cwd: process.cwd(), encoding: "utf8" }).trim();
    try { process.exitCode = lakeGcCli(rest, top, fwcoreCall(process.cwd())); } catch (e) { throw e instanceof LakeGcUsage ? new UsageError(e.message) : e; }
  } else if (group === "disk-gc") {
    const { DiskGcUsage, diskGcCli } = await import("./disk-gc.ts");
    try { process.exitCode = diskGcCli(rest, process.cwd(), fwcoreCall(process.cwd())); } catch (e) { throw e instanceof DiskGcUsage ? new UsageError(e.message) : e; }
  } else if (group === "reap") {
    const { ReapUsage, reapCli } = await import("./reap.ts");
    const top = execFileSync("git", ["rev-parse", "--show-toplevel"], { cwd: process.cwd(), encoding: "utf8" }).trim();
    try { process.exitCode = reapCli(rest, top, fwcoreCall(process.cwd())); } catch (e) { throw e instanceof ReapUsage ? new UsageError(e.message) : e; }
  } else if (group === "slot") {
    const { SlotUsage, realDeps, slotCli } = await import("./slot.ts");
    try { process.exitCode = await slotCli(rest, realDeps(process.cwd())); } catch (e) { throw e instanceof SlotUsage ? new UsageError(e.message) : e; }
  } else if (group === "polish") {
    process.exitCode = await (await import("./polish.ts")).polishCli(rest, process.cwd());
  } else if (group === "watch") {
    process.exitCode = await watchMain(rest, process.cwd());
  } else if (group === "next") {
    process.exitCode = await nextMain(rest, process.cwd());
  } else if (group === "console") {
    const { consoleCli } = await import("./console.ts");
    process.exitCode = await consoleCli(rest, { call: fwcoreCall(process.cwd()), env: process.env, cwd: process.cwd(), out: console.log, err: console.error, now: Date.now });
  } else if (group === "preview") {
    process.exitCode = await (await import("./preview.ts")).previewCli(rest, base);
  } else if (group === "status") {
    const b = await (await fetch(`${base}/api/board`)).json();
    console.log(renderBoard(b as never));
  } else if (group === "plan") {
    if (rest[0] === "show") {
      const b = (await (await fetch(`${base}/api/board`)).json()) as { plan: never };
      console.log(renderPlan(b.plan));
    } else if (rest[0] === "sync" && rest[1]) {
      const refusal = syncRefusal(process.cwd());
      if (refusal) throw new Error(refusal);
      const cmds = syncCommands(JSON.parse(readFileSync(rest[1], "utf8")) as WorkGraph, "lead", gitOnMain(process.cwd()));
      const { body } = await send(base, cmds, process.argv.slice(2));
      const rs = body.replies ?? [];
      const n = (f: (r: { ok: boolean; duplicate?: boolean }) => boolean) => rs.filter(f).length;
      console.log(`plan sync: ${cmds.length} commands, ${n((r) => r.ok && !r.duplicate)} applied, ${n((r) => r.ok && !!r.duplicate)} unchanged, ${n((r) => !r.ok)} refused`);
      for (const r of rs) if (!r.ok) console.error(`refused: ${r.reason}`);
      if (!body.ok) { if (!rs.length) console.error(`refused: ${body.reason}`); process.exitCode = 2; }
    } else if (rest[0] === "overlap") {
      process.exitCode = await (await import("./plan-overlap.ts")).overlapCli(rest.slice(1), process.cwd());
    } else if (rest[0] === "lint") {
      process.exitCode = await lintCli(rest.slice(1), process.cwd());
    } else throw new UsageError("usage: fw plan sync <work-graph.json> | fw plan show | fw plan lint <work-graph.json> | fw plan overlap [<task>] [--running a,b] [--override <reason>]");
  } else if (group === "land") {
    const LAND_USAGE = "usage: fw land <branch> [--task <task-id>] [--allow <glob>]... [--dry]\n       fw land --queue <branch> --task <task-id> [--allow <glob>]... [--no-run]\n       fw land --queue-status";
    const flags = new Set(["--queue", "--queue-status", "--no-run", "--dry"]);
    const args = rest.filter((a) => !flags.has(a));
    const queue = rest.includes("--queue"), qstatus = rest.includes("--queue-status");
    if (!qstatus && !args[0]) throw new UsageError(LAND_USAGE);
    const ti = args.indexOf("--task");
    if (ti >= 0 && !args[ti + 1]) throw new UsageError(LAND_USAGE);
    if (queue && ti < 0) throw new UsageError(LAND_USAGE);
    const allow = args.flatMap((a, i) => (a === "--allow" ? [args[i + 1] ?? ""] : []));
    if (allow.some((a) => !a)) throw new UsageError(LAND_USAGE);
    const task = ti >= 0 ? args[ti + 1] : undefined;
    const landOpts = (task: string | undefined, allow: string[]) => ({ http: httpFor(base), cwd: process.cwd(), argv: process.argv.slice(2), task, allow, dry: !queue && rest.includes("--dry"),
      base,
      reap: async (d: string) => (await import("./reap.ts")).reapStopLines(d),
      checks: process.env.FW_LAND_CHECKS ? JSON.parse(process.env.FW_LAND_CHECKS) : undefined });
    if (queue || qstatus) {
      const { runQueue, landAttemptResult, enqueue, readLog, pending, results } = await import("./land-queue.ts");
      const { worktreeOf } = await import("./land.ts");
      const mainDir = worktreeOf(process.cwd(), "main");
      if (!mainDir) throw new Error("no main checkout found");
      const consoleDir = join(mainDir, ".fw-console");
      if (qstatus) {
        const log = readLog(consoleDir);
        for (const e of pending(log)) console.log(verdictLine("queued", e.task));
        for (const r of results(log)) if (!pending(log).some((e) => e.task === r.task)) console.log(verdictLine(r.kind, r.task));
      } else {
        const branch = args[0]!, t = task!;
        enqueue(consoleDir, { task: t, branch, allow });
        const run = rest.includes("--no-run") ? { ran: false, results: [] } : await runQueue({ consoleDir,
          attempt: async (e) => {
            const res = await land(e.branch, landOpts(e.task, e.allow));
            for (const l of res.lines) console.error(l);
            return landAttemptResult(res);
          },
          health: async () => { try { return (await fetch(`${loopback(base)}/api/health`, { headers: { connection: "close" }, signal: AbortSignal.timeout(3000) })).ok; } catch { return false; } },
          head: () => execFileSync("git", ["rev-parse", "main"], { cwd: mainDir, encoding: "utf8" }).trim(),
          diff: (from) => execFileSync("git", ["diff", "--name-only", "--no-renames", from, "main"], { cwd: mainDir, encoding: "utf8" }).split("\n").filter(Boolean),
          rebuild: async () => (await span("fw land", "fwcore rebuild (queue)", async () => spawnSync("sh", ["scripts/fwcore-build.sh"], { cwd: mainDir, stdio: ["ignore", 2, 2] }).status ?? 1, (st) => st)) === 0 && fwcorePreflight(mainDir, "main") === null });
        for (const r of run.results) console.log(verdictLine(r.kind, r.task));
        if (run.results.some((r) => r.kind === "done")) await postLandGc(mainDir);
        const own = run.results.find((r) => r.task === t);
        if (!own) console.log(verdictLine("queued", t));
        process.exitCode = exitCode(own?.kind ?? "queued");
      }
    } else {
      const dry = rest.includes("--dry");
      const res = await land(args[0]!, landOpts(task, allow)).catch((e: unknown): LandResult => ({ ok: false, lines: [`REFUSED: ${e instanceof Error ? e.message : String(e)}`], kind: "unknown", outcome: dry ? outcome({ threw: true }) : undefined }));
      if (dry) { const s = lastDryStep(); if (s !== null) spanExtra = { ...spanExtra, step: s.replace(/^dry total/, "land dry") }; }
      if (dry) {
        const rep = dryLandReport(res, task ?? args[0]!);
        for (const l of rep.err) console.error(l);
        for (const l of rep.out) console.log(l);
        process.exitCode = rep.code;
      } else {
        for (const l of res.lines) (res.ok && !l.startsWith("WARNING") ? console.log : console.error)(l);
        const kind = res.kind ?? (res.ok ? "done" : "unknown");
        if (kind === "done") { const { worktreeOf } = await import("./land.ts"); const m = worktreeOf(process.cwd(), "main"); if (m) await postLandGc(m); }
        console.log(verdictLine(kind, task ?? args[0]!));
        process.exitCode = landExit(res);
      }
    }
  } else if (group === "review" && (rest[0] === "ready" || rest[0] === "verdict")) {
    process.exitCode = await (await import("./review-ready.ts")).readyCli(rest, process.cwd());
  } else if (group === "review" && rest[0] === "report") {
    console.log(await (await import("./review.ts")).reportPostCli(rest.slice(1), base));
  } else if (group === "review" && rest[0] === "feedback") {
    console.log(await (await import("./review.ts")).feedbackCli(rest.slice(1), base));
  } else if (group === "step" && rest[0] === "questions") {
    console.log(await (await import("./step-threads.ts")).questionsCli(rest.slice(1), base));  } else if (group === "step" || group === "card" || group === "task" || group === "send" || group === "review") {
    const cmd = group === "step" && rest[0] === "topic" ? (await import("./step-threads.ts")).topicCommand(rest.slice(1), process.env)
      : group === "step" && rest[0] === "reply" ? await (await import("./step-threads.ts")).replyCommand(rest.slice(1), process.env, base)
      : group === "step" ? (await import("./step-threads.ts")).stepWithTopic(rest, process.env)
      : group === "card" ? cardCommand(rest, process.env)
      : group === "task" ? taskCommand(rest, process.env, Date.now(), (b) => gitFullRef(b))
      : group === "review" ? (await import("./review.ts")).reviewCommand(rest, process.env)
      : Command.parse(JSON.parse(rest[0] ?? "{}"));
    const { body } = await send(base, cmd, process.argv.slice(2));
    if (body.ok) console.log(body.duplicate ? "duplicate (already applied)" : `ok seq ${body.seq}`);
    else { console.error(`refused: ${body.reason}`); process.exitCode = 2; }
  } else {
    throw new UsageError(`usage: fw status | fw console start|stop|restart|status|logs | fw preview grant [<id>] | fw plan sync <file>|show|overlap [task] | fw watch [--json] [--interval s] [--until-alert] | fw next | fw engine-check --rows <jsonl> --run <dir> | fw ci state <run id> | fw land <branch> [--task id] [--allow glob] [--dry] | fw land --queue <branch> --task id | fw land --queue-status | fw incidents lint [ledger.json] | fw lake-gc [--list|--json|--delete] [--check] | fw reap --list|--stop | fw disk-gc [--list|--json|--delete] [--class c] | fw step post|start|answer|done|cancel|topic|reply|questions ... | fw task handback|integrate|park|unpark ... | fw review reply|feedback|report|ready|verdict ... | fw polish plan|cuts|commit|--staged ... | fw send '<json>'\n${CARD_USAGE}`);
  }
} catch (e) {
  console.error(e instanceof Error ? e.message : String(e));
  process.exitCode ||= e instanceof UsageError ? 64 : 1;
}
