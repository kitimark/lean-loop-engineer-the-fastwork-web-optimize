// Git facts about a task, for the detail panel and the preview target. I/O only: which commit is shown is decided by
// Lean `console.previewTarget` (`Fw.Console.Preview.headOf`): the head and the target. This file only gathers facts.
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

export type Cand = { ref: string; sha: string; contains: boolean };
/** One head candidate of a task and what repository history says about it (the Lean `Fw.Console.Preview.Fact`). */
/** One commit of the first-parent ancestry path from a head to main, oldest first (the Lean `Fw.Console.Preview.PathC`). */
export type PathC = { sha: string; p2Has: boolean };
export type Fact = {
  src: string; sha: string; onMain: boolean; noCode: boolean; cands: Cand[];
  /** the head is a commit of main's first-parent line */
  fpLine: boolean;
  /** the first-parent ancestry path from the head to main, up to and including the first commit whose second parent holds the head */
  path: PathC[];
  /** a merge's second parent contains the task's own work (true for every other source) */
  ownWork: boolean;
  /** another candidate of the task holds code this one lacks */
  behind: boolean;
};
/**
 * Everything the repository knows about a task, gathered with no decision: the candidates in priority order
 * (in any order: Lean `ordered` ranks them: handoff branch line, merge second parent, branch named like the task,
 * newest commit touching the handoff, ci/<task>, origin/ci/<task>), and for
 * an umbrella the candidates of each sub-task. Which candidate is the head and what to show is Lean
 * (`console.previewTarget`).
 */
export type TaskFacts = {
  task: string;
  mainSha: string;
  facts: Fact[];
  refOf: Record<string, string>; // candidate source -> the ref name it came from
  children: { task: string; facts: Fact[] }[];
  handoff: { ref: string; text: string } | null;
};

export type Git = (args: string[]) => string | null;

export function gitIn(root: string): Git {
  return (args) => {
    try { return execFileSync("git", args, { cwd: root, stdio: ["ignore", "pipe", "ignore"], maxBuffer: 16 << 20 }).toString(); } catch { return null; }
  };
}

const short = (s: string) => s.trim().slice(0, 7);
const ISO = /^[0-9a-z][0-9a-zA-Z._/-]*$/; // a ref name from a handoff must look like one before it reaches git

/** Integration refs, newest commit first (`git for-each-ref --sort=-committerdate`). */
export function integrationRefs(git: Git): { ref: string; sha: string }[] {
  const out = git(["for-each-ref", "--sort=-committerdate", "--format=%(refname:short) %(objectname)",
    "refs/heads/integrate-*", "refs/remotes/origin/ci/integrate-*"]) ?? "";
  return out.split("\n").filter(Boolean).map((l) => { const [ref = "", sha = ""] = l.split(" "); return { ref, sha: short(sha) }; });
}

/** Everything that can change these facts: the tip of every branch. A cache key. */
export function refsKey(git: Git): string {
  return createHash("sha1").update(git(["for-each-ref", "--format=%(refname) %(objectname)"]) ?? "").digest("hex");
}

function readHandoff(git: Git, task: string, refs: string[]): { ref: string; text: string } | null {
  for (const ref of refs) {
    const t = git(["show", `${ref}:docs/team/handoffs/${task}.md`]);
    if (t) return { ref, text: t };
  }
  return null;
}

/** The branch a handoff names ("Branch `x`" or "Branch: x"), if it is a plausible ref. */
export function branchOfHandoff(text: string): string | null {
  const m = /\bbranch(?::\s*`?|\s+`)([A-Za-z0-9][A-Za-z0-9._/-]*)/i.exec(text.split("\n").slice(0, 12).join("\n"));
  const b = m?.[1];
  return b && ISO.test(b) ? b : null;
}

function resolveRef(git: Git, ref: string): string | null {
  const o = git(["rev-parse", "--verify", "--quiet", `${ref}^{commit}`]);
  return o ? short(o) : null;
}

/** How many matching merge commits become head candidates. */
const MERGES = 4;
const DOCS = /^(docs|research)\//;

/** True when the commits of `sha` beyond its fork point from `ref` touch only documentation (a handoff note). */
function docsOnly(git: Git, sha: string, ref: string | undefined): boolean {
  if (!ref) return false;
  const base = git(["merge-base", sha, ref])?.trim();
  if (!base) return false;
  const names = git(["diff", "--name-only", base, sha]);
  if (names === null) return false;
  return names.split("\n").filter(Boolean).every((p) => DOCS.test(p));
}

