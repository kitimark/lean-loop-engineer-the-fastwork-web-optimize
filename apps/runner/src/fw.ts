#!/usr/bin/env node
import { Command } from "@fw/contracts";
import { UsageError, apiBase, renderBoard, send, stepCommand } from "./lib.ts";
import { CARD_USAGE, cardCommand } from "./card.ts";
import { httpFor, land } from "./land.ts";
import { lintCli, renderPlan, syncCommands, syncRefusal, syncViaCommands, type WorkGraph } from "./plan.ts";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { nextMain, watchMain } from "./watch.ts";
import { runCli } from "./run.ts";
import { ciCli } from "./ci.ts";
import { ghBudgetCli } from "@fw/gh-budget";
import { engineCheckCli } from "./engine-check.ts";
import { begin, timingsView } from "./timing.ts";
import { backfill, ingestRuns, runIdsOf } from "./timing-ci.ts";

const [group, ...rest] = process.argv.slice(2);
// timing-spans: one span per invocation (step = group + subcommand); `watch` times each pass itself, `timings` is a view
const SUBS = new Set(["plan", "ci", "incidents", "step", "card"]);
if (group && group !== "watch" && group !== "timings") { const end = begin("fw", SUBS.has(group) && rest[0] && !rest[0].startsWith("-") ? `${group} ${rest[0]}` : group); process.once("exit", (c) => end(c)); }
try {
  const base = group === "run" || group === "ci" || group === "next" || group === "engine-check" || group === "incidents" ? "" : apiBase(process.env); // `fw run` needs no console-api
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
    if (rest[0] === "wait") await ingestRuns(runIdsOf(seen.flatMap((x) => x.split("\n"))), process.cwd()); // jobs fetched once, deduped by run id
  } else if (group === "ci") {
    process.exitCode = await ciCli(rest, process.cwd());
  } else if (group === "incidents") {
    process.exitCode = await (await import("./incidents.ts")).incidentsCli(rest, process.cwd()); // incident-lint: board optional
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
      const cmds = syncCommands(JSON.parse(readFileSync(rest[1], "utf8")) as WorkGraph);
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
    const LAND_USAGE = "usage: fw land <branch> [--task <task-id>] [--allow <glob>]...";
    if (!rest[0]) throw new UsageError(LAND_USAGE);
    const ti = rest.indexOf("--task");
    if (ti >= 0 && !rest[ti + 1]) throw new UsageError(LAND_USAGE);
    const allow = rest.flatMap((a, i) => (a === "--allow" ? [rest[i + 1] ?? ""] : []));
    if (allow.some((a) => !a)) throw new UsageError(LAND_USAGE);
    const res = await land(rest[0], { http: httpFor(base), cwd: process.cwd(), argv: process.argv.slice(2), task: ti >= 0 ? rest[ti + 1] : undefined, allow,
      // after a landing, sync the board from the work graph of the main checkout, through the plain command door: the
      // capability of this `pnpm fw land` call may be spent, and the hook mints one only for `pnpm fw ...` commands
      base,
      after: async (mainDir) => {
        const f = join(mainDir, "docs/team/work-graph.json");
        if (!existsSync(f)) return [];
        const refusal = syncRefusal(mainDir);
        if (refusal) throw new Error(refusal);
        return [await syncViaCommands(httpFor(base), JSON.parse(readFileSync(f, "utf8")) as WorkGraph)];
      },
      // FW_LAND_CHECKS='[["cmd","arg"]]' replaces the default checks (used by the e2e script on a temp repo)
      checks: process.env.FW_LAND_CHECKS ? JSON.parse(process.env.FW_LAND_CHECKS) : undefined });
    for (const l of res.lines) (res.ok && !l.startsWith("WARNING") ? console.log : console.error)(l);
    if (!res.ok) process.exitCode = 2;
  } else if (group === "step" || group === "card" || group === "send") {
    // `fw send '<json command>'` is the escape hatch for run.* commands
    const cmd = group === "step" ? stepCommand(rest, process.env)
      : group === "card" ? cardCommand(rest, process.env)
      : Command.parse(JSON.parse(rest[0] ?? "{}"));
    const { body } = await send(base, cmd, process.argv.slice(2));
    if (body.ok) console.log(body.duplicate ? "duplicate (already applied)" : `ok seq ${body.seq}`);
    else { console.error(`refused: ${body.reason}`); process.exitCode = 2; }
  } else {
    throw new UsageError(`usage: fw status | fw plan sync <file>|show | fw watch [--json] [--interval s] [--until-alert] | fw next | fw engine-check --rows <jsonl> --run <dir> | fw land <branch> [--task id] [--allow glob] | fw incidents lint [ledger.json] | fw step post|start|answer|done|cancel ... | fw send '<json>'\n${CARD_USAGE}`);
  }
} catch (e) {
  console.error(e instanceof Error ? e.message : String(e));
  process.exitCode ||= e instanceof UsageError ? 64 : 1;
}
