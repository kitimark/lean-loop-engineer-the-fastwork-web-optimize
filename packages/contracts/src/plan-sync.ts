// Plan sync, shared by `fw plan sync` (apps/runner) and the console reconciler (apps/console-api): the work graph
// file -> typed commands. Pure: the content digest is injected (node:crypto stays out of the browser bundle).
// It decides nothing about ready/blocked/done; the reducer (Lean Fw.Plan) does. Re-sending an unchanged define is a
// duplicate key (no-op), and Lean proves a repeated define changes nothing (`Fw.Plan.step_define_idem`).
import { Command, type Actor } from "./index.ts";

export type GraphTask = {
  id: string; title: string; stream: string; milestone?: string | null; deps?: string[]; owner: string;
  writes?: string[]; devices?: string[]; needs?: string[]; evidence?: string | null; cut?: boolean;
};
export type WorkGraph = { milestones: { id: string; title: string }[]; tasks: GraphTask[] };
/** A content digest (10 hex characters in practice) of a JSON value. */
export type ContentDigest = (v: unknown) => string;
type MkErr = (msg: string) => Error;
/** The ancestry fact of an evidence sha: `git merge-base --is-ancestor <sha> main` succeeded. Collected by the glue
 *  (runner: the checkout; reconciler: the console repo); the decision is Lean's (`Fw.Plan.check`: a define whose
 *  commit evidence is not on main is refused, task `evidence-on-main`). */
export type OnMain = (sha: string) => boolean;
/** Glue filter, not a decision: ask git only about strings that can be a commit id (Lean `Fw.Plan.Lint.evKind` =
 *  commit: 7-40 lowercase hex, not a CI run id of 8+ digits). Lean ignores the fact for every other kind. */
const shaLike = (e: string) => /^[0-9a-f]{7,40}$/.test(e) && !/^[0-9]{8,}$/.test(e);
const plainErr: MkErr = (m) => new Error(m);

/** Dependencies first (Kahn, ties keep file order). Throws on a cycle or an unknown dep, naming the tasks. */
export function topoSort(tasks: GraphTask[], err: MkErr = plainErr): GraphTask[] {
  const byId = new Map(tasks.map((t) => [t.id, t]));
  for (const t of tasks) for (const d of t.deps ?? []) if (!byId.has(d)) throw err(`task ${t.id}: dep ${d} is not in the graph`);
  const out: GraphTask[] = [];
  const placed = new Set<string>();
  while (out.length < tasks.length) {
    const next = tasks.find((t) => !placed.has(t.id) && (t.deps ?? []).every((d) => placed.has(d)));
    if (!next) throw err(`dependency cycle among: ${tasks.filter((t) => !placed.has(t.id)).map((t) => t.id).join(", ")}`);
    out.push(next); placed.add(next.id);
  }
  return out;
}

/** The contract caps titles at 200 characters; a longer one is clipped here (the file keeps the full text). */
export const clipTitle = (s: string) => (s.length <= 200 ? s : `${s.slice(0, 199)}…`);

/** Commands for the whole file: milestones, then tasks in dependency order. The key carries a digest of the content,
 *  so re-syncing an unchanged file is a no-op (duplicate) and an edited task is a new upsert. */
export function syncCommands(g: WorkGraph, actor: Actor, digest: ContentDigest, err: MkErr = plainErr, onMain?: OnMain): Command[] {
  const cmds: Command[] = [];
  for (const m of g.milestones) {
    cmds.push(Command.parse({ type: "milestone.define", key: `plan:m:${m.id}:${digest([m.id, m.title])}`, actor, milestone: m.id, title: clipTitle(m.title) }));
  }
  for (const t of topoSort(g.tasks, err)) {
    const body = { task: t.id, title: clipTitle(t.title), stream: t.stream, milestone: t.milestone ?? null, deps: t.deps ?? [], owner: t.owner,
      writes: t.writes ?? [], devices: t.devices ?? [],
      // only when present, so a task without needs keeps its key (digest) from before the field existed
      ...(t.needs?.length ? { needs: t.needs } : {}), evidence: t.evidence ?? null,
      // only when false: an on-main task keeps its key from before the fact existed, and an off-main define (refused)
      // has another key, so the same row is re-sent and accepted once its commit lands on main
      ...(t.evidence && onMain && shaLike(t.evidence) && !onMain(t.evidence) ? { evidenceOnMain: false } : {}),
      // likewise only when true (a task cut from the plan: fwcore derives state "cut")
      ...(t.cut ? { cut: true } : {}) };
    cmds.push(Command.parse({ type: "task.define", key: `plan:d:${t.id}:${digest(body)}`, actor, ...body }));
  }
  return cmds;
}

/** Which commit a plan sync reads the work graph from: main's head (the first ref named `main`) when it differs from
 *  the last synced commit; null (skip) when main is unknown or has not moved.
 *  TS STAND-IN of Lean `Fw.Plan.syncFrom` (theorems sync_only_main, sync_skip_same, sync_due), checked against
 *  packages/contracts/golden/plan/sync.jsonl. */
export function syncFrom(main: string, refs: readonly (readonly [string, string])[], last: string | null): string | null {
  const r = refs.find(([name]) => name === main);
  if (!r) return null;
  return last === r[1] ? null : r[1];
}
