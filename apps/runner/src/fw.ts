#!/usr/bin/env node
import { Command } from "@fw/contracts";
import { NO_API_GROUPS, UsageError, apiBase, renderBoard, send, stepCommand } from "./lib.ts";
import { CARD_USAGE, cardCommand } from "./card.ts";
import { httpFor, land, type LandResult } from "./land.ts";
import { dryRun, exitCode, outcome, outcomeKind, verdictLine } from "./land-verdict.ts";
import { gitOnMain, lintCli, renderPlan, syncCommands, syncRefusal, syncViaCommands, type WorkGraph } from "./plan.ts";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { nextMain, watchMain } from "./watch.ts";
import { runCli } from "./run.ts";
import { ciCli } from "./ci.ts";
import { ghBudgetCli } from "@fw/gh-budget";
import { engineCheckCli } from "./engine-check.ts";
import { begin, timingsView } from "./timing.ts";
import { backfill, ingestRuns, runIdsOf } from "./timing-ci.ts";
import { collect as collectShape, finishedOf } from "./ci-shape.ts";

const [group, ...rest] = process.argv.slice(2);
// timing-spans: one span per invocation (step = group + subcommand); `watch` times each pass itself, `timings` is a view
const SUBS = new Set(["plan", "ci", "incidents", "step", "card"]);
if (group && group !== "watch" && group !== "timings") { const end = begin("fw", SUBS.has(group) && rest[0] && !rest[0].startsWith("-") ? `${group} ${rest[0]}` : group); process.once("exit", (c) => end(c)); }
try {
  const base = NO_API_GROUPS.includes(group ?? "") ? "" : apiBase(process.env); // these need no console-api (CI runs some of them)
  if (group === "timings") {
    console.log(rest.includes("--backfill") ? await backfill(rest, process.cwd()) : timingsView(rest, process.cwd()));
  } else if (group === "engine-check") {
    process.exitCode = engineCheckCli(rest, process.cwd());
  } else if (group === "run") {
    process.exitCode = await runCli(rest, process.cwd());
  } else if (group === "ci" && (rest[0] === "wait" || rest[0] === "budget")) {
    const seen: string[] = []; const log = console.log;
    if (rest[0] === "wait") console.log = (...a: unknown[]) => { seen.push(String(a[0])); log(...a); }; // timing-spans: run ids that finished
    process.exitCode = await ghBudgetCli(rest, process.cwd()); // shared GitHub poller: no gh loops (packages/gh-budget)
    console.log = log;
    if (rest[0] === "wait") {
      const lines = seen.flatMap((x) => x.split("\n"));
      await ingestRuns(runIdsOf(lines), process.cwd()); // jobs fetched once, deduped by run id
      await collectShape(finishedOf(lines), process.cwd()); // ci-shape-obs: job rows of the finished runs, cancelled skipped
    }
  } else if (group === "ci") {
    process.exitCode = await ciCli(rest, process.cwd());
  } else if (group === "incidents") {
    process.exitCode = await (await import("./incidents.ts")).incidentsCli(rest, process.cwd()); // incident-lint: board optional
  } else if (group === "premises") { process.exitCode = await (await import("./premises.ts")).premisesCli(rest, process.cwd()); // Lean premises vs browser tests
  } else if (group === "coverage") {
    process.exitCode = await (await import("./coverage.ts")).coverageCli(rest, process.cwd()); // lean-coverage: warn mode
  } else if (group === "watch") {
    process.exitCode = await watchMain(rest, process.cwd());
  } else if (group === "next") {
    process.exitCode = await nextMain(rest, process.cwd()); // read-only: prints the NEXT list once
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
      const { body } = await send(base, cmds, process.argv.slice(2)); // one capability, one array
      const rs = body.replies ?? [];
      const n = (f: (r: { ok: boolean; duplicate?: boolean }) => boolean) => rs.filter(f).length;
      console.log(`plan sync: ${cmds.length} commands, ${n((r) => r.ok && !r.duplicate)} applied, ${n((r) => r.ok && !!r.duplicate)} unchanged, ${n((r) => !r.ok)} refused`);
      for (const r of rs) if (!r.ok) console.error(`refused: ${r.reason}`);
      if (!body.ok) { if (!rs.length) console.error(`refused: ${body.reason}`); process.exitCode = 2; }
    } else if (rest[0] === "lint") {
      process.exitCode = await lintCli(rest.slice(1), process.cwd());
    } else throw new UsageError("usage: fw plan sync <work-graph.json> | fw plan show | fw plan lint <work-graph.json>");
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
      // after a landing, sync the board from the work graph of the main checkout, through the plain command door: the
      // capability of this `pnpm fw land` call may be spent, and the hook mints one only for `pnpm fw ...` commands
      base,
      after: async (mainDir: string) => {
        const f = join(mainDir, "docs/team/work-graph.json");
        if (!existsSync(f)) return [];
        const refusal = syncRefusal(mainDir);
        if (refusal) throw new Error(refusal);
        return [await syncViaCommands(httpFor(base), JSON.parse(readFileSync(f, "utf8")) as WorkGraph, gitOnMain(mainDir))];
      },
      // FW_LAND_CHECKS='[["cmd","arg"]]' replaces the default checks (used by the e2e script on a temp repo)
      checks: process.env.FW_LAND_CHECKS ? JSON.parse(process.env.FW_LAND_CHECKS) : undefined });
    if (queue || qstatus) {
      const { runQueue, enqueue, readLog, pending, results } = await import("./land-queue.ts");
      const { worktreeOf } = await import("./land.ts");
      const mainDir = worktreeOf(process.cwd(), "main");
      if (!mainDir) throw new Error("no main checkout found");
      const consoleDir = join(mainDir, ".fw-console");
      if (qstatus) {
        // one VERDICT line per task: queued for pending entries, the recorded kind otherwise; exit 0
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
            return res.kind ?? (res.ok ? "done" : "unknown");
          } });
        for (const r of run.results) console.log(verdictLine(r.kind, r.task));
        const own = run.results.find((r) => r.task === t);
        if (!own) console.log(verdictLine("queued", t)); // another runner (or --no-run) will land it
        process.exitCode = exitCode(own?.kind ?? "queued");
      }
    } else {
      // an exception inside `land` still ends in a refusal: kind unknown, exit 2 (a dry run: `outcome({ threw: true })`)
      const dry = rest.includes("--dry");
      const res = await land(args[0]!, landOpts(task, allow)).catch((e: unknown): LandResult => ({ ok: false, lines: [`REFUSED: ${e instanceof Error ? e.message : String(e)}`], kind: "unknown", outcome: dry ? outcome({ threw: true }) : undefined }));
      if (dry) {
        // glue only: prose to stderr, then exactly the lines Lean `Fw.Console.LandDry.dryRun` returns for the stage outcomes
        // (one VERDICT line: `dryRun_one_verdict`), and the exit code of the kind it printed
        const oc = res.outcome ?? outcome({ threw: true });
        for (const l of res.lines) console.error(l);
        for (const l of dryRun(oc, task ?? args[0]!)) console.log(l);
        process.exitCode = exitCode(outcomeKind(oc));
      } else {
        for (const l of res.lines) (res.ok && !l.startsWith("WARNING") ? console.log : console.error)(l);
        // one machine-readable line and a distinct exit code per kind (Lean Fw.Console.LandVerdict); scripts never grep prose
        const kind = res.kind ?? (res.ok ? "done" : "unknown");
        console.log(verdictLine(kind, task ?? args[0]!));
        process.exitCode = exitCode(kind);
      }
    }
  } else if (group === "step" || group === "card" || group === "send") {
    // `fw send '<json command>'` is the escape hatch for run.* commands
    const cmd = group === "step" ? stepCommand(rest, process.env)
      : group === "card" ? cardCommand(rest, process.env)
      : Command.parse(JSON.parse(rest[0] ?? "{}"));
    const { body } = await send(base, cmd, process.argv.slice(2));
    if (body.ok) console.log(body.duplicate ? "duplicate (already applied)" : `ok seq ${body.seq}`);
    else { console.error(`refused: ${body.reason}`); process.exitCode = 2; }
  } else {
    throw new UsageError(`usage: fw status | fw plan sync <file>|show | fw watch [--json] [--interval s] [--until-alert] | fw next | fw engine-check --rows <jsonl> --run <dir> | fw land <branch> [--task id] [--allow glob] [--dry] | fw land --queue <branch> --task id | fw land --queue-status | fw incidents lint [ledger.json] | fw step post|start|answer|done|cancel ... | fw send '<json>'\n${CARD_USAGE}`);
  }
} catch (e) {
  console.error(e instanceof Error ? e.message : String(e));
  process.exitCode ||= e instanceof UsageError ? 64 : 1;
}
