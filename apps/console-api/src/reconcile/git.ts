// Thin git I/O for the reconciler. No decisions here: it lists refs, ancestry and commit messages; which trailer marks
// which task done is Lean's `plan.trailers` (`Fw.Plan.Trailer`).
import { execFileSync } from "node:child_process";
import type { Core } from "../core/index.ts";

export const git = (cwd: string, args: string[]): string =>
  execFileSync("git", args, { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }).trim();

export type Ref = { ref: string; sha: string };

/** All local branches (main checkout and every worktree share the one ref store). */
export function branches(repo: string): Ref[] {
  const out = git(repo, ["for-each-ref", "--format=%(refname:short) %(objectname)", "refs/heads"]);
  return out.split("\n").filter(Boolean).map((l) => {
    const [ref, sha] = l.split(" ");
    return { ref: ref!, sha: sha! };
  });
}

/** Commits reachable from `tip` and not from `base`, oldest first. */
export function commitsAhead(repo: string, base: string, tip: string): string[] {
  const out = git(repo, ["rev-list", "--reverse", `${base}..${tip}`]);
  return out ? out.split("\n") : [];
}

export function isAncestor(repo: string, sha: string, of: string): boolean {
  try { execFileSync("git", ["merge-base", "--is-ancestor", sha, of], { cwd: repo, stdio: "ignore" }); return true; }
  catch { return false; }
}

/** The last `max` commits on the first-parent history of `ref` with their full messages, newest first ([] if the ref
 *  is unknown). */
export function firstParentLog(repo: string, ref: string, max = 300): { sha: string; body: string }[] {
  let out: string;
  try { out = git(repo, ["log", "--first-parent", `-n${max}`, "--format=%H%x1f%B%x1e", ref]); } catch { return []; }
  const res: { sha: string; body: string }[] = [];
  for (const rec of out.split("\x1e")) {
    const [sha, body] = rec.trim().split("\x1f");
    if (sha) res.push({ sha, body: body ?? "" });
  }
  return res;
}

/** The `task.done` facts of the `Task: <id>` trailers on the first-parent history of `ref`, oldest first: Lean
 *  `plan.trailers` decides (a whole-line trailer of an undone task, its oldest commit as evidence; done, unknown and
 *  repeated ids give no fact). */
export async function trailerFacts(core: Pick<Core, "ops">, repo: string, ref: string, tasks: readonly { id: string; state: string }[],
  max = 300): Promise<{ task: string; evidence: string }[]> {
  const commits = firstParentLog(repo, ref, max);
  if (commits.length === 0) return [];
  const r = await core.ops("plan.trailers", { commits, tasks: tasks.map((t) => ({ id: t.id, state: t.state })) });
  return r.done as { task: string; evidence: string }[];
}

/** Public web URL of the repo, derived from `origin` at runtime (never hard-coded); null if there is no usable remote. */
export function repoUrl(repo: string): string | null {
  let u: string;
  try { u = git(repo, ["remote", "get-url", "origin"]); } catch { return null; }
  const m = /^(?:https?:\/\/(?:[^@/]+@)?|ssh:\/\/(?:[^@/]+@)?|[^@/:]+@)([^/:]+)[:/](.+?)(?:\.git)?\/?$/.exec(u);
  return m ? `https://${m[1]}/${m[2]}` : null;
}
export const commitUrl = (repo: string, sha: string): string | null => {
  const b = repoUrl(repo);
  return b ? `${b}/commit/${sha}` : null;
};
