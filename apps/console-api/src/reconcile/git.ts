// Thin git I/O for the reconciler. No decisions here: it only lists refs and ancestry.
import { execFileSync } from "node:child_process";

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

/** `Task: <id>` trailers on the first-parent history of `ref`, newest first (TS STAND-IN: the id -> done mapping is
 *  still decided by the Lean plan reducer; this only reads text from commit messages). */
export function taskTrailers(repo: string, ref: string, max = 300): { sha: string; task: string }[] {
  let out: string;
  try { out = git(repo, ["log", "--first-parent", `-n${max}`, "--format=%H%x1f%B%x1e", ref]); } catch { return []; }
  const res: { sha: string; task: string }[] = [];
  for (const rec of out.split("\x1e")) {
    const [sha, body] = rec.trim().split("\x1f");
    if (!sha || !body) continue;
    for (const m of body.matchAll(/^Task:[ \t]*([A-Za-z0-9._-]+)[ \t]*$/gm)) res.push({ sha, task: m[1]! });
  }
  return res;
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
