// fw CLI core: argv -> typed Command, and a tiny HTTP client. The CLI has NO way to write status:
// it only sends typed requests to console-api, which may refuse them.
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { Actor, Command, StepKind, type Board } from "@fw/contracts";

export class UsageError extends Error {}

export function parseFlags(argv: string[]): { pos: string[]; flags: Record<string, string> } {
  const pos: string[] = [];
  const flags: Record<string, string> = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]!;
    if (a.startsWith("--")) {
      const v = argv[i + 1];
      if (v === undefined || v.startsWith("--")) throw new UsageError(`flag ${a} needs a value`);
      flags[a.slice(2)] = v;
      i++;
    } else pos.push(a);
  }
  return { pos, flags };
}

const need = (v: string | undefined, what: string): string => {
  if (!v) throw new UsageError(`missing ${what}`);
  return v;
};

/** `fw step post|start|answer|done|cancel ...` -> Command (key derived so retries are idempotent). */
export function stepCommand(argv: string[], env: Record<string, string | undefined>): Command {
  const [verb, ...rest] = argv;
  const { pos, flags } = parseFlags(rest);
  const actor = Actor.parse(flags.as ?? env.FW_ACTOR ?? "owner");
  const key = flags.key;
  switch (verb) {
    case "post": {
      const step = need(flags.id ?? pos[0], "--id <step>");
      const kind = StepKind.parse(flags.kind ?? "action");
      return Command.parse({ type: "step.post", key: key ?? `step.post:${step}`, actor, step,
        card: flags.card ?? null, title: need(flags.title, "--title <text>"), kind,
        options: flags.options ? flags.options.split(",") : null });
    }
    case "start": case "done": case "cancel": {
      const step = need(pos[0], "<step id>");
      return Command.parse({ type: `step.${verb}`, key: key ?? `step.${verb}:${step}`, actor, step });
    }
    case "answer": {
      const step = need(pos[0], "<step id>");
      return Command.parse({ type: "step.answer", key: key ?? `step.answer:${step}`, actor, step,
        answer: need(pos.slice(1).join(" "), "<answer>") });
    }
    default:
      throw new UsageError("usage: fw step post|start|answer|done|cancel ...");
  }
}

export const TASK_USAGE = "usage: fw task handback <task> [--agent a] [--tip sha] | fw task integrate <task> --into <branch> --tip <sha>\n" +
  "       fw task park <task> --reason <text> | fw task unpark <task>   (--as <actor>, --key <k>; default actor lead)";

/** The full ref name git resolves `name` to (`git rev-parse --verify --symbolic-full-name`, e.g. `HEAD` on main ->
 *  `refs/heads/main`, `ci/x` -> `refs/heads/ci/x`), or null when git does not resolve it to one ref (`main~0`, a sha,
 *  an unknown name, an option-like `-x`). I/O only: whether the ref may be integrated into is Lean's
 *  (`Fw.Plan.integrate_allowlist`). */
export function gitFullRef(name: string, cwd = process.cwd()): string | null {
  if (name === "" || name.startsWith("-")) return null;
  try {
    const out = execFileSync("git", ["rev-parse", "--verify", "--quiet", "--symbolic-full-name", "--end-of-options", name],
      { cwd, stdio: ["ignore", "pipe", "ignore"] }).toString().trim();
    return out.startsWith("refs/") && !out.includes("\n") ? out : null;
  } catch { return null; }
}

/** `fw task handback|integrate|park|unpark`: an outcome mark of a task (Lean `Fw.Plan`, task task-state-truth). Only
 *  argument mapping: fwcore decides what the mark means (`tstate`) and refuses unknown/done tasks and every branch outside
 *  refs/heads/ci/*, refs/heads/worktree-*, refs/heads/integrate-* (`Fw.Plan.integrate_allowlist`). `--into` is sent as
 *  the full ref git resolves it to (`resolveRef`, `gitFullRef` in `fw`), so `HEAD` on main reaches Lean as
 *  `refs/heads/main` and is refused; a name git does not resolve is sent only when it is already a full ref
 *  (`refs/heads/...`, e.g. a branch not fetched yet), else the CLI refuses it. The default key names the content (a
 *  repeat is a duplicate); park/unpark add the time. */
