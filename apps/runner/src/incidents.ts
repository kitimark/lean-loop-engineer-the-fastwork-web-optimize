// `fw incidents lint [docs/team/incidents/ledger.json]`: collect the facts the incident lint needs (which commit refs are
// commits on main, which file refs exist, the work graph rows with their board state, the mistake class ids of
// research/mistakes/ledger.json), ask fwcore `plan.incidentLint` (Fw.Plan.Incident) for every finding and the derived
// status, print one line per incident. No decision logic here.
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { isAbsolute, join, relative, resolve } from "node:path";
import { UsageError, apiBase } from "./lib.ts";
import { coreCandidates, coreCaller, type CoreCall } from "./watch.ts";

export const INCIDENTS_SUBS = ["lint"] as const;
export const INCIDENTS_USAGE = "usage: fw incidents lint [docs/team/incidents/ledger.json]   (exit 1 on any error)";
export const LEDGER = "docs/team/incidents/ledger.json";
export const MISTAKES = "research/mistakes/ledger.json";

type Ev = { kind?: unknown; ref?: unknown };
type Raw = { id?: unknown; evidence?: Ev[] };
/** A work graph / board row as fwcore reads it: done iff evidence, claimed iff agent. */
export type TaskRow = { id: string; evidence: string | null; agent: string | null };
export type Finding = { code: string; severity: string; detail: string };
export type IncidentReply = {
  ok: boolean; errors: number; warnings: number;
  incidents: { id: string; status: string; findings: Finding[] }[];
};
export interface Deps {
  core?: CoreCall;
  /** Board plan tasks, or null when the console-api is not reachable. */
  board?: () => Promise<{ id: string; evidence?: string | null; agent?: string | null }[] | null>;
  /** Is `ref` a commit reachable from main? */
  onMain?: (ref: string) => boolean;
}

/** The refs of one evidence kind, as written. */
const refsOf = (incidents: Raw[], kind: string): string[] =>
  [...new Set(incidents.flatMap((i) => (Array.isArray(i.evidence) ? i.evidence : [])
    .filter((e) => e?.kind === kind && typeof e.ref === "string").map((e) => e.ref as string)))];

/** `git cat-file -e <ref>^{commit}` and `git merge-base --is-ancestor <ref> main`, both quiet. */
export function gitOnMain(cwd: string, main = "main"): (ref: string) => boolean {
  const ok = (...a: string[]) => { try { execFileSync("git", a, { cwd, stdio: "ignore" }); return true; } catch { return false; } };
  // a ref that starts with "-" would be read as an option: never passed to git (so never a fact)
  return (ref) => !ref.startsWith("-") && ok("cat-file", "-e", `${ref}^{commit}`) && ok("merge-base", "--is-ancestor", ref, main);
}

/** File refs that exist inside the repo (a ref outside the repo is never a fact). */
export function existingFiles(root: string, refs: string[]): string[] {
  return refs.filter((r) => {
    const p = resolve(root, r);
    const rel = relative(root, p);
    return !isAbsolute(r) && rel !== "" && !rel.startsWith("..") && existsSync(p);
  });
}

/** The class ids of the mistake retro ledger (`classes[].id`); none when the file is missing or unreadable. */
export function mistakeClasses(root: string): string[] {
  try {
    const m = JSON.parse(readFileSync(join(root, MISTAKES), "utf8")) as { classes?: { id?: unknown }[] };
    return (Array.isArray(m.classes) ? m.classes : []).map((c) => c?.id).filter((x): x is string => typeof x === "string");
  } catch { return []; }
}

/** Work graph rows with their state: the board's row when the board has one, else the file's row (no agent). */
export function taskRows(graph: { tasks: { id: string; evidence?: string | null }[] },
  board: { id: string; evidence?: string | null; agent?: string | null }[] | null): TaskRow[] {
  const b = new Map((board ?? []).map((t) => [t.id, t]));
  return graph.tasks.map((t) => {
    const r = b.get(t.id);
    return r ? { id: t.id, evidence: r.evidence ?? null, agent: r.agent ?? null } : { id: t.id, evidence: t.evidence ?? null, agent: null };
  });
}

/** One line per incident: id, derived status, then the error and warning findings. */
export function renderIncidents(r: IncidentReply): string {
  const L = r.incidents.map((i) => {
    const f = i.findings.map((x) => `${x.severity} ${x.code}${x.detail ? `: ${x.detail.slice(0, 110)}` : ""}`);
    return `${i.id.padEnd(30)} ${i.status.padEnd(6)} ${f.length ? f.join("; ") : "ok"}`;
  });
  L.push(`incidents lint: ${r.incidents.length} incidents, ${r.errors} errors, ${r.warnings} warnings`);
  return L.join("\n");
}

async function boardTasks(): Promise<{ id: string; evidence?: string | null; agent?: string | null }[] | null> {
  try {
    const res = await fetch(`${apiBase(process.env)}/api/board`, { signal: AbortSignal.timeout(3000) });
    const b = (await res.json()) as { plan?: { tasks?: { id: string; evidence?: string | null; agent?: string | null }[] } };
    return b.plan?.tasks ?? null;
  } catch { return null; }
}

/** `fw incidents lint [file]`: exit 1 when fwcore finds an error. */
export async function incidentsCli(args: string[], cwd: string, deps: Deps = {}): Promise<number> {
  if (!(INCIDENTS_SUBS as readonly string[]).includes(args[0] ?? "") || args.length > 2) throw new UsageError(INCIDENTS_USAGE);
  const root = execFileSync("git", ["rev-parse", "--show-toplevel"], { cwd, encoding: "utf8" }).trim();
  const common = execFileSync("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd, encoding: "utf8" }).trim();
  const file = args[1] ? resolve(cwd, args[1]) : join(root, LEDGER);
  const ledger = JSON.parse(readFileSync(file, "utf8")) as { incidents?: Raw[] };
  const incidents = Array.isArray(ledger.incidents) ? ledger.incidents : [];
  const graph = JSON.parse(readFileSync(join(root, "docs/team/work-graph.json"), "utf8")) as { tasks: { id: string; evidence?: string | null }[] };
  const board = await (deps.board ?? boardTasks)();
  const onMain = deps.onMain ?? gitOnMain(root);
  const call = deps.core ?? coreCaller(coreCandidates(root, join(common, "..")));
  const r = (await call({ op: "plan.incidentLint", incidents: ledger.incidents ?? null, tasks: taskRows(graph, board),
    commits: refsOf(incidents, "commit").filter(onMain), files: existingFiles(root, refsOf(incidents, "file")),
    classes: mistakeClasses(root) })) as unknown as IncidentReply;
  if (!board) console.log("incidents lint: console-api not reachable; task states from docs/team/work-graph.json (no claims, so no 'fixing')");
  console.log(renderIncidents(r));
  return r.ok ? 0 : 1;
}