const isAncestor = (git: Git, a: string, b: string): boolean => git(["merge-base", "--is-ancestor", a, b]) !== null;

const fpCache = new WeakMap<Git, Map<string, string[]>>();
/** Main's first-parent line, newest first (full shas), cached per main sha. */
function firstParentLine(git: Git, main: string): string[] {
  let m = fpCache.get(git);
  if (!m) { m = new Map(); fpCache.set(git, m); }
  let l = m.get(main);
  if (!l) { l = (git(["rev-list", "--first-parent", main]) ?? "").split("\n").filter(Boolean); m.set(main, l); }
  return l;
}
const mainFull = (git: Git) => git(["rev-parse", "main"])?.trim() ?? "main";
const onLine = (git: Git, sha: string): boolean => firstParentLine(git, mainFull(git)).includes(git(["rev-parse", sha])?.trim() ?? sha);

/** Facts only: is the head on main's first-parent line, and the commits of that line that contain the head, oldest first, cut
 * after the first one whose second parent contains the head (a later one cannot change Lean's `find?`). Containment only ever
 * grows along the line, so the oldest containing commit is found by bisection (`git log --first-parent --ancestry-path` is not
 * used: with `--first-parent` it drops a merge whose second parent reaches the head through another merge). Which commit is the
 * land commit is Lean (`Fw.Console.Preview.landOf`). */
export function landFacts(git: Git, sha: string): { fpLine: boolean; path: PathC[] } {
  if (onLine(git, sha)) return { fpLine: true, path: [] };
  const line = firstParentLine(git, mainFull(git)); // newest first; line[0] contains the head (the head is on main)
  let lo = 0, hi = line.length - 1; // invariant: line[lo] contains the head; find the largest index that does
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (isAncestor(git, sha, line[mid]!)) lo = mid; else hi = mid - 1;
  }
  const path: PathC[] = [];
  for (let k = lo; k >= 0; k--) {
    const parents = (git(["rev-list", "--parents", "-n", "1", line[k]!])?.trim().split(" ") ?? []).slice(1);
    const p2Has = parents.slice(1).some((p) => isAncestor(git, sha, p));
    path.push({ sha: short(line[k]!), p2Has });
    if (p2Has) break;
  }
  return { fpLine: false, path };
}

/** A merge's second parent contains the task's own work when it descends from `origin/ci/<task>` or the handoff branch head
 * (`own`; with neither to compare, any) and is not on main's first-parent line (a "merge main into the branch" commit has its
 * second parent there: that is main's work, and every later main commit descends from a landed task's head). */
function ownWorkOf(git: Git, sha: string, own: string[]): boolean {
  return !onLine(git, sha) && (own.length === 0 || own.some((o) => isAncestor(git, o, sha)));
}

/** True when `d` holds code that `f` lacks: `f` is a strict ancestor of `d` and the commits between touch more than documentation. */
function codeAhead(git: Git, f: string, d: string): boolean {
  if (f === d || !isAncestor(git, f, d)) return false;
  const names = git(["diff", "--name-only", f, d]);
  return names === null || names.split("\n").filter(Boolean).some((x) => !DOCS.test(x));
}

function factOf(git: Git, c: { src: string; sha: string }, integ: { ref: string; sha: string }[], own: string[]): Fact {
  const { src, sha } = c;
  const cands: Cand[] = integ.map((i) => ({ ref: i.ref, sha: i.sha, contains: isAncestor(git, sha, i.ref) }));
  const onMain = isAncestor(git, sha, "main");
  const held = onMain || cands.some((x) => x.contains);
  const lf = onMain ? landFacts(git, sha) : { fpLine: false, path: [] };
  return { src, sha, onMain, noCode: !held && docsOnly(git, sha, integ[0]?.ref), cands, ...lf,
    ownWork: src === "merge" ? ownWorkOf(git, sha, own) : true, behind: false };
}

/** Facts for a task's candidates, with `behind` set against the candidates that may be the head (a merge that holds the
 * task's work, or any other source): another such candidate holds code this one lacks. */
function factsOf(git: Git, cs: { src: string; sha: string }[], integ: { ref: string; sha: string }[]): Fact[] {
  const own = cs.filter((c) => c.src === "handoff" || c.src === "originCi").map((c) => c.sha);
  const fs = cs.map((c) => factOf(git, c, integ, own));
  return fs.map((f) => ({ ...f, behind: fs.some((d) => (d.src !== "merge" || d.ownWork) && codeAhead(git, f.sha, d.sha)) }));
}