export function taskCommand(argv: string[], env: Record<string, string | undefined>, now = Date.now(),
  resolveRef: (name: string) => string | null = () => null): Command {
  const [verb, ...rest] = argv;
  const { pos, flags } = parseFlags(rest);
  const actor = Actor.parse(flags.as ?? env.FW_ACTOR ?? "lead");
  const task = need(pos[0], "<task>");
  switch (verb) {
    case "handback": {
      const agent = flags.agent ?? task, tip = flags.tip ?? null;
      return Command.parse({ type: "task.handback", key: flags.key ?? `task.handback:${task}:${agent}:${tip ?? "none"}`, actor, task, agent, tip });
    }
    case "integrate": {
      const into = need(flags.into, "--into <branch>"), tip = need(flags.tip, "--tip <sha>");
      const branch = resolveRef(into) ?? (into.startsWith("refs/heads/") ? into : null);
      if (branch === null) throw new UsageError(`--into ${into}: git does not resolve it to a branch; give a full ref (refs/heads/ci/...)`);
      return Command.parse({ type: "task.integrate", key: flags.key ?? `task.integrate:${task}:${branch}:${tip}`, actor, task, branch, tip });
    }
    case "park":
      return Command.parse({ type: "task.park", key: flags.key ?? `task.park:${task}:${now}`, actor, task, reason: need(flags.reason, "--reason <text>") });
    case "unpark":
      return Command.parse({ type: "task.unpark", key: flags.key ?? `task.unpark:${task}:${now}`, actor, task });
    default:
      throw new UsageError(TASK_USAGE);
  }
}

/** `fw` groups that run without console-api. Every `pnpm fw <group>` in .github/** must be one of these (CI has no
 *  console-api; test/lib.test.ts checks the workflows). */
export const NO_API_GROUPS: readonly string[] = ["run", "ci", "next", "engine-check", "incidents", "coverage", "premises", "lake-gc", "checks", "console"];

/** Where console-api listens: FW_API, else .fw-console/api.json at the main checkout root. */
export function consoleDirOf(env: Record<string, string | undefined>, cwd = process.cwd()): string {
  return env.FW_CONSOLE_DIR ?? join(dirname(execFileSync("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd }).toString().trim()), ".fw-console");
}

/** The console secret (`.fw-console/secret`) for the door without a capability, or "" when unreadable. The runner's own
 *  tools (`fw land`'s plan sync speaks as the lead) show it; console-api refuses agent actors there without it. */
export function consoleSecret(env: Record<string, string | undefined> = process.env, cwd = process.cwd()): string {
  try { return readFileSync(join(consoleDirOf(env, cwd), "secret"), "utf8").trim(); } catch { return ""; }
}

export function apiBase(env: Record<string, string | undefined>, cwd = process.cwd()): string {
  if (env.FW_API) return env.FW_API;
  const dir = consoleDirOf(env, cwd);
  try {
    const { port } = JSON.parse(readFileSync(join(dir, "api.json"), "utf8")) as { port: number };
    return `http://127.0.0.1:${port}`;
  } catch {
    throw new Error(`console-api is not running (no ${join(dir, "api.json")}); start it with: pnpm --filter @fw/console-api start`);
  }
}

/** Agents' only door: `/api/agent/commands` with the argv `fw` was started with. console-api accepts it only with a
 *  capability the PreToolUse hook (hooks/cap.mjs) wrote for exactly this command, and stamps the actor itself.
 *  (`/api/commands`, which trusts the actor in the body, is for the web UI only.) */
export async function send(base: string, cmd: Command | Command[], argv: string[]): Promise<{ status: number; body: { ok: boolean; reason?: string; seq?: number | null; duplicate?: boolean; replies?: { ok: boolean; reason?: string; duplicate?: boolean }[] } }> {
  const r = await fetch(`${base}/api/agent/commands`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ argv, command: cmd }) });
  return { status: r.status, body: (await r.json()) as never };
}

const ago = (ms: number) => (ms < 60_000 ? `${Math.round(ms / 1000)}s` : ms < 3_600_000 ? `${Math.round(ms / 60_000)}m` : `${(ms / 3_600_000).toFixed(1)}h`);

/** Plain-text status board; every column is derived from events by console-api. */
export function renderBoard(b: Board): string {
  const rows = b.cards.map((c) =>
    [c.id, c.stage, c.owner, `${c.next.who}: ${c.next.command}`, ago(b.now - c.lastAt),
      c.needsYou ? `YOU: ${c.needsYou.action} (${c.needsYou.step})` : "-", c.violation ? "VIOLATION" : c.stale ? "STALE" : ""]);
  const head = ["card", "stage", "owner", "next", "age", "needs-you", "flag"];
  const all = [head, ...rows];
  const w = head.map((_, i) => Math.max(...all.map((r) => r[i]!.length)));
  const lines = all.map((r) => r.map((v, i) => v.padEnd(w[i]!)).join("  ").trimEnd());
  const loose = b.needsYou.filter((n) => !b.cards.some((c) => c.needsYou?.step === n.step));
  for (const n of loose) lines.push(`YOU: ${n.action} (${n.step}) ${n.title}`);
  return `seq ${b.seq}, ${b.cards.length} cards, ${b.needsYou.length} need you\n${lines.join("\n")}`;
}
