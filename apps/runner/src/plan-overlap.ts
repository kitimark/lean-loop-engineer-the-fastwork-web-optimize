// `fw plan overlap [<task>] [--running a,b] [--override "<reason>"]`: before a spawn, ask fwcore `plan.overlap`
// (Fw.Plan.Overlap) whether the task's graph writes intersect those of a running task. Running tasks come from the
// board (a task with a live agent and no evidence, the same fact as Fw.Plan.Core `tstate` = running) unless --running
// names them. An overlap is refused (exit 1) unless a reason is given; an override is recorded in the event log as a
// step the lead closes at once. No decision logic here.
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { Command } from "@fw/contracts";
import { UsageError, apiBase, parseFlags, send } from "./lib.ts";
import { coreCandidates, coreCaller, type CoreCall } from "./watch.ts";

export const OVERLAP_USAGE = "usage: fw plan overlap [<task>] [--running a,b] [--override \"<reason>\"]   (exit 1 refused, 2 unknown id or unrecorded override)";

export type Conflict = { a: string; b: string; ga: string; gb: string };
export type OverlapReply = { verdict: "clear" | "refused" | "overridden" | "unknown"; conflicts: Conflict[]; unknown: string[] };
export type Row = { id: string; writes: string[] };
type Board = { id: string; evidence?: string | null; agent?: string | null }[];

export interface Deps {
  core?: CoreCall;
  /** Board plan tasks, or null when the console-api is not reachable. */
  board?: () => Promise<Board | null>;
  /** Post commands to the event log (the lead's capability); returns whether every command was accepted. */
  record?: (cmds: Command[]) => Promise<boolean>;
  log?: (line: string) => void;
}

/** Ids of the board tasks that hold their writes: a live agent, no landed evidence. */
export const runningOf = (board: Board): string[] => board.filter((t) => !!t.agent && !t.evidence).map((t) => t.id);

/** The step pair that records an override: posted for the lead and closed at once by the script (the reducer lets only the script close a
 * waiting lead step, Fw.Console stepRefusal), keyed by task, reason and pairs. */
export function overrideCommands(cand: string | null, reason: string, r: OverlapReply): Command[] {
  const others = [...new Set(r.conflicts.flatMap((c) => [c.a, c.b]).filter((x) => x !== cand))];
  const h = createHash("sha1").update(JSON.stringify([cand, reason, r.conflicts])).digest("hex").slice(0, 10);
  const step = `overlap-override-${cand ?? "running"}-${h}`;
  const what = cand ? `start ${cand} over ${others.join(", ")}` : `running ${others.join(", ")}`;
  const body = `override reason: ${reason}\n${r.conflicts.map((c) => `${c.a} writes ${c.ga} <-> ${c.b} writes ${c.gb}`).join("\n")}`.slice(0, 2000);
  return [
    { type: "step.post", key: `${step}:post`, actor: "lead", step, card: null, title: `write-overlap override: ${what}`.slice(0, 200), kind: "action", options: null, audience: "lead", body },
    { type: "step.done", key: `${step}:done`, actor: "script", step, note: reason.slice(0, 200) },
  ];
}

export function renderOverlap(cand: string | null, r: OverlapReply): string {
  const L = r.conflicts.map((c) => `  ${c.a} writes ${c.ga}  <->  ${c.b} writes ${c.gb}`);
  if (r.unknown.length) L.unshift(`  not in the work graph: ${r.unknown.join(", ")}`);
  L.unshift(`overlap${cand ? ` ${cand}` : ""}: ${r.verdict.toUpperCase()} (${r.conflicts.length} overlapping pairs)`);
  return L.join("\n");
}

async function boardTasks(): Promise<Board | null> {
  try {
    const res = await fetch(`${apiBase(process.env)}/api/board`, { signal: AbortSignal.timeout(3000) });
    const b = (await res.json()) as { plan?: { tasks?: Board } };
    return b.plan?.tasks ?? null;
  } catch { return null; }
}

/** Exit codes: 0 clear or overridden, 1 refused, 2 unknown id / override not recorded. */
export async function overlapCli(args: string[], cwd: string, deps: Deps = {}): Promise<number> {
  const { pos, flags } = parseFlags(args);
  if (pos.length > 1) throw new UsageError(OVERLAP_USAGE);
  const cand = pos[0] ?? null;
  const out = deps.log ?? ((l: string) => console.log(l));
  const root = execFileSync("git", ["rev-parse", "--show-toplevel"], { cwd, encoding: "utf8" }).trim();
  const common = execFileSync("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd, encoding: "utf8" }).trim();
  const graph = JSON.parse(readFileSync(join(root, "docs/team/work-graph.json"), "utf8")) as { tasks: Row[] };
  let running: string[];
  if (flags.running !== undefined) running = flags.running.split(",").map((x) => x.trim()).filter(Boolean);
  else {
    const board = await (deps.board ?? boardTasks)();
    if (!board) throw new UsageError("console-api not reachable, so the running tasks are unknown: pass --running a,b");
    running = runningOf(board);
  }
  const call = deps.core ?? coreCaller(coreCandidates(root, join(common, "..")));
  const rows = graph.tasks.map((t) => ({ id: t.id, writes: t.writes ?? [] }));
  const r = (await call({ op: "plan.overlap", rows, running, candidate: cand, override: flags.override ?? null })) as unknown as OverlapReply;
  out(renderOverlap(cand, r));
  if (r.verdict === "overridden") {
    const cmds = overrideCommands(cand, flags.override!, r);
    const ok = await (deps.record ?? (async (c) => {
      const res = await send(apiBase(process.env), c, ["plan", "overlap", ...args]);
      return res.body.ok;
    }))(cmds).catch(() => false);
    if (!ok) { out("override NOT recorded in the event log (console-api refused or is down): do not start"); return 2; }
    out(`override recorded as step ${(cmds[0] as { step: string }).step}`);
    return 0;
  }
  if (r.verdict === "refused") out("refused: finish or park one of them, split the writes, or pass --override \"<reason>\"");
  return r.verdict === "clear" ? 0 : r.verdict === "refused" ? 1 : 2;
}