/** The head candidates of a task in priority order: refs that resolve, then a merge's second parent. */
export function candidates(git: Git, task: string, handoff: string | null): { src: string; ref: string; sha: string }[] {
  const out: { src: string; ref: string; sha: string }[] = [];
  const hb = handoff ? branchOfHandoff(handoff) : null;
  const tries: [string, string][] = [];
  if (hb) tries.push(["handoff", hb]);
  tries.push(["ci", `ci/${task}`], ["originCi", `origin/ci/${task}`], ["named", task]);
  for (const [src, ref] of tries) { const sha = resolveRef(git, ref); if (sha) out.push({ src, ref, sha }); }
  // a merge of the task into main or an integration branch: its second parent is a task head
  // (newest first, up to MERGES of them: Lean drops a "merge main into <branch>" one, so an older real merge can still win)
  const merges = git(["log", "--merges", "--format=%H %P %s", "-n", "400", "--all", `--grep=${task}`, "--fixed-strings"]) ?? "";
  const re = new RegExp(`(^|[^a-z0-9-])${task.replace(/[^a-z0-9-]/gi, "")}($|[^a-z0-9-])`);
  let nm = 0;
  for (const l of merges.split("\n").filter(Boolean)) {
    const [, , p2, ...subject] = l.split(" ");
    if (p2 && re.test(subject.join(" ")) && !out.some((o) => o.src === "merge" && o.sha === short(p2))) {
      out.push({ src: "merge", ref: "(merged)", sha: short(p2) });
      if (++nm >= MERGES) break;
    }
  }
  // the newest commit on any ref that touches the task's handoff: a branch nobody named and nothing merged
  const hc = git(["log", "--all", "-n", "1", "--format=%H", "--", `docs/team/handoffs/${task}.md`])?.trim();
  if (hc) out.push({ src: "handoffCommit", ref: short(hc), sha: short(hc) });
  return out;
}

export function taskFacts(root: string, task: string, git: Git = gitIn(root)): TaskFacts {
  const main = git(["rev-parse", "main"]);
  const mainSha = main ? short(main) : "";
  const integ = integrationRefs(git);
  let handoff = readHandoff(git, task, ["main", ...integ.map((i) => i.ref)]);
  let cs = candidates(git, task, handoff?.text ?? null);
  if (!handoff) { // the handoff exists only on the task's own branch
    handoff = readHandoff(git, task, cs.filter((c) => c.ref !== "(merged)").map((c) => c.ref));
    if (handoff) cs = candidates(git, task, handoff.text);
  }
  const facts = factsOf(git, cs, integ);
  const refOf = Object.fromEntries(cs.map((c) => [c.src, c.ref]));
  const children = facts.length > 0 ? [] : subTasks(root, task).map((t) => {
    const sub = candidates(git, t, readHandoff(git, t, ["main", ...integ.map((i) => i.ref)])?.text ?? null);
    return { task: t, facts: factsOf(git, sub, integ) };
  });
  return { task, mainSha, facts, refOf, children, handoff };
}

/** Tasks named `<task>-*` in the work graph: the sub-tasks of an umbrella. */
export function subTasks(root: string, task: string): string[] {
  const f = join(root, "docs/team/work-graph.json");
  if (!existsSync(f)) return [];
  const g = JSON.parse(readFileSync(f, "utf8")) as { tasks?: { id: string }[] } | { id: string }[];
  const tasks = Array.isArray(g) ? g : g.tasks ?? [];
  return tasks.map((t) => t.id).filter((id) => id.startsWith(task + "-"));
}

/** The work graph row of a task (writes, deps, title), read from the main checkout. */
export function workGraphRow(root: string, task: string): { id: string; title: string; writes: string[]; deps: string[]; owner: string } | null {
  const f = join(root, "docs/team/work-graph.json");
  if (!existsSync(f)) return null;
  const g = JSON.parse(readFileSync(f, "utf8")) as { tasks?: Record<string, unknown>[] } | Record<string, unknown>[];
  const tasks = (Array.isArray(g) ? g : g.tasks ?? []) as { id: string; title?: string; writes?: string[]; deps?: string[]; owner?: string }[];
  const t = tasks.find((x) => x.id === task);
  return t ? { id: t.id, title: t.title ?? "", writes: t.writes ?? [], deps: t.deps ?? [], owner: t.owner ?? "" } : null;
}

/** Parts a task writes (`apps/site/src/parts/<part>/**`), for the panel and for locating the part on the page. */
export const partsOf = (writes: string[]): string[] =>
  writes.flatMap((w) => { const m = /^apps\/site\/src\/parts\/([^/*]+)/.exec(w)?.[1]; return m ? [m] : []; });
