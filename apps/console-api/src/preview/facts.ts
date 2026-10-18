// Git facts about a task, for the detail panel and the preview target. I/O only: which commit is shown is decided by
// Lean `console.previewTarget`. TS STAND-IN (temporary, to replace by a Lean rule): `findHead` picks the task head from
// an ordered list of git facts (handoff branch line, then ci/<task>, then the merge commit of the task).
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

export type Cand = { ref: string; sha: string; contains: boolean };
export type TaskFacts = {
  task: string;
  head: string | null;
  headSource: string; // where the head came from, for the panel
  branch: string | null;
  onMain: boolean;
  mainSha: string;
  cands: Cand[];
  containedIn: string[];
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

export function findHead(git: Git, task: string, handoff: string | null): { head: string; branch: string; source: string } | null {
  const tries: [string, string][] = [];
  const hb = handoff ? branchOfHandoff(handoff) : null;
  if (hb) tries.push([hb, "handoff branch line"]);
  tries.push([`ci/${task}`, "ci/<task>"], [`origin/ci/${task}`, "origin/ci/<task>"], [task, "branch named like the task"]);
  for (const [ref, source] of tries) { const sha = resolveRef(git, ref); if (sha) return { head: sha, branch: ref, source }; }
  // a merge of the task into main or an integration branch: its second parent is the task head
  const merges = git(["log", "--merges", "--format=%H %P %s", "-n", "400", "--all", `--grep=${task}`, "--fixed-strings"]) ?? "";
  for (const l of merges.split("\n").filter(Boolean)) {
    const [, , p2, ...subject] = l.split(" ");
    if (p2 && new RegExp(`(^|[^a-z0-9-])${task.replace(/[^a-z0-9-]/gi, "")}($|[^a-z0-9-])`).test(subject.join(" "))) {
      return { head: short(p2), branch: "(merged)", source: "second parent of a merge named for the task" };
    }
  }
  return null;
}

const isAncestor = (git: Git, a: string, b: string): boolean => git(["merge-base", "--is-ancestor", a, b]) !== null;

export function taskFacts(root: string, task: string, git: Git = gitIn(root)): TaskFacts {
  const main = git(["rev-parse", "main"]);
  const mainSha = main ? short(main) : "";
  const integ = integrationRefs(git);
  const handoff = readHandoff(git, task, ["main", ...integ.map((i) => i.ref)]);
  const found = findHead(git, task, handoff?.text ?? null);
  const head = found?.head ?? null;
  const own = !handoff && found && found.branch !== "(merged)" ? readHandoff(git, task, [found.branch]) : null;
  const h = handoff ?? own;
  const onMain = head !== null && mainSha !== "" && isAncestor(git, head, "main");
  const cands: Cand[] = integ.map((i) => ({ ref: i.ref, sha: i.sha, contains: head !== null && isAncestor(git, head, i.ref) }));
  const containedIn = [...(onMain ? ["main"] : []), ...cands.filter((c) => c.contains).map((c) => c.ref)];
  return { task, head, headSource: found?.source ?? "no branch, ci ref or merge found", branch: found?.branch ?? null,
    onMain, mainSha, cands, containedIn, handoff: h };
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
